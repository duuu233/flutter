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
import '../ai_last_session.dart';
import '../ai_token.dart';
import 'ai_chat_page.dart';
import 'ai_visuals.dart';

/// AI 会话列表页。对齐小程序 `subpackages/ai/sessions`：
/// 时间倒序、**按日期分组**、标题 = 首条消息、每页 20 条滚动加载、左滑或长按删除单条、新建会话。
/// 数据仅保留最近 7 天（后端策略）。
///
/// ## 「原路径返回」（对齐小程序 2026-07-25 重做）
/// 点某条会话 / 点「新建」都是 **push 一个新的聊天页**，本页留在页面栈里 —— 于是新聊天页的
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
/// 串行请求），且中途任一条失败就留下「删了一半且无法回滚」的状态。要清理一律**左滑删 / 长按删**。
/// 2026-07-25 已按用户要求整功能移除，别再加回来。
///
/// ## 2026-08-10 AI 助手八项优化（本页三项）
/// - 1.1 顶部显示 **Token 余额**（占「仅保留最近 7 天」原来那一行，提示整体下移一行）。
///   余额与聊天页同源（[AiToken]）；聊天页顶栏那颗胶囊已撤，**这里是余额唯一的展示位**。
/// - 1.2 右上「新建」由文字改为图标 `ai-new-chat.png`。
/// - 6 删除会话加 loading 闸；左滑手势由「整条轨道」收到**卡片**上 —— 罩住轨道时，手指落在
///   已滑开的删除按钮上也算新一轮滑动，点按时那一两像素抖动就把卡片吸回去，表现就是「点不动」。
///   删除按钮同步加宽到 80（小程序 160rpx）。
///
/// ## 2026-07-31 视觉同步（小程序 2026-07-30 / 07-31 两轮）
/// 日期分组标题、毛玻璃会话卡、左滑露出的删除按钮（`ai-del-btn-bg.png`）、空态插画与
/// 顶部「仅保留最近 7 天」提示都按视觉稿重做；「新建」从整块主按钮改为导航栏右上的文字入口。
/// ⚠️ 背景图**本轮不动**（用户指定）：本页仍用全 App 统一的 [FigmaScreenBackground]，
/// 没有跟着小程序换成 AI 那张 OSS 全屏图。
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
  /// 快照即可：本页盖在它上面期间它不会变。点「新建」时靠它决定退回去还是叠一张新空页。
  final bool openerPristine;

  @override
  State<AiSessionsPage> createState() => _AiSessionsPageState();
}

/// 接口一次回全部，前端按 20 条/页分段展示（需求的分页交互）。
const int _kPageSize = 20;

/// 左滑露出删除按钮的位移：小程序 176rpx = 删除按钮 160rpx + 与卡片的 16rpx 间距。
/// ⚠️ 与 [_kDeleteWidth] + [_kDeleteGap] 是同一组数，改一处要改三处（小程序侧同样）。
const double _kDeleteReveal = 88;

/// 删除按钮本体宽度（2026-08-10 需求 6：136rpx → 160rpx）与它和卡片之间的间距（16rpx）。
const double _kDeleteWidth = 80;
const double _kDeleteGap = 8;

/// 松手吸附判据（对齐小程序 onSessionTouchEnd）：甩得够快直接开，
/// 否则看有没有拉过 42%。小程序的 0.35 px/ms 换算成 Flutter 的 px/s 就是 350。
const double _kFlingVelocity = 350;
const double _kOpenRatio = 0.42;

/// 卡片高度（112rpx）。
const double _kCardHeight = 56;

/// 列表行。
///
/// ⚠️ 2026-07-31 起**不再显示「N 条消息」**（视觉稿改成「标题 + 时间 + 箭头」三栏，日期由分组
/// 标题承载），所以原先那套「`/session/list` 的 msg_count 恒为 0 → 逐条打 `/chat/history`
/// 拿 total 补数」的 N+1 兜底一并删除：没有任何界面消费它，留着就是每次进列表白打十几个请求。
/// 要恢复条数展示时再连同补数逻辑一起加回（历史实现见 git）。
class _SessionRow {
  _SessionRow({
    required this.sessionId,
    required this.title,
    required this.updatedAt,
  });

