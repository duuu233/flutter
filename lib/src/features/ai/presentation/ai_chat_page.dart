import 'dart:async';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:http/http.dart' as http;

import '../../../network/boltfox_api.dart';
import '../../../network/boltstar_ai_api.dart';
import '../../../native_device_api.dart';
import '../../../routes/app_routes.dart';
import '../../../shared/ai_service_consent.dart';
import '../../../shared/l10n/app_l10n.dart';
import '../../../shared/widgets/app_dialog.dart';
import '../../../shared/widgets/app_toast.dart';
import '../../../shared/widgets/app_widgets.dart';
import '../../../shared/widgets/device_picker_sheet.dart';
import '../../../shared/widgets/figma_common.dart';
import '../../../shared/widgets/low_battery_tip.dart';
import '../../../state.dart';
import '../../cast/cast_photo_picker.dart';
import '../../cast/presentation/cast_preview_page.dart';
import '../ai_i18n.dart';
import '../ai_image_compress.dart';
import '../ai_last_session.dart';
import '../ai_token.dart';
import '../ai_voice_input.dart';
import 'ai_sessions_page.dart';
import 'ai_visuals.dart';

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
/// - 长按气泡**空白处**→删除确认框；每张图下方**常驻**「下载 / 投屏 / 删除」操作条
///   （2026-08-10 起，见下）。投屏复用现有投屏链路（下载成本地文件后进预览页）；
/// - 无绑定设备拦截（文档 §5.5）、22002/22003 封禁弹窗 + 禁用输入 + 顶部横幅、
///   20013 会话数达上限引导去清理。Token 余额移到「历史会话」页展示（见 [AiToken]）。
///
/// ## 2026-08-10 AI 助手八项优化（小程序同日同批，逐项对齐）
/// 1.3 标题**屏幕正中**、定宽 170 超出省略；5 默认页（还没建会话）标题留空，不写「新对话」；
/// 2 长按不再弹底部面板：正文长按只走选字/复制，气泡空白处长按弹全站同版式的删除确认框；
/// 3 比例浮层顶部加标题「设置文生图比例」；4 右侧按钮三态（语音/发送/麦克风）同盒不位移，
/// 发送图标按「除去阴影后上下居中」放大；6 会话删除加 loading 闸（在 [AiSessionsPage]）；
/// 7 图片操作条常驻（AI 回复里的每张图 + 用户自己发的图气泡），删除统一走确认框；
/// 8 输入框默认文案改为「按住说话或输入您的想法...」。
/// 🔶 **第 5 项两端排布不同**：小程序把「会话列表」排在返回键右边（它的顶栏右侧被微信原生胶囊
///    占着），App 按需求把会话列表放到**最右**；App 本来就没有底部 tabbar 可隐藏。
///
/// ## 2026-07-31 视觉同步（小程序 2026-07-30 UI 接入 + 07-31 校准两轮）
/// 按 `assets/ai/UI` 视觉稿重做：顶部历史入口 + 会话标题（Token 胶囊已于 08-10 移走）、暖米白配色、
/// 欢迎页星标与三条灵感词、常驻四工具输入卡（相册 / 拍照 / 比例 / 一键生图）、比例与风格两个上拉
/// 浮层、图下方的「下载 / 投屏 / 删除」操作条、30xxx 失败原地变成可重试的失败卡、
/// 投屏设备底部弹层。图标全部改用与小程序**同一批** `assets/images/ai-*.png`。
/// ⚠️ 背景图**本轮不动**（用户指定「flutter 先不改背景图」）：本页仍用全 App 统一的
/// [FigmaScreenBackground]，没有跟着小程序换成 AI 那张 OSS 全屏图。
///
/// ## 与小程序有意的差异（无对应端能力 / 平台机制不同）
/// - **语音输入**：2026-08-28 已接（[AiVoiceInput]）。交互与小程序同款（按住说话、上滑取消、
///   松手直发、录音期间不显示识别文字），只是识别引擎不同：小程序用微信「同声传译」插件，
///   App 首选**系统自带的语音识别**（`speech_to_text` → iOS SFSpeechRecognizer /
///   Android SpeechRecognizer），同样是端上转文字、接口不参与。
///   🔶 由此带来两点差异：① App 支持日语（微信那个插件没有）；
///   ② **安卓国行无 GMS 的机型没有系统识别服务**，这些机器 2026-08-29 起自动落到备胎
///   「录音上传后端 ASR」（`POST /speech/recognize`），按住说话照常可用，只是松手后
///   多一个「识别中…」的等待（见 [_transcribing] 与 `ai_voice_input.dart` 文件头）。
/// - **保存到系统相册**：2026-08-28 已接原生通道（[NativeDeviceApi.saveImageToGallery]：
///   Android→MediaStore `Pictures/BoltStar`、iOS→Photos addOnly 授权）。
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

/// 打字机的出字节拍（2026-07-27 优化顺滑度）。原实现是 `Timer.periodic(30ms)` 每帧追 3 字
/// —— 30ms 一跳、一跳 3 字，肉眼能看出「一顿一顿」。现在按 ~60fps 出字、每帧尽量只追 1 字。
///
/// 用**递归 Timer** 自计时而非 `Timer.periodic`：后者遇上 setState 慢会堆帧、追上来时一次吐
/// 一大段，就是那种「卡一下、蹦一截」的观感；自计时永远「渲染完再排下一帧」。
///
/// 切字一律用 `runes` 而不是 `split('')`：后者按 UTF-16 **码元**切，会把 emoji / 生僻字的
/// 代理对劈成两半，打到一半那一帧渲染出乱码方块 —— 星宝回复里 ✨ 之类相当常见。
const Duration _kTypeTick = Duration(milliseconds: 16);

/// 流式打字机（2026-08-07 SSE 接入）：服务端一段一段推 `text` 事件，打字机不再一次拿到全文，
/// 而是「一路追着积压的字打」。每帧字数 = `max(1, ceil(未打字数 / _kStreamTypeTicks))`
/// —— 即任意时刻的积压都在约 _kStreamTypeTicks 帧内打完：来得慢就一字一字（最顺滑），
/// 突然来一大段也不会落下十几秒的尾巴。
///
/// 180 帧 ≈ 2.9s。别调回 60（≈1s）：服务端的 text 事件常常是连着涌进来的（尤其响应体一次性
/// 到达、靠 [unescapeEventSeparators] 兜底解析的那条路，所有事件在同一帧解析完），积压瞬间就是
/// 全文 —— 压在 1 秒内打完，100 字就是每帧 2 字、0.8 秒冲完，肉眼基本看不出在打字。
const int _kStreamTypeTicks = 180;

/// 字打完了但流还没结束时的空转间隔。这时没内容可渲染，没必要还按 16ms 空跑。
const Duration _kStreamIdleTick = Duration(milliseconds: 60);

/// 进度补间（接入文档「后端只发里程碑，前端负责平滑动画」）。
/// 后端只推 5/15/30/45/50/80/85/90/100 这几级，而占位盒正中间摆的是一个**数字**——
/// 数字没法像进度条宽度那样靠动画抹平，直接贴上去就是 45→50→80 地跳。
/// 每 [_kProgressTick] 走一步（离目标远时一步 3、近了一步 1），补成 46、47、48… 的连续读数。
///
/// ⚠️ 只补到服务端给的目标值，绝不自己往前跑：宁可停在 45% 等下一条，也不能爬到 99% 再倒回去。
const Duration _kProgressTick = Duration(milliseconds: 80);
const int _kProgressStepFar = 3;
const int _kProgressStepNear = 1;
const int _kProgressNearGap = 20;

/// 进度文案的**兜底**映射（文档 §四 对照表）。
///
/// 正常情况下直接用服务端 `progress` 事件里的 `message` 字段（2026-08-07 新增，文案归后端管，
/// 改文案不用发版）。这张表只在 `message` 缺失时用：`pre_text` / `done` 本来就没有 message，
/// 老部署也没有 —— 删了占位盒里会空着一行。
///
/// **认 stage 而不只看数值**：`progress=5` 有 starting / request_sent 两种 stage，光看数字分不开。
const Map<String, String> _kStageLabels = <String, String>{
  'starting': '正在连接生图引擎…',
  'request_sent': '正在连接生图引擎…',
  'generating': 'AI 正在创作中…',
  'partial_succeeded': '初稿已完成 ✨',
  'completed': '正在优化细节…',
  'downloading': '正在下载图片…',
  'uploaded': '正在下载图片…',
  'done': '生成完成',
};

/// 进度文案：服务端 message > stage 映射 > 数值分档。
/// 数值分档的边界与 [_kStageLabels] 对齐，所以「45→50 爬到一半」和「刚好落在 50」
/// 不会给出矛盾的两句话。
String _progressLabel(int progress, {String stage = '', String message = ''}) {
  final fromServer = message.trim();
  if (fromServer.isNotEmpty) {
    return fromServer;
  }
  final byStage = stage.isEmpty ? null : _kStageLabels[stage];
  if (byStage != null) {
    return byStage;
  }
  if (progress < 5) {
    return '正在连接生图引擎…';
  }
  if (progress < 50) {
    return 'AI 正在创作中…';
  }
  if (progress < 80) {
    return '初稿已完成 ✨';
  }
  if (progress < 85) {
    return '正在优化细节…';
  }
  if (progress < 100) {
    return '正在下载图片…';
  }
  return '生成完成';
}

/// 打字期间贴底的节流间隔：每帧都滚会和出字的 setState 抢主线程，反而更卡。
/// 80ms 一次 ≈ 落后不到 5 个字，打完还会强制贴一次底。
const Duration _kStickThrottle = Duration(milliseconds: 80);

/// 距底多少逻辑像素以内算「还贴着底」。用户主动往上翻看历史时就别再把他拽回来了。
const double _kStickPx = 60;

/// 图文多模态一次最多带几张图。2026-08-12 产品由 4 张放宽到 5 张
///（BoltStar 文档 v1.0.3/v1.0.4 §二 image_urls 写的仍是 4 张，尚未同步；超限服务端回 20012）。
/// ⚠️ 改这个数要连着改 [AppL10n.aiMaxImages] 与 `ai_i18n.dart` 的 error.20012 文案（都写着张数）。
const int _kMaxImages = 5;

/// 会话标题截断长度：v1.0.4 §二「首条用户消息前 20 字自动填充，默认『新对话』」。
/// 本地同步标题时按同一规则截，避免列表页重拉后标题突然变短、两处对不上。
const int _kSessionTitleMax = 20;

// Token 余额本地模拟（支付体系未接）2026-08-10 提取到 `features/ai/ai_token.dart`：
// 会话列表页顶部也要显示同一份余额（需求 1.1），常量再复制一份必然会漂。

/// 一键生图风格。**顺序与绑定都逐项对齐小程序 `STYLE_OPTIONS`**：
/// 漫画(anime) / 人物(portrait) / 风景(landscape) / 卡通(cartoon)。
///
/// ⚠️ 2026-08-28 修：这里原来写的是 `['cartoon', 'portrait', 'landscape', 'anime']`，
/// 即「漫画」绑 `cartoon`、末位「动漫」绑 `anime` —— 与小程序**正好互换**，于是同一个标签
/// 在两端出的是不同风格的图，点「漫画」发出去的还是「生成图片-卡通」。
/// 小程序侧同样的错早前已修（见 `chat.js` STYLE_OPTIONS 上方注释），这次把 App 对齐过来。
/// 文案见 [AppL10n.aiStyleLabel]，自动拼的 message 见 [AiI18n.genMessage]，三处同一口径。
const List<String> _kStyleKeys = ['anime', 'portrait', 'landscape', 'cartoon'];

/// 按住说话：手指相对起手点上滑超过这么多逻辑像素即进入「松开取消」态
/// （小程序 `VOICE_CANCEL_DY` 同款交互，仿微信）。
const double _kVoiceCancelDy = 60;

/// 一段语音的最长时长（与小程序 `VOICE_MAX_MS` 同值）。
///
/// 到点**不丢**：按「松手」处理 —— 把已经识别到的内容照常发出去，再提示一句
/// （见 [_AiChatPageState._endVoice] 的 `reachedLimit`）。说太久本来也不好识别，
/// 更不该让用户按了一分钟最后什么都没发出去。
/// ⚠️ 改这个数要同时改 [AppL10n.aiVoiceMaxDuration] 里的「1 分钟」字样。
const Duration _kVoiceMaxDuration = Duration(seconds: 60);

/// 图片比例（需求：竖向/横向/方形；API `img_orientation` 必传，只认这三个值）。
const List<String> _kOrientationKeys = ['vertical', 'horizontal', 'square'];

/// 比例浮层里每项的图标：选中态用 `-active`，未选中态用各自的默认图。
/// ⚠️ 竖向那张默认图的文件名是 `-vertical-default`，另外两张没有 `-default` 后缀 ——
/// 图源就是这么给的，别按规律改名。
const Map<String, String> _kOrientationIcons = <String, String>{
  'vertical': 'assets/images/ai-orientation-vertical-default.png',
  'horizontal': 'assets/images/ai-orientation-horizontal.png',
  'square': 'assets/images/ai-orientation-square.png',
};

String _orientationActiveIcon(String key) =>
    'assets/images/ai-orientation-$key-active.png';

/// 输入卡常驻四工具（相册 / 拍照 / 比例 / 一键生图）的宽度比例，
/// 对应小程序 `.quick-tools` 的 `grid-template-columns: 1fr 1fr 1.35fr 1.75fr`。
/// ⚠️ 两个上拉浮层是按这组比例**算出**自己该贴哪一格的（见 `_buildPopover`），
/// 改比例必须两处一起看。
const List<int> _kToolFlex = <int>[100, 100, 135, 175];
const double _kToolGap = 4;
const double _kToolHeight = 29;
const Color _kToolText = Color(0xFF6F6F6F);

/// 工具胶囊里文字的基准字号（小程序 25rpx≈12.5；2026-08-28 收到 12）。
///
/// ⚠️ 真正解决「英文太大放不下」的不是这个数，是 [_buildToolLabel] 的 `BoxFit.scaleDown`：
/// 四个语种的词长差得远（相册/Album、一键生图/Generate），写死任何一个字号都会顾此失彼。
const double _kToolFontSize = 12;

/// 胶囊左右内边距：文字不要贴着圆角边（小程序那边靠 grid 的余量带出同样的呼吸感）。
const double _kToolPadding = 8;

/// 胶囊里图标的边长、图标与文字之间的间距、比例格右侧那枚箭头的边长。
/// 抽成常量是因为 `_resolveToolFontSizes` 要拿它们**算每格能给文字多少宽度**，
/// 写死在各个 builder 里就没法算了。
const double _kToolIconSize = 13.5;
const double _kToolIconGap = 4.5;
const double _kToolChevronSize = 11;

/// 一键生图那格的图标外框（魔杖/关闭切换时宽度不变，见 `_buildGenerateButton`）。
const double _kToolGenerateIconSize = 18;

/// 输入卡的外边距与内边距。浮层要按输入卡的**内容区**对齐，所以两边共用这两个值。
const double _kInputCardMargin = 16;
const double _kInputCardPadding = 10;

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

  /// 服务端 message_id。历史消息一进来就有；本轮新发的要等 SSE `init` 事件贴回来
  /// （见 [_AiChatPageState._applyUserMessageIds]），所以**不是 final**。
  String? serverId;
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

  /// 服务端 message_id。历史消息一进来就有；本轮新发的要等 SSE `init` 事件贴回来
  /// （见 [_AiChatPageState._applyUserMessageIds]），所以**不是 final**。
  String? serverId;

  final List<_AiImage> images;
  bool loading;
  bool typing;

  /// 流式预描述（SSE `pre_text`）：秒回的一句「正在为您绘制…」，生成完成后保留，
  /// 当作这条回复的前情提要。
  String preText = '';

  /// 生成中：挂着渐变占位盒、显示 [progress] / [progressLabel]。
  /// 读数真的爬到 100 时才落下，占位盒原地换成真图。
  bool streaming = false;
  int progress = 0;
  String progressLabel = '';

  /// 渐变占位盒的比例（高/宽×100），与这轮回复图将来的占位比例取同一个值，
  /// 100% 换真图时高度不跳。
  double genPad = _kPadDefault;

  /// 30xxx / 未知上游失败：气泡原地变成可重试的失败卡（2026-07-30 视觉稿），
  /// 重试所需的原始请求参数记在 [_AiChatPageState._retryByMessage] 里。
  bool failed = false;

  bool get isUser => role == 'user';
}

