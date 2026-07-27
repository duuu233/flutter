import 'package:flutter/material.dart';

import '../../../network/boltstar_ai_api.dart';
import '../../../routes/app_routes.dart';
import '../../../shared/l10n/app_l10n.dart';
import '../../../shared/widgets/app_dialog.dart';
import '../../../shared/widgets/app_toast.dart';
import '../../../shared/widgets/app_widgets.dart';
import '../../../shared/widgets/figma_common.dart';
import '../../../state.dart';
import '../ai_i18n.dart';
import 'ai_chat_page.dart';

/// AI 会话列表页。对齐小程序 `subpackages/ai/sessions`：
/// 时间倒序、标题 = 首条消息、每页 20 条滚动加载、长按删除单条、新建会话。
/// 数据仅保留最近 7 天（后端策略）。
///
/// ## 「原路径返回」（对齐小程序 2026-07-25 重做）
/// 点某条会话 / 点「新建对话」都是 **push 一个新的聊天页**，本页留在页面栈里 —— 于是新聊天页的
/// 返回键天然原路退回本列表，再返回才回到进来时那个聊天页。
/// 老实现是「pop 回一个结果、由下层那个聊天页就地换会话」：那样返回键直接退出了 AI，
/// 而且点「新建对话」还会把下层那段对话从界面上抹掉（正是小程序当时用户报的两个现象）。
/// 下层已经是同一条会话 / 已经是干净空态时不叠页，直接 pop 回去。
///
/// 🔶 与小程序的差异：小程序有 10 层页面栈硬上限，所以它还有一套「栈快满就降级成就地换会话」的
/// 兜底（`sessions.goChat` 的 degrade）；Flutter 没有这个限制，直接 push 即可。
///
/// ## ⚠️ 本模块没有也不要再加任何「清空」入口
/// 接口**没有批量/清空会话的能力**，只能 for 循环串行打 `DELETE /session`（上限 20 条 = 最坏 20 个
/// 串行请求），且中途任一条失败就留下「删了一半且无法回滚」的状态。要清理一律**长按逐条删**
/// （列表底部有提示）。2026-07-25 已按用户要求整功能移除，别再加回来。
class AiSessionsPage extends StatefulWidget {
  const AiSessionsPage({
    super.key,
    required this.state,
    required this.api,
    this.currentId = '',
    this.openerPristine = false,
  });

  final PhotoFrameState state;
  final BoltStarAiApi api;

  /// 打开本页的那个聊天页当前显示的会话，列表里高亮标记；点它就直接 pop 回去而不是叠新页。
  final String currentId;

  /// 打开本页的那个聊天页是不是「还没开口的新对话空态」。
  /// 快照即可：本页盖在它上面期间它不会变。点「新建对话」时靠它决定退回去还是叠一张新空页。
  final bool openerPristine;

  @override
  State<AiSessionsPage> createState() => _AiSessionsPageState();
}

/// 接口一次回全部，前端按 20 条/页分段展示（需求的分页交互）。
const int _kPageSize = 20;

/// 「N 条消息」补数的并发上限。
///
/// 背景：`/session/list` 回来的 `msg_count` **恒为 0**（排查结论见
/// photo-album/docs/2026-07-24-AI模块开发进度.md —— **前端取值无误**，同一个对象里的
/// title/updated_at 都正常，只有 msg_count 是 0），只能拿 `/chat/history` 的 `total` 兜底。
/// 代价是 N+1 请求，所以严格设限：只补**当前已渲染出来的那几行**、`page_size=1` 只要 total、
/// 并发 ≤ 本值、失败静默、每条只试一次。
/// ⚠️ 后端把 msg_count 修好后，把 [_AiSessionsPageState._fillMsgCounts] / `_counted` 及两处调用
/// 一并删掉即可（自动回落到接口值）。
const int _kHistoryFillConcurrency = 4;

