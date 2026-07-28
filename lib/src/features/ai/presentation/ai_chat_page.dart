import 'dart:async';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../network/boltfox_api.dart';
import '../../../network/boltstar_ai_api.dart';
import '../../../routes/app_routes.dart';
import '../../../shared/ai_service_consent.dart';
import '../../../shared/l10n/app_l10n.dart';
import '../../../shared/widgets/app_dialog.dart';
import '../../../shared/widgets/app_toast.dart';
import '../../../shared/widgets/app_widgets.dart';
import '../../../shared/widgets/figma_common.dart';
import '../../../state.dart';
import '../../cast/cast_photo_picker.dart';
import '../../cast/presentation/cast_preview_page.dart';
import '../ai_i18n.dart';
import '../ai_image_compress.dart';
import 'ai_sessions_page.dart';

/// AI 对话（星宝）主界面。对齐小程序 `subpackages/ai/chat`
/// （需求：`assets/ai/支付&ai&官方图库.docx`「一、AI对话模块」；接口：`BoltStar-API-Doc-v2-1.0.4.md`）。
///
/// ## 会话创建时机（2026-07-25 用户二次拍板，改动前先看 [_AiChatPageState._createSession] 注释）
/// **只有「空态下发出第一条消息」才建会话**。进页面不建、点「新对话」不建（只把界面退回空态；
/// 已经在空态还点就提示「已经在新对话中」）、当前会话被别处删掉也只回空态。
/// 道理很简单：还没说一句话就先占一条会话，用户看看就走就是一条空会话，v1.0.4 起上限 20 条，占不起。
///
/// ## 已实现（与小程序一致）
/// - 招呼语默认态、用户右 / AI 左气泡流、占位三点 loading → **客户端打字机**、「停止生成」；
/// - **AI 回复的文字与图片渲染在同一个气泡里**（2026-07-27 需求 3）；图片按 `img_orientation`
///   预占高宽、加载完用真实尺寸校正，不会在加载完那一刻把上面的内容顶飞；
/// - 图文多模态（v1.0.3）：相册可多选（最多 4 张）→ **先压到 ~100KB** → 上传拿 URL →
///   缩略图**停在输入框内**（每张可删、上传中转圈）→ **必须配文字**一起发，随 `image_urls` 走
///   `/chat`，服务端按「张数 + 生图关键词」自行分流，前端不判关键词；
/// - 一键生图（漫画/风景/肖像/动漫 → img_style）+ 图片比例（竖/横/方 → img_orientation，必传）；
/// - 长按气泡→删除整条；长按 AI 气泡里的**某一张图**→下载 / 投屏 / 只删这一张。
///   投屏复用现有投屏链路（下载成本地文件后进预览页）；
/// - 无绑定设备拦截（文档 §5.5）、Token 余额展示 + 每次成功对话扣 1（**本地模拟**，支付未接）、
///   22002/22003 封禁弹窗 + 禁用输入 + 顶部横幅、20013 会话数达上限引导去清理。
///
/// ## 与小程序有意的差异（无对应端能力 / 平台机制不同）
/// - **语音输入**：小程序已接微信「同声传译」插件（按住说话、松手直发，动效盖住整个输入区）。
///   App 侧没有录音 + 语音转写能力（微信插件是小程序独有；App 要接得额外引入录音插件 +
///   第三方 STT 服务），本轮**不擅自加依赖**，按住仍只给同语义的占位提示。
/// - **保存到系统相册**：Flutter 无内置相册写入能力（需 gal / image_gallery_saver 之类插件），
///   「下载」先落到应用缓存目录并如实提示。
/// - **「停止生成」浮标**：小程序是 `position: fixed` 悬浮在输入区上方、会盖住正在打出来的最后两行
///   （2026-07-27 靠底部留白解决）；App 这颗是 Column 里的正常一行，不存在遮挡，无需对应处理。
/// - **页面栈**：小程序有 10 层硬上限，所以会话列表页跳聊天页带一套「栈快满就降级就地换会话」的
///   兜底；Flutter 没有这个限制，直接 push（见 [AiSessionsPage]）。
class AiChatPage extends StatefulWidget {
  const AiChatPage({
    super.key,
    required this.state,
    this.api,
    this.sessionId,
    this.sessionTitle,
  });

  final PhotoFrameState state;

  /// 复用调用方已有的接口实例（会话列表页 push 新聊天页时传）。缺省自己建一个 ——
  /// 反正 user_id 由登录用户决定，两者等价，传进来只是省一个对象。
  final BoltStarAiApi? api;

  /// 从会话列表 / 深链进来时带上；缺省则停在「新对话」空态（**不建会话**）。
  final String? sessionId;
  final String? sessionTitle;

  /// 某条会话被删掉了：通知**正打开着这条会话**的聊天页退回空态，
  /// 免得用户继续往已删会话发消息。
  ///
  /// 对齐小程序 2026-07-25 的点对点通知（`sessions.js` 用 `getCurrentPages()` 找出那一页直接调
  /// `resetFromList()`）。为什么不能用「弹一个全局标记、谁先看到谁消费」：会话列表现在打开会话是
  /// **push 一个新聊天页**，于是「删掉会话 A → 紧接着打开会话 B」时，新页会把本该给下层那页的
  /// 标记吃掉，B 刚载入就被清成空白页。点对点则只命中该命中的那一页。
  static void notifySessionDeleted(String sessionId) {
    for (final page in _livePages.toList()) {
      page._handleSessionDeleted(sessionId);
    }
  }

  @override
  State<AiChatPage> createState() => _AiChatPageState();
}

/// 当前活着的聊天页实例（页面栈里可能同时躺着好几个：每从会话列表打开一条会话就多一个）。
final Set<_AiChatPageState> _livePages = <_AiChatPageState>{};

/// 打字机（2026-07-27 优化顺滑度）。原实现是 `Timer.periodic(30ms)` 每帧追 3 字 —— 30ms 一跳、
/// 一跳 3 字，肉眼能看出「一顿一顿」。现在按 ~60fps 出字、每帧尽量只追 1 字：
/// - [_kTypeTick] 16ms ≈ 一帧，用**递归 Timer** 自计时（`Timer.periodic` 遇上 setState 慢会堆帧，
///   追上来时一次吐一大段，就是那种「卡一下、蹦一截」的观感）；
/// - 每帧字数 = `max(1, ceil(总字数 / _kTypeMaxTicks))`，长回复自动加快，整段最长 ~6.7s 打完。
const Duration _kTypeTick = Duration(milliseconds: 16);
const int _kTypeMaxTicks = 420;

/// 打字期间贴底的节流间隔：每帧都滚会和出字的 setState 抢主线程，反而更卡。
/// 80ms 一次 ≈ 落后不到 5 个字，打完还会强制贴一次底。
const Duration _kStickThrottle = Duration(milliseconds: 80);

/// 距底多少逻辑像素以内算「还贴着底」。用户主动往上翻看历史时就别再把他拽回来了。
const double _kStickPx = 60;

/// 图文多模态一次最多带 4 张图（文档 v1.0.3；超出服务端回 20012）。
const int _kMaxImages = 4;

/// 会话标题截断长度：v1.0.4 §二「首条用户消息前 20 字自动填充，默认『新对话』」。
/// 本地同步标题时按同一规则截，避免列表页重拉后标题突然变短、两处对不上。
const int _kSessionTitleMax = 20;

/// Token 余额本地模拟（支付体系未接）：接入真实接口后把读写换成后端调用即可。
const String _kTokenPrefsKey = 'aiTokenBalanceDemo';
const int _kTokenDefault = 100;

/// 一键生图风格（需求文案：漫画/风景/肖像/动漫；API 值：cartoon/landscape/portrait/anime）。
const List<String> _kStyleKeys = ['cartoon', 'landscape', 'portrait', 'anime'];

/// 图片比例（需求：竖向/横向/方形；API `img_orientation` 必传，只认这三个值）。
const List<String> _kOrientationKeys = ['vertical', 'horizontal', 'square'];

/// 方向 → 图片占位比例（**高/宽×100**，2026-07-27 需求 1.2）：图片没加载完时先按已知比例把高度
/// 占住，加载完不会把上面的内容顶飞。
///
/// ⚠️ 比例来源：按 API 文档 v1.0.4 §四/§参数速查表的**实际出图尺寸**算 ——
///    vertical 1104×1472(3:4) / horizontal 1472×1104(4:3) / square 1328×1328(1:1)。
///    用户口述的是 `{square 1:1, landscape 16:9, portrait 9:16}`，与文档的 4:3 / 3:4 **不一致**，
///    待后端确认到底出哪种。无论哪种都不会出错 —— 图片加载完会用**真实尺寸**改写这个比例
///    （见 [_AiBubbleImage]）；文档若变了只需改下面三个数（16:9/9:16 → 横 56.25 / 竖 177.78）。
const Map<String, double> _kOrientationPad = {
  'vertical': 133.33,
  'horizontal': 75,
  'square': 100,
};