/// 在途流式回复的状态。一次只可能有一条（`_sending` 期间不许再发）。
class _StreamState {
  _StreamState(
    this.holderId, {
    required this.imageBubbleIds,
    required this.textBubbleId,
  });

  /// 内容写进哪个气泡。
  final int holderId;

  /// 已收到的全部文字，按 rune 拆好（emoji / 生僻字的代理对不会被劈成两半）。
  final List<String> chars = <String>[];

  /// 已经打上屏的字数。[chars] 与它的差就是「积压」。
  int shown = 0;

  /// 流已结束（成功或中断），打字机排空后才收尾。
  bool ended = false;

  /// 已经吐出过预描述/图/文字 —— 决定中断时是保留已上屏的部分还是换失败卡。
  bool hasContent = false;

  /// 服务端 `mode` 事件定的这一轮走向：`image` = 生图（出渐变占位盒）、`text` = 纯文字、
  /// `''` = 还没收到（老部署不推这个事件，各处按「未知」兜底走 progress 那条路）。
  String mode = '';

  /// 本轮**用户图片气泡**的本地 id，顺序与请求里的 `image_urls` 一一对应；
  /// `init` 事件回来的 `image_msg_ids` 按同样的顺序贴回去。
  final List<int> imageBubbleIds;

  /// 本轮**用户文字气泡**的本地 id，对应 `init` 的 `user_msg_id`。
  final int textBubbleId;

  /// 服务端最新推到的里程碑，只增不减（重复/乱序推也不会让进度倒退）。
  int target = 0;

  /// 当前**上屏**的进度，由 `_pumpProgress` 一步步爬向 [target]。
  int progress = 0;

  /// [target] 那一级的 stage 与服务端文案，用来出文案（见 [_progressLabel]）。
  String stage = '';
  String message = '';
}

/// 失败卡「重新生成」要重发的原始请求参数。
class _RetryPayload {
  const _RetryPayload(this.message, this.styleKey, this.urls);

  final String message;
  final String? styleKey;
  final List<String> urls;
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

class _AiChatPageState extends State<AiChatPage> with RouteAware {
  late final BoltStarAiApi _api =
      widget.api ??
      BoltStarAiApi(userId: BoltStarAiApi.userIdOf(widget.state.currentUser.id));

  final ScrollController _scroll = ScrollController();
  final TextEditingController _input = TextEditingController();

  final List<_AiMessage> _messages = [];
  final List<_PendingImage> _pending = [];

  String _sessionId = '';
  String _sessionTitle = '';
  /// 星币余额。null = 未知（接口挂了/未登录），页面显示 `--`，**绝不用 0 兜底**
  /// （见 [AiToken]）。本页只展示与刷新，不扣数。
  // 同会话列表页：先显示登录带回的值，再异步刷权威值（见 AiToken.cachedBalance）。
  int? _tokenBalance = AiToken.cachedBalance();

  bool _historyLoading = false;

  /// 首屏「先渲染 → 贴底 → 再显形」用（需求 5.1）：false 时消息列表**已渲染但透明**。
  /// 必须已渲染 —— 没有布局就没法滚到底；显形放在贴底之后，用户就看不到那一下
  /// 「从最老一条一路飞到最新」的下滑。
  bool _chatReady = true;

  bool _sending = false;

  /// 已点发送、但请求还没真正发出（正在确认服务协议 / 建会话）。见 [_guardedSend]。
  bool _submitting = false;
  bool _banned = false;
  bool _voiceMode = false;

  /// 正在录音（按住说话）。见 [_beginVoice] / [_endVoice]。
  bool _recording = false;

  /// 松手之后、文字回来之前（**仅安卓备胎链路**：录音要上传后端转文字，
  /// 见 [AiVoiceInput.remote]）。
  ///
  /// 端上识别是瞬时出结果的，不进这个态（多晃一下反而闪）。这段时间浮层不收，
  /// 只把文案换成「识别中…」——不然松手后会有一两秒既没浮层也没消息的空白，像卡住了。
  bool _transcribing = false;

  /// 手指已滑进「松开取消」区（浮层变红，松手丢弃）。
  bool _voiceCancel = false;

  /// 本次按下的起手点（全局坐标）。上滑距离按它算。
  Offset? _voiceStart;

  /// 起手起到一半被 [_beginVoice] 判定为「起不来」（不支持/无权限/正在发送）时置 true，
  /// 后续的 move/up 事件直接忽略，不再重复弹提示。
  bool _voiceRejected = false;

  /// 录满 [_kVoiceMaxDuration] 的闹钟。到点自动收尾（见 [_beginVoice]）；
  /// 手动松手 / 取消 / 页面销毁都要把它取消掉，否则会在录音早就结束后空放一枪。
  Timer? _voiceLimitTimer;

  /// 手指还按在「按住说话」上。
  ///
  /// ⚠️ 这个标记是给 [_beginVoice] 里的 await 用的：首次按下要先 `initialize()`
  /// （会弹系统麦克风授权框），用户完全可能在那期间就松手了。不检查的话，
  /// 授权回来后才 `listen()`，而抬手事件早已过去 —— 麦克风会一直开到 60s 超时。
  bool _voiceHolding = false;

  /// 两个上拉浮层（比例 / 一键生图风格）。视觉稿里四个工具入口是**常驻**的，
  /// 原来那个「＋ 展开工具面板」的 `_showTools` 随之取消。
  bool _showOrientationPicker = false;
  bool _showStylePicker = false;

  // 「长按某张图才展开操作条」的 _activeImageMessageId / _activeImageIndex 2026-08-10 整套删除：
  // 操作条改为常驻（需求 7），没有「展开中的那一条」这个状态了。

  String _orientation = 'vertical'; // 默认竖向（电子相框主流为竖屏）

  /// 失败卡 id → 重试要重发的原始请求参数（对齐小程序 `_retryByMessage`）。
  final Map<int, _RetryPayload> _retryByMessage = <int, _RetryPayload>{};

  int _uid = 0;
  int _pid = 0;
  Timer? _typeTimer;

  /// 进度补间的定时器。与打字机分开用一支：文字和进度是两条互不等待的流，
  /// 共用一支会互相拖节奏。
  Timer? _progressTimer;

  /// 在途流式回复的状态（见 [_StreamState]）。被停止生成/切会话清空后，
  /// 迟到的 SSE 事件会认出「这条流已经不归我管」而被丢弃。
  _StreamState? _stream;

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
    _rememberAsLastAiPage();
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
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 聊天页可能叠着好几个（每从会话列表点开一条就多一页）：谁变可见谁把「上次停在哪」
    // 抢回来（[didPopNext]），所以必须订阅路由事件。
    final route = ModalRoute.of(context);
    if (route is PageRoute) {
      appRouteObserver.subscribe(this, route);
    }
  }

  /// 上层页面（会话列表 / 投屏预览 …）pop 回来，本页重新可见。
  @override
  void didPopNext() {
    _rememberAsLastAiPage();
  }

  @override
  void dispose() {
    _livePages.remove(this);
    // 「用户离开了 AI」。⚠️ 只有**栈里没有别的聊天页**时才记：否则本页是被退回下层
    // 聊天页的那一页，用户眼前的是下面那页（那页的 didPopNext 会把记忆抢回去，
    // 但两者的触发顺序不该赌）。
    if (_livePages.isEmpty) {
      _rememberAsLastAiPage();
    }
    appRouteObserver.unsubscribe(this);
    _stopGenerate(silent: true);
    // 页面走了还按着说话（返回手势/被 pop）：丢掉这一轮，别让隐藏页继续占着麦克风。
    _voiceLimitTimer?.cancel();
    _voiceLimitTimer = null;
    if (_recording || _transcribing) {
      unawaited(AiVoiceInput.instance.cancel());
    }
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    _input.dispose();
    super.dispose();
  }

  /// 记下「离开 AI 时停在哪一页」：有会话就回会话、空态就回空态（见 [AiLastSession]）。
  void _rememberAsLastAiPage() {
    AiLastSession.remember(sessionId: _sessionId, title: _sessionTitle);
  }

  // ── 会话 ─────────────────────────────────────────────────