  final String sessionId;
  final String title;
  final String updatedAt;
}

/// 渲染项：日期分组标题只挂在该组第一条上（对齐小程序 `decorateGroups`）——
/// 列表仍是单层，分页与滚动逻辑不用变形态。
class _SessionEntry {
  _SessionEntry({required this.row, required this.groupLabel});

  final _SessionRow row;

  /// 空串 = 不是本组第一条，不画标题。
  final String groupLabel;
}

class _AiSessionsPageState extends State<AiSessionsPage> {
  final ScrollController _scroll = ScrollController();

  List<_SessionRow> _all = [];
  int _shown = _kPageSize;
  bool _loading = true;

  /// 顶部星币余额（2026-08-10 需求 1.1；2026-08-12 起是**真实账户值**，见 [AiToken]）。
  /// 与聊天页同源；聊天页顶栏那颗胶囊已撤，**这里是余额唯一的展示位**。
  /// null = 未知（接口挂了/未登录），显示 `--`，不用 0 兜底。
  // 先用登录带回的余额渲染第一帧（2026-08-11 同步小程序：登录/用户信息出参含 availableToken），
  // 再由 _refreshTokenBalance 刷权威值。没有缓存值时仍是 null → 显示 `--`。
  int? _tokenBalance = AiToken.cachedBalance();

  /// 在途删除，删除期间不接第二次点击（见 [_deleteSession]）。
  bool _deleting = false;

  /// 上次从本页打开的会话（退回本页后静默刷新时用来对齐标题/时间）。
  String _lastOpened = '';

  /// 在途跳转，防连点叠出两页聊天页。
  bool _navigating = false;

  /// 本页高亮的「当前会话」。初值来自打开本页的聊天页，删除后会清掉。
  late String _currentId = widget.currentId;

  /// 左滑后停在「露出删除按钮」位的那条。
  String _openedId = '';

  /// 正随手指移动的那条 + 它当前的位移（负值向左）。
  String _draggingId = '';
  double _dragOffset = 0;