/// 列表行（接口字段 + 前端补出来的条数）。[msgCount] 为 0 表示**未知**，此时只显示时间，
/// 不摆一个明知是错的「0 条消息」。
class _SessionRow {
  _SessionRow({
    required this.sessionId,
    required this.title,
    required this.updatedAt,
    this.msgCount = 0,
  });

  final String sessionId;
  final String title;
  final String updatedAt;
  int msgCount;
}

class _AiSessionsPageState extends State<AiSessionsPage> {
  final ScrollController _scroll = ScrollController();

  List<_SessionRow> _all = [];
  int _shown = _kPageSize;
  bool _loading = true;

  /// sessionId → 已试过补数（不论成败只试一次，防翻页来回反复打接口）。
  final Set<String> _counted = <String>{};

  /// 上次从本页打开的会话：退回本页时只重新补它的条数（它才刚变过）。
  String _lastOpened = '';

  /// 在途跳转，防连点叠出两页聊天页。
  bool _navigating = false;

  /// 本页高亮的「当前会话」。初值来自打开本页的聊天页，删除后会清掉。
  late String _currentId = widget.currentId;

  bool get _hasMore => _all.length > _shown;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_hasMore || !_scroll.hasClients) {
      return;
    }
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 80) {
      setState(() => _shown += _kPageSize);
      _fillMsgCounts(); // 新露出来的几行也补
    }
  }

  /// [silent] = true：静默刷新（不显示整页 loading、失败也不打扰），用于从聊天页退回本页时对齐
  /// 最新的标题/时间/条数 —— 本页现在**常驻页面栈**，聊完退回来数据可能已经变了。
  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() => _loading = true);
    }
    try {
      final sessions = await widget.api.listSessions();
      if (!mounted) {
        return;
      }
      // 已经补到的条数带过来，否则静默刷新会把补好的条数刷没了，还得再打一轮 /chat/history。
      // 只带 _counted 里还认账的那些：退回本页时会把「刚聊过那条」从 _counted 里删掉，
      // 于是它这里也不被带过来 → msgCount 归 0 → _fillMsgCounts 会重新补它的真实条数。
      final kept = <String, int>{
        for (final row in _all)
          if (row.msgCount > 0 && _counted.contains(row.sessionId))
            row.sessionId: row.msgCount,
      };
      setState(() {
        _all = [
          for (final item in sessions)
            _SessionRow(
              sessionId: item.sessionId,
              title: item.title,
              updatedAt: item.updatedAt,
              msgCount: item.msgCount > 0
                  ? item.msgCount
                  : (kept[item.sessionId] ?? 0),
            ),
        ];
        // 静默刷新保持用户已翻到的行数，别把人拉回第一页
        _shown = _shown < _kPageSize ? _kPageSize : _shown;
        _loading = false;
      });
      _fillMsgCounts(); // 不 await：列表先出来，条数补到了再刷一次
    } catch (error) {
      if (!mounted) {
        return;
      }
      if (silent) {
        return; // 静默刷新失败就保持旧列表，不打扰用户（下次退回本页还会再试）
      }
      setState(() => _loading = false);
      // 包一层 lambda 而不是直接传 _load：它现在带了可选具名参数，别让重试把 silent 的语义带进来
      await AiI18n.of(context).handleError(
        context,
        error,
        onRetry: () => _load(),
      );
    }
  }

  /// 给 `msg_count = 0` 的行补真实条数：逐条拿 `/chat/history` 的 `total`
  ///（`page_size=1`，只要 total 不要内容）。只处理**已渲染出来的行**，并发
  /// [_kHistoryFillConcurrency] 条，失败静默 —— 补数只是锦上添花，挂了也不该影响列表本身。
  /// 结果攒齐后**只 setState 一次**（逐条刷会打出十几次重建）。
  Future<void> _fillMsgCounts() async {
    final targets = [
      for (final row in _all.take(_shown))
        if (row.msgCount <= 0 && !_counted.contains(row.sessionId)) row,
    ];
    if (targets.isEmpty) {
      return;
    }
    final found = <String, int>{};
    var cursor = 0;
    Future<void> worker() async {
      while (cursor < targets.length) {
        final row = targets[cursor++];
        _counted.add(row.sessionId);
        try {
          final history = await widget.api.getHistory(
            row.sessionId,
            page: 1,
            pageSize: 1,
          );
          if (history.total > 0) {
            found[row.sessionId] = history.total;
          }
        } catch (_) {
          // 静默：补不到就继续「只显示时间、不带条数」
        }
      }
    }

    await Future.wait([
      for (var i = 0; i < _kHistoryFillConcurrency && i < targets.length; i++)
        worker(),
    ]);
    if (!mounted || found.isEmpty) {
      return;
    }
    setState(() {
      for (final row in _all) {
        final count = found[row.sessionId];
        if (count != null) {
          row.msgCount = count;
        }
      }
    });
  }

  // ── 跳转 ─────────────────────────────────────────────────

  /// 点击会话：**push 一页新的聊天页**载入这条会话（返回键即原路退回本列表）。
  Future<void> _openSession(_SessionRow row) async {
    if (_navigating) {
      return; // 连点去重：否则会叠出两页一样的聊天页
    }
    // 点的正是下层聊天页已经打开的那条（带「当前」标记的）：没必要再叠一页一样的，直接退回去
    if (row.sessionId.isNotEmpty && row.sessionId == _currentId) {
      _navigating = true;
      Navigator.of(context).pop();
      return;
    }
    _lastOpened = row.sessionId;
    await _pushChat(
      sessionId: row.sessionId,
      title: row.title.isEmpty ? null : row.title,
    );
  }

  /// 新建对话：push 一页**空**聊天页（＝招呼语空态）。
  /// 这里**不建会话** —— 会话统一等首次发送时才建（见 `ai_chat_page._createSession`），
  /// 所以也没有「会话数已达上限」可拦：真到 20 条上限，是首次发送时接口回 20013，
  /// 由聊天页的 `onSessionLimit` 把用户引回本页清理。
  Future<void> _createNew() async {
    if (_navigating) {
      return;
    }
    // 下层本来就是一张还没开口的「新对话」空页：直接退回去，别再叠一页一样的
    if (widget.openerPristine && _currentId.isEmpty) {
      _navigating = true;
      Navigator.of(context).pop();
      return;
    }
    _lastOpened = '';
    await _pushChat();
  }

  Future<void> _pushChat({String? sessionId, String? title}) async {
    _navigating = true;
    await Navigator.of(context).push<void>(
      AppPageRoute<void>(
        builder: (_) => AiChatPage(
          state: widget.state,
          api: widget.api,
          sessionId: sessionId,
          sessionTitle: title,
        ),
      ),
    );
    if (!mounted) {
      return;
    }
    _navigating = false;
    // 刚聊过的那条条数/标题/时间肯定变了，允许再补一次后静默刷新
    if (_lastOpened.isNotEmpty) {
      _counted.remove(_lastOpened);
    }
    await _load(silent: true);
  }

  // ── 删除 ─────────────────────────────────────────────────

  Future<void> _deleteSession(_SessionRow row) async {
    try {
      await widget.api.deleteSession(row.sessionId);
      if (!mounted) {
        return;
      }
      setState(() {
        _all = _all.where((item) => item.sessionId != row.sessionId).toList();
        if (row.sessionId == _currentId) {
          _currentId = '';
        }
      });
      _counted.remove(row.sessionId);
      if (row.sessionId == _lastOpened) {
        _lastOpened = '';
      }
      AppToast.show(context, AppL10n.of(context).aiDeleted);
      // 删的是某个聊天页正打开的会话：只通知那一页退回空态，避免用户继续往已删会话发消息。
      // 点对点通知（不是广播一个「谁看到谁消费」的标记），理由见 AiChatPage.notifySessionDeleted。
      // 也**不替他建新会话** —— 这是「没得可显示了」，不是用户要新建。
      AiChatPage.notifySessionDeleted(row.sessionId);
    } catch (error) {
      if (mounted) {
        await AiI18n.of(context).handleError(context, error);
      }
    }
  }

  Future<void> _confirmDelete(_SessionRow row) async {
    final l10n = AppL10n.of(context);
    final confirmed = await showAppConfirmDialog(
      context,
      title: l10n.aiDeleteSessionTitle,
      message: l10n.aiDeleteSessionMessage,
      icon: Icons.delete_outline_rounded,
      tone: AppDialogTone.danger,
      confirmLabel: l10n.aiDelete,
    );
    if (confirmed == true && mounted) {
      await _deleteSession(row);
    }
  }

  // ── UI ───────────────────────────────────────────────────

  /// ISO 时间 → 列表友好展示：今天显示 HH:mm，其余显示 MM-DD HH:mm（对齐小程序 formatTime）。
  String _formatTime(String iso) {
    final date = DateTime.tryParse(iso);
    if (date == null) {
      return '';
    }
    final local = date.toLocal();
    final now = DateTime.now();
    String pad(int n) => n < 10 ? '0$n' : '$n';
    final hm = '${pad(local.hour)}:${pad(local.minute)}';
    final sameDay =
        local.year == now.year &&
        local.month == now.month &&
        local.day == now.day;
    return sameDay ? hm : '${pad(local.month)}-${pad(local.day)} $hm';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final visible = _all.take(_shown).toList();
    return FigmaScreen(
      title: l10n.aiSessionsTitle,
      scrollable: false,
      bodyPadding: EdgeInsets.zero,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
            child: SizedBox(
              width: double.infinity,
              child: FigmaPrimaryButton(
                label: l10n.aiNewChat,
                height: 44,
                onPressed: _createNew,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.aiKeep7Days,
                    style: const TextStyle(
                      color: Color(0xFF8B9098),
                      fontSize: 12,
                    ),
                  ),
                ),
                // 「清空全部」已下线（见类注释），清理一律长按逐条删 —— 所以这句提示必须有
                Text(
                  l10n.aiLongPressToDelete,
                  style: const TextStyle(
                    color: Color(0xFFB9BFC8),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const PageLoading()
                : (visible.isEmpty
                      ? Center(
                          child: Text(
                            l10n.aiNoSessions,
                            style: const TextStyle(
                              color: Color(0xFF8B9098),
                              fontSize: 14,
                            ),
                          ),
                        )
                      : ListView.builder(
                          controller: _scroll,
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          itemCount: visible.length + (_hasMore ? 1 : 0),
                          itemBuilder: (context, index) {
                            if (index >= visible.length) {
                              return const Padding(
                                padding: EdgeInsets.symmetric(vertical: 16),
                                child: Center(
                                  child: SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                ),
                              );
                            }
                            return _buildItem(visible[index]);
                          },
                        )),
          ),
        ],
      ),
    );
  }

  Widget _buildItem(_SessionRow row) {
    final l10n = AppL10n.of(context);
    final active = row.sessionId == _currentId;
    final title = row.title.isEmpty ? l10n.aiNewChat : row.title;
    // 条数未知（后端 msg_count 恒 0 且没补到）时**只显示时间**，不摆一个明知是错的「0 条消息」
    final time = _formatTime(row.updatedAt);
    final meta = row.msgCount > 0
        ? '$time  ·  ${l10n.aiMsgCount(row.msgCount)}'
        : time;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _openSession(row),
      // 需求「左滑或长按删除」取长按实现（与小程序一致）
      onLongPress: () => _confirmDelete(row),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: active
              ? Border.all(color: const Color(0xFFFF5F1F), width: 1.5)
              : Border.all(color: const Color(0xFFEDF1F7)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF2A2D32),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    meta,
                    style: const TextStyle(
                      color: Color(0xFF8B9098),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: Color(0xFFB9BFC8),
            ),
          ],
        ),
      ),
    );
  }
}