  /// 从后端取权威余额（扣费在服务端发生，端上只能重取）。静默失败：读不到就保持当前值。
  Future<void> _loadTokenBalance() async {
    final value = await AiToken.fetchBalance();
    if (mounted && value != _tokenBalance) {
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
      final newChatTitle = AppL10n.of(context).aiNewChat;
      final serverTitle = session.title.isNotEmpty
          ? session.title
          : newChatTitle;
      setState(() {
        _sessionId = session.sessionId;
        // 刚建出来的会话，后端给的标题一律是占位的「新对话」（要等首条用户消息入库才自动填）。
        // 而这一刻页面上的标题**可能已经**同步成首条用户消息了 —— [_sendChat] 现在是
        // 「气泡先上屏、再建会话」，顺序与 2026-08-07 前相反。别让这个占位把它盖回去。
        if (serverTitle != newChatTitle ||
            _sessionTitle.isEmpty ||
            _sessionTitle == newChatTitle) {
          _sessionTitle = serverTitle;
        }
      });
      // 会话是刚刚才建出来的：记忆要跟着走，否则「离开→再点 AI」会回到默认页
      _rememberAsLastAiPage();
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
    _rememberAsLastAiPage();
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
          // 用户图片消息：**message 与 images[0] 都记上同一个 serverId**。
          //
          // ⚠️ 2026-08-28 修「用户自己发的照片删不掉」（两端同款 bug）：原来这里只把 id 记在
          // 消息本身上、`images[0]` 留空，理由是「免得删整条时对同一个 message_id 打两次 DELETE」。
          // 但用户图片气泡下面那条常驻操作条走的是 [_deleteBubbleImage]，它只认
          // `image.serverId` —— 拿到空值就**只删本地、不调接口**，重进会话照旧躺在那儿。
          // （AI 回复的图 id 记在 image 上，所以那边一直是好的，正是用户观察到的差别。）
          // 现在两处都记，重复由 [_deleteMessage] 去重收口 —— 数据模型如实反映
          // 「这条用户图片消息就是这一个 message_id」，比靠约定记在哪一处稳。
          images: isImage
              ? [_AiImage(url: row.content, serverId: row.id)]
              : null,
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
      // ⚠️ 这个遮罩**不做「点外面关闭」**（2026-08-12 同步小程序，与其它两个自绘弹窗不同）：
      // 它是「去绑定 / 返回」的二选一，点空白处溜走只会把用户留在一个投不了屏的页面上，
      // 还以为是自己点错了。
      barrierDismissible: false,
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
    _retryByMessage.clear();
    setState(() {
      _messages.clear();
      _showOrientationPicker = false;
      _showStylePicker = false;
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
    // 退回空态也要记：否则用户从会话退回默认页再离开，下次点 AI 又被带回那条旧会话
    _rememberAsLastAiPage();
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
    // _submitting 同 _sending 一起挡：上一条正卡在「建会话」空窗时点＋，界面会退回空态，
    // 而那条消息随后仍会发进刚建出来的会话里——一次操作两个矛盾结果（见 [_guardedSend]）。
    if (_sending || _submitting) {
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

  /// 发送入口的**同步**闸（2026-07-29）。
  ///
  /// 病灶：[_sending] 要等 [_sendChat] 内真正发出请求那一刻（追加 loading 气泡时）才置起，而在
  /// 它之前还隔着「AI 服务协议确认 + 建会话」最多两次网络往返 —— **首次进入 AI 在空态发第一条
  /// 消息**时这段空窗最长（必须先 POST /session/new），期间发送按钮仍是亮的、[_onSendTap] 开头的
  /// 守卫里 `_sending` 仍是 false，用户连点就能把同一条消息发出去好几遍（[_createSession] 只去重了
  /// 「建会话」，没去重「发送」）。
  ///
  /// 这里在任何 await 之前先同步置起 [_submitting]（与 [_sending] 一起决定按钮灰不灰），
  /// 无论成功/失败/提前 return 都由 finally 归位。返回 false = 被闸挡下。
  Future<bool> _guardedSend(Future<void> Function() task) async {
    if (_sending || _submitting || _banned) {
      return false;
    }
    setState(() => _submitting = true);
    try {
      await task();
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
    return true;
  }

  Future<void> _onSendTap() async {
    if (_sending || _submitting || _banned) {
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
    await _guardedSend(() async {
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
      // 星币校验排在**建会话之前**（2026-08-12 同步小程序需求）：确定发得出去，才值得去占一条会话。
      // 反过来的话，余额见底的用户每点一次发送就在服务端多留一条空的「新对话」——
      // 每个用户上限 20 条，几次就占满了，还得自己去列表里删。
      // 拦下时草稿与待发图原样保留（这里还没清），下面 [_sendChat] 就不必再查一遍。
      if (!await _guardAiDialogue() || !mounted) {
        return;
      }
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
      // await：让 _submitting 一直持有到请求真正发出（_sendChat 内 _sending 接棒），中间不留空窗
      await _sendChat(text, images: images, dialogueChecked: true);
    });
  }

  /// 发送对话 / 一键生图 / 图文多模态。先把用户消息（图片气泡 + 文字气泡）上屏，
  /// 再交给 [_dispatchChat] 发请求——这样 30xxx 重试只重发请求、不重复堆用户气泡。
  Future<void> _sendChat(
    String message, {
    String? styleKey,
    List<_AiImage> images = const [],
    bool dialogueChecked = false,
  }) async {
    if (_sending || _banned) {
      return;
    }
    if (!await _ensureAiServiceConsent(sendAttempt: true) || !mounted) {
      return;
    }
    // 服务端裁决「星币够不够发这一轮」。放在任何 setState **之前**：不够时用户气泡一条都不该上屏，
    // 否则界面上会闪出一句发不出去的话再被撤掉 —— 而余额见底的用户**每次**发送都会走到这一步。
    // [dialogueChecked]：[_onSendTap] 已经在建会话之前查过了，别重复打一次接口。
    if (!dialogueChecked && !await _guardAiDialogue()) {
      return;
    }
    if (!mounted) {
      return;
    }
    final newChatTitle = AppL10n.of(context).aiNewChat;
    final prevTitle = _sessionTitle;
    // 图片气泡与文字气泡的本地 id **分开记**：SSE `init` 事件会回来
    // `image_msg_ids`（与图片顺序一一对应）+ `user_msg_id`，要按各自的位置贴回去
    // （见 [_applyUserMessageIds]）。userMsgIds 是两者的合集，只用于建会话失败时整批撤回。
    final imageBubbleIds = <int>[];
    var textBubbleId = 0;
    final userMsgIds = <int>[];
    setState(() {
      // 用户消息：先按张追加图片气泡，再追加文字气泡（需求 6.3 用户侧维持原样）
      for (final image in images) {
        final bubble = _AiMessage(
          id: ++_uid,
          role: 'user',
          kind: _MsgKind.image,
          images: [image],
        );
        imageBubbleIds.add(bubble.id);
        userMsgIds.add(bubble.id);
        _messages.add(bubble);
      }
      final textBubble = _AiMessage(
        id: ++_uid,
        role: 'user',
        kind: _MsgKind.text,
        content: message,
      );
      textBubbleId = textBubble.id;
      userMsgIds.add(textBubble.id);
      _messages.add(textBubble);
      // 首条消息后标题自动变为首条内容（与后端 session.title 行为一致，本地同步免重拉）。
      // v1.0.4 §二明确后端只取**前 20 字**，这里同样截断，免得列表页重拉后标题突然变短对不上。
      if (_sessionTitle.isEmpty || _sessionTitle == newChatTitle) {
        _sessionTitle = message.length > _kSessionTitleMax
            ? message.substring(0, _kSessionTitleMax)
            : message;
      }
    });
    _stickToBottom(force: true, animate: true);

    // 空态下发出第一条消息，这时才真正建会话——**全项目唯一的建会话时机**。
    // [_onSendTap] 走到这之前已经建过了（它要先建再清输入框），这里主要给「一键生图」兜底；
    // [_createSession] 自带在途去重，重复调不会多建。
    //
    // ⚠️ 顺序：用户气泡**先上屏，再** await 建会话。反过来（2026-08-07 前的写法）时，
    // 「一键生图」点完要干等一整趟 POST /session/new（真机上约 1s）文案才出现在对话框里，
    // 点下去像没反应。建会话失败时把刚上屏的这几条撤掉、标题也还原，界面回到点击前的样子
    // ——错误提示由 [_createSession] 内部弹，用户重点一次即可。
    if (_sessionId.isEmpty) {
      await _createSession();
      if (!mounted) {
        return;
      }
      if (_sessionId.isEmpty) {
        setState(() {
          _messages.removeWhere((item) => userMsgIds.contains(item.id));
          _sessionTitle = prevTitle;
        });
        return;
      }
    }
    await _dispatchChat(
      message,
      styleKey,
      images.map((image) => image.url).toList(),
      imageBubbleIds: imageBubbleIds,
      textBubbleId: textBubbleId,
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

  /// 本轮回复图的占位比例。渐变占位盒与真图取同一个值，100% 换图时高度才不跳。
  ///
  /// 🔶 与小程序的差异：小程序在图生图/融合图时会改用**用户原图**的比例（后端等比放大、
  /// 不改宽高比），App 侧从来没接过那一段（`_sendChat` 不往下传用户图的 pad），
  /// 这次同步维持现状 —— 图加载完会用真实尺寸改写比例（见 [_AiBubbleImage]），
  /// 差别只是加载中那一下的占位高度。
  double get _replyImagePad => _orientationPad;

  /// 发一次 `/chat` 并渲染回复（可被「重试」重复调用，不再追加用户气泡）。
  Future<void> _dispatchChat(
    String message,
    String? styleKey,
    List<String> urls, {
    /// 本轮用户图片气泡的本地 id（顺序同 [urls]）与文字气泡的本地 id，
    /// 交给 [_StreamState] 保管，等 `init` 事件把服务端 message_id 贴回去。
    /// 重试路径（[_onRetryMessage]）不重建用户气泡，传空即可。
    List<int> imageBubbleIds = const <int>[],
    int textBubbleId = 0,
  }) async {
    // 占位气泡就是最终那一个气泡：文字打进它的 content、图片挂进它的 images（需求 3：图文同一气泡）
    final holder = _AiMessage(
      id: ++_uid,
      role: 'assistant',
      kind: _MsgKind.rich,
      loading: true,
    )..genPad = _orientationPad;
    setState(() {
      _messages.add(holder);
      _sending = true;
    });
    _stickToBottom(force: true, animate: true);

    // 局部持有这次的流状态：[_stream] 会被停止生成/切会话清空，catch 里靠它分辨
    // 「这条流是不是还归我管」，以及「断线前已经吐出内容了没有」。
    final stream = _beginStream(
      holder.id,
      imageBubbleIds: imageBubbleIds,
      textBubbleId: textBubbleId,
    );
    try {
      final call = _api.chatStream(
        sessionId: _sessionId,
        message: message,
        imgOrientation: _normalizedOrientation,
        imgStyle: styleKey,
        imageUrls: urls,
        onEvent: (event) => _onStreamEvent(holder.id, event),
      );
      _chatCall = call;
      final reply = await call.future;
      _chatCall = null;
      if (!mounted) {
        return;
      }
      // 一次 AI 调用完成后对齐余额。⚠️ **端上不扣数**：swagger 里没有「消费星币」的 Client
      // 端点，扣费在服务端发生（消费记录见 getUserAccountTrade inOutType=2），端上自减就是双重记账。
      unawaited(_loadTokenBalance());
      _finishStream(holder.id, reply);
      return;
    } catch (error) {
      _chatCall = null;
      if (!mounted) {
        return;
      }
      // 走到任何一条失败分支，这条流就都不归 _stream 管了（迟到的事件一律丢弃）。
      // ⚠️ 必须在动界面之前清，否则 _onStreamEvent 还会往一个正在被拆的气泡里写。
      if (identical(_stream, stream)) {
        _stream = null;
      }
      _progressTimer?.cancel();
      _progressTimer = null;
      _typeTimer?.cancel();
      _typeTimer = null;
      if (error is AiApiException && error.aborted) {
        setState(() {
          _messages.removeWhere((item) => item.id == holder.id);
          _sending = false;
        });
        return; // 用户主动停止，静默
      }
      // 流中途断了、但预描述/图/文字已经上屏：保留已生成的部分（用户明明已经看到图了，
      // 这时候把整条换成失败卡片更像 bug）。错误照常按码分发提示，但**不给重试入口**
      // —— 这一轮服务端已经算过、也可能已扣过费，重试等于再来一遍。
      if (stream.hasContent) {
        final aiError = error is AiApiException ? error : null;
        debugPrint(
          '[BoltStar] 流中断，保留已上屏内容 code=${aiError?.code} ${aiError?.detail}',
        );
        _settleStreamAt(holder.id);
        await _ai.handleError(
          context,
          error,
          onBanned: (_) => setState(() => _banned = true),
        );
        return;
      }
      // 30xxx 上游失败 / 未知错误（31001）：气泡**原地**变成可重试的失败卡，而不是弹一次性
      // 提示后把这一轮抹掉（对齐小程序 2026-07-30）。网关白名单那类自带 userMessage 的错误
      // 要原样弹给用户看（含 RequestId），仍走 handleError。
      final aiError = error is AiApiException ? error : null;
      final code = aiError == null || aiError.code == 0 ? 31001 : aiError.code;
      final inlineFailure =
          (aiError?.userMessage == null || aiError!.userMessage!.isEmpty) &&
          ((code >= 30000 && code < 31000) || code == 31001);
      final index = _messages.indexWhere((item) => item.id == holder.id);
      if (inlineFailure && index >= 0) {
        if (aiError?.detail != null) {
          debugPrint('[BoltStar] code=$code ${aiError!.detail}');
        }
        _retryByMessage[holder.id] = _RetryPayload(message, styleKey, urls);
        setState(() {
          _messages[index]
            ..loading = false
            ..typing = false
            ..failed = true;
          _sending = false;
        });
        _stickToBottom(force: true, animate: true);
        return;
      }
      setState(() {
        _messages.removeWhere((item) => item.id == holder.id);
        _sending = false;
      });
      await _ai.handleError(
        context,
        error,
        onRetry: () => _dispatchChat(message, styleKey, urls),
        onBanned: (_) => setState(() => _banned = true),
      );
    }
  }

  /// 失败卡「重新生成」：删掉这张卡，用原参数重发一次（同样过发送同步闸，防连点重复发）。
  Future<void> _onRetryMessage(int messageId) async {
    final retry = _retryByMessage[messageId];
    if (retry == null || _sending || _submitting || _banned) {
      return;
    }
    await _guardedSend(() async {
      // 重试也是一次真实调用，同样要过服务端校验（上一轮失败到现在，余额可能已经不够了）。
      // 失败卡片原样留着：这里什么都还没删，用户买完星币回来还能接着点重试。
      if (!await _guardAiDialogue() || !mounted) {
        return;
      }
      _retryByMessage.remove(messageId);
      setState(() => _messages.removeWhere((item) => item.id == messageId));
      await _dispatchChat(retry.message, retry.styleKey, retry.urls);
    });
  }

  /// 失败卡右上角「删除」：只清本地这张卡（服务端本来就没这条消息）。
  void _onFailureDelete(int messageId) {
    _retryByMessage.remove(messageId);
    setState(() => _messages.removeWhere((item) => item.id == messageId));
  }

  // ⚠️ 2026-08-07 起没有「一次性拿到全文再渲染」这条路了（原 `_renderReply` / `_startTyping`
  //    已删）：主链路是流式，文字边收边打（[_pumpTyping]），服务端只在汇总结果里给全文的
  //    情况由 [_finishStream] 兜底补进同一个打字机。
  //    非流式的 `BoltStarAiApi.chat()` 仍在，但只作手动回退用，页面没有接它的渲染路径。

  // ── 流式回复（SSE） ───────────────────────────────────────
  //
  // 事件顺序（服务端 2026-08-07 起新增 init / heartbeat / **mode**）：
  //   生图：  init → pre_text「星宝努力思考中」→ heartbeat → mode:"image" → pre_text(换成真文案)
  //          → progress(5/15/30/45/50/80/85/90) → image → text（逐条）→ progress(100) → done
  //   纯文字：init → pre_text「星宝努力思考中」→ heartbeat → mode:"text" → pre_text:""
  //          → text（逐条）→ done
  //
  // ⚠️ **渐变占位盒（生图进度条）的显形时机由 mode 决定，不是 pre_text**
  //    （2026-08-28 补齐，对齐小程序 `chat.js beginStream` 上方那段注释）。
  //    两条路开头一模一样（都有那句「星宝努力思考中」），服务端要到 mode 事件才知道走哪条。
  //    本页原来是 pre_text 一到就把占位盒亮出来 —— 于是**纯文字对话也会先闪一个生图占位盒
  //    再收掉**，正是用户报的「纯文字对话不该有加载图片的 loading」。
  //    现在 pre_text 只管写文案，mode:"image" 才唤出占位盒 + 起进度。
  //    mode:"text" 之后紧跟的 pre_text:"" 是服务端来擦「思考中」那句的，擦完气泡若空了
  //    要把三点动画放回去，别晾出一个空白气泡。
  // ⚠️ image 排在 progress 90(uploaded) **之后**，不是 50% —— 50 那级只是「初稿完成」，
  //    图还没下载上传完、URL 拿不到。占位盒因此几乎会挂满整个生成过程。
  //
  // 兼容没有 mode 的老部署：progress 事件照旧能把占位盒唤出来（见 case 'progress'），
  // 只是显形时机从 pre_text 推迟到第一条 progress —— 两者本来就前后脚，观感无差。

  _StreamState _beginStream(
    int holderId, {
    List<int> imageBubbleIds = const <int>[],
    int textBubbleId = 0,
  }) {
    final stream = _StreamState(
      holderId,
      imageBubbleIds: imageBubbleIds,
      textBubbleId: textBubbleId,
    );
    _stream = stream;
    return stream;
  }

  void _onStreamEvent(int holderId, AiStreamEvent event) {
    final stream = _stream;
    if (stream == null || stream.holderId != holderId || !mounted) {
      return; // 已被停止生成/切会话清掉，这条流的后续事件一律丢弃
    }
    final index = _messages.indexWhere((item) => item.id == holderId);
    if (index < 0) {
      return; // 气泡被删了（用户长按删除），静默丢弃
    }

    switch (event.type) {
      // 开流握手。不带要渲染的内容（界面继续挂着三点动画），但 2026-08-28 起**带回本轮
      // 用户消息的 message_id** —— 刚发出去的图/文能不能删得掉全靠它，见 [_applyUserMessageIds]。
      case 'init':
        _applyUserMessageIds(stream, event);

      // 心跳：长等待期间用来续命连接的空包，什么都不用做。
      // 显式列出来，免得以后有人以为漏处理了。
      case 'heartbeat':
        break;

      // 这一轮走生图还是纯文字。**渐变占位盒只认这个事件**（理由见本段上方注释）。
      case 'mode':
        {
          final mode = event.mode.trim().toLowerCase();
          if (mode != 'image' && mode != 'text') {
            break; // 未知取值：当没收到，让 progress 那条兜底路照旧生效
          }
          stream.mode = mode;
          if (mode == 'image') {
            // 占位盒显形并起步到 5%：这两件事原来挂在 pre_text 上，现在挪到这儿。
            _markStreamStarted(index, showProgress: true);
            _applyProgress(
              stream.target == 0 ? 5 : stream.target,
              stage: 'starting',
            );
            _stickToBottom(force: true, animate: true);
          }
        }

      // 预描述。服务端会推**两条**：先秒回一句占位的「星宝努力思考创作中」顶掉空等，
      // 之后按 mode 分两种走向 —— 生图是替换成真正的「正在为您绘制…」，纯文字是推一条**空串**
      // 把它擦掉。前端不用分辨是哪一条，直接覆盖即可 —— 所以这里没有「只写第一次」的判断，别加。
      case 'pre_text':
        {
          final content = event.content.trim();
          if (content.isEmpty) {
            // 空串 = 擦掉预描述（mode:"text" 之后紧跟的那条）。擦完气泡里可能什么都不剩，
            // 正文还在路上，这时候要把三点动画放回去，别晾出一个空白气泡。
            final message = _messages[index];
            if (message.preText.isEmpty) {
              return;
            }
            final emptied =
                message.content.isEmpty &&
                !message.streaming &&
                message.images.isEmpty;
            if (emptied) {
              // 屏上又什么都不剩了：这时候断线该走「失败卡 + 可重试」，而不是
              // 「保留已生成内容」那条（那条不给重试入口，见 _dispatchChat 的 catch）。
              stream.hasContent = false;
            }
            setState(() {
              _messages[index]
                ..preText = ''
                ..loading = emptied || message.loading;
            });
            return;
          }
          // 第一条是「凭空多出一块内容」，必须强制贴底；后一条只是就地换字，
          // 这时候还硬拽用户回底部，正在上翻看历史的人会被打断。
          final first = _messages[index].preText.isEmpty;
          stream.hasContent = true;
          // 只收三点动画；占位盒交给 mode:"image"（纯文字这一轮永远不该出现它）。
          _markStreamStarted(index, showProgress: false);
          setState(() => _messages[index].preText = content);
          _stickToBottom(force: first, animate: true);
        }

      case 'progress':
        // mode 已经定了走纯文字：迟到/多余的 progress 不能把占位盒翻出来。
        if (stream.mode == 'text') {
          break;
        }
        // ⚠️ `stream.target < 100` 这个闸不能省：读数走到 100 时占位盒已经收起、真图已经上屏，
        // 这时候服务端再补推一条 progress（重复/迟到的都可能），不挡就会把占位盒重新翻出来
        // 盖在真图上。[_applyProgress] 那边只挡了「进度倒退」，挡不住这里的显形。
        //
        // 这一行同时是**没有 mode 的老部署**的兜底：进度一来照样把占位盒唤出来。
        _markStreamStarted(index, showProgress: stream.target < 100);
        _applyProgress(
          (event.progress ?? 0).round(),
          stage: event.stage,
          message: event.message,
        );

      // 图到了先收进 images，但要等读数真的爬到 100% 才换掉占位盒（见 [_showProgress]）
      case 'image':
        {
          final url = event.content.trim();
          if (url.isEmpty) {
            return;
          }
          stream.hasContent = true;
          setState(() {
            _messages[index]
              ..loading = false
              ..images.add(_AiImage(url: url, pad: _replyImagePad));
          });
          _stickToBottom(force: true, animate: true);
        }

      // 文字逐条推送：只往队列里追加，真正上屏交给 _pumpTyping（边收边打）
      case 'text':
        if (event.content.isEmpty) {
          return;
        }
        stream.hasContent = true;
        stream.chars.addAll(event.content.runes.map(String.fromCharCode));
        if (_messages[index].loading || !_messages[index].typing) {
          setState(() {
            _messages[index]
              ..loading = false
              ..typing = true;
          });
        }
        _pumpTyping();

      case 'done':
        _applyProgress(100, stage: 'done');

      default:
        break; // 文档未列出的事件类型：忽略，别让未知事件把这一轮搞挂
    }
  }

  /// 把 SSE `init` 事件带回的服务端 message_id 贴到刚上屏的用户气泡上。
  ///
  /// 事件形状（后端 2026-08-28 新增）：
  /// ```json
  /// { "type": "init", "user_msg_id": "文字消息id", "image_msg_ids": ["图1id", "图2id"] }
  /// ```
  /// `image_msg_ids` 与请求里的 `image_urls` **顺序一一对应**（一张图 = 一条消息 = 一个 id）。
  ///
  /// ⚠️ 这一步解决的是「发一张照片 → 立刻删 → 退出重进又回来」：在此之前 `/chat` 全程不回
  /// 消息 id，本轮新发的气泡 `serverId` 是空的，删除只能删本地（[_deleteBubbleImage] 里那个
  /// `serverId.isNotEmpty` 判断过不去）。贴上之后，刚发的照片点删除就会真的打
  /// `DELETE /chat/history`，不必再等一次历史刷新。
  ///
  /// 图片气泡**两处都贴**（消息本身 + `images[0]`），与历史消息的模型保持一致：
  /// 删单图走 `images[0].serverId`、删整条走消息上的那个，重复由 [_deleteMessage] 去重收口。
  ///
  /// 不 setState：`serverId` 不参与渲染，贴上去只是为了后续删除能用，刷一帧纯属浪费。
  /// 老部署不推这两个字段 → 取到空，行为与改动前完全一致。
  void _applyUserMessageIds(_StreamState stream, AiStreamEvent event) {
    _AiMessage? bubbleOf(int localId) {
      if (localId == 0) {
        return null;
      }
      for (final item in _messages) {
        if (item.id == localId) {
          return item;
        }
      }
      return null; // 气泡已被用户删掉：静默跳过
    }

    if (event.userMsgId.isNotEmpty) {
      bubbleOf(stream.textBubbleId)?.serverId = event.userMsgId;
    }
    // 按位取：后端给的条数理论上等于本轮发的图数，取两者的较小值，多/少都不越界。
    final count = event.imageMsgIds.length < stream.imageBubbleIds.length
        ? event.imageMsgIds.length
        : stream.imageBubbleIds.length;
    for (var i = 0; i < count; i++) {
      final id = event.imageMsgIds[i];
      final bubble = bubbleOf(stream.imageBubbleIds[i]);
      if (id.isEmpty || bubble == null) {
        continue;
      }
      bubble.serverId = id;
      if (bubble.images.isNotEmpty) {
        bubble.images.first.serverId = id;
      }
    }
  }

  /// 收起三点动画 /（按需）让渐变占位盒显形，对齐小程序 `showProgress` 的同名动作。
  ///
  /// [showProgress] 为 false 时**只**收三点动画，绝不碰 `streaming` —— 纯文字那一轮
  /// 靠的就是这一点：pre_text 到了先把三点收掉，占位盒留给 `mode:"image"` 去开。
  /// 只在真要改时才 setState：一次生图有十来条 progress 事件，每条都无脑再写一遍纯属白刷渲染。
  void _markStreamStarted(int index, {required bool showProgress}) {
    final message = _messages[index];
    final needLoadingOff = message.loading;
    final needStreamingOn = showProgress && !message.streaming;
    if (!needLoadingOff && !needStreamingOn) {
      return;
    }
    setState(() {
      if (needLoadingOff) {
        _messages[index].loading = false;
      }
      if (needStreamingOn) {
        _messages[index].streaming = true;
      }
    });
  }

  /// 收到服务端的里程碑：只记成**目标值**，不直接上屏 —— 上屏交给 [_pumpProgress] 一步步爬过去。
  /// 目标只增不减，迟到/乱序的小值连同它的 stage 一起丢。
  void _applyProgress(int value, {String stage = '', String message = ''}) {
    final stream = _stream;
    // ⚠️ 别写成 `value.clamp(0, 100)`：`num.clamp` 回的是 **num**，赋给 int 字段编译不过
    //（同一个坑见 [_clampPad] 上方注释）。
    final int next = value < 0
        ? 0
        : value > 100
        ? 100
        : value;
    if (stream == null || next <= stream.target) {
      return;
    }
    stream.target = next;
    stream.stage = stage;
    stream.message = message;
    _pumpProgress();
  }

  /// 进度补间：每 [_kProgressTick] 往 target 走一步，到了就停表（下一条里程碑再把它叫醒）。
  void _pumpProgress() {
    if (_progressTimer != null) {
      return; // 已经在爬了，新的 target 自然会被追上
    }

    void step() {
      _progressTimer = null;
      final stream = _stream;
      if (stream == null || !mounted) {
        return;
      }
      final index = _messages.indexWhere((item) => item.id == stream.holderId);
      final gap = stream.target - stream.progress;
      if (index < 0 || gap <= 0) {
        return;
      }
      final stride = gap > _kProgressNearGap
          ? _kProgressStepFar
          : _kProgressStepNear;
      final next = stream.progress + stride > stream.target
          ? stream.target
          : stream.progress + stride;
      _showProgress(index, next);
      if (stream.progress < stream.target) {
        _progressTimer = Timer(_kProgressTick, step);
      }
    }

    step(); // 首步立即走，别让占位盒先亮一下 0%
  }

  /// 把补间出来的值写上屏。文案按**已上屏**的值出，爬到目标那一刻才用目标的 stage/message
  /// —— 否则会出现「52% + 正在优化细节…」这种数字与文案对不上的组合。
  ///
  /// 到 100% 就把 [_AiMessage.streaming] 落下：占位盒收起、真图原地顶上。
  /// **不能等 [_settleStreamAt]** —— 那要等打字机把几十条 text 全打完才收，
  /// 图会被压到文字之后好几秒才出来。服务端漏推 100 时仍由它兜底置 false。
  void _showProgress(int index, int value) {
    final stream = _stream;
    if (stream == null) {
      return;
    }
    stream.progress = value;
    final reached = value >= stream.target;
    setState(() {
      _messages[index]
        ..progress = value
        ..progressLabel = _progressLabel(
          value,
          stage: reached ? stream.stage : '',
          message: reached ? stream.message : '',
        );
      if (value >= 100) {
        _messages[index].streaming = false;
      }
    });
    if (value >= 100) {
      _stickToBottom(); // 占位盒换成真图，高度一般会变，跟着贴一下底
    }
  }

  /// 流式打字机：一路追着积压的字打，队列空了就等下一段（每帧字数见 [_kStreamTypeTicks]）。
  /// 与 [_startTyping] 共用 [_typeTimer]，所以 [_stopGenerate] 那套清理原样有效。
  void _pumpTyping() {
    if (_typeTimer != null) {
      return; // 已经在打了，新来的字自然会被追上
    }

    void step() {
      _typeTimer = null;
      final stream = _stream;
      if (stream == null || !mounted) {
        return;
      }
      final index = _messages.indexWhere((item) => item.id == stream.holderId);
      if (index < 0) {
        _stream = null;
        setState(() => _sending = false);
        return;
      }
      final backlog = stream.chars.length - stream.shown;
      if (backlog <= 0) {
        if (stream.ended) {
          _settleStream(index);
          return;
        }
        _typeTimer = Timer(_kStreamIdleTick, step); // 等服务端推下一段
        return;
      }
      final perTick = (backlog / _kStreamTypeTicks).ceil();
      stream.shown += perTick < 1 ? 1 : perTick;
      if (stream.shown > stream.chars.length) {
        stream.shown = stream.chars.length;
      }
      setState(() {
        _messages[index].content = stream.chars.take(stream.shown).join();
      });
      _stickToBottom(); // 内部按 _kStickThrottle 节流，并尊重「用户已上翻」
      _typeTimer = Timer(_kTypeTick, step);
    }

    step();
  }

  /// 流结束（成功）：标记 ended 并按汇总结果兜底补齐，剩下的交给打字机排空后 [_settleStream] 收尾。
  /// 兜底是必要的 —— 事件流里漏推、或服务端某次只在最终结果里给全文时，界面不能少内容。
  void _finishStream(int holderId, AiChatReply reply) {
    final stream = _stream;
    if (stream == null || stream.holderId != holderId) {
      return; // 期间被停止生成/切会话清掉了
    }
    stream.ended = true;
    final index = _messages.indexWhere((item) => item.id == holderId);
    if (index < 0) {
      _stream = null;
      setState(() => _sending = false);
      return;
    }
    final shown = _messages[index].images.map((item) => item.url).toSet();
    final missing = [
      for (final url in reply.images)
        if (url.isNotEmpty && !shown.contains(url)) url,
    ];
    if (missing.isNotEmpty) {
      setState(() {
        _messages[index].images.addAll(
          missing.map((url) => _AiImage(url: url, pad: _replyImagePad)),
        );
      });
    }
    // 一个 text 事件都没收到、但汇总里有文字：按最终文本补上，照样走打字机
    if (stream.chars.isEmpty && reply.text.isNotEmpty) {
      stream.chars.addAll(reply.text.runes.map(String.fromCharCode));
      setState(() => _messages[index].typing = true);
    }
    _pumpTyping();
  }

  /// 按 id 收尾（流中断时用：这时打字机不一定还在跑，不能等它来触发）。
  void _settleStreamAt(int holderId) {
    final index = _messages.indexWhere((item) => item.id == holderId);
    if (index < 0) {
      _stream = null;
      setState(() => _sending = false);
      return;
    }
    _settleStream(index);
  }

  /// 收尾：隐藏占位盒、结束打字机、放行发送。
  /// 流都结束了就没什么可等的，补间没爬完也直接落到 100（服务端漏推 100 时也靠这一手兜底）。
  void _settleStream(int index) {
    _stream = null;
    _progressTimer?.cancel();
    _progressTimer = null;
    final message = _messages[index];
    // 一句话、一张图都没有（服务端只推了进度就结束）：留个空气泡纯属让人以为坏了
    if (message.content.isEmpty &&
        message.preText.isEmpty &&
        message.images.isEmpty) {
      setState(() {
        _messages.removeWhere((item) => item.id == message.id);
        _sending = false;
      });
      AppToast.show(context, AppL10n.of(context).aiEmptyReply);
      return;
    }
    setState(() {
      _messages[index]
        ..typing = false
        ..streaming = false
        ..progress = 100;
      _sending = false;
    });
    _stickToBottom(force: true, animate: true);
  }

  /// 停止生成：中断请求 + 结束打字机（已打出的内容保留）。
  /// [silent] 用于切会话 / 页面销毁时的清理（**不动 `_sending`**，调用方自己归位）。
  void _stopGenerate({bool silent = false}) {
    _chatCall?.abort();
    _chatCall = null;
    _typeTimer?.cancel();
    _typeTimer = null;
    _progressTimer?.cancel(); // 进度补间同理（见 [_pumpProgress]）
    _progressTimer = null;
    // 之后 abort 的错误与迟到的 SSE 事件都会认出「这条流已经不归我管」
    _stream = null;
    if (silent || !mounted) {
      return;
    }
    setState(() {
      // 还什么都没渲染出来的气泡直接去掉：加载态的占位气泡，以及只收到进度、
      // 连预描述都还没来的流式气泡（留着就是一条空白气泡）
      _messages.removeWhere(
        (item) =>
            item.loading ||
            (item.streaming &&
                item.content.isEmpty &&
                item.preText.isEmpty &&
                item.images.isEmpty),
      );
      for (final item in _messages) {
        item
          ..typing = false
          ..streaming = false;
      }
      _sending = false;
    });
  }

  /// 星币权限控制（文档 §5.5）：发起对话前的**服务端**校验
  /// （2026-08-12 `GET /Client/Order/chkAiDialogue`，见 [AiToken.canDialogue]）。
  ///
  /// 这是**唯一**的闸。此前那道 `_guardToken()`（端上按本地假余额比大小 + `limitEnabled=false`）
  /// 已随 [AiToken] 一并删除：它既不知道一轮对话扣多少星币，开关又一直关着，余额为 0 也照发
  /// —— 留着只会和服务端口径打架。
  ///
  /// 校验接口本身失败一律放行（见 [AiToken.canDialogue]），所以这里只处理「明确不允许」。
  /// 顺带刷一次余额：会话列表页那颗胶囊的数字要与「不够了」这个结论对得上。
  Future<bool> _guardAiDialogue() async {
    final verdict = await AiToken.canDialogue();
    if (verdict.allowed) {
      return true;
    }
    if (!mounted) {
      return false;
    }
    unawaited(_loadTokenBalance());
    _showTokenShortDialog(verdict);
    return false;
  }

  /// 星币不足弹窗。用全站统一的 [showAppConfirmDialog]（与删除确认等同款），不另造样式。
  ///
  /// 文案来源（2026-08-12 真机）：后端原话是「token余额不足，需要最低余额：30.0 token」
  /// ——「token」是内部叫法（对外一律「星币」）、「30.0」是浮点、整句还带着接口味，
  /// 直接甩给用户不合适。所以：**数字用后端的，话是我们自己说的**；抠不到数字才退回
  /// 后端原话（把 token 换成星币）—— 403 也可能是余额之外的别的理由，
  /// 那时硬套「星币不足」反而是错的。
  ///
  /// 🔶 与小程序的差异：小程序的确认键是「去购买」，直达星币管理页；**APP 侧还没有购买页**
  /// （支付体系目前只有小程序端有），所以这里只有一颗「知道了」。IAP 接上后补跳转即可。
  void _showTokenShortDialog(AiDialogueVerdict verdict) {
    final l10n = AppL10n.of(context);
    final requiredText = verdict.requiredText;
    final fallback = verdict.message.replaceAll(
      RegExp('token', caseSensitive: false),
      l10n.aiTokenUnit,
    );
    final message = requiredText.isNotEmpty
        ? l10n.aiTokenShortMessage(requiredText)
        : (fallback.isNotEmpty ? fallback : l10n.aiTokenEmptyMessage);
    showAppConfirmDialog(
      context,
      title: l10n.aiTokenEmptyTitle,
      message: message,
      icon: Icons.toll_rounded,
      showCancel: false,
      confirmLabel: l10n.otaKnow,
    );
  }

  // ── 工具面板 ──────────────────────────────────────────────

  /// 「点外面就收起」（对齐小程序 `closeTools`）。收的是两个上拉浮层
  /// （图片操作条 2026-08-10 起常驻，不再参与收起）。
  /// 入口：点消息区任意位置、点顶部导航行、输入框获得焦点（键盘和浮层不该同时占着底部）。
  ///
  /// ⚠️ 故意**不做**全屏透明遮罩：遮罩会把拖动一起吃掉，浮层开着时聊天记录就滑不动了。
  /// 挂在容器上的 onTap 只吃点击，滚动照常交给 ListView（手势竞技场里拖动归可滚动组件）。
  /// 气泡里的图有自己的 onTap（要看大图），点图不会收浮层 —— 与小程序一致，是有意的。
  void _closeTools() {
    if (!_showOrientationPicker && !_showStylePicker) {
      return;
    }
    setState(() {
      _showOrientationPicker = false;
      _showStylePicker = false;
    });
  }

  /// 点空白处：**收键盘** + 收浮层。
  ///
  /// ⚠️ 2026-08-28 补的是前半句。小程序不用管这件事 —— 微信原生输入框点外面会自己收起；
  /// Flutter 的 [TextField] 不会，焦点一直留着，键盘就一直杵在那儿挡住半屏聊天记录，
  /// 想收只能按系统返回键（iOS 连返回键都没有）。
  ///
  /// 只在真的有焦点时 unfocus：没焦点时白调一次也会让 [FocusManager] 走一遍焦点变更。
  /// ⚠️ 输入框自己的 onTap 仍走 [_closeTools] —— 点输入框是要**唤起**键盘，不是收。
  void _dismissKeyboardAndTools() {
    final focus = FocusManager.instance.primaryFocus;
    if (focus != null && focus.hasFocus) {
      focus.unfocus();
    }
    _closeTools();
  }

  /// 欢迎页灵感词：只填入输入草稿，**不自动发送**，避免误触就直接建会话 / 触发生图计费。
  void _useSuggestion(String prompt) {
    _closeTools();
    setState(() {
      _input.text = prompt;
      _input.selection = TextSelection.collapsed(offset: prompt.length);
    });
  }

  Future<void> _pickImages({required bool camera}) async {
    _closeTools();
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

  /// 「一键生图」按钮：开合风格浮层（视觉稿改成靠近输入区的上拉浮层，不再是底部弹窗）。
  void _toggleStylePicker() {
    setState(() {
      _showStylePicker = !_showStylePicker;
      _showOrientationPicker = false;
    });
  }

  /// 比例按钮：开合比例浮层。
  void _toggleOrientationPicker() {
    setState(() {
      _showOrientationPicker = !_showOrientationPicker;
      _showStylePicker = false;
    });
  }

  void _onOrientationTap(String key) {
    setState(() {
      _orientation = key;
      _showOrientationPicker = false;
    });
  }

  /// 选中风格即发（浮层副标题已写明「选择后立即发送」）：按语种自动拼 message
  ///（如「生成图片-漫画」），img_style 触发生图（文档 §5.3.2）。
  ///
  /// 需求 15.3「发送完要关掉这个弹层」：**发之前就收**（[_closeTools]，两个上拉浮层一起收）。
  /// 不放在发送之后 —— 发送这一步可能先弹服务协议确认 / 星币不足弹窗，浮层还开着的话
  /// 会隔着弹窗露在下面；而且失败路径下它同样该收起来。
  Future<void> _onStyleTap(String key) async {
    _closeTools();
    // 同样过一遍同步闸（见 [_guardedSend]）：这条路径也要先建会话，连点样式一样会重复发。
    await _guardedSend(() => _sendChat(_ai.genMessage(key), styleKey: key));
  }

  // ── 消息长按菜单 ──────────────────────────────────────────

  /// 长按气泡的**空白处**（内边距、边缘）→ 删除确认框。
  ///
  /// 2026-08-10 需求 2 重做：原先长按整个气泡弹底部操作面板，与正文的「选字/复制」是两套
  /// 叠在一起的交互。现在按**区域**分工，互不重叠：
  /// - 正文是 [SelectableText]，它在手势竞技场里自己吃掉落在文字上的长按 → 只走选字/复制；
  /// - 长按气泡内边距、边缘等空白处才冒泡到这里 → 弹与全站同版式的删除确认框
  ///   （小程序侧同步撤掉了 `wx.showActionSheet`，两端从此都不再用系统面板）。
  ///
  /// 图片的下载/投屏/删除不再靠长按，改成常驻在图下方的操作条（需求 7，见 [_onImageActionTap]）。
  Future<void> _onBubbleLongPress(_AiMessage message) async {
    // 生成中的气泡不给删：请求还在途，删了本地这条也停不下服务端那边（要停用「停止生成」）
    if (message.loading || message.typing || message.streaming) {
      return;
    }
    final l10n = AppL10n.of(context);
    final confirmed = await showAppConfirmDialog(
      context,
      title: l10n.aiDeleteMessageTitle,
      message: message.images.isEmpty
          ? l10n.aiDeleteMessageDesc
          : l10n.aiDeleteMessageWithImagesDesc,
      icon: Icons.delete_outline_rounded,
      tone: AppDialogTone.danger,
      confirmLabel: l10n.aiDelete,
    );
    if (confirmed == true && mounted) {
      await _runDelete(() => _deleteMessage(message));
    }
  }

  /// 图下方**常驻**操作条上的一次点击（需求 7）：下载/投屏都只针对这一张；
  /// 删除也只摘掉这一张（气泡里还有文字或别的图就留着，都没了才整条移除），
  /// 且同样过一次确认框 —— 按钮从「长按才出现」变成常驻后，误触一下就少一张图。
  Future<void> _onImageActionTap(
    String action,
    _AiMessage message,
    int index,
  ) async {
    if (index >= message.images.length) {
      return;
    }
    final url = message.images[index].url;
    switch (action) {
      case 'download':
        await _downloadImage(url);
      case 'cast':
        await _castImage(url);
      case 'delete':
        final l10n = AppL10n.of(context);
        final confirmed = await showAppConfirmDialog(
          context,
          title: l10n.aiDeleteImageTitle,
          message: l10n.aiDeleteImageDesc,
          icon: Icons.delete_outline_rounded,
          tone: AppDialogTone.danger,
          confirmLabel: l10n.aiDelete,
        );
        if (confirmed == true && mounted) {
          await _runDelete(() => _deleteBubbleImage(message, index));
        }
    }
  }

  /// 删除是一次真实往返（历史消息要逐个 message_id 打接口），期间加 loading 遮罩挡住重复点击，
  /// 与会话列表页的删除同款（对齐小程序 `confirmDeleteMessage`）。
  Future<void> _runDelete(Future<void> Function() task) async {
    AppLoadingDialog.show(context, AppL10n.of(context).galDeleting);
    try {
      await task();
    } finally {
      AppLoadingDialog.hide(context);
    }
  }

  /// 删整条消息。图文合并进一个气泡后一条消息可能对应**多个** message_id
  ///（文字行 + 每张图各一行），逐个删掉，漏一个就会重进会话时诡异地只剩半条。
  Future<void> _deleteMessage(_AiMessage message) async {
    // 历史消息带服务端 id 走接口删除；本轮新产生的消息接口未回 id，仅本地移除
    //（重进会话会重新出现，待后端在 /chat 响应中带回 message_id 后可彻底删除）
    //
    // ⚠️ **Set 去重**（2026-08-28）：用户图片消息的 id 在 message 与 images[0] 上各记了一份
    //（见 [_buildHistoryMessages] 的说明），不去重就会对同一个 message_id 打两次 DELETE，
    // 第二次多半回「消息不存在」，把一次成功的删除报成失败。
    // Set 字面量是 LinkedHashSet，插入顺序保持不变（文字行仍排在图片行前面）。
    final serverIds = <String>{
      if (message.serverId != null && message.serverId!.isNotEmpty)
        message.serverId!,
      for (final image in message.images)
        if (image.serverId != null && image.serverId!.isNotEmpty)
          image.serverId!,
    };
    try {
      for (final serverId in serverIds) {
        await _api.deleteMessage(_sessionId, serverId);
      }
      if (!mounted) {
        return;
      }
      _retryByMessage.remove(message.id);
      setState(() {
        _messages.removeWhere((item) => item.id == message.id);
      });
      AppToast.show(context, AppL10n.of(context).aiDeleted);
    } catch (error) {
      // 错误提示要盖在「删除中」遮罩之上，先关掉它再弹（[_runDelete] 的 finally 再关一次是空操作）
      AppLoadingDialog.hide(context);
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
      AppLoadingDialog.hide(context); // 同 [_deleteMessage]：错误提示要盖在遮罩之上
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

  /// 「下载」：拉到本地临时文件 → **存进系统相册**（2026-08-28 需求 17）。
  ///
  /// 原来只写到应用缓存目录就完事，提示语还得如实写「保存到系统相册待接入插件」——
  /// 用户在相册里找不到图，等于没下载成。现在补了原生通道
  /// （[NativeDeviceApi.saveImageToGallery]：Android→MediaStore、iOS→Photos addOnly），
  /// 三种收尾各自给话：拉不到图 / 拉到了但写相册失败（多半是权限被拒）/ 成功。
  Future<void> _downloadImage(String url) async {
    AppLoadingDialog.show(context, AppL10n.of(context).castProcessing);
    String? path;
    var saved = false;
    try {
      path = await _downloadToFile(url);
      if (path != null) {
        saved = await NativeDeviceApi.saveImageToGallery(path);
      }
    } finally {
      AppLoadingDialog.hide(context);
    }
    if (!mounted) {
      return;
    }
    final l10n = AppL10n.of(context);
    AppToast.show(
      context,
      path == null
          ? l10n.aiImageExpired
          : (saved ? l10n.aiDownloaded : l10n.aiDownloadFailed),
    );
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

    // 「投屏」是主动操作：本来就连着 / 刚在弹层里连上，都提醒一次电量
    // （2026-08-27 补齐 08-21 遗留入口）。放在下载蒙层之前，不与蒙层抢屏。
    final tipTarget = target;
    if (tipTarget != null) {
      await showLowBatteryTipIfNeeded(context, widget.state, tipTarget.id);
      if (!mounted) {
        return;
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

  /// 未连接时的设备选择弹层（与官方图库详情页共用 [showDevicePickerSheet]）。
  ///
  /// 2026-08-13 起**不默认选中、点一行只选中**，按下弹层里的「连接并投屏」才返回设备——
  /// 投屏是往设备写图且不可撤销，端上替用户选好、他顺手一点就投到了别的设备上。
  /// 弹层与本页此前那份自绘列表已整块删除（留着既不生效、又会误导下一个人）。
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
    return showDevicePickerSheet(context, devices: devices);
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
    return FigmaScreen(
      // 顶部导航自绘（返回 + 历史入口 + 会话标题 + Token 胶囊），所以不给 FigmaScreen 传 title。
      scrollable: false,
      bodyPadding: EdgeInsets.zero,
      body: Column(
        children: [
          _buildHeader(),
          if (_banned) _buildBannedBar(),
          Expanded(child: _buildMessages()),
          if (_sending) _buildStopPill(),
          // 两个浮层放在消息区与输入卡之间：视觉上就是「浮在输入卡上方」，而聊天区是 Expanded，
          // 弹出时只是被压短一点，输入卡本身纹丝不动（小程序那边靠 absolute 定位达到同样效果）。
          if (_showOrientationPicker) _buildOrientationPopover(),
          if (_showStylePicker) _buildStylePopover(),
          _buildInputArea(),
        ],
      ),
    );
  }

  /// 顶部导航（2026-08-10 需求 1.3 / 5）：左**返回**、右**会话列表**，标题屏幕正中、定宽超出省略。
  ///
  /// 🔶 与小程序**有意的排布差异**（见 `docs/changes/2026-08-10-AI助手八项优化.md`）：
  /// 小程序两颗按钮都在左边（返回 + 会话列表并排），App 把会话列表放到**最右**——
  /// App 顶栏右侧没有微信原生胶囊占位，空着反而失衡；返回键仍在最左，与全站一致。
  ///
  /// Token 胶囊本轮从这里**移除**，改在「历史会话」页顶部展示（需求 1.1）：标题要真正居中，
  /// 两侧就必须等距，右边挂着一颗 100+ 宽的胶囊时标题只能偏左，两者不可兼得。
  Widget _buildHeader() {
    // 默认页（还没建会话）标题留空，不再写「新对话」（需求 5）。
    final title = _sessionId.isEmpty ? '' : _sessionTitle;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _dismissKeyboardAndTools, // 点导航行空白处同样收键盘 + 收浮层
      child: SizedBox(
        height: 44,
        child: Stack(
          children: [
            // 标题真正屏幕居中（不是「按钮之间居中」），定宽 170 超出省略：
            // 两侧按钮各占 ~48，170 的盒子在最窄机型上也压不到它们。
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 170),
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFF111111),
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                  ),
                ),
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(left: 4),
                child: FigmaBackButton(onTap: () => Navigator.maybePop(context)),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(right: 4),
                child: _buildHistoryButton(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 历史会话入口。图源几何与返回键完全一致（白块只占画布 48.5%、且偏上 5.15%），
  /// 所以处理方式也一致：图放到 62、再下推 5.15%，命中盒仍是 44。详见 [FigmaBackButton]。
  Widget _buildHistoryButton() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _goSessions,
      child: SizedBox(
        width: 44,
        height: 44,
        child: OverflowBox(
          maxWidth: 62,
          maxHeight: 62,
          child: Transform.translate(
            offset: const Offset(0, 62 * 0.0515),
            child: const AiIcon(
              'assets/images/ai-history-button.png',
              size: 62,
            ),
          ),
        ),
      ),
    );
  }

  // Token 余额胶囊 2026-08-10 从本页顶栏移除（需求 1.1/1.3），改在「历史会话」页顶部展示
  //（`ai_sessions_page._buildTokenPill`）。余额本身仍由 [AiToken] 统一读写，本页只剩
  // 「扣费 + 不足拦截」两处调用。若日后要在聊天页恢复展示，必须重新核对与居中标题的几何冲突。

  Widget _buildBannedBar() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFFDECEC),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        AppL10n.of(context).aiBannedBanner,
        textAlign: TextAlign.center,
        style: const TextStyle(color: Color(0xFFD64541), fontSize: 11.5),
      ),
    );
  }

  /// 消息区。首屏「已渲染但透明」+ 上面盖 loading，等定位到底部再显形（需求 5.1）；
  /// 不能用 `if` 把列表整块换掉 —— 没有布局就没法滚到底。
  Widget _buildMessages() {
    final showWelcome = _messages.isEmpty && !_historyLoading;
    return GestureDetector(
      // 点消息区任意位置：收键盘 + 收浮层（见 [_dismissKeyboardAndTools]）。
      // 只吃点击，拖动仍归 ListView。
      behavior: HitTestBehavior.opaque,
      onTap: _dismissKeyboardAndTools,
      child: Stack(
        children: [
          Positioned.fill(
            child: showWelcome
                ? _buildWelcome()
                : Opacity(
                    opacity: _chatReady ? 1.0 : 0.0,
                    child: ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 13),
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

  /// 空态：星标 + 招呼语 + 三条灵感词（点了只填草稿，不自动发送）。
  /// 与小程序一致是**顶部对齐**（84rpx 上留白），不是垂直居中 —— 居中会随灵感词的行数上下跳。
  Widget _buildWelcome() {
    final l10n = AppL10n.of(context);
    final suggestions = l10n.aiWelcomeSuggestions;
    const icons = [
      'assets/images/ai-suggestion-home.png',
      'assets/images/ai-suggestion-sunrise.png',
      'assets/images/ai-suggestion-palette.png',
    ];
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 42, 18, 15),
        child: Column(
          children: [
            const AiIcon('assets/images/ai-welcome-star.png', size: 105),
            const SizedBox(height: 7),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: Text(
                    l10n.aiWelcomeGreeting,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFF5A5A5A),
                      fontSize: 17,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const SizedBox(width: 4.5),
                const AiIcon('assets/images/ai-spark-orange.png', size: 15),
              ],
            ),
            const SizedBox(height: 5),
            Text(
              l10n.aiWelcomeText,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF5F5F5F),
                fontSize: 13.5,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 16),
            for (var i = 0; i < suggestions.length; i++)
              Padding(
                padding: EdgeInsets.only(top: i == 0 ? 0 : 7.5),
                child: _buildSuggestion(
                  suggestions[i],
                  i < icons.length ? icons[i] : icons.last,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSuggestion(String prompt, String icon) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _useSuggestion(prompt),
      child: Container(
        constraints: const BoxConstraints(minHeight: 28),
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.white.withValues(alpha: 0.88)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x12544633),
              blurRadius: 13,
              offset: Offset(0, 5),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AiIcon(icon, size: 14),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                prompt,
                style: const TextStyle(
                  color: Color(0xFF656565),
                  fontSize: 12.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 一行消息。AI 侧（需求 6）：**不放头像**、气泡按屏宽铺满；用户侧维持现状（右对齐、按内容宽）。
  Widget _buildBubbleRow(_AiMessage message) {
    final isUser = message.isUser;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        mainAxisAlignment: isUser
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isUser)
            Flexible(child: _buildUserBubble(message))
          // 「正在加载」气泡（一张 71 宽的动图）和失败卡都是**定宽**的，不跟着铺满屏宽：
          // 一个占满整行的空白大框看着像出错/空回复。内容一到（content/images 上屏，
          // loading 转 false）就回到铺满的正常 AI 气泡。
          else if (message.loading || message.failed)
            Flexible(child: _buildAiBubble(message))
          else
            Expanded(child: _buildAiBubble(message)),
        ],
      ),
    );
  }

  /// AI 回复气泡（需求 3）：文字与图片在**同一个气泡**里。
  /// 气泡本体长按 = 删整条；里面某张图的长按/点击由图自己接住（见 [_AiBubbleImage]）。
  Widget _buildAiBubble(_AiMessage message) {
    if (message.failed) {
      return _buildFailureCard(message);
    }
    // 加载态：外层不套卡片底（小程序 `.bubble--loading` 把底和投影都去掉了），
    // 胶囊与阴影由这里自己画。
    //
    // 2026-08-12（同步小程序需求 5）：原来整块是一张**静态图**
    // `assets/images/ai-loading-bubble.png`（白胶囊 + 三个深浅不同的点），现在改成
    // 「胶囊照原图还原 + 三个点跑动画」。几何取自原图：画布 213×151、可见胶囊 150×88（两端全圆）、
    // 填充 #FBF9F4、暖褐色往下糊的阴影；按原来的 width:71 折算，胶囊约 50×29。
    // 点复用页面里本来就有的 [_TypingDots]（此前只在图加载失败时兜底用），
    // 颜色改成品牌橙以贴近原图。
    if (message.loading) {
      return Container(
        width: 50,
        height: 29,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0xFFFBF9F4),
          borderRadius: BorderRadius.circular(999),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF402A15).withValues(alpha: 0.10),
              blurRadius: 11,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: const _TypingDots(color: Color(0xFFFF7A3D)),
      );
    }
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPress: () => _onBubbleLongPress(message),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.78),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.9)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x14594C3A),
              blurRadius: 15,
              offset: Offset(0, 6),
            ),
          ],
        ),
        // 气泡内顺序：预描述 → 占位盒 → 真图 → 正文。
        //
        // ⚠️ 正文在**图片下方**（2026-08-07）：SSE 里 text 事件本来就排在 image 之后，
        //    先出图、文字再往下续，比「文字在上、图从下面顶出来」更贴事件顺序。
        // ⚠️ 占位盒与真图必须**都在正文之前** —— 它俩是同一个位置的两个状态，
        //    跨到正文两边去的话，100% 换图那一下图会整块跳过正文。
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (message.preText.isNotEmpty) _buildPreText(message),
            if (message.streaming)
              Padding(
                padding: EdgeInsets.only(
                  top: message.preText.isEmpty ? 0.0 : 9.0,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 255),
                  child: _buildGenCanvas(message),
                ),
              ),
            // 生成中先不显示真图：占位盒还占着这个位置，等读数爬到 100%（streaming 落下）再上屏
            if (!message.streaming)
              for (var i = 0; i < message.images.length; i++) ...[
                Padding(
                  padding: EdgeInsets.only(
                    // 与上一块之间 18rpx，图与图之间 14rpx
                    top: i == 0 ? (message.preText.isEmpty ? 0.0 : 9.0) : 7.0,
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 255),
                    child: _buildBubbleImage(message, i),
                  ),
                ),
                // 下载/投屏/删除**常驻**在每张图下方（2026-08-10 需求 7），不再靠长按唤起
                _buildImageActions(message, i),
              ],
            if (message.content.isNotEmpty)
              Padding(
                padding: EdgeInsets.only(
                  top:
                      (message.preText.isEmpty &&
                          !message.streaming &&
                          message.images.isEmpty)
                      ? 0.0
                      : 9.0,
                ),
                child: _buildBubbleText(message),
              ),
          ],
        ),
      ),
    );
  }

  /// 流式预描述（SSE `pre_text`）：橙色淡底的小胶囊 + 火花图标，与正文在视觉上分开
  /// —— 它是「前情提要」不是回复本身。生成完成后保留。
  Widget _buildPreText(_AiMessage message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFFEF641E).withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 3),
            child: AiIcon('assets/images/ai-spark-orange.png', size: 14),
          ),
          const SizedBox(width: 5),
          Expanded(
            child: Text(
              message.preText,
              style: const TextStyle(
                color: Color(0xFF8A6A52),
                fontSize: 13,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 生成中的图片占位：一整块跟成图同尺寸的渐变盒，百分比摆正中间、进度文案压在它下面。
  ///
  /// 出图要几十秒，光有一条细进度条的话用户就是在盯一片空白等。
  ///
  /// ⚠️ 圆角与宽高比必须与真图那个盒子**逐一对齐**（[_AiBubbleImage] 是
  /// `ClipRRect(10)` + `AspectRatio(100 / pad)`），读数到 100% 原地换图才不跳。
  /// 改这里就得同时改那里。
  Widget _buildGenCanvas(_AiMessage message) {
    return AspectRatio(
      // pad 是「高/宽×100」，AspectRatio 要的是宽/高
      aspectRatio: 100 / message.genPad,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          // 底色取项目那套暖调（橙 #EF641E / 用户气泡 #FFE0CD）的柔化版，
          // 压住饱和度别抢成图的风头
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFFF0C2E0),
              Color(0xFFE3C6E4),
              Color(0xFFC8BCE9),
            ],
          ),
        ),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const AiIcon('assets/images/ai-magic-white.png', size: 26),
                const SizedBox(height: 5),
                Text(
                  '${message.progress}%',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                    shadows: [
                      // 渐变亮处白字会发飘，垫一层很淡的暖影
                      Shadow(color: Color(0x38785C4A), blurRadius: 4),
                    ],
                  ),
                ),
                if (message.progressLabel.isNotEmpty) ...[
                  const SizedBox(height: 5),
                  Text(
                    message.progressLabel,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      // 压在渐变上用半透明白：与百分比拉开层级，
                      // 一眼分得出「47%」是主、文案是注解
                      color: Colors.white.withValues(alpha: 0.88),
                      fontSize: 12,
                      letterSpacing: 0.25,
                      shadows: const [
                        Shadow(color: Color(0x38785C4A), blurRadius: 4),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 气泡正文。打字机进行中在末尾挂一个橙色光标块。
  /// 🔶 与小程序的差异：小程序那个光标是 CSS 动画在闪，这里是常亮 —— 文字本身每 16ms 就在长，
  /// 已经足够「活」；为闪烁单开一个 AnimationController 会在打字期间和文本重建打架。
  Widget _buildBubbleText(_AiMessage message) {
    const style = TextStyle(
      color: kAiText,
      fontSize: 14.5,
      height: 1.55,
    );
    if (!message.typing) {
      return SelectableText(message.content, style: style);
    }
    return SelectableText.rich(
      TextSpan(
        style: style,
        children: [
          TextSpan(text: message.content),
          const TextSpan(text: '▍', style: TextStyle(color: Color(0xFFEF641E))),
        ],
      ),
    );
  }

  /// 贴在每张图下方的**常驻**操作条（下载 / 投屏 / 删除，2026-08-10 需求 7）。
  ///
  /// [onUserBubble]：用户自己发的图气泡里那条 —— 气泡本身已经是白底，再画一层白底白框
  /// 「白压白」看不出边界，改成一条顶部细分隔线（对齐小程序 `.image-actions--user`）。
  Widget _buildImageActions(
    _AiMessage message,
    int index, {
    bool onUserBubble = false,
  }) {
    final l10n = AppL10n.of(context);
    final row = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildImageAction(
          label: l10n.aiDownload,
          icon: 'assets/images/ai-download.png',
          onTap: () => _onImageActionTap('download', message, index),
        ),
        _buildImageActionDivider(),
        _buildImageAction(
          label: l10n.aiCast,
          icon: 'assets/images/ai-project.png',
          onTap: () => _onImageActionTap('cast', message, index),
        ),
        _buildImageActionDivider(),
        _buildImageAction(
          label: l10n.aiDelete,
          icon: 'assets/images/ai-delete-red.png',
          danger: true,
          onTap: () => _onImageActionTap('delete', message, index),
        ),
      ],
    );
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Align(
        alignment: onUserBubble ? Alignment.center : Alignment.centerLeft,
        child: Container(
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 9),
          decoration: onUserBubble
              ? const BoxDecoration(
                  border: Border(
                    top: BorderSide(color: Color(0x14594C3A)),
                  ),
                )
              : BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.94),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.92)),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x1F4A3E2E),
                      blurRadius: 14,
                      offset: Offset(0, 6),
                    ),
                  ],
                ),
          // 用户图气泡只有 215 宽，英文/日文标签比中文长得多（Download/Cast/Delete 就撑不下）：
          // 放不下时整体等比缩一点，好过一条红黄条的溢出警告。AI 气泡是整行宽度，用不着。
          child: onUserBubble
              ? FittedBox(fit: BoxFit.scaleDown, child: row)
              : row,
        ),
      ),
    );
  }

  Widget _buildImageAction({
    required String label,
    required String icon,
    required VoidCallback onTap,
    bool danger = false,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AiIcon(icon, size: 12.5),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                color: danger ? const Color(0xFFEF4545) : const Color(0xFF2F2F2F),
                fontSize: 12.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImageActionDivider() {
    return Container(width: 1, height: 17, color: const Color(0xFFDEDBD7));
  }

  /// 30xxx / 未知上游失败的失败卡：定宽 260，右上角浮一颗「删除」，卡内是标题 + 说明 +
  /// 「重新生成」。删除/重试都 `catchtap` 语义（GestureDetector 自己吃掉，不冒泡到气泡长按）。
  Widget _buildFailureCard(_AiMessage message) {
    final l10n = AppL10n.of(context);
    return SizedBox(
      width: 260,
      // 「删除」浮标要探出卡片上沿 27，所以整块留出这段上边距，别被 ListView 裁掉。
      child: Padding(
        padding: const EdgeInsets.only(top: 27),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.78),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white.withValues(alpha: 0.9)),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x14594C3A),
                    blurRadius: 15,
                    offset: Offset(0, 6),
                  ),
                ],
              ),
              child: Container(
                constraints: const BoxConstraints(minHeight: 200),
                padding: const EdgeInsets.all(19),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(11),
                  gradient: const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xFFFFF0E7), Color(0xFFF5EEE8)],
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      l10n.aiFailureTitle,
                      style: const TextStyle(
                        color: Color(0xFF2B2B2B),
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      l10n.aiFailureDesc,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFF85817D),
                        fontSize: 12.5,
                      ),
                    ),
                    const SizedBox(height: 16),
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _onRetryMessage(message.id),
                      child: Container(
                        constraints: const BoxConstraints(minWidth: 130),
                        height: 36,
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(999),
                          gradient: const LinearGradient(
                            colors: [Color(0xFFED8A69), Color(0xFFED744F)],
                          ),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x38E26F4B),
                              blurRadius: 13,
                              offset: Offset(0, 7),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // 固定 18×18 的居中盒（小程序 .retry-placeholder 36rpx）：
                            // ↻ 字形在行盒里本身偏上，不框住它按钮里的文字会跟着被顶偏。
                            const SizedBox(
                              width: 18,
                              height: 18,
                              child: Center(
                                child: Text(
                                  '↻',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    height: 1,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 7),
                            Text(
                              l10n.aiRetryGenerate,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13.5,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              top: -27,
              right: -9,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _onFailureDelete(message.id),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 7.5,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.94),
                    borderRadius: BorderRadius.circular(11),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x1A4A3E2E),
                        blurRadius: 12,
                        offset: Offset(0, 5),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const AiIcon('assets/images/ai-delete-red.png', size: 14),
                      const SizedBox(width: 4.5),
                      Text(
                        l10n.aiDelete,
                        style: const TextStyle(
                          color: Color(0xFFEF4545),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 用户气泡（需求 6.3：维持现状不变）——文字是浅橙块、图片是白底小卡片。
  Widget _buildUserBubble(_AiMessage message) {
    if (message.kind == _MsgKind.image && message.images.isNotEmpty) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onLongPress: () => _onBubbleLongPress(message),
        child: Container(
          width: 215,
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.86),
            borderRadius: BorderRadius.circular(14),
            boxShadow: const [
              BoxShadow(
                color: Color(0x12594C3A),
                blurRadius: 15,
                offset: Offset(0, 6),
              ),
            ],
          ),
          // 用户自己发的图同样常驻三颗按钮（需求 7）：长按菜单撤掉后，这里是「下载/投屏」
          // 仅剩的入口，不补上等于功能回退（需求原文只写了「回复内容」，但两处都得有）。
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildBubbleImage(message, 0),
              _buildImageActions(message, 0, onUserBubble: true),
            ],
          ),
        ),
      );
    }
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPress: () => _onBubbleLongPress(message),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: const BoxDecoration(
          color: Color(0xFFFFE0CD),
          // 右上角收成小圆角 = 视觉稿里指向发送者的那个「尖」
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(14),
            topRight: Radius.circular(5),
            bottomLeft: Radius.circular(14),
            bottomRight: Radius.circular(14),
          ),
        ),
        child: SelectableText(
          message.content,
          style: const TextStyle(
            color: kAiText,
            fontSize: 14.5,
            height: 1.55,
          ),
        ),
      ),
    );
  }

  /// 气泡里的一张图。占位比例先按已知值把高度占住，加载完用真实尺寸校正（需求 1.2 / 5.2）。
  ///
  /// ⚠️ 2026-08-10 起图本身**吃掉长按**（[_AiBubbleImage] 收到 onLongPress 就不再往上冒泡）：
  /// 下载/投屏/删除已改成图下方的常驻操作条（需求 7），长按图片再弹「删除整条」是误触源。
  Widget _buildBubbleImage(_AiMessage message, int index) {
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
      // 空实现而不是 null：给了回调，[_AiBubbleImage] 的 GestureDetector 才会在竞技场里
      // 认领这次长按，长按图片就不会冒泡到气泡上弹出「删除整条」的确认框。
      onLongPress: () {},
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
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6.5),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.95),
            borderRadius: BorderRadius.circular(999),
            boxShadow: const [
              BoxShadow(
                color: Color(0x1F4A3E2E),
                blurRadius: 14,
                offset: Offset(0, 5),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: const Color(0xFFEF641E),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                AppL10n.of(context).aiStopGenerating,
                style: const TextStyle(color: kAiText, fontSize: 12.5),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 输入卡：常驻四工具（相册 / 拍照 / 比例 / 一键生图）+ 输入行。
  /// 视觉稿里这是一张**浮在背景上的圆角卡**，不再是「顶到屏幕底边的白条 + ＋ 展开的工具面板」，
  /// 所以四个工具入口常驻、原来的 `_showTools` 随之取消。
  Widget _buildInputArea() {
    return Padding(
      // 键盘避让由 FigmaScreen 的 Scaffold(resizeToAvoidBottomInset: true) 负责，
      // 这里**不要**再加 viewInsets，否则弹键盘时输入区会被顶两次。
      padding: const EdgeInsets.fromLTRB(
        _kInputCardMargin,
        4,
        _kInputCardMargin,
        9,
      ),
      // 录音动效**盖住整个输入区**（含工具栏与卡片自己的内边距），对齐小程序 `.voice-cover`
      //（`position: absolute; inset: 0` 挂在 `.input-area` 上 + 同款 42rpx 圆角）。
      // 所以 Stack 包在**卡片外面**：包在里面只能盖住内容区，四周会露出一圈卡片底。
      child: Stack(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(
              _kInputCardPadding,
              9,
              _kInputCardPadding,
              10,
            ),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.84),
              borderRadius: BorderRadius.circular(21),
              border: Border.all(color: Colors.white.withValues(alpha: 0.94)),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x295B482D),
                  blurRadius: 22,
                  offset: Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_pending.isNotEmpty) _buildPendingStrip(),
                _buildQuickTools(),
                const SizedBox(height: 8),
                _buildInputLine(),
              ],
            ),
          ),
          // ⚠️ 必须 IgnorePointer（小程序那边是 `pointer-events: none`）：它是在手指按下
          // **之后**才出现的，绝不能把后续的 move/up 从下面那条「按住说话」的 Listener 手里抢走。
          if (_recording || _transcribing)
            Positioned.fill(
              child: _VoiceCover(
                cancel: _voiceCancel,
                transcribing: _transcribing,
              ),
            ),
        ],
      ),
    );
  }

  /// 常驻四工具行。宽度比例 1 : 1 : 1.35 : 1.75（见 [_kToolFlex]）——
  /// 后两格文字更长，等分会挤成两行。
  Widget _buildQuickTools() {
    final l10n = AppL10n.of(context);
    // ⚠️ 必须先量宽度再决定字号（2026-08-31 需求 6），理由见 [_resolveToolFontSizes]。
    return LayoutBuilder(
      builder: (context, constraints) {
        final font = _resolveToolFontSizes(constraints.maxWidth, l10n);
        return Row(
          children: [
            Expanded(
              flex: _kToolFlex[0],
              child: _buildQuickTool(
                icon: 'assets/images/ai-album-outline.png',
                label: l10n.aiAlbum,
                fontSize: font.compact,
                onTap: () => _pickImages(camera: false),
              ),
            ),
            const SizedBox(width: _kToolGap),
            Expanded(
              flex: _kToolFlex[1],
              child: _buildQuickTool(
                icon: 'assets/images/ai-camera-outline.png',
                label: l10n.aiCamera,
                fontSize: font.compact,
                onTap: () => _pickImages(camera: true),
              ),
            ),
            const SizedBox(width: _kToolGap),
            Expanded(
              flex: _kToolFlex[2],
              child: _buildOrientationButton(font.compact),
            ),
            const SizedBox(width: _kToolGap),
            Expanded(
              flex: _kToolFlex[3],
              child: _buildGenerateButton(font.generate),
            ),
          ],
        );
      },
    );
  }

  /// 量一段文字在给定字号下的宽度（单行、不换行）。
  double _measureToolLabel(String text, double fontSize, FontWeight? weight) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(fontSize: fontSize, fontWeight: weight),
      ),
      maxLines: 1,
      textDirection: Directionality.of(context),
    )..layout();
    return painter.width;
  }

  /// 四个工具胶囊的字号：**前三个（相册/拍照/比例）共用一个**，一键生图大一号。
  ///
  /// ⚠️ 这是 2026-08-31 需求 6 的正解，只调 [_kToolFontSize] 是修不好的。
  /// 原来四个格子各自套 `FittedBox(scaleDown)` **独立缩放**：格宽按 1:1:1.35:1.75 分死，
  /// 而四个词长短不一（Album/Camera/Portrait/Generate），于是每格缩出不同比例——
  /// 英文下实测约 9.8 / 7.9 / 8.9 / 12，四个字号全不一样，看着就像做坏了。
  ///
  /// 现在改成：先按格宽算出每格**能给文字多少宽度**，量出三个词在基准字号下的实际宽度，
  /// 取三者里最紧的那个比例作为**共用缩放**，三个词于是必然同号。
  /// 一键生图按「共用字号 + 1」给（需求原话「大一号就行」），它那格最宽通常放得下；
  /// 万一放不下再按自己的可用宽度收回来，绝不撑破。
  ///
  /// ⚠️ 中文/日文词短，三格都放得下 → 缩放为 1，字号仍是 [_kToolFontSize]，
  /// 与改动前逐像素相同，只有英文那版会真的缩。
  ({double compact, double generate}) _resolveToolFontSizes(
    double totalWidth,
    AppL10n l10n,
  ) {
    if (!totalWidth.isFinite || totalWidth <= 0) {
      return (compact: _kToolFontSize, generate: _kToolFontSize);
    }
    final flexTotal = _kToolFlex.reduce((a, b) => a + b);
    final usable = totalWidth - _kToolGap * (_kToolFlex.length - 1);
    double cellWidth(int i) => usable * _kToolFlex[i] / flexTotal;

    // 每格留给文字的宽度 = 格宽 − 左右内边距 − 图标 − 图标与文字的间距
    //（比例格右侧还多一枚箭头和一个间距）。
    const double plainOverhead =
        _kToolPadding * 2 + _kToolIconSize + _kToolIconGap;
    final available = <double>[
      cellWidth(0) - plainOverhead,
      cellWidth(1) - plainOverhead,
      cellWidth(2) - plainOverhead - _kToolIconGap - _kToolChevronSize,
    ];
    final labels = <String>[
      l10n.aiAlbum,
      l10n.aiCamera,
      l10n.aiOrientationLabel(_orientation),
    ];

    var scale = 1.0;
    for (var i = 0; i < labels.length; i++) {
      final width = _measureToolLabel(labels[i], _kToolFontSize, null);
      if (width > 0 && available[i] > 0) {
        final fit = available[i] / width;
        if (fit < scale) {
          scale = fit;
        }
      }
    }
    final compact = _kToolFontSize * (scale > 1 ? 1 : scale);

    // 「大一号」：比前三个大 1pt。放不下就按自己那格的可用宽度收回来。
    final generateAvailable = cellWidth(3) -
        _kToolPadding * 2 -
        _kToolGenerateIconSize -
        _kToolIconGap;
    var generate = compact + 1;
    final generateWidth =
        _measureToolLabel(l10n.aiGenerateImage, generate, FontWeight.w500);
    if (generateWidth > generateAvailable && generateWidth > 0) {
      generate = generate * (generateAvailable / generateWidth);
    }
    // 收回来之后也不该比前三个还小——那就不叫「大一号」了。
    return (compact: compact, generate: generate < compact ? compact : generate);
  }

  /// 工具胶囊里的文字。
  ///
  /// [fontSize] 由 [_resolveToolFontSizes] 按格宽统一算好传进来 —— **前三格必然同号**，
  /// 一键生图大一号。不要在这里读 [_kToolFontSize]：那是基准值，不是最终值。
  ///
  /// 外面仍留 `BoxFit.scaleDown` 作**兜底**（系统大字号、异形屏等量算之外的情况）：
  /// 字号已按可用宽度算过，正常情况下它不会触发，一个像素都不会缩。
  /// 早年这里是 `Flexible + ellipsis`，英文会被截成「Gener…」，故一直不用省略号。
  Widget _buildToolLabel(
    String text, {
    required Color color,
    required double fontSize,
    FontWeight? weight,
  }) {
    return Flexible(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.center,
        child: Text(
          text,
          maxLines: 1,
          style: TextStyle(
            color: color,
            fontSize: fontSize,
            fontWeight: weight,
          ),
        ),
      ),
    );
  }

  /// 工具行里一颗普通胶囊（相册 / 拍照）。
  Widget _buildQuickTool({
    required String icon,
    required String label,
    required double fontSize,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: _kToolHeight,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.42),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: const Color(0x2E7D7D7D)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: _kToolPadding),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AiIcon(icon, size: _kToolIconSize),
            const SizedBox(width: _kToolIconGap),
            _buildToolLabel(label, color: _kToolText, fontSize: fontSize),
          ],
        ),
      ),
    );
  }

  /// 比例按钮：显示当前比例，点开/收起比例浮层。展开时整颗按钮转橙描边态。
  Widget _buildOrientationButton(double fontSize) {
    final active = _showOrientationPicker;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _toggleOrientationPicker,
      child: Container(
        height: _kToolHeight,
        decoration: BoxDecoration(
          color: active
              ? const Color(0xFFFFF4ED)
              : Colors.white.withValues(alpha: 0.42),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: active ? const Color(0xFFF5A77E) : const Color(0x2E7D7D7D),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: _kToolPadding),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AiIcon(
              _orientationActiveIcon(_orientation),
              size: _kToolIconSize,
              opacity: 0.75,
            ),
            const SizedBox(width: _kToolIconGap),
            _buildToolLabel(
              AppL10n.of(context).aiOrientationLabel(_orientation),
              color: active ? kAiOrange : _kToolText,
              fontSize: fontSize,
            ),
            const SizedBox(width: _kToolIconGap),
            // 箭头/关闭都用等大的方图：切换时按钮里的内容宽度不变，
            // 也不会像 ›/× 那样因字形基线不同而整体偏上偏左。
            // 2026-07-31 由 17 收到 11（小程序 34rpx → 22rpx）：原尺寸压过了左边的比例图标。
            AiIcon(
              active
                  ? 'assets/images/ai-close-orange.png'
                  : 'assets/images/ai-chevron-right.png',
              size: _kToolChevronSize,
            ),
          ],
        ),
      ),
    );
  }

  /// 一键生图按钮：默认是橙色渐变实心，展开风格浮层时转成白底橙描边。
  Widget _buildGenerateButton(double fontSize) {
    final active = _showStylePicker;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _toggleStylePicker,
      child: Container(
        height: _kToolHeight,
        decoration: BoxDecoration(
          color: active ? Colors.white.withValues(alpha: 0.78) : null,
          gradient: active
              ? null
              : const LinearGradient(
                  colors: [Color(0xFFFF5F24), Color(0xFFFF884A)],
                ),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: active ? kAiOrange : Colors.transparent),
          boxShadow: active
              ? null
              : const [
                  BoxShadow(
                    color: Color(0x38FF6827),
                    blurRadius: 11,
                    offset: Offset(0, 5),
                  ),
                ],
        ),
        padding: const EdgeInsets.symmetric(horizontal: _kToolPadding),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // 外层固定 18，魔杖/关闭切换不改宽度；× 的图源四周留白多（笔画只占 64%），
            // 所以关闭态把图放大到 18，才和魔杖看着一样大。
            SizedBox(
              width: _kToolGenerateIconSize,
              height: _kToolGenerateIconSize,
              child: Center(
                child: active
                    ? const AiIcon(
                        'assets/images/ai-close-orange.png',
                        size: _kToolGenerateIconSize,
                      )
                    : const AiIcon('assets/images/ai-magic-white.png', size: 14.5),
              ),
            ),
            const SizedBox(width: _kToolIconGap),
            _buildToolLabel(
              AppL10n.of(context).aiGenerateImage,
              color: active ? kAiOrange : Colors.white,
              fontSize: fontSize,
              weight: FontWeight.w500,
            ),
          ],
        ),
      ),
    );
  }

  /// 输入行：输入框（或「按住说话」占位）+ 右侧发送/语音圆钮。
  Widget _buildInputLine() {
    final l10n = AppL10n.of(context);
    final canSend =
        _input.text.trim().isNotEmpty && !_sending && !_submitting && !_banned;
    return Container(
      constraints: const BoxConstraints(minHeight: 41),
      // 右侧是 35 的圆钮，右边只留 3，四周才等距
      padding: const EdgeInsets.only(left: 12, right: 3),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.34),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0x246C6C6C)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _voiceMode
                // 「按住说话」条。用 [Listener] 收原始指针事件而不是 GestureDetector：
                // 需要的是「按下即录、抬起即发」，而 tap 系手势一移动就被判成取消，
                // 上滑取消这套手势用 tap 根本表达不了。本条不在可滚动区里，
                // 不进手势竞技场也不会跟谁抢。
                ? Listener(
                    onPointerDown: _onVoicePointerDown,
                    onPointerMove: _onVoicePointerMove,
                    onPointerUp: _onVoicePointerUp,
                    onPointerCancel: (_) {
                      _voiceStart = null;
                      _voiceHolding = false;
                      _voiceRejected = false;
                      unawaited(_endVoice(cancel: true));
                    },
                    child: Container(
                      height: 34,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        // 小程序 `.voice-hold`：常态米底 #f2eee9 + #555 字；
                        // 按住时整条转 90° 橙色渐变 + 白字（`.voice-hold--recording`）。
                        //
                        // ⚠️ **常态底色改中性灰**（2026-08-31 需求，与小程序有意不同）：
                        // #f2eee9 是暖米色，配 2026-08-21 换上的浅蓝墙面背景会发脏、
                        // 看着像没渲染完。按住录音时那条橙色渐变**保持不变**——
                        // 它是「正在录」的状态色，不属于这次要改的「背景色」。
                        color: _recording ? null : const Color(0xFFEFEFEF),
                        gradient: _recording
                            ? const LinearGradient(
                                begin: Alignment.centerLeft,
                                end: Alignment.centerRight,
                                colors: [Color(0xFFFF6C2A), Color(0xFFFF884A)],
                              )
                            : null,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        // 三态文案与小程序逐字一致：按住 说话 / 松开发送 / 松开取消
                        _recording
                            ? (_voiceCancel
                                  ? l10n.aiVoiceBarCancel
                                  : l10n.aiVoiceBarRelease)
                            : l10n.aiHoldToTalk,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: _recording ? Colors.white : kAiText,
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
                    // 键盘和浮层不该同时占着底部（对齐小程序 bindfocus="closeTools"）
                    onTap: _closeTools,
                    style: const TextStyle(
                      color: Color(0xFF3A3A3A),
                      fontSize: 15,
                    ),
                    decoration: InputDecoration(
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 10),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      disabledBorder: InputBorder.none,
                      hintText: _banned
                          ? l10n.aiBannedHint
                          : (_pending.isEmpty
                                ? l10n.aiInputHint
                                : l10n.aiInputWithImagesHint),
                      hintStyle: const TextStyle(
                        color: Color(0xFF9C9791),
                        fontSize: 15,
                      ),
                    ),
                  ),
          ),
          const SizedBox(width: 7),
          // 右侧那一颗按钮的三态（2026-08-10 需求 4）。三态**同一个 35 的盒子**，切换不位移：
          //   · 语音模式 → 画发送图标，点它切回键盘（原先是灰底「键」字占位块，即「UI 没同步」）；
          //   · 有草稿   → 发送；
          //   · 空输入框 → 麦克风，点它进语音模式。
          if (_voiceMode)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _toggleVoiceMode,
              child: _buildSendIcon(),
            )
          else if (_input.text.isNotEmpty)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _onSendTap,
              child: Opacity(opacity: canSend ? 1 : 0.42, child: _buildSendIcon()),
            )
          else
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _toggleVoiceMode,
              child: const SizedBox(
                width: 35,
                height: 35,
                child: Center(
                  child: AiIcon('assets/images/ai-microphone.png', size: 24),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _toggleVoiceMode() {
    // 切走时把在途录音丢掉：留着的话隐藏的输入条还占着麦克风。
    if (_voiceMode && _recording) {
      unawaited(_endVoice(cancel: true));
    }
    setState(() {
      _voiceMode = !_voiceMode;
      _showOrientationPicker = false;
      _showStylePicker = false;
    });
  }

  // ── 按住说话（2026-08-28 接入，见 `features/ai/ai_voice_input.dart`）─────
  //
  // 交互照小程序 `chat.js` 的 onVoice* 一套（仿微信，需求文档 §5.1.2「松手直接发送」）：
  //   按住 → 开始录音 + 震一下 + 弹居中浮层；
  //   按住不放上滑超过 [_kVoiceCancelDy] → 转「松开取消」，浮层变红；
  //   松手 → 在取消区就安静丢弃，否则把识别结果**直接发出去**。
  //
  // ⚠️ **录音期间一个字都不上屏**（2026-07-27 需求 4.3，两端同口径）：不显示中间识别结果，
  //    松手后结果直接变成一条已发送的用户消息（参考 DeepSeek），而不是回填输入框再让用户点发送。

  void _onVoicePointerDown(PointerDownEvent event) {
    _voiceStart = event.position;
    _voiceRejected = false;
    _voiceHolding = true;
    unawaited(_beginVoice());
  }

  void _onVoicePointerMove(PointerMoveEvent event) {
    final start = _voiceStart;
    if (!_recording || start == null) {
      return;
    }
    // 上滑为正：起手点 y 减去当前 y。
    final cancel = start.dy - event.position.dy > _kVoiceCancelDy;
    if (cancel != _voiceCancel) {
      setState(() => _voiceCancel = cancel);
    }
  }

  void _onVoicePointerUp(PointerUpEvent event) {
    _voiceStart = null;
    _voiceHolding = false;
    if (_voiceRejected) {
      _voiceRejected = false;
      return;
    }
    unawaited(_endVoice(cancel: _voiceCancel));
  }

  /// 起手：确认能录 → 开始监听。返回是否真的起来了。
  Future<void> _beginVoice() async {
    // 与发送按钮同一批闸：上一条正卡在「建会话」空窗时不该再录一句叠上来。
    // `_transcribing` 一并挡住：上一段还在上传转写，这时再按只会两段互相抢麦克风。
    if (_recording || _transcribing || _sending || _submitting || _banned) {
      _voiceRejected = true;
      return;
    }
    final voice = AiVoiceInput.instance;
    final l10n = AppL10n.of(context);
    // 首次按下才去 ensureReady（它会拉起系统授权弹窗）——不能在进页面时偷偷弹权限。
    final ready = await voice.ensureReady();
    if (!mounted) {
      return;
    }
    // 授权框还开着的时候用户就松手了：这一轮作废，别在抬手之后才把麦克风打开。
    if (!_voiceHolding) {
      return;
    }
    // ⚠️ 顺序不能反：「授权被拒」也会让 ensureReady 返回 false，先判它才能弹对提示。
    if (voice.permissionDenied) {
      _voiceRejected = true;
      await _showVoicePermissionGuide();
      return;
    }
    if (!ready) {
      _voiceRejected = true;
      AppToast.show(context, _voiceUnavailableText(l10n, voice));
      return;
    }
    // 起手震一下（与投屏预览页长按拖拽同一套反馈）。
    unawaited(HapticFeedback.lightImpact());
    setState(() {
      _recording = true;
      _voiceCancel = false;
    });
    // ⚠️ 取当前语种走 `AppL10n.of(context).language`：`languageOf` 是
    // [AppLocalizationsScope] 上的静态方法，不在 [AppL10n] 上。
    final started = await voice.start(
      language: AppL10n.of(context).language,
      maxDuration: _kVoiceMaxDuration,
    );
    if (!mounted) {
      return;
    }
    // listen() 期间松手（起手到真正开录之间还有一次平台往返）：立刻按松手处理，
    // 否则录音会一直开到 60s 上限，而用户以为自己已经取消了。
    if (!_voiceHolding) {
      await _endVoice(cancel: !started || _voiceCancel);
      return;
    }
    if (!started) {
      setState(() {
        _recording = false;
        _voiceCancel = false;
      });
      _voiceRejected = true;
      AppToast.show(context, _voiceUnavailableText(l10n, voice));
      return;
    }
    // 录满上限自动收尾。引擎那边 `listenFor` 到点也会停，但那只停了识别 ——
    // 界面还挂在「录音中」等抬手，用户会以为还在录（可能一直按着不放）。
    // 所以这里自己拿表，到点按「松手」走一遍：内容照发、提示一句。
    _voiceLimitTimer?.cancel();
    _voiceLimitTimer = Timer(_kVoiceMaxDuration, () {
      if (mounted && _recording) {
        unawaited(_endVoice(cancel: _voiceCancel, reachedLimit: true));
      }
    });
  }

  /// 松手 / 取消 / 录满上限：收浮层，再决定发不发。
  ///
  /// [reachedLimit]：这一次不是用户松的手，而是录满了 [_kVoiceMaxDuration]。
  /// **内容照发**（说没说完都发出去，别让人白按一分钟），发完补一句提示。
  /// ⚠️ 唯一的例外是「手指正停在取消区」：那时用户已经明确表示这段不要了，
  /// 上限只是替他松了手，语义应当仍是取消 —— 所以这里沿用当前的 [cancel] 状态，
  /// 而不是无条件发送。
  Future<void> _endVoice({
    required bool cancel,
    bool reachedLimit = false,
  }) async {
    if (!_recording) {
      return;
    }
    _voiceLimitTimer?.cancel();
    _voiceLimitTimer = null;
    final voice = AiVoiceInput.instance;
    setState(() {
      _recording = false;
      _voiceCancel = false;
    });
    if (cancel) {
      await voice.cancel(); // 上滑取消：安静丢弃，不发不上传
      return;
    }
    // 走安卓备胎（录音上传）时这一步要传给后端转文字（可能一两秒），浮层不收、只换文案；
    // 端上识别是瞬时出结果的，不进这个态。
    if (voice.remote) {
      setState(() => _transcribing = true);
    }
    final result = await voice.stop();
    if (!mounted) {
      return;
    }
    if (_transcribing) {
      setState(() => _transcribing = false);
    }
    if (voice.permissionDenied) {
      await _showVoicePermissionGuide();
      return;
    }
    // 转写失败（网络/服务异常）走错误码文案，**不能**混进下面那句「没听清」——
    // 那会让用户对着一个根本发不出去的请求反复重录。
    if (result.failed) {
      await AiI18n.of(context).handleError(context, result.error!);
      return;
    }
    final text = result.text;
    if (text.isEmpty) {
      // 一个字都没识别到：这句比「已达上限」更该说，两条提示不叠着弹。
      AppToast.show(context, AppL10n.of(context).aiVoiceNoSpeech);
      return;
    }
    if (reachedLimit) {
      AppToast.show(context, AppL10n.of(context).aiVoiceMaxDuration);
    }
    await _sendVoiceText(text);
  }

  /// 「起不来」的提示按选中的链路分：走备胎（安卓录音上传）时是录音起不来
  /// （麦克风被占 / 初始化失败，重试有用）；走端上识别时是这台机器没有识别服务
  /// （重试没用，得引导去用输入法的语音输入）。
  String _voiceUnavailableText(AppL10n l10n, AiVoiceInput voice) {
    return voice.remote ? l10n.aiVoiceRecordFailed : l10n.aiVoiceUnavailable;
  }

  Future<void> _showVoicePermissionGuide() async {
    final l10n = AppL10n.of(context);
    final go = await showAppConfirmDialog(
      context,
      title: l10n.aiVoiceMicDeniedTitle,
      message: l10n.aiVoiceMicDeniedMessage,
      icon: Icons.mic_off_rounded,
      confirmLabel: l10n.bindGoSettings,
    );
    if (go != true) {
      return;
    }
    try {
      await NativeDeviceApi.openAppSettings();
    } catch (_) {
      // 打不开系统设置不阻断（如通道未实现），用户可手动去设置。
    }
  }

  /// 识别结果**直接发送**（不经过输入框）。
  ///
  /// 顺序与 [_onSendTap] 逐条一致：服务协议 → 图片上传中 → 星币闸 → 建会话 → 发。
  /// 任何一步没发出去都把文字**回填输入框** —— 语音内容重说一遍的代价比重打一遍高得多
  /// （小程序 `sendVoiceText` 同款约定）。
  Future<void> _sendVoiceText(String text) async {
    void restore() {
      if (!mounted) {
        return;
      }
      setState(() {
        _input.text = text;
        _input.selection = TextSelection.collapsed(offset: text.length);
      });
    }

    final passed = await _guardedSend(() async {
      if (!await _ensureAiServiceConsent(sendAttempt: true) || !mounted) {
        restore();
        return;
      }
      if (_pending.any((item) => item.uploading)) {
        AppToast.show(context, AppL10n.of(context).aiImageUploading);
        restore();
        return;
      }
      final images = [
        for (final item in _pending)
          if (item.url.isNotEmpty) _AiImage(url: item.url, pad: item.pad),
      ];
      // 星币校验排在建会话之前，理由同 [_onSendTap]。
      if (!await _guardAiDialogue() || !mounted) {
        restore();
        return;
      }
      if (_sessionId.isEmpty) {
        await _createSession();
        if (!mounted || _sessionId.isEmpty) {
          restore();
          return;
        }
      }
      setState(() => _pending.clear());
      await _sendChat(text, images: images, dialogueChecked: true);
    });
    if (!passed) {
      restore(); // 被同步闸挡下（上一条还在发）：文字别丢
    }
  }

  /// 发送图标（2026-08-10 需求 4 的「除去阴影后上下居中 + 放大」）。
  ///
  /// `ai-send-active.png` 是 141×141 的画布，实心橙圆只占中间 64px（45.4%），其余是外发光，
  /// 且圆心偏上（y=63.5 而非 70）。按 35 画的话圆实际只有 ~16，比左邻的麦克风（24）还小。
  /// 所以图放大到 57 画（圆 ≈26）再下推 4.61%，让「圆」而不是「圆+阴影」在盒子里上下居中；
  /// 命中盒仍是 35，与麦克风态一致，切换时不位移。
  Widget _buildSendIcon() {
    return SizedBox(
      width: 35,
      height: 35,
      child: OverflowBox(
        maxWidth: 57,
        maxHeight: 57,
        child: Transform.translate(
          offset: const Offset(0, 57 * 0.0461),
          child: const AiIcon('assets/images/ai-send-active.png', size: 57),
        ),
      ),
    );
  }

  /// 比例浮层：顶部标题「设置文生图比例」（2026-08-10 需求 3）+ 竖向 / 横向 / 方形，
  /// 选中项橙底 + 右侧对勾。
  Widget _buildOrientationPopover() {
    final l10n = AppL10n.of(context);
    return _buildPopover(
      cellIndex: 2,
      width: 145,
      padding: const EdgeInsets.all(6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 6),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                l10n.aiImageRatioPickerTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFF8C8C8C),
                  fontSize: 12,
                  height: 1.2,
                ),
              ),
            ),
          ),
          for (final key in _kOrientationKeys)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _onOrientationTap(key),
              child: Container(
                height: 36,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: _orientation == key
                      ? const Color(0xFFFFF0E7)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Row(
                  children: [
                    AiIcon(
                      _orientation == key
                          ? _orientationActiveIcon(key)
                          : _kOrientationIcons[key]!,
                      size: 14,
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        l10n.aiOrientationLabel(key),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: _orientation == key
                              ? kAiOrange
                              : const Color(0xFF303030),
                          fontSize: 14,
                        ),
                      ),
                    ),
                    if (_orientation == key) ...[
                      const SizedBox(width: 7),
                      const AiIcon(
                        'assets/images/ai-check-orange.png',
                        size: 12,
                      ),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// 一键生图风格浮层。点风格**立即发送**（副标题已写明），所以没有二次确认。
  Widget _buildStylePopover() {
    final l10n = AppL10n.of(context);
    return _buildPopover(
      cellIndex: 3,
      width: 155,
      alignRight: true,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const AiIcon('assets/images/ai-generate.png', size: 27),
              const SizedBox(width: 7),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.aiGenerateImage,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF2C2C2C),
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      l10n.aiGenerateImageDesc,
                      maxLines: 2,
                      style: const TextStyle(
                        color: Color(0xFF9B9691),
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          for (final key in _kStyleKeys)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _onStyleTap(key),
              child: SizedBox(
                height: 32,
                child: Row(
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: const BoxDecoration(
                        color: Color(0xFFFF7840),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        l10n.aiStyleLabel(key),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF303030),
                          fontSize: 13.5,
                        ),
                      ),
                    ),
                    const SizedBox(width: 7),
                    const AiIcon('assets/images/ai-send-outline.png', size: 14),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// 浮层外壳 + 水平定位。
  ///
  /// 小程序靠 `position:absolute` + 一个按 750rpx 算死的 left/right 贴住对应的工具按钮；
  /// App 屏宽不定，所以这里按 [_kToolFlex] **实算**那一格的位置，再把浮层夹回屏内 ——
  /// 窄屏上浮层不会探出屏幕，宽屏上也仍旧对着自己的按钮。
  Widget _buildPopover({
    required int cellIndex,
    required double width,
    required EdgeInsets padding,
    required Widget child,
    bool alignRight = false,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const inset = _kInputCardMargin + _kInputCardPadding;
        final content = constraints.maxWidth - inset * 2;
        var totalFlex = 0;
        for (final flex in _kToolFlex) {
          totalFlex += flex;
        }
        final unit =
            (content - _kToolGap * (_kToolFlex.length - 1)) / totalFlex;
        var cellLeft = inset;
        for (var i = 0; i < cellIndex; i++) {
          cellLeft += unit * _kToolFlex[i] + _kToolGap;
        }
        final cellWidth = unit * _kToolFlex[cellIndex];
        final wanted = alignRight
            ? cellLeft + cellWidth - width
            : cellLeft + cellWidth / 2 - width / 2;
        final maxLeft = constraints.maxWidth - inset - width;
        var left = wanted;
        if (left > maxLeft) {
          left = maxLeft;
        }
        if (left < inset) {
          left = inset;
        }
        if (left < 0) {
          left = 0;
        }
        return Padding(
          // 输入卡自己还有 4 的上边距，这里再补 5 就是小程序那 18rpx 的间隙
          padding: EdgeInsets.only(left: left, bottom: 5),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Container(
              width: width,
              padding: padding,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.97),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.92),
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x2E4D3E2B),
                    blurRadius: 21,
                    offset: Offset(0, 9),
                  ),
                ],
              ),
              child: child,
            ),
          ),
        );
      },
    );
  }

  /// 待发送图片缩略图（v1.0.3 §5.1.4）：停在输入卡内，每张可删、最多 4 张。
  Widget _buildPendingStrip() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: SizedBox(
        height: 50,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: _pending.length,
          separatorBuilder: (context, index) => const SizedBox(width: 7),
          itemBuilder: (context, index) {
            final item = _pending[index];
            return SizedBox(
              width: 50,
              height: 50,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: ColoredBox(
                        color: const Color(0xFFEEE9E2),
                        child: Image.file(File(item.path), fit: BoxFit.cover),
                      ),
                    ),
                  ),
                  if (item.uploading)
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F141E).withValues(alpha: 0.42),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Center(
                          child: SizedBox(
                            width: 15,
                            height: 15,
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
                          color: Color(0x8C0F141E),
                          borderRadius: BorderRadius.only(
                            bottomLeft: Radius.circular(7),
                          ),
                        ),
                        child: const Text(
                          '×',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            height: 1,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
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

/// 录音动效层（小程序 `.voice-cover`）：盖住整个输入区的白面板 + 七根跳动的波形条 + 一句提示。
///
/// 逐项对齐 `chat.wxss`：
/// - 面板：`rgba(255,255,255,.98)` / 圆角 42rpx / 内边距 20-32rpx / 元素间距 13rpx；
///   取消态整块转 `#fdecec`。
/// - 波形：7 根，宽 8rpx、圆角全圆、间距 9rpx，容器高 52rpx；
///   高度在 20↔50rpx 之间来回（0.9s / ease-in-out），**逐根延迟 0.12s** 形成波浪；
///   常态 `#ef641e`、取消态 `#d64541`。
/// - 提示：24rpx `#8b8681`，取消态 `#d64541`。
///
/// ⚠️ 自己带 Ticker（[SingleTickerProviderStateMixin]）而不是挂在页面 State 上：
/// 它只在录音时被 build，动画随之自然起停，页面不必为一个短暂动效常驻一支 Ticker。
class _VoiceCover extends StatelessWidget {
  const _VoiceCover({required this.cancel, this.transcribing = false});

  /// 手指是否已滑进「松开取消」区。
  final bool cancel;

  /// 已松手、正在把录音传给后端转文字（**仅安卓备胎链路**，见 [_AiChatPageState._transcribing]）。
  /// 此时手指已经抬起，取消态无从谈起，所以一律按常态配色。
  final bool transcribing;

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final cancelling = cancel && !transcribing;
    return IgnorePointer(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: cancelling ? const Color(0xFFFDECEC) : const Color(0xFAFFFFFF),
          // 与输入卡同款圆角，盖上去边到边严丝合缝
          borderRadius: BorderRadius.circular(21),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            // 转写期间波形继续跳：这一段等的是网络，用静止的波形表示「还在忙」
            // 反而像卡死了（文案已经说清楚在做什么）。
            _VoiceWave(
              color: cancelling
                  ? const Color(0xFFD64541)
                  : const Color(0xFFEF641E),
            ),
            const SizedBox(height: 6.5),
            Text(
              transcribing
                  ? l10n.aiVoiceTranscribing
                  : (cancel ? l10n.aiVoiceTipCancel : l10n.aiVoiceTip),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: cancelling
                    ? const Color(0xFFD64541)
                    : const Color(0xFF8B8681),
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 七根跳动的波形条（小程序 `.voice-wave` + `@keyframes voiceWave`）。
class _VoiceWave extends StatefulWidget {
  const _VoiceWave({required this.color});

  final Color color;

  @override
  State<_VoiceWave> createState() => _VoiceWaveState();
}

class _VoiceWaveState extends State<_VoiceWave>
    with SingleTickerProviderStateMixin {
  static const int _bars = 7;
  static const double _barWidth = 4; // 8rpx
  static const double _gap = 4.5; // 9rpx
  static const double _minHeight = 10; // 20rpx
  static const double _maxHeight = 25; // 50rpx
  static const double _boxHeight = 26; // 52rpx

  /// 一个完整周期 0.9s；每根比前一根晚 0.12s 起跳（= 周期的 2/15）。
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
    return SizedBox(
      height: _boxHeight,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) => Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            for (var i = 0; i < _bars; i++) ...[
              if (i > 0) const SizedBox(width: _gap),
              SizedBox(
                width: _barWidth,
                height: _heightAt(i),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: widget.color,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 第 i 根此刻的高度。CSS 那条 keyframes 是「0%/100% 最矮、50% 最高」的来回，
  /// 等价于把相位套进一个 0→1→0 的三角波，再用 easeInOut 把两端的速度压下来。
  double _heightAt(int index) {
    final phase = (_controller.value + index * 0.12 / 0.9) % 1.0;
    final triangle = phase <= 0.5 ? phase * 2 : (1 - phase) * 2;
    final eased = Curves.easeInOut.transform(triangle);
    return _minHeight + (_maxHeight - _minHeight) * eased;
  }
}

/// AI 回复占位的三点 loading。
/// 三个点依次亮起的等待动画。两处在用：AI 回复的等待气泡（[_buildAiBubble] 的加载态，
/// 2026-08-12 起由静态图改成它）、以及其它需要「正在处理」的小位置。
/// [color] 默认灰点；等待气泡传品牌橙，与原来那张图上的点同色。
class _TypingDots extends StatefulWidget {
  const _TypingDots({this.color = const Color(0xFF9AA1AB)});

  final Color color;

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
                  decoration: BoxDecoration(
                    color: widget.color,
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

// 底部弹层外壳 _AiSheet / _AiSheetAction 2026-08-10 随「消息长按 → 底部操作面板」一起删除
// （需求 2：删除改走全站统一的确认框，图片操作改走常驻操作条）。设备选择弹窗有自己的
// _buildDeviceSheet，不依赖这两个类。

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