  bool get _hasMore => _all.length > _shown;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    _refreshTokenBalance();
  }

  /// 余额会在聊天页用掉（扣费在服务端发生），进页面和退回本页时都对齐一次。
  Future<void> _refreshTokenBalance() async {
    final balance = await AiToken.fetchBalance();
    if (mounted && balance != _tokenBalance) {
      setState(() => _tokenBalance = balance);
    }
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
    }
  }

  /// [silent] = true：静默刷新（不显示整页 loading、失败也不打扰），用于从聊天页退回本页时对齐
  /// 最新的标题/时间 —— 本页现在**常驻页面栈**，聊完退回来数据可能已经变了。
  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() => _loading = true);
    }
    try {
      final sessions = await widget.api.listSessions();
      if (!mounted) {
        return;
      }
      setState(() {
        _all = [
          for (final item in sessions)
            _SessionRow(
              sessionId: item.sessionId,
              title: item.title,
              updatedAt: item.updatedAt,
            ),
        ];
        // 静默刷新保持用户已翻到的行数，别把人拉回第一页
        _shown = _shown < _kPageSize ? _kPageSize : _shown;
        _loading = false;
        _openedId = ''; // 列表换了一批，别让位移状态挂在别人身上
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      if (silent) {
        return; // 静默刷新失败就保持旧列表，不打扰用户（下次退回本页还会再试）
      }
      setState(() => _loading = false);
      // 包一层 lambda 而不是直接传 _load：它现在带了可选具名参数，别让重试把 silent 的语义带进来
      await AiI18n.of(context).handleError(context, error, onRetry: () => _load());
    }
  }

  // ── 跳转 ─────────────────────────────────────────────────

  /// 点击会话：**push 一页新的聊天页**载入这条会话（返回键即原路退回本列表）。
  Future<void> _openSession(_SessionRow row) async {
    if (_navigating) {
      return; // 连点去重：否则会叠出两页一样的聊天页
    }
    // 有卡片正露着删除按钮：这一下先收起来，不跳转（对齐小程序 onSessionTap）
    if (_openedId.isNotEmpty) {
      setState(() => _openedId = '');
      return;
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
    // 刚聊过的那条标题/时间肯定变了
    _lastOpened = '';
    await _refreshTokenBalance();
    await _load(silent: true);
  }

  // ── 删除 ─────────────────────────────────────────────────

  /// 删除一条会话。接口是一次真实往返，慢的时候界面毫无反馈、用户会以为没点上而反复点
  /// （2026-08-10 需求 6）：加 loading 遮罩 + [_deleting] 闸，删除期间不再接第二次点击。
  Future<void> _deleteSession(_SessionRow row) async {
    if (_deleting) {
      return;
    }
    _deleting = true;
    AppLoadingDialog.show(context, AppL10n.of(context).galDeleting);
    try {
      await widget.api.deleteSession(row.sessionId);
      AppLoadingDialog.hide(context);
      if (!mounted) {
        return;
      }
      setState(() {
        _all = _all.where((item) => item.sessionId != row.sessionId).toList();
        if (row.sessionId == _currentId) {
          _currentId = '';
        }
        if (row.sessionId == _openedId) {
          _openedId = '';
        }
      });
      if (row.sessionId == _lastOpened) {
        _lastOpened = '';
      }
      AppToast.show(context, AppL10n.of(context).aiDeleted);
      // 清掉指向这条会话的「上次停在哪」记忆，否则下次点 AI 入口会打开一条已删会话
      AiLastSession.forget(row.sessionId);
      // 删的是某个聊天页正打开的会话：只通知那一页退回空态，避免用户继续往已删会话发消息。
      // 点对点通知（不是广播一个「谁看到谁消费」的标记），理由见 AiChatPage.notifySessionDeleted。
      // 也**不替他建新会话** —— 这是「没得可显示了」，不是用户要新建。
      AiChatPage.notifySessionDeleted(row.sessionId);
    } catch (error) {
      // 错误提示要盖在 loading 之上，所以先关遮罩再弹（hide 可重复调用，成功路径已关过）。
      AppLoadingDialog.hide(context);
      if (mounted) {
        await AiI18n.of(context).handleError(context, error);
      }
    } finally {
      AppLoadingDialog.hide(context);
      _deleting = false;
    }
  }

  /// 长按删除的兜底路径（左滑不便时仍可用），保留二次确认。
  /// 左滑露出的那颗红按钮是**点了就删**（对齐小程序 `onSessionDeleteTap`）——
  /// 它本身要「刻意滑开 + 再点一次」，已经够重了。
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

  // ── 左滑 ─────────────────────────────────────────────────

  void _onSwipeStart(_SessionRow row) {
    setState(() {
      _draggingId = row.sessionId;
      // 已经是打开态就从 -76 continue，不要一按下去就弹回 0
      _dragOffset = _openedId == row.sessionId ? -_kDeleteReveal : 0;
      _openedId = '';
    });
  }

  void _onSwipeUpdate(DragUpdateDetails details) {
    if (_draggingId.isEmpty) {
      return;
    }
    setState(() {
      _dragOffset = (_dragOffset + details.delta.dx).clamp(-_kDeleteReveal, 0.0);
    });
  }

  void _onSwipeEnd(DragEndDetails details, _SessionRow row) {
    if (_draggingId.isEmpty) {
      return;
    }
    final velocity = details.primaryVelocity ?? 0;
    final shouldOpen =
        velocity < -_kFlingVelocity ||
        (velocity <= _kFlingVelocity &&
            _dragOffset <= -_kDeleteReveal * _kOpenRatio);
    setState(() {
      _openedId = shouldOpen ? row.sessionId : '';
      _draggingId = '';
      _dragOffset = 0;
    });
  }

  void _onSwipeCancel() {
    if (_draggingId.isEmpty) {
      return;
    }
    setState(() {
      _draggingId = '';
      _dragOffset = 0;
    });
  }

  // ── UI ───────────────────────────────────────────────────

  /// ISO 时间 → 卡片右侧只显示 HH:mm；日期由分组标题承载（对齐小程序 formatTime）。
  String _formatTime(String iso) {
    final date = DateTime.tryParse(iso);
    if (date == null) {
      return '';
    }
    final local = date.toLocal();
    String pad(int n) => n < 10 ? '0$n' : '$n';
    return '${pad(local.hour)}:${pad(local.minute)}';
  }

  /// 分组标题：今天单列，其余「几月几日」；时间解析不出来的归到最后一组「更早」。
  String _dateLabel(String iso) {
    final l10n = AppL10n.of(context);
    final date = DateTime.tryParse(iso);
    if (date == null) {
      return l10n.aiSessionsTitle; // 极少见：时间字段坏了，标题至少不空
    }
    final local = date.toLocal();
    final now = DateTime.now();
    if (local.year == now.year &&
        local.month == now.month &&
        local.day == now.day) {
      return l10n.aiToday;
    }
    return l10n.aiMonthDay(local.month, local.day);
  }

  String _dateKey(String iso) {
    final date = DateTime.tryParse(iso)?.toLocal();
    if (date == null) {
      return 'unknown';
    }
    return '${date.year}-${date.month}-${date.day}';
  }

  /// 只给每组第一条写标题（对齐小程序 decorateGroups）。
  List<_SessionEntry> _decorateGroups(List<_SessionRow> rows) {
    final entries = <_SessionEntry>[];
    var previousKey = '';
    for (final row in rows) {
      final key = _dateKey(row.updatedAt);
      entries.add(
        _SessionEntry(
          row: row,
          groupLabel: key == previousKey ? '' : _dateLabel(row.updatedAt),
        ),
      );
      previousKey = key;
    }
    return entries;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final entries = _decorateGroups(_all.take(_shown).toList());
    return FigmaScreen(
      title: l10n.aiSessionsTitle,
      scrollable: false,
      bodyPadding: EdgeInsets.zero,
      // 「新建」2026-08-10 需求 1.2 由文字改为图标（与小程序 page-nav 的 right-icon 同一张图）。
      trailing: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _createNew,
        child: const SizedBox(
          width: 32,
          height: 32,
          child: Center(child: AiIcon('assets/images/ai-new-chat.png', size: 22)),
        ),
      ),
      body: Column(
        children: [
          // Token 余额（2026-08-10 需求 1.1）：占「仅保留最近 7 天」原来那一行，提示整体下移一行。
          // 聊天页顶栏那颗胶囊已撤（标题要真正屏幕居中，两者几何上放不下），这里是余额唯一展示位。
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: _buildTokenPill(),
            ),
          ),
          if (!_loading && entries.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 6),
              child: Row(
                children: [
                  const AiIcon('assets/images/ai-info.png', size: 13),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      l10n.aiKeep7Days,
                      style: const TextStyle(
                        color: Color(0xFF8B8B8B),
                        fontSize: 12.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: _loading
                ? const PageLoading()
                : (entries.isEmpty ? _buildEmpty() : _buildList(entries)),
          ),
        ],
      ),
    );
  }

  /// 星币余额胶囊（真实账户值，见 [AiToken]）。
  /// 与聊天页原先右上角那颗同一套视觉，这里靠左排、不与任何原生元素对位。
  ///
  /// 2026-08-13 同步小程序：整颗可点，右端补一个 `>`，直接进星币管理页 ——
  /// 余额看着不够时用户在这一页就能去看规则/记录，不用退回「我的」再找入口。
  /// 回来时 [_refreshTokenBalance] 重取余额，数字自动对上。
  /// 🔶 与小程序有意不同：小程序那颗指向「去购买」，App 的 IAP 未接，星币页是只读的。
  Widget _buildTokenPill() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () async {
        await Navigator.of(context).pushNamed(AppRoutes.starCoin);
        await _refreshTokenBalance();
      },
      child: _buildTokenPillBody(),
    );
  }

  Widget _buildTokenPillBody() {
    return Container(
      height: 29,
      padding: const EdgeInsets.fromLTRB(11, 0, 7, 0),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.94)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1A53493C),
            blurRadius: 7,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const AiIcon('assets/images/ai-token-spark.png', size: 12.5),
          const SizedBox(width: 4),
          Text(
            AiToken.displayBalance(_tokenBalance),
            style: const TextStyle(
              color: Color(0xFFFF6F25),
              fontSize: 14,
              fontWeight: FontWeight.w600,
              height: 1,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            // 2026-08-12 全站文案 Token → 星币（后端字段名不动）
            AppL10n.of(context).aiTokenUnit,
            style: const TextStyle(
              color: Color(0xFF777777),
              fontSize: 11,
              height: 1,
            ),
          ),
          const SizedBox(width: 2),
          const Icon(
            Icons.chevron_right_rounded,
            size: 15,
            color: Color(0xFF9A948C),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    final l10n = AppL10n.of(context);
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 150, 20, 0),
        child: Column(
          children: [
            const AiIcon('assets/images/ai-empty-sessions-art.png', size: 110),
            const SizedBox(height: 18),
            Text(
              l10n.aiNoSessions,
              style: const TextStyle(
                color: Color(0xFF2E2E2E),
                fontSize: 19,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 9),
            Text(
              l10n.aiNoSessionsDesc,
              style: const TextStyle(color: Color(0xFF929292), fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildList(List<_SessionEntry> entries) {
    final l10n = AppL10n.of(context);
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      itemCount: entries.length + (_hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= entries.length) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(0, 6, 0, 12),
            child: Text(
              l10n.aiPullToLoadMore,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFFAAA49C), fontSize: 11.5),
            ),
          );
        }
        final entry = entries[index];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (entry.groupLabel.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(0, 13, 0, 9),
                child: Row(
                  children: [
                    Container(
                      width: 3.5,
                      height: 14,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF762E),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      entry.groupLabel,
                      style: const TextStyle(
                        color: Color(0xFF292929),
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            _buildSwipeRow(entry.row),
          ],
        );
      },
    );
  }

  /// 一条会话：卡片与删除按钮同处一条「轨道」上一起位移，删除按钮从轨道右侧滑进来，
  /// 露出多少由外层 [ClipRect] 决定 —— 没左滑时它整块在轨道外，看不见。
  ///
  /// ⚠️ 别改成「删除按钮垫在卡片下面」：卡片是半透明毛玻璃（白 0.74），垫在底下的红色会直接
  /// 透出来，等于没滑就露出删除按钮（小程序 2026-07-31 踩过这个坑）。
  /// 代价是卡片那层很淡的投影也被裁掉，接受（0.07 透明度，肉眼几乎无差）。
  ///
  /// ⚠️⚠️ **2026-08-28 修「会话删不掉」**：这里原来是
  /// `OverflowBox(maxWidth: 卡片宽 + 8 + 80) → Row[卡片, 间距, 删除按钮]`，整条 Row 再一起
  /// `Transform.translate` 左移。画面完全正确，但**删除按钮一次也点不中**：
  /// Flutter 的命中测试到 [RenderBox.hitTest] 就会先判 `size.contains(position)`，
  /// 而 OverflowBox 自己的 size 只有卡片那么宽，删除按钮整块落在它的 size 之外 ——
  /// 溢出的部分**只画不接事件**。左滑能滑开、按钮看得见、点下去毫无反应，正是用户报的现象
  /// （长按卡片那条兜底路径没坏，所以不是接口的问题）。
  ///
  /// 改法：换成 `Stack` + `Positioned`，删除按钮按 `left = 卡片宽 + 间距 + 位移` 摆放。
  /// 它随位移一起进出轨道（视觉与原来逐像素一致），但**位移多少就有多少落在 Stack 自己的
  /// size 之内**，那一段就能正常命中；轨道外的部分照旧由 [ClipRect] 裁掉。
  Widget _buildSwipeRow(_SessionRow row) {
    final dragging = _draggingId == row.sessionId;
    final offset = dragging
        ? _dragOffset
        : (_openedId == row.sessionId ? -_kDeleteReveal : 0.0);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final cardWidth = constraints.maxWidth;
          return ClipRect(
            child: SizedBox(
              height: _kCardHeight,
              child: TweenAnimationBuilder<double>(
                tween: Tween<double>(end: offset),
                // 跟手拖动期间不要过渡，否则位移会慢半拍；松手才吸附
                duration: dragging
                    ? Duration.zero
                    : const Duration(milliseconds: 260),
                curve: Curves.easeOut,
                builder: (context, value, child) => Stack(
                  // 裁剪交给外层 ClipRect：这里若也裁，Stack 会在自己的 size 上再切一刀，
                  // 效果一样但多一层，且 clipBehavior 不影响命中测试（那由 size 决定）。
                  clipBehavior: Clip.none,
                  children: [
                    // 卡片：左滑手势挂在**卡片**上，不罩整条轨道（2026-08-10 需求 6）——
                    // 罩住轨道时，手指落在已滑开的删除按钮上也会被当成新一轮滑动，
                    // 点按时那一两像素的抖动就把卡片吸回去，表现同样是「点不动」。
                    // 只接横向拖动：纵向滚动仍归 ListView（手势竞技场按主轴分派）。
                    Positioned(
                      left: value,
                      top: 0,
                      bottom: 0,
                      width: cardWidth,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onHorizontalDragStart: (_) => _onSwipeStart(row),
                        onHorizontalDragUpdate: _onSwipeUpdate,
                        onHorizontalDragEnd: (details) =>
                            _onSwipeEnd(details, row),
                        onHorizontalDragCancel: _onSwipeCancel,
                        child: _buildCard(row),
                      ),
                    ),
                    // 删除按钮：位移为 0 时整块停在轨道右侧之外（left = 轨道宽 + 间距），
                    // 左滑多少就露出多少。
                    Positioned(
                      left: cardWidth + _kDeleteGap + value,
                      top: 0,
                      bottom: 0,
                      width: _kDeleteWidth,
                      child: _buildDeleteButton(row),
                    ),
                  ],
                ),
                // child 不再复用（两个子节点都依赖 value），传 null 即可。
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildCard(_SessionRow row) {
    final l10n = AppL10n.of(context);
    final active = row.sessionId == _currentId;
    final title = row.title.isEmpty ? l10n.aiNewChat : row.title;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _openSession(row),
      // 左滑之外保留长按删除兜底（与小程序一致）
      onLongPress: () => _confirmDelete(row),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 15),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: active ? 0.9 : 0.74),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: active
                ? const Color(0x57FF7E39)
                : Colors.white.withValues(alpha: 0.9),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFF5C5C5C),
                  fontSize: 14.5,
                  height: 1.2,
                ),
              ),
            ),
            const SizedBox(width: 11),
            Text(
              _formatTime(row.updatedAt),
              style: const TextStyle(color: Color(0xFF9A9A9A), fontSize: 14),
            ),
            const SizedBox(width: 11),
            const AiIcon('assets/images/ai-chevron-right.png', size: 12),
          ],
        ),
      ),
    );
  }

  Widget _buildDeleteButton(_SessionRow row) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      // 刻意不加二次确认：要走到这一步必须「先滑开、再点」，见 [_confirmDelete] 注释
      onTap: () => _deleteSession(row),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: ColoredBox(
          // #d9755f 是图没加载出来时的兜底底色（图本身就是这个红）
          color: const Color(0xFFD9755F),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.asset(
                'assets/images/ai-del-btn-bg.png',
                fit: BoxFit.fill,
                errorBuilder: (context, error, stackTrace) =>
                    const SizedBox.shrink(),
              ),
              Center(
                child: Text(
                  AppL10n.of(context).aiDelete,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