/// 「landscape/portrait」这套叫法归一化到接口认的三个值。接口只认
/// horizontal/square/vertical（文档 §八 20007 `INVALID_IMAGE_ORIENTATION` 明确写了），
/// 传别名过去必定报错，所以在发请求前统一映射一次。
const Map<String, String> _kOrientationAlias = {
  'landscape': 'horizontal',
  'portrait': 'vertical',
  '1:1': 'square',
  '16:9': 'horizontal',
  '9:16': 'vertical',
};

/// 历史消息取不到方向时按默认的竖向占位。
const double _kPadDefault = 133.33;
const double _kPadMin = 40; // 过于扁/长的图钳一下，免得占位盒把整屏撑没了
const double _kPadMax = 240;

double _clampPad(double? pad) {
  // ⚠️ 必须写成 `final double value`：不给上下文类型时 `pad ?? 0` 的静态类型是 num
  //（double? 与 int 的 LUB），num.clamp 也回 num，返回 double 就编译不过。
  final double value = pad ?? 0;
  if (!(value > 0)) {
    return _kPadDefault;
  }
  return value.clamp(_kPadMin, _kPadMax);
}

/// 由宽高算占位比例；拿不到尺寸返回 null，交给调用方决定用不用默认值。
double? _padFromSize(num? width, num? height) {
  final w = (width ?? 0).toDouble();
  final h = (height ?? 0).toDouble();
  if (w <= 0 || h <= 0) {
    return null;
  }
  return _clampPad(h / w * 100);
}

/// 消息种类。`rich` = AI 回复：文字与图片**同一个气泡**（2026-07-27 需求 3）。
/// `image` 只用于用户侧的纯图气泡（需求 6.3：用户侧维持现状不变）。
enum _MsgKind { text, image, rich }

/// 气泡里的一张图。[serverId] 只有历史消息才有（本轮新产生的接口未回 id）；
/// [pad] 是占位比例（高/宽×100），加载完会被真实尺寸改写。
class _AiImage {
  _AiImage({required this.url, this.serverId, double? pad})
    : pad = _clampPad(pad);

  final String url;
  final String? serverId;
  double pad;
}

/// 一条消息。[serverId] 只有历史消息才有。
///
/// AI 回复恒为 [_MsgKind.rich]：一次回复里的文字和图**必须同一个气泡**，所以图不再各自成一条
/// 消息，而是挂在同一条消息的 [images] 上。历史消息里连着的 assistant 图片行也会并回它前面那条
/// （见 [_AiChatPageState._buildHistoryMessages]），保证重进会话与刚回复时长得一样。
class _AiMessage {
  _AiMessage({
    required this.id,
    required this.role,
    required this.kind,
    this.content = '',
    this.serverId,
    this.loading = false,
    this.typing = false,
    List<_AiImage>? images,
  }) : images = images ?? <_AiImage>[];

  final int id;
  final String role;
  final _MsgKind kind;
  String content;
  final String? serverId;
  final List<_AiImage> images;
  bool loading;
  bool typing;

  bool get isUser => role == 'user';
}

/// 输入框内待发送的图片（v1.0.3 §5.1.4）。
///
/// [pad] 是发出去后用户图片气泡的占位比例（需求 5.2）：小程序能直接从相册回的宽高算，
/// App 的 `CastPhotoPicker` 只回路径，所以这里取**压缩时顺手带回来的像素尺寸**
/// （压缩必然要解码一次，白拿）。原图本来就够小时不解码 → 仍为 null，气泡退回默认比例、
/// 等图加载完再校正。
class _PendingImage {
  _PendingImage({required this.id, required this.path});

  final int id;
  final String path;
  double? pad;
  String url = '';
  bool uploading = true;
}

class _AiChatPageState extends State<AiChatPage> {
  late final BoltStarAiApi _api =
      widget.api ??
      BoltStarAiApi(userId: BoltStarAiApi.userIdOf(widget.state.currentUser.id));

  final ScrollController _scroll = ScrollController();
  final TextEditingController _input = TextEditingController();

  final List<_AiMessage> _messages = [];
  final List<_PendingImage> _pending = [];

  String _sessionId = '';
  String _sessionTitle = '';
  int _tokenBalance = _kTokenDefault;

  bool _historyLoading = false;

  /// 首屏「先渲染 → 贴底 → 再显形」用（需求 5.1）：false 时消息列表**已渲染但透明**。
  /// 必须已渲染 —— 没有布局就没法滚到底；显形放在贴底之后，用户就看不到那一下
  /// 「从最老一条一路飞到最新」的下滑。
  bool _chatReady = true;

  bool _sending = false;
  bool _banned = false;
  bool _voiceMode = false;
  bool _showTools = false;
  String _orientation = 'vertical'; // 默认竖向（电子相框主流为竖屏）

  int _uid = 0;
  int _pid = 0;
  Timer? _typeTimer;
  AiCall<AiChatReply>? _chatCall;

  /// 在途的建会话请求，用于连点发送时去重（见 [_createSession]）。
  Future<void>? _createReq;

  /// AI 服务协议弹窗在途去重：首次进入与发送动作不能叠出两层弹窗。
  Future<bool>? _consentPrompt;

  /// 视图是否还贴着底（用户上翻看历史时置 false，见 [_onScroll]）。
  bool _stick = true;
  DateTime _lastStickAt = DateTime.fromMillisecondsSinceEpoch(0);

  AiI18n get _ai => AiI18n.of(context);

  /// 已经停在「新对话」空态：没有会话、也没有任何消息。
  /// ⚠️ 判据是「有没有开始对话」，**不看输入框草稿** —— 用户打了字还没发，仍算在新对话中，
  /// 这时点「新对话」只提示、不清草稿（清了等于让人白打一遍）。
  bool get isPristineNewSession => _sessionId.isEmpty && _messages.isEmpty;

  @override
  void initState() {
    super.initState();
    _livePages.add(this);
    _scroll.addListener(_onScroll);
    _sessionId = widget.sessionId ?? '';
    _sessionTitle = widget.sessionTitle ?? '';
    _loadTokenBalance();
    // 带 sessionId 进来（会话列表 / 深链）才载入那条会话；否则停在「新对话」空态，
    // **不建会话**（建会话的唯一时机见 _createSession 注释）。
    if (_sessionId.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _openSession(_sessionId));
    }
    // 首次进入先确认 AI 服务协议，再检查设备绑定，避免两层弹窗互相覆盖。
    // 不同意仍可正常查看与输入；发送时会再次引导，直到当前用户同意。
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _ensureAiServiceConsent(sendAttempt: false);
      if (mounted) {
        await _checkDeviceBound();
      }
    });
  }

  @override
  void dispose() {
    _livePages.remove(this);
    _stopGenerate(silent: true);
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    _input.dispose();
    super.dispose();
  }

  // ── 会话 ─────────────────────────────────────────────────

  Future<void> _loadTokenBalance() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getInt(_kTokenPrefsKey) ?? _kTokenDefault;
    if (mounted) {
      setState(() => _tokenBalance = value);
    }
  }

  /// 建会话（`POST /session/new`）。**只有一个触发点**（2026-07-25 用户二次拍板）：
  /// 用户在「新对话」空态发出第一条消息（[_onSendTap] / [_sendChat] 里「没有 sessionId 就先建」）。
  /// 进页面、点「新对话」、当前会话被删，**一律只重置界面不建** —— 任何「还没说一句话就先占一条
  /// 会话」的做法都会留下空会话，v1.0.4 起每用户上限 20 条，占不起。
  ///
  /// 在途去重（[_createReq]）：发送按钮连点时两次 [_onSendTap] 都会看到 `_sessionId` 仍为空，
  /// 不去重就会建出两条会话、后一条还是空的。复用同一个 future，连点只建一条。
  Future<void> _createSession() {
    // `??=` 只在为空时才求值右侧，所以在途期间所有调用方拿到的是同一个 future
    return _createReq ??= _doCreateSession().whenComplete(() => _createReq = null);
  }

  Future<void> _doCreateSession() async {
    try {
      final session = await _api.newSession();
      if (!mounted) {
        return;
      }
      setState(() {
        _sessionId = session.sessionId;
        _sessionTitle = session.title.isNotEmpty
            ? session.title
            : AppL10n.of(context).aiNewChat;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      // 建会话失败不阻塞界面（招呼语照常显示），下次发送会再试
      await _ai.handleError(
        context,
        error,
        onRetry: _createSession,
        // 20013 会话数已达上限（20 个，v1.0.4 §5.2）：重试没用，把人送到会话列表页删旧的
        onSessionLimit: _goSessions,
      );
    }
  }

  /// 打开历史会话并拉取消息。历史超 7 天已清除时接口回 10001，按文档 toast `info.10001`。
  Future<void> _openSession(String sessionId) async {
    setState(() {
      _sessionId = sessionId;
      _historyLoading = true;
      _chatReady = false; // 载入期间消息列表保持隐形，等定位到底部再显形（需求 5.1）
    });
    try {
      final history = await _api.getHistory(sessionId, pageSize: 100);
      if (!mounted) {
        return;
      }
      if (history.expired) {
        AppToast.show(context, _ai.t('info.10001'));
      }
      final list = _buildHistoryMessages(history.list);
      setState(() {
        _messages
          ..clear()
          ..addAll(list);
        _historyLoading = false;
      });
      // 需求 5.1 的全部要点就是这个顺序：**先渲染 → 再贴底 → 最后显形**，一层都不能省。
      // 两次 postFrame：第一帧消息才刚有布局（才滚得动），第二帧贴底已经落地（才能显形）。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        if (_scroll.hasClients) {
          _scroll.jumpTo(_scroll.position.maxScrollExtent);
        }
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            setState(() => _chatReady = true);
          }
        });
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _historyLoading = false;
        _chatReady = true;
      });
      await _ai.handleError(
        context,
        error,
        onRetry: () => _openSession(sessionId),
      );
    }
  }

  /// 历史消息 → 页面消息模型。两件事：
  /// ① assistant 的图片行**并回它前面那条 assistant 消息**（需求 3：一次回复的图文同一个气泡）。
  ///    一轮对话 = 1 条 user + 1 条 assistant（文字）+ N 条 assistant（图），所以「连着的
  ///    assistant 行属于同一轮」这个前提成立，不会把两轮回复并到一起。
  /// ② 用户侧维持原样（需求 6.3）：文字一条、图片一条，各自成气泡。
  List<_AiMessage> _buildHistoryMessages(List<AiHistoryItem> rows) {
    final messages = <_AiMessage>[];
    for (final row in rows.reversed) {
      final isImage = RegExp(r'^https?://').hasMatch(row.content);
      final isUser = row.role == 'user';
      if (!isUser && isImage) {
        final last = messages.isEmpty ? null : messages.last;
        if (last != null && !last.isUser && last.kind == _MsgKind.rich) {
          last.images.add(_AiImage(url: row.content, serverId: row.id));
          continue;
        }
        // 前面没有可挂的文字气泡（纯图回复）：自己起一条无文字的 rich
        messages.add(
          _AiMessage(
            id: ++_uid,
            role: row.role,
            kind: _MsgKind.rich,
            images: [_AiImage(url: row.content, serverId: row.id)],
          ),
        );
        continue;
      }
      messages.add(
        _AiMessage(
          id: ++_uid,
          serverId: row.id,
          role: row.role,
          kind: isUser
              ? (isImage ? _MsgKind.image : _MsgKind.text)
              : _MsgKind.rich,
          content: isImage ? '' : row.content,
          // 用户图片消息：serverId 已记在消息本身上，images[0] 就别再记一遍，
          // 否则删这条会对同一个 message_id 打两次 DELETE
          images: isImage ? [_AiImage(url: row.content)] : null,
        ),
      );
    }
    return messages;
  }

  /// 无绑定设备拦截（文档 §5.5）。查询失败（未登录/网络异常）不拦截。
  Future<void> _checkDeviceBound() async {
    if (widget.state.devices.isNotEmpty || !mounted) {
      return;
    }
    try {
      await widget.state.refreshDevices();
    } catch (_) {
      return;
    }
    if (!mounted || widget.state.devices.isNotEmpty) {
      return;
    }
    final l10n = AppL10n.of(context);
    final go = await showAppConfirmDialog(
      context,
      title: l10n.tipTitle,
      message: l10n.aiBindDeviceFirst,
      icon: Icons.devices_other_rounded,
      confirmLabel: l10n.aiGoBind,
      cancelLabel: l10n.aiBack,
    );
    if (!mounted) {
      return;
    }
    // 无论选哪个都退出 AI 页：没有已绑定设备时本页不可用。
    // ⚠️ 与小程序的差异：小程序「去绑定」直接跳绑定页；App 的绑定流程是**首页内嵌浮层**
    //（`home_page` 的 _startScan/BindDeviceFlow），没有可 push 的独立路由，
    // 所以这里只能退回上一页由用户在首页「添加设备」入口绑定。
    Navigator.of(context).pop(go == true);
  }

  /// 检查当前登录用户是否已同意 AI 服务协议；未同意时弹出多语种确认框。
  ///
  /// 同意状态由 [AiServiceConsent] 按用户 ID 隔离。缓存丢失、切换账号、退出、
  /// 注销或登录态失效后都会重新确认。拒绝不禁用输入，只让本次发送原样返回。
  Future<bool> _ensureAiServiceConsent({required bool sendAttempt}) async {
    final userId = widget.state.currentUser.id.trim();
    if (userId.isEmpty) {
      if (sendAttempt && mounted) {
        AppToast.warn(context, AppL10n.of(context).aiServiceAgreementRequired);
      }
      return false;
    }
    if (await AiServiceConsent.isAccepted(userId)) {
      return true;
    }
    if (!mounted) {
      return false;
    }
    final pending = _consentPrompt;
    if (pending != null) {
      return pending;
    }
    final request = _showAiServiceConsentDialog(
      userId: userId,
      sendAttempt: sendAttempt,
    );
    _consentPrompt = request;
    try {
      return await request;
    } finally {
      if (identical(_consentPrompt, request)) {
        _consentPrompt = null;
      }
    }
  }

  Future<bool> _showAiServiceConsentDialog({
    required String userId,
    required bool sendAttempt,
  }) async {
    final l10n = AppL10n.of(context);
    final accepted = await showAppConfirmDialog(
      context,
      title: sendAttempt
          ? l10n.aiServiceAgreementRequired
          : l10n.aiServiceAgreementTitle,
      message: l10n.aiServiceAgreementSummary,
      icon: Icons.auto_awesome_rounded,
      confirmLabel: l10n.agree,
      cancelLabel: l10n.disagree,
      messageTextAlign: TextAlign.left,
      barrierDismissible: false,
    );
    if (accepted != true) {
      return false;
    }
    final saved = await AiServiceConsent.accept(userId);
    if (!saved && mounted) {
      AppToast.warn(context, l10n.aiServiceAgreementRequired);
    }
    return saved;
  }

  /// 打开会话列表。列表页自己 push 新的聊天页（所以从那儿进去的会话，返回键**原路退回列表**，
  /// 对齐小程序 2026-07-25 的「原路径返回」）；本页只管把它推上去。
  Future<void> _goSessions() async {
    await Navigator.of(context).push<void>(
      AppPageRoute<void>(
        builder: (_) => AiSessionsPage(
          state: widget.state,
          api: _api,
          currentId: _sessionId,
          // 快照即可：本页被列表页盖住期间不会变（用来决定点「新建对话」是退回本页还是叠新页）
          openerPristine: isPristineNewSession,
        ),
      ),
    );
  }

  /// 回到「新对话」空态：清消息/输入/待发图，sessionId 置空（招呼语随之显示）。
  /// 只动本地状态，**不碰服务端** —— 建不建会话由调用方决定（而且只认「首次发送」）。
  void _resetToNewSession() {
    _stick = true; // 别把上一条会话「用户翻上去了」的状态带过来
    setState(() {
      _messages.clear();
      _sessionTitle = AppL10n.of(context).aiNewChat;
      _sessionId = '';
      _banned = false;
      // 刚被 _stopGenerate(silent: true) 掐掉在途回复时它不动 _sending，
      // 漏了这一下这一页会永远停在「正在回复中」、再也发不出消息
      _sending = false;
      _pending.clear();
      _input.clear();
      // 有可能是在某条会话「还没定位完」时被重置的（正载入时列表页把这条删了），
      // 漏了这一下招呼语就一直透明着，看着像白屏
      _chatReady = true;
    });
  }

  /// 本页打开着的会话在别处（会话列表页）被删了：退回空态，免得用户继续往已删会话发消息。
  /// **不建会话** —— 这是「没得可显示了」，不是用户要新建。
  void _handleSessionDeleted(String sessionId) {
    if (!mounted || sessionId.isEmpty || sessionId != _sessionId) {
      return;
    }
    _stopGenerate(silent: true);
    _resetToNewSession();
  }

  /// 「新对话」按钮：**只把界面退回空态，不建会话**（见 [_createSession]）。
  void _startNewSession() {
    if (_sending) {
      return;
    }
    if (isPristineNewSession) {
      AppToast.show(context, AppL10n.of(context).aiAlreadyNewChat);
      return;
    }
    _stopGenerate(silent: true);
    _resetToNewSession();
  }

  // ── 发送 ─────────────────────────────────────────────────

  Future<void> _onSendTap() async {
    if (_sending || _banned) {
      return;
    }
    final text = _input.text.trim();
    // 纯图片不可发（v1.0.3 §5.1.4 状态机）：必须配文字一起发送
    if (text.isEmpty) {
      AppToast.show(
        context,
        _pending.isEmpty
            ? _ai.t('error.20005')
            : AppL10n.of(context).aiNeedTextWithImages,
      );
      return;
    }
    if (!await _ensureAiServiceConsent(sendAttempt: true) || !mounted) {
      return; // 草稿和待发图片保持不变；下次发送继续引导
    }
    // 还有图片在上传：等 URL 就绪再发，否则 image_urls 会缺图
    if (_pending.any((item) => item.uploading)) {
      AppToast.show(context, AppL10n.of(context).aiImageUploading);
      return;
    }
    final images = [
      for (final item in _pending)
        if (item.url.isNotEmpty) _AiImage(url: item.url, pad: item.pad),
    ];
    // 先把会话建出来，**再清输入框**。顺序不能反：建会话可能失败（网络异常 / 20013 会话已达上限），
    // 先清的话用户打的字和选的图就白没了 —— 而「首次发送才建会话」之后，每轮新对话的第一条都走这。
    if (_sessionId.isEmpty) {
      await _createSession();
      if (!mounted || _sessionId.isEmpty) {
        return; // 错误提示已由 _createSession 弹出；草稿原样留着，用户可直接重发
      }
    }
    setState(() {
      _input.clear();
      _pending.clear();
    });
    await _sendChat(text, images: images);
  }

  /// 发送对话 / 一键生图 / 图文多模态。先把用户消息（图片气泡 + 文字气泡）上屏，
  /// 再交给 [_dispatchChat] 发请求——这样 30xxx 重试只重发请求、不重复堆用户气泡。
  Future<void> _sendChat(
    String message, {
    String? styleKey,
    List<_AiImage> images = const [],
  }) async {
    if (_sending || _banned) {
      return;
    }
    if (!await _ensureAiServiceConsent(sendAttempt: true) ||
        !mounted ||
        !_guardToken()) {
      return;
    }
    // 空态下发出第一条消息，这时才真正建会话——**全项目唯一的建会话时机**。
    // [_onSendTap] 走到这之前已经建过了（它要先建再清输入框），这里主要给「一键生图」兜底；
    // [_createSession] 自带在途去重，重复调不会多建。
    if (_sessionId.isEmpty) {
      await _createSession();
      if (!mounted || _sessionId.isEmpty) {
        return;
      }
    }
    final newChatTitle = AppL10n.of(context).aiNewChat;
    setState(() {
      // 用户消息：先按张追加图片气泡，再追加文字气泡（需求 6.3 用户侧维持原样）
      for (final image in images) {
        _messages.add(
          _AiMessage(
            id: ++_uid,
            role: 'user',
            kind: _MsgKind.image,
            images: [image],
          ),
        );
      }
      _messages.add(
        _AiMessage(
          id: ++_uid,
          role: 'user',
          kind: _MsgKind.text,
          content: message,
        ),
      );
      // 首条消息后标题自动变为首条内容（与后端 session.title 行为一致，本地同步免重拉）。
      // v1.0.4 §二明确后端只取**前 20 字**，这里同样截断，免得列表页重拉后标题突然变短对不上。
      if (_sessionTitle.isEmpty || _sessionTitle == newChatTitle) {
        _sessionTitle = message.length > _kSessionTitleMax
            ? message.substring(0, _kSessionTitleMax)
            : message;
      }
    });
    _stickToBottom(force: true, animate: true);
    await _dispatchChat(
      message,
      styleKey,
      images.map((image) => image.url).toList(),
    );
  }

  /// 归一化到接口认的三个值（horizontal/square/vertical）。别名见 [_kOrientationAlias]，
  /// 认不出来就退回默认竖向 —— 传个空/错值过去会被服务端回 20006/20007，白跑一趟。
  String get _normalizedOrientation {
    final key = _orientation.toLowerCase();
    final mapped = _kOrientationAlias[key] ?? key;
    return _kOrientationPad.containsKey(mapped) ? mapped : 'vertical';
  }

  /// 当前方向对应的图片占位比例（高/宽×100），生图回来时先按它把气泡里的图占好高度。
  double get _orientationPad =>
      _clampPad(_kOrientationPad[_normalizedOrientation]);

  /// 发一次 `/chat` 并渲染回复（可被「重试」重复调用，不再追加用户气泡）。
  Future<void> _dispatchChat(
    String message,
    String? styleKey,
    List<String> urls,
  ) async {
    // 占位气泡就是最终那一个气泡：文字打进它的 content、图片挂进它的 images（需求 3：图文同一气泡）
    final holder = _AiMessage(
      id: ++_uid,
      role: 'assistant',
      kind: _MsgKind.rich,
      loading: true,
    );
    setState(() {
      _messages.add(holder);
      _sending = true;
    });
    _stickToBottom(force: true, animate: true);

    try {
      final call = _api.chat(
        sessionId: _sessionId,
        message: message,
        imgOrientation: _normalizedOrientation,
        imgStyle: styleKey,
        imageUrls: urls,
      );
      _chatCall = call;
      final reply = await call.future;
      _chatCall = null;
      if (!mounted) {
        return;
      }
      _spendToken();
      _renderReply(holder.id, reply.text, reply.images);
    } catch (error) {
      _chatCall = null;
      if (!mounted) {
        return;
      }
      setState(() {
        _messages.removeWhere((item) => item.id == holder.id);
        _sending = false;
      });
      if (error is AiApiException && error.aborted) {
        return; // 用户主动停止，静默
      }
      await _ai.handleError(
        context,
        error,
        onRetry: () => _dispatchChat(message, styleKey, urls),
        onBanned: (_) => setState(() => _banned = true),
      );
    }
  }

  /// 回复渲染（需求 3：文字与图片渲染进**同一个气泡**）：文字走打字机，图片打完字后挂到
  /// 同一条消息的 images 上。图片先按当前 `img_orientation` 占好高度（需求 1.2），
  /// 加载完再用真实尺寸校正（见 [_AiBubbleImage]）。
  void _renderReply(int holderId, String text, List<String> images) {
    final pad = _orientationPad;
    final replyImages = [
      for (final url in images)
        if (url.isNotEmpty) _AiImage(url: url, pad: pad),
    ];

    final index = _messages.indexWhere((item) => item.id == holderId);
    if (index < 0) {
      setState(() => _sending = false);
      return;
    }

    if (text.isEmpty) {
      // 只有图没有文字：占位气泡直接变成图片气泡（仍是同一个气泡）
      setState(() {
        _messages[index]
          ..loading = false
          ..typing = false
          ..images.addAll(replyImages);
        _sending = false;
      });
      _stickToBottom(force: true, animate: true);
      return;
    }

    setState(() {
      _messages[index]
        ..loading = false
        ..typing = true;
    });
    _startTyping(holderId, text, replyImages);
  }

  /// 客户端打字机。两点与旧实现不同（2026-07-27 需求 2.1「再顺滑一点」）：
  /// ① **递归 Timer** 而非 `Timer.periodic` —— setState 偶尔慢一点时 periodic 会堆帧、
  ///    追上来时一次吐一大段（就是那种「卡一下、蹦一截」的观感）；自计时永远「渲染完再排下一帧」。
  /// ② 切字用 `runes` 而不是 `split('')`：后者按 UTF-16 **码元**切，会把 emoji / 生僻字的
  ///    代理对劈成两半，打到一半那一帧渲染出乱码方块 —— 星宝回复里 ✨ 之类相当常见。
  void _startTyping(int holderId, String text, List<_AiImage> replyImages) {
    final chars = text.runes.map(String.fromCharCode).toList();
    final perTick = (chars.length / _kTypeMaxTicks).ceil().clamp(1, chars.length);
    final buffer = StringBuffer();
    var pos = 0;

    void step() {
      _typeTimer = null;
      if (!mounted) {
        return;
      }
      // 打字期间用户可能删掉了前面的消息导致下标变化，每帧按 id 重新定位
      final index = _messages.indexWhere((item) => item.id == holderId);
      if (index < 0) {
        setState(() => _sending = false);
        return;
      }
      if (pos >= chars.length) {
        setState(() {
          _messages[index]
            ..typing = false
            ..images.addAll(replyImages);
          _sending = false;
        });
        _stickToBottom(force: true, animate: true);
        return;
      }
      final end = pos + perTick > chars.length ? chars.length : pos + perTick;
      buffer.writeAll(chars.getRange(pos, end));
      pos = end;
      setState(() => _messages[index].content = buffer.toString());
      _stickToBottom(); // 内部按 _kStickThrottle 节流，并尊重「用户已上翻」
      _typeTimer = Timer(_kTypeTick, step);
    }

    _typeTimer?.cancel();
    step();
  }

  /// 停止生成：中断请求 + 结束打字机（已打出的内容保留）。
  /// [silent] 用于切会话 / 页面销毁时的清理（**不动 `_sending`**，调用方自己归位）。
  void _stopGenerate({bool silent = false}) {
    _chatCall?.abort();
    _chatCall = null;
    _typeTimer?.cancel();
    _typeTimer = null;
    if (silent || !mounted) {
      return;
    }
    setState(() {
      _messages.removeWhere((item) => item.loading);
      for (final item in _messages) {
        item.typing = false;
      }
      _sending = false;
    });
  }

  /// Token 权限控制（文档 §5.5）：不足时弹窗引导购买并拦截 AI 调用。
  bool _guardToken() {
    if (_tokenBalance > 0) {
      return true;
    }
    final l10n = AppL10n.of(context);
    showAppConfirmDialog(
      context,
      title: l10n.aiTokenEmptyTitle,
      message: l10n.aiTokenEmptyMessage,
      icon: Icons.toll_rounded,
      showCancel: false,
      confirmLabel: l10n.otaKnow,
    );
    return false;
  }

  Future<void> _spendToken() async {
    final balance = (_tokenBalance - 1).clamp(0, 1 << 30);
    if (mounted) {
      setState(() => _tokenBalance = balance);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kTokenPrefsKey, balance);
  }

  // ── 工具面板 ──────────────────────────────────────────────

  /// ＋ 工具栏「点外面就收起」（对齐小程序 2026-07-27 的 `closeTools`）。三个入口共用：
  /// 点消息区任意位置、点顶部工具行、输入框获得焦点（键盘和工具栏不该同时占着底部）。
  ///
  /// ⚠️ 故意**不做**全屏透明遮罩：遮罩会把拖动一起吃掉，工具栏开着时聊天记录就滑不动了。
  /// 挂在容器上的 onTap 只吃点击，滚动照常交给 ListView（手势竞技场里拖动归可滚动组件）。
  /// 气泡里的图有自己的 onTap（要看大图），点图不会收工具栏 —— 与小程序一致，是有意的。
  void _closeTools() {
    if (_showTools) {
      setState(() => _showTools = false);
    }
  }

  Future<void> _pickImages({required bool camera}) async {
    setState(() => _showTools = false);
    if (_banned) {
      return;
    }
    final remain = _kMaxImages - _pending.length;
    if (remain <= 0) {
      AppToast.show(context, AppL10n.of(context).aiMaxImages);
      return;
    }
    List<String> files;
    try {
      files = camera
          ? await CastPhotoPicker.takePhoto()
          : await CastPhotoPicker.pickFromAlbum(limit: remain);
    } catch (_) {
      return; // 用户取消选图
    }
    if (!mounted || files.isEmpty) {
      return;
    }
    // 客户端兜底拦截超限（部分机型相册不严格限制张数）
    if (files.length > remain) {
      files = files.sublist(0, remain);
      AppToast.show(context, AppL10n.of(context).aiMaxImages);
    }
    // 先各插一张 uploading 缩略图占位，再逐张上传回填 URL（单张失败只移除该张）
    final items = files
        .map((path) => _PendingImage(id: ++_pid, path: path))
        .toList();
    setState(() => _pending.addAll(items));
    for (final item in items) {
      unawaited(_uploadPending(item));
    }
  }

  /// 单张上传：**先压到 ~100KB**（需求 1.1）再传。AI 只需要看清内容，原图动辄 3~8MB，
  /// 纯粹在浪费上传时间和流量；压缩失败/压不动会原样返回原图（见 [AiImageCompress.toTarget]），
  /// 绝不因此发不出图。
  Future<void> _uploadPending(_PendingImage item) async {
    try {
      final shrunk = await AiImageCompress.toTarget(item.path);
      // 压缩是异步的，压完先确认这张还在（用户可能已经点 ✕ 删了）
      if (!mounted || !_pending.contains(item)) {
        return;
      }
      // 顺手把像素尺寸变成占位比例，发出去后气泡就不用等图加载完才知道多高（需求 5.2）
      item.pad = _padFromSize(shrunk.width, shrunk.height);
      final uploaded = await BoltFoxApi.setFileUpload([shrunk.path]);
      final url = _extractUploadedUrl(uploaded);
      if (!mounted || !_pending.contains(item)) {
        return; // 上传期间用户已删掉这张
      }
      if (url.isEmpty) {
        setState(() => _pending.remove(item));
        AppToast.show(context, _ai.t('error.30003'));
        return;
      }
      setState(() {
        item.url = url;
        item.uploading = false;
      });
    } catch (_) {
      // setFileUpload 的失败原因已由 ApiClient 提示，这里只移除占位缩略图
      if (!mounted) {
        return;
      }
      setState(() => _pending.remove(item));
      AppToast.show(context, _ai.t('error.30003'));
    }
  }

  /// 兼容 setFileUpload 的返回形态（字符串 / 数组 / 对象），同 `state._extractUploadedUrl`。
  String _extractUploadedUrl(dynamic data) {
    if (data is String) {
      return data.trim();
    }
    if (data is List && data.isNotEmpty) {
      return _extractUploadedUrl(data.first);
    }
    if (data is Map) {
      final url =
          data['url'] ??
          data['fileUrl'] ??
          data['filePath'] ??
          data['path'] ??
          data['src'];
      if (url is String) {
        return url.trim();
      }
    }
    return '';
  }

  /// 一键生图：按语种自动拼 message（如「生成图片-卡通」），img_style 触发生图（文档 §5.3.2）。
  Future<void> _openStylePicker() async {
    setState(() => _showTools = false);
    final l10n = AppL10n.of(context);
    final key = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => _AiSheet(
        title: l10n.aiPickStyle,
        cancelLabel: l10n.cancel,
        child: Wrap(
          alignment: WrapAlignment.center,
          spacing: 18,
          runSpacing: 18,
          children: [
            for (var i = 0; i < _kStyleKeys.length; i++)
              _AiStyleTile(
                label: l10n.aiStyleLabel(_kStyleKeys[i]),
                accent: i.isEven
                    ? const Color(0xFFFF5F1F)
                    : const Color(0xFF3E8BFF),
                onTap: () => Navigator.of(sheetContext).pop(_kStyleKeys[i]),
              ),
          ],
        ),
      ),
    );
    if (key == null || !mounted) {
      return;
    }
    await _sendChat(_ai.genMessage(key), styleKey: key);
  }

  // ── 消息长按菜单 ──────────────────────────────────────────

  /// 长按气泡本体：用户纯图气泡 → 下载/投屏/删除；其余（文字 / AI 图文气泡）→ 删除整条。
  /// AI 气泡里**某一张图**的长按走 [_onImageLongPress]，否则「图文同一个气泡」之后就没法
  /// 只针对某张图下载/投屏了。
  Future<void> _onBubbleLongPress(_AiMessage message) async {
    if (message.loading || message.typing) {
      return;
    }
    final onlyImage =
        message.kind == _MsgKind.image && message.images.length == 1;
    final action = await _showMessageActions(withImageActions: onlyImage);
    if (action == null || !mounted) {
      return;
    }
    switch (action) {
      case 'delete':
        await _deleteMessage(message);
      case 'download':
        await _downloadImage(message.images.first.url);
      case 'cast':
        await _castImage(message.images.first.url);
    }
  }

  /// 长按 AI 气泡里的单张图：下载/投屏都只针对这一张；删除也只摘掉这一张
  ///（气泡里还有文字或别的图就留着，都没了才整条移除）。
  Future<void> _onImageLongPress(_AiMessage message, int index) async {
    if (message.loading || message.typing || index >= message.images.length) {
      return;
    }
    final image = message.images[index];
    final action = await _showMessageActions(withImageActions: true);
    if (action == null || !mounted) {
      return;
    }
    switch (action) {
      case 'download':
        await _downloadImage(image.url);
      case 'cast':
        await _castImage(image.url);
      case 'delete':
        await _deleteBubbleImage(message, index);
    }
  }

  Future<String?> _showMessageActions({required bool withImageActions}) {
    final l10n = AppL10n.of(context);
    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => _AiSheet(
        title: l10n.aiMessageActions,
        cancelLabel: l10n.cancel,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (withImageActions) ...[
              _AiSheetAction(
                label: l10n.aiDownload,
                icon: Icons.download_rounded,
                onTap: () => Navigator.of(sheetContext).pop('download'),
              ),
              _AiSheetAction(
                label: l10n.aiCast,
                icon: Icons.cast_rounded,
                onTap: () => Navigator.of(sheetContext).pop('cast'),
              ),
            ],
            _AiSheetAction(
              label: l10n.aiDelete,
              icon: Icons.delete_outline_rounded,
              danger: true,
              onTap: () => Navigator.of(sheetContext).pop('delete'),
            ),
          ],
        ),
      ),
    );
  }

  /// 删整条消息。图文合并进一个气泡后一条消息可能对应**多个** message_id
  ///（文字行 + 每张图各一行），逐个删掉，漏一个就会重进会话时诡异地只剩半条。
  Future<void> _deleteMessage(_AiMessage message) async {
    // 历史消息带服务端 id 走接口删除；本轮新产生的消息接口未回 id，仅本地移除
    //（重进会话会重新出现，待后端在 /chat 响应中带回 message_id 后可彻底删除）
    final serverIds = <String>[
      if (message.serverId != null && message.serverId!.isNotEmpty)
        message.serverId!,
      for (final image in message.images)
        if (image.serverId != null && image.serverId!.isNotEmpty)
          image.serverId!,
    ];
    try {
      for (final serverId in serverIds) {
        await _api.deleteMessage(_sessionId, serverId);
      }
      if (!mounted) {
        return;
      }
      setState(() => _messages.removeWhere((item) => item.id == message.id));
      AppToast.show(context, AppL10n.of(context).aiDeleted);
    } catch (error) {
      if (mounted) {
        await _ai.handleError(context, error);
      }
    }
  }

  /// 只删气泡里的某一张图。
  Future<void> _deleteBubbleImage(_AiMessage message, int index) async {
    if (index >= message.images.length) {
      return;
    }
    final image = message.images[index];
    try {
      final serverId = image.serverId;
      if (serverId != null && serverId.isNotEmpty) {
        await _api.deleteMessage(_sessionId, serverId);
      }
    } catch (error) {
      if (mounted) {
        await _ai.handleError(context, error);
      }
      return;
    }
    if (!mounted) {
      return;
    }
    setState(() {
      message.images.removeAt(index);
      // 文字和图都没了，这个气泡就该整条消失，别留个空白框
      if (message.images.isEmpty && message.content.isEmpty) {
        _messages.removeWhere((item) => item.id == message.id);
      }
    });
    AppToast.show(context, AppL10n.of(context).aiDeleted);
  }

  /// 下载 AI 生成图到本地文件，返回文件路径（失败返回 null）。生成图 24 小时后过期。
  Future<String?> _downloadToFile(String url) async {
    try {
      final response = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 30));
      if (response.statusCode != 200 || response.bodyBytes.isEmpty) {
        return null;
      }
      final name = 'ai_image_${DateTime.now().microsecondsSinceEpoch}.jpg';
      final file = File('${Directory.systemTemp.path}/$name');
      await file.writeAsBytes(response.bodyBytes, flush: true);
      return file.path;
    } catch (_) {
      return null;
    }
  }

  Future<void> _downloadImage(String url) async {
    AppLoadingDialog.show(context, AppL10n.of(context).castProcessing);
    final path = await _downloadToFile(url);
    AppLoadingDialog.hide(context);
    if (!mounted) {
      return;
    }
    final l10n = AppL10n.of(context);
    AppToast.show(context, path == null ? l10n.aiImageExpired : l10n.aiDownloaded);
  }

  /// 投屏：已连接活动设备 → 直接进投屏预览；未连接 → 弹已绑定设备列表，选中后连接再进。
  /// 与手选照片完全同链路（AI 图先下载成本地文件，交给 [CastPreviewPage]）。
  Future<void> _castImage(String url) async {
    final selected = widget.state.selectedDevice;
    DeviceItem? target = selected.isPlaceholder ? null : selected;
    if (target == null ||
        !widget.state.isDeviceActuallyConnected(target.id)) {
      target = await _pickDevice();
      if (target == null || !mounted) {
        return;
      }
      if (!widget.state.isDeviceActuallyConnected(target.id)) {
        AppLoadingDialog.show(context, AppL10n.of(context).castConnectingDevice);
        final feedback = await widget.state.connectDevice(target.id);
        AppLoadingDialog.hide(context);
        if (!mounted) {
          return;
        }
        if (!feedback.success) {
          AppToast.show(context, feedback.message);
          return;
        }
        target = widget.state.deviceById(target.id);
      }
    }

    AppLoadingDialog.show(context, AppL10n.of(context).aiPreparingCast);
    final path = await _downloadToFile(url);
    AppLoadingDialog.hide(context);
    if (!mounted) {
      return;
    }
    if (path == null) {
      AppToast.show(context, AppL10n.of(context).aiImageExpired);
      return;
    }
    await Navigator.of(context).push<void>(
      AppPageRoute<void>(
        builder: (_) => CastPreviewPage(
          state: widget.state,
          device: target!,
          imagePaths: [path],
        ),
      ),
    );
  }

  /// 未连接时的设备选择弹层（对齐小程序 devicePicker）。
  Future<DeviceItem?> _pickDevice() async {
    final l10n = AppL10n.of(context);
    if (widget.state.devices.isEmpty) {
      try {
        await widget.state.refreshDevices();
      } catch (_) {}
    }
    if (!mounted) {
      return null;
    }
    final devices = widget.state.devices;
    if (devices.isEmpty) {
      AppToast.show(context, l10n.aiNoBoundDevice);
      return null;
    }
    return showModalBottomSheet<DeviceItem>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => _AiSheet(
        title: l10n.aiPickCastDevice,
        cancelLabel: l10n.cancel,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final device in devices)
              _AiSheetAction(
                label: device.name,
                subtitle: device.connected
                    ? l10n.aiDeviceConnected
                    : l10n.aiDeviceWillConnect,
                icon: Icons.photo_size_select_actual_rounded,
                onTap: () => Navigator.of(sheetContext).pop(device),
              ),
          ],
        ),
      ),
    );
  }

  // ── 滚动 ─────────────────────────────────────────────────

  /// 记录「用户是不是自己翻上去了」。只改字段不 setState，很便宜。
  void _onScroll() {
    if (!_scroll.hasClients) {
      return;
    }
    final position = _scroll.position;
    _stick = (position.maxScrollExtent - position.pixels) <= _kStickPx;
  }

  /// 贴到底部。
  /// - [force]：忽略节流、也忽略「用户已上翻」，并把贴底状态复位（发消息/打字结束时用）；
  /// - [animate]：是否带滚动动画。打字期间必须 **false** —— 动画本身就是「滚动赶不上打字机」的
  ///   来源，一帧一帧地补动画会越追越远；发消息那一下开动画才好看。
  void _stickToBottom({bool force = false, bool animate = false}) {
    if (force) {
      _stick = true;
    } else {
      if (!_stick) {
        return; // 用户正在往上翻看历史，别把他拽回来
      }
      if (DateTime.now().difference(_lastStickAt) < _kStickThrottle) {
        return;
      }
    }
    _lastStickAt = DateTime.now();
    // 新内容要等这一帧布局完成才有新的 maxScrollExtent，所以必须 postFrame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) {
        return;
      }
      final max = _scroll.position.maxScrollExtent;
      if (animate) {
        _scroll.animateTo(
          max,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
        );
      } else {
        _scroll.jumpTo(max);
      }
    });
  }

  // ── UI ───────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final title = _sessionTitle.isEmpty ? l10n.aiNewChat : _sessionTitle;
    return FigmaScreen(
      title: title,
      scrollable: false,
      bodyPadding: EdgeInsets.zero,
      body: Column(
        children: [
          _buildToolbar(),
          if (_banned)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0x14D64541),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                l10n.aiBannedBanner,
                style: const TextStyle(color: Color(0xFFD64541), fontSize: 12),
              ),
            ),
          Expanded(child: _buildMessages()),
          if (_sending) _buildStopPill(),
          _buildInputArea(),
        ],
      ),
    );
  }

  /// 标题栏下方工具行：左「会话」入口 / 右 Token 余额 + 新对话。
  Widget _buildToolbar() {
    final l10n = AppL10n.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _closeTools, // 点工具行空白处也收起 ＋ 工具栏
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Row(
          children: [
            _AiChip(
              label: l10n.aiSessions,
              icon: Icons.menu_rounded,
              onTap: _goSessions,
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0x1AFFAA00),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                'Token $_tokenBalance',
                style: const TextStyle(
                  color: Color(0xFFB07800),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 8),
            _AiChip(
              label: l10n.aiNewChat,
              icon: Icons.add_rounded,
              onTap: _startNewSession,
            ),
          ],
        ),
      ),
    );
  }

  /// 消息区。首屏「已渲染但透明」+ 上面盖 loading，等定位到底部再显形（需求 5.1）；
  /// 不能用 `if` 把列表整块换掉 —— 没有布局就没法滚到底。
  Widget _buildMessages() {
    final showWelcome = _messages.isEmpty && !_historyLoading;
    return GestureDetector(
      // 点消息区任意位置收起 ＋ 工具栏（见 _closeTools）。只吃点击，拖动仍归 ListView。
      behavior: HitTestBehavior.opaque,
      onTap: _closeTools,
      child: Stack(
        children: [
          Positioned.fill(
            child: showWelcome
                ? _buildWelcome()
                : Opacity(
                    opacity: _chatReady ? 1.0 : 0.0,
                    child: ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                      itemCount: _messages.length,
                      itemBuilder: (context, index) =>
                          _buildBubbleRow(_messages[index]),
                    ),
                  ),
          ),
          if (_historyLoading || !_chatReady)
            const Positioned.fill(child: PageLoading()),
        ],
      ),
    );
  }

  /// 默认状态：星宝招呼语居中（需求原文案）。
  Widget _buildWelcome() {
    final l10n = AppL10n.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 64,
            height: 64,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: Color(0x1A7B61FF),
              shape: BoxShape.circle,
            ),
            child: const Text('✨', style: TextStyle(fontSize: 28)),
          ),
          const SizedBox(height: 16),
          Text(
            l10n.aiWelcome,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF2A2D32),
              fontSize: 15,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            l10n.aiWelcomeTip,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFF8B9098), fontSize: 12),
          ),
        ],
      ),
    );
  }

  /// 一行消息。AI 侧（需求 6）：**不放头像**、气泡按屏宽铺满；用户侧维持现状（右对齐、按内容宽）。
  Widget _buildBubbleRow(_AiMessage message) {
    final isUser = message.isUser;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: isUser
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isUser)
            Flexible(child: _buildUserBubble(message))
          else
            Expanded(child: _buildAiBubble(message)),
        ],
      ),
    );
  }

  /// AI 回复气泡（需求 3）：文字与图片在**同一个气泡**里。
  /// 气泡本体长按 = 删整条；里面某张图的长按/点击由图自己接住（见 [_AiBubbleImage]）。
  Widget _buildAiBubble(_AiMessage message) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPress: () => _onBubbleLongPress(message),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0F7991B2),
              blurRadius: 16,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (message.loading)
              const _TypingDots()
            else if (message.content.isNotEmpty)
              SelectableText(
                message.typing ? '${message.content}▍' : message.content,
                style: const TextStyle(
                  color: Color(0xFF2A2D32),
                  fontSize: 14,
                  height: 1.6,
                ),
              ),
            for (var i = 0; i < message.images.length; i++)
              Padding(
                padding: EdgeInsets.only(
                  top: (i == 0 && message.content.isEmpty && !message.loading)
                      ? 0.0
                      : 8.0,
                ),
                child: _buildBubbleImage(message, i),
              ),
          ],
        ),
      ),
    );
  }

  /// 用户气泡（需求 6.3：维持现状不变）——文字是橙色渐变块、图片是白底小卡片。
  Widget _buildUserBubble(_AiMessage message) {
    if (message.kind == _MsgKind.image && message.images.isNotEmpty) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onLongPress: () => _onBubbleLongPress(message),
        child: Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: const [
              BoxShadow(
                color: Color(0x0F7991B2),
                blurRadius: 16,
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 220),
            child: _buildBubbleImage(message, 0, handleLongPressHere: false),
          ),
        ),
      );
    }
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPress: () => _onBubbleLongPress(message),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFFF5F1F),
          borderRadius: BorderRadius.circular(14),
        ),
        child: SelectableText(
          message.content,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            height: 1.6,
          ),
        ),
      ),
    );
  }

  /// 气泡里的一张图。占位比例先按已知值把高度占住，加载完用真实尺寸校正（需求 1.2 / 5.2）。
  ///
  /// [handleLongPressHere]：AI 气泡里要按张长按（下载/投屏/只删这张），所以图自己接住长按；
  /// 用户的纯图气泡整条就是这一张，长按交给气泡本体处理即可（传 false 让手势冒泡上去）。
  Widget _buildBubbleImage(
    _AiMessage message,
    int index, {
    bool handleLongPressHere = true,
  }) {
    final image = message.images[index];
    return _AiBubbleImage(
      key: ValueKey('${message.id}-${image.url}'),
      url: image.url,
      pad: image.pad,
      onPadResolved: (pad) {
        // 写回模型：列表滚出去再滚回来时不必再量一次，也不会跳回猜的比例
        if (mounted && (image.pad - pad).abs() >= 1) {
          setState(() => image.pad = pad);
          _stickToBottom();
        }
      },
      onTap: () => _previewImage(image.url),
      onLongPress: handleLongPressHere
          ? () => _onImageLongPress(message, index)
          : null,
    );
  }

  void _previewImage(String url) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (dialogContext) => GestureDetector(
        onTap: () => Navigator.of(dialogContext).pop(),
        child: InteractiveViewer(
          child: Center(child: CachedNetworkImage(imageUrl: url)),
        ),
      ),
    );
  }

  /// 生成中的「停止生成」浮标（终止 AI 回复，文档 §5.3.4）。
  /// ⚠️ 与小程序的差异：小程序那颗是 `position: fixed` 悬在输入区上方、会盖住正在打出来的
  /// 最后两行（2026-07-27 靠底部留白治），App 这颗在 Column 里占正常一行，不存在遮挡。
  Widget _buildStopPill() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _stopGenerate(),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: const Color(0xFFE2E6EE)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 10, height: 10, color: const Color(0xFF2A2D32)),
              const SizedBox(width: 8),
              Text(
                AppL10n.of(context).aiStopGenerating,
                style: const TextStyle(color: Color(0xFF2A2D32), fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInputArea() {
    final l10n = AppL10n.of(context);
    return Container(
      // 键盘避让由 FigmaScreen 的 Scaffold(resizeToAvoidBottomInset: true) 负责，
      // 这里**不要**再加 viewInsets，否则弹键盘时输入区会被顶两次。
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFEDF1F7))),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_pending.isNotEmpty) _buildPendingStrip(),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _AiRoundButton(
                icon: _voiceMode
                    ? Icons.keyboard_alt_outlined
                    : Icons.mic_none_rounded,
                onTap: () => setState(() {
                  _voiceMode = !_voiceMode;
                  _showTools = false;
                }),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _voiceMode
                    ? GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        // ⚠️ App 侧没有录音 + 语音转写能力：小程序那套「按住说话、松手直发、
                        // 动效盖住整个输入区」靠的是微信「同声传译」插件（小程序独有）。
                        // App 要做得引入录音插件 + 第三方 STT 服务，本轮不擅自加依赖，
                        // 仍只给同语义的占位提示（详见文件头「与小程序有意的差异」）。
                        onLongPress: () =>
                            AppToast.show(context, l10n.aiVoicePending),
                        onTap: () => AppToast.show(context, l10n.aiVoicePending),
                        child: Container(
                          height: 40,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: const Color(0xFFF2F5FC),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            l10n.aiHoldToTalk,
                            style: const TextStyle(
                              color: Color(0xFF777E88),
                              fontSize: 14,
                            ),
                          ),
                        ),
                      )
                    : TextField(
                        controller: _input,
                        enabled: !_banned,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _onSendTap(),
                        onChanged: (_) => setState(() {}),
                        // 键盘和 ＋ 工具栏不该同时占着底部（对齐小程序 bindfocus="closeTools"）
                        onTap: _closeTools,
                        decoration: InputDecoration(
                          isDense: true,
                          filled: true,
                          fillColor: const Color(0xFFF2F5FC),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(20),
                            borderSide: BorderSide.none,
                          ),
                          hintText: _banned
                              ? l10n.aiBannedHint
                              : (_pending.isEmpty
                                    ? l10n.aiInputHint
                                    : l10n.aiInputWithImagesHint),
                          hintStyle: const TextStyle(
                            color: Color(0xFF9AA1AB),
                            fontSize: 14,
                          ),
                        ),
                      ),
              ),
              const SizedBox(width: 8),
              _AiRoundButton(
                icon: Icons.add_rounded,
                onTap: () => setState(() => _showTools = !_showTools),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _onSendTap,
                child: Container(
                  height: 40,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: (_input.text.trim().isNotEmpty && !_sending && !_banned)
                        ? const Color(0xFFFF5F1F)
                        : const Color(0xFFE2E6EE),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    l10n.aiSend,
                    style: TextStyle(
                      color:
                          (_input.text.trim().isNotEmpty &&
                              !_sending &&
                              !_banned)
                          ? Colors.white
                          : const Color(0xFF9AA1AB),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (_showTools) _buildToolsPanel(),
        ],
      ),
    );
  }

  /// 待发送图片缩略图（v1.0.3 §5.1.4）：停在输入框内，每张可删、最多 4 张。
  Widget _buildPendingStrip() {
    return SizedBox(
      height: 68,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.only(bottom: 8),
        itemCount: _pending.length,
        separatorBuilder: (context, index) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final item = _pending[index];
          return SizedBox(
            width: 60,
            height: 60,
            child: Stack(
              children: [
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.file(File(item.path), fit: BoxFit.cover),
                  ),
                ),
                if (item.uploading)
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Center(
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                Positioned(
                  right: 0,
                  top: 0,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => setState(() => _pending.remove(item)),
                    child: Container(
                      width: 18,
                      height: 18,
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(
                        color: Color(0xCC11151C),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.close_rounded,
                        size: 12,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// ＋ 工具面板：相册 / 拍照 / 一键生图 + 图片比例。
  Widget _buildToolsPanel() {
    final l10n = AppL10n.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _AiToolItem(
                label: l10n.aiAlbum,
                icon: Icons.photo_library_outlined,
                accent: const Color(0xFF3BB273),
                onTap: () => _pickImages(camera: false),
              ),
              _AiToolItem(
                label: l10n.aiCamera,
                icon: Icons.photo_camera_outlined,
                accent: const Color(0xFF3E8BFF),
                onTap: () => _pickImages(camera: true),
              ),
              _AiToolItem(
                label: l10n.aiGenerateImage,
                icon: Icons.auto_awesome_outlined,
                accent: const Color(0xFFFF5F1F),
                onTap: _openStylePicker,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Text(
                l10n.aiImageRatio,
                style: const TextStyle(color: Color(0xFF777E88), fontSize: 12),
              ),
              const SizedBox(width: 10),
              for (final key in _kOrientationKeys)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => setState(() => _orientation = key),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: _orientation == key
                            ? const Color(0x1AFF5F1F)
                            : const Color(0xFFF2F5FC),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        l10n.aiOrientationLabel(key),
                        style: TextStyle(
                          color: _orientation == key
                              ? const Color(0xFFFF5F1F)
                              : const Color(0xFF777E88),
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 气泡里的一张图：**先按传入的占位比例把高度占住**，图加载完再用真实尺寸校正
/// （2026-07-27 需求 1.2 / 5.2 —— 不这样做，图一加载完就把上面的内容顶飞）。
///
/// 为什么自己去 resolve 一遍 provider：`CachedNetworkImage` 不回调图片的原始尺寸，
/// 而占位比例校正必须拿到真实宽高。resolve 的是**同一个** [CachedNetworkImageProvider]，
/// 命中的是同一份缓存，不会多下一次。
///
/// 只在这张图**被真的构建出来**时才 resolve（ListView.builder 只构建可见项），
/// 所以历史会话里屏幕外的几十张图不会被一次性拉下来。
class _AiBubbleImage extends StatefulWidget {
  const _AiBubbleImage({
    super.key,
    required this.url,
    required this.pad,
    required this.onPadResolved,
    required this.onTap,
    this.onLongPress,
  });

  final String url;

  /// 占位比例：高/宽×100。
  final double pad;

  /// 量到真实比例后回报给模型（避免滚出去再滚回来又跳回猜的比例）。
  final ValueChanged<double> onPadResolved;

  final VoidCallback onTap;

  /// 传 null 表示不在这一层接长按（让手势冒泡给外层气泡处理）。
  final VoidCallback? onLongPress;

  @override
  State<_AiBubbleImage> createState() => _AiBubbleImageState();
}

class _AiBubbleImageState extends State<_AiBubbleImage> {
  late double _pad = widget.pad;
  ImageStream? _stream;
  ImageStreamListener? _listener;

  @override
  void initState() {
    super.initState();
    _resolveSize();
  }

  @override
  void didUpdateWidget(_AiBubbleImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _detach();
      _pad = widget.pad;
      _resolveSize();
    } else if (oldWidget.pad != widget.pad) {
      _pad = widget.pad;
    }
  }

  @override
  void dispose() {
    _detach();
    super.dispose();
  }

  void _detach() {
    final stream = _stream;
    final listener = _listener;
    if (stream != null && listener != null) {
      stream.removeListener(listener);
    }
    _stream = null;
    _listener = null;
  }

  void _resolveSize() {
    if (widget.url.isEmpty) {
      return;
    }
    final provider = CachedNetworkImageProvider(widget.url);
    final listener = ImageStreamListener((info, _) {
      final pad = _padFromSize(info.image.width, info.image.height);
      if (pad == null) {
        return;
      }
      // ⚠️ 图已在缓存里时这个回调是**同步**触发的（就在 initState 里），
      // 那时 setState / 通知父级都会撞上「build 期间改状态」。统一推到帧后再应用。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || (_pad - pad).abs() < 1) {
          return;
        }
        setState(() => _pad = pad);
        widget.onPadResolved(pad);
      });
    });
    _stream = provider.resolve(ImageConfiguration.empty)
      ..addListener(listener);
    _listener = listener;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: AspectRatio(
          // pad = 高/宽×100 → aspectRatio(宽/高) = 100/pad
          aspectRatio: 100 / _pad,
          child: ColoredBox(
            color: const Color(0xFFF2F5FC),
            child: CachedNetworkImage(
              imageUrl: widget.url,
              // 比例已经按真实尺寸校正过，contain 不裁不留边；校正前略有留边也看不出来（图还没出来）
              fit: BoxFit.contain,
              placeholder: (context, url) => const Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
              errorWidget: (context, url, error) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(
                    AppL10n.of(context).castImageLoadFailed,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFF828A95),
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// AI 回复占位的三点 loading。
class _TypingDots extends StatefulWidget {
  const _TypingDots();

  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List<Widget>.generate(3, (index) {
            final t = ((_controller.value * 3) - index).clamp(0.0, 1.0);
            final opacity = 0.3 + 0.7 * (t < 0.5 ? t * 2 : (1 - t) * 2);
            return Padding(
              padding: EdgeInsets.only(right: index == 2 ? 0 : 5),
              child: Opacity(
                opacity: opacity.clamp(0.3, 1.0),
                child: Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                    color: Color(0xFF9AA1AB),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}

class _AiChip extends StatelessWidget {
  const _AiChip({required this.label, required this.icon, required this.onTap});

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFFF2F5FC),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: const Color(0xFF777E88)),
            const SizedBox(width: 4),
            Text(
              label,
              style: const TextStyle(color: Color(0xFF777E88), fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _AiRoundButton extends StatelessWidget {
  const _AiRoundButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: const BoxDecoration(
          color: Color(0xFFF2F5FC),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 20, color: const Color(0xFF777E88)),
      ),
    );
  }
}

class _AiToolItem extends StatelessWidget {
  const _AiToolItem({
    required this.label,
    required this.icon,
    required this.accent,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, size: 22, color: accent),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: const TextStyle(color: Color(0xFF777E88), fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

/// 底部弹层外壳（标题 + 内容 + 取消），对齐小程序 `.sheet`。
class _AiSheet extends StatelessWidget {
  const _AiSheet({
    required this.title,
    required this.cancelLabel,
    required this.child,
  });

  final String title;
  final String cancelLabel;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: const TextStyle(
                color: Color(0xFF2A2D32),
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 14),
            Flexible(child: SingleChildScrollView(child: child)),
            const SizedBox(height: 6),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(context).pop(),
              child: Container(
                height: 44,
                alignment: Alignment.center,
                child: Text(
                  cancelLabel,
                  style: const TextStyle(
                    color: Color(0xFF777E88),
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AiSheetAction extends StatelessWidget {
  const _AiSheetAction({
    required this.label,
    required this.icon,
    required this.onTap,
    this.subtitle,
    this.danger = false,
  });

  final String label;
  final String? subtitle;
  final IconData icon;
  final bool danger;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = danger ? const Color(0xFFD64541) : const Color(0xFF2A2D32);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: TextStyle(color: color, fontSize: 14)),
                  if (subtitle != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        subtitle!,
                        style: const TextStyle(
                          color: Color(0xFF8B9098),
                          fontSize: 12,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AiStyleTile extends StatelessWidget {
  const _AiStyleTile({
    required this.label,
    required this.accent,
    required this.onTap,
  });

  final String label;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        width: 72,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                label.isEmpty ? '' : label.substring(0, 1),
                style: TextStyle(
                  color: accent,
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: const TextStyle(color: Color(0xFF777E88), fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
