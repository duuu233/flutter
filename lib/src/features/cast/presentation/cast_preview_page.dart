import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:BoltStar/src/shared/widgets/app_dialog.dart';
import 'package:BoltStar/src/shared/widgets/app_widgets.dart';
import 'package:BoltStar/src/shared/widgets/figma_common.dart';
import '../../../device/ble/frame_protocol.dart';
// `screenType.code` 是 FrameScreenTypeDetails 扩展方法：扩展必须导入其定义库才能用。
import '../../../device/frame_device_protocol.dart';
import '../../../network/dithering_api.dart';
import '../../../routes/app_routes.dart';
import '../../../shared/l10n/app_l10n.dart';
import '../../../state.dart';
import '../cast_image_editor.dart';
import 'casting_progress_page.dart';

/// 投屏预览页。**2026-07-25 按小程序 07-22 ~ 07-24 的三轮重构整页重写**
/// （对齐 `photo-album/subpackages/projection/preview` + `docs/2026-07-22-照片预览需求调整.md`）。
///
/// ## 交互模型（与小程序一一对应）
/// - **常驻编辑**：进页 / 切图即自动对当前图开启编辑层，没有「进入编辑 / 保存」按钮，
///   点「开始投屏」时才按取景框内所见烘焙上传。
/// - **竖向 / 横向取景**：工具栏前两颗按钮切的是**可视区域（取景框）**——竖向 = 设备物理比例，
///   横向 = 宽高对调（相框躺着摆）。图片本身位置/大小/角度不动，换框后用 zoom 反向补偿保住绝对显示尺寸。
/// - **自由缩放、所见即所得**（2026-07-31 需求第 4 项）：缩放只受
///   [_kMinZoomFactor] ~ [_kMaxZoomFactor] 限制，**不强制铺满取景框**；缩小/平移露出的区域
///   是白色画布，与导出画布的白底一一对应（见 [_clampTransform] 与 [_bake]）。
/// - **长按 0.5s 才拖拽**（[_kLongPress]，仿苹果相册长按取图）：单指按住几乎不动满 0.5s → 震动 +
///   「拿起」放大回弹动画，此后单指移动才平移图片；按住期间位移超 [_kMoveCancelPx] 判为切图滑动。
/// - **双指缩放 + 旋转**随时可用，不需长按；右上角悬浮按钮每点一次顺时针 +90°。
/// - **左右滑动切图**：松手时按横向位移方向提交（[_kSwipeCommitPx]），PageView 负责 Banner 式
///   过场动画（[_kSlideDuration] = 360ms，需求第 14 项）——触摸全部由上层 [Listener] 独占后在
///   JS 同款状态机里分流（小程序那边 swiper 无法与「同一根手指长按后转拖拽」共存，
///   App 照抄这个取舍以保证两端手感一致）。
///
/// ## 导出铁律（改这里前先读完，错了不报错、设备直接花屏）
/// 两种取景方向**恒导出竖向设备物理分辨率**（480×720 / 680×960）：
/// - 竖向：把框内所见整幅转设备字段 `verticalRotation`（2026-08-04 新增，**缺省 0 = 不转**）后画进画布；
/// - 横向：把框内所见整幅转 **[_kLandscapeExportRotateDeg] = 270°** 再画进**竖向**画布
///   （90° 进竖向 + 180° 真机倒置校正，2026-07-20 结论）。
///
/// 放大系数 `k` 只看**导出角是否对调轴向**：奇数直角（90/270，横向默认即属此类）时
/// 取景框的「宽」落到画布的「高」→ `k = outH / frameW`；0/180 时 → `k = outW / frameW`。
///
/// **横向绝不能直接输出横向尺寸**（如 960×680）：像素总数与竖向相同、帧字节数(宽×高÷2)也相同，
/// 所以 seekink 抖动接口不会报错——但设备按 680px 一行解析 960px 一行的数据会整幅错位，
/// 表现为**花屏且无任何报错**。2026-07-22 当天曾短暂改成「对调分辨率直出」，同日即被用户拍板撤销。
class CastPreviewPage extends StatefulWidget {
  const CastPreviewPage({
    super.key,
    this.state,
    required this.device,
    required this.imagePaths,
  });

  /// 投屏目标设备。取景框比例与导出分辨率都取它的屏幕分辨率。
  final DeviceItem device;

  /// 用于投屏完成后把真机最新内存同步回设备列表/详情。
  final PhotoFrameState? state;

  /// 待投屏的本地原图路径（已由 CastPhotoPicker 降采样到长边 1920）。
  final List<String> imagePaths;

  @override
  State<CastPreviewPage> createState() => _CastPreviewPageState();
}

/// 取景方向（对齐小程序 ORIENT_PORTRAIT / ORIENT_LANDSCAPE）。
enum _Orientation { portrait, landscape }

/// 触摸状态机（对齐小程序 `this._mode`）。
enum _Mode { none, idle, swipe, drag, pinch }

/// 单张图的编辑数值真值（对齐小程序 `this._edit` / `_states[index]`）。
///
/// 手势期间只读写这个对象，不读 setState 之后的异步字段；切图时整份快照进 `_states`，
/// 切回来原样恢复（非破坏性编辑：**始终不落文件**，点「开始投屏」才统一烘焙）。
class _EditState {
  _EditState({
    required this.src,
    required this.natW,
    required this.natH,
    required this.stage,
    required this.orientation,
    required this.baseScale,
    required this.frame,
    required this.zoom,
    required this.tx,
    required this.ty,
    required this.angle,
  });

  /// 建立这份状态时的图片源。切图回来时源变了（还原过）就作废重建。
  final String src;

  /// 图片真实像素尺寸（取**解码后**的 ui.Image 尺寸，与展示、烘焙同源，见 [_CastPreviewPageState._decode]）。
  final double natW;
  final double natH;

  /// 舞台尺寸（编辑层可用区域）。换方向时重算取景框要用。
  final Size stage;

  _Orientation orientation;

  /// 图片「铺满取景框(cover)」时的 显示px/原图px，作为 zoom=1 的基准。
  double baseScale;

  /// 取景框（可视区域）在舞台内的位置尺寸，锁定当前方向比例、居中不动。
  Rect frame;

  double zoom;
  double tx;
  double ty;

  /// 用户旋转角（度，顺时针，可累加超过 360）。
  double angle;

  double get baseW => natW * baseScale;
  double get baseH => natH * baseScale;

  /// 「什么都没动」：方向仍是默认竖向、没缩放、没平移、旋转角为整圈。
  /// 这类图与未编辑图完全等价，投屏时走 coverCropToSize 即可，不必过画布烘焙一遍
  /// （对齐小程序 isPristineEdit）。
  bool get pristine {
    if (orientation != _Orientation.portrait) {
      return false;
    }
    final a = ((angle % 360) + 360) % 360;
    return (zoom - 1).abs() < 0.001 &&
        tx.abs() < 0.5 &&
        ty.abs() < 0.5 &&
        (a < 0.01 || a > 359.99);
  }

  _EditState copy() => _EditState(
    src: src,
    natW: natW,
    natH: natH,
    stage: stage,
    orientation: orientation,
    baseScale: baseScale,
    frame: frame,
    zoom: zoom,
    tx: tx,
    ty: ty,
    angle: angle,
  );
}

/// 双指基准（缩放 + 旋转 + 随中点平移）。
class _PinchAnchor {
  const _PinchAnchor({
    required this.dist,
    required this.ang,
    required this.mid,
    required this.zoom,
    required this.tx,
    required this.ty,
    required this.angle,
  });

  final double dist;
  final double ang;
  final Offset mid;
  final double zoom;
  final double tx;
  final double ty;
  final double angle;
}

/// 切图前烘焙出的预览成图：底层轮播过场时显示它，避免闪回未裁剪的原图。
/// [landscape] 决定展示框的形状，[exportDeg] 决定要反向转回多少度。
class _BakedPreview {
  const _BakedPreview({
    required this.path,
    required this.key,
    required this.landscape,
    this.exportDeg = 0,
  });

  final String path;

  /// 生成它时的编辑指纹，用于判断缓存是否仍新鲜。
  final String key;

  /// 生成它时的取景方向：决定**展示框的形状**（横向 = 宽高对调的框）。
  /// 与 [exportDeg] 是两件事——框的形状看方向，画面转多少看导出角。
  final bool landscape;

  /// 生成它时的导出角（度，顺时针）：展示时要按 `-exportDeg` 反向转回来。
  /// 横向恒 270°；竖向取设备 `verticalRotation`（2026-08-04 起，缺省 0 = 不转）。
  final double exportDeg;
}

/// 拖拽基准（长按进入拖拽态时的起手点 + 当时的变换）。
class _DragAnchor {
  const _DragAnchor({
    required this.origin,
    required this.zoom,
    required this.tx,
    required this.ty,
    required this.angle,
  });

  final Offset origin;
  final double zoom;
  final double tx;
  final double ty;
  final double angle;
}

/// 长按进入拖拽所需时长（对齐小程序 `LONG_PRESS_MS`）。
/// 2026-07-25：2s 太久（按着像没反应）改 1s；2026-07-31 按需求第 4 项两端统一到 **0.5s**。
/// 改这里记得同步 `castEditHint` 文案。
const Duration _kLongPress = Duration(milliseconds: 500);

/// 长按判定的位移容差(px)：按住期间移动超过它即认定用户在左右滑动切图，取消长按计时。
const double _kMoveCancelPx = 12;

/// 左右滑动切图的提交阈值(px)：单指横向滑动累计超过它，松手切到上一张/下一张。
const double _kSwipeCommitPx = 50;

/// 编辑态里图片相对「铺满取景框(cover)」还能再放大的上限倍数。
const double _kMaxZoomFactor = 8;

/// 缩小下限（相对 cover 的倍数，对齐小程序 `MIN_ZOOM_FACTOR`）。
///
/// 2026-07-31 需求第 4 项：图片要能「想缩小多少就缩小多少，所见即所得」——所以**不再强制
/// cover 取景框**，缩小后露出的区域就是白色画布，导出时原样带上（见 `_bake`）。
/// 不取 0 是因为 scale=0 之后任何倍率手势都乘不回来，图片会永久消失、手势再也救不回。
const double _kMinZoomFactor = 0.02;

/// **横向**导出时整幅构图的旋转量（度，顺时针）：90°（横转竖）+ 180°（真机倒置校正）。
/// 横向的**唯一真源**，别在别处另写角度。
///
/// ⚠️ 小程序侧横向角取的是后端设备字段 `rotationDegree`（缺失才回退 270°），App 仍写死 270°，
/// 两端在这一点上尚未对齐（属既有差异，不在 2026-08-04 竖向旋转这一轮的范围内）。
const double _kLandscapeExportRotateDeg = 270;

/// **竖向**导出时整幅构图的旋转量：取设备字段 `verticalRotation`（[DeviceItem.verticalRotation]），
/// 2026-08-04 新增；**未下发即 0 = 不旋转**（此前竖向从不旋转，行为等价）。
///
/// 这个角度决定的是「上传给抖动接口、随后图传到设备的那张成品图」的朝向，不是页面展示朝向；
/// 展示侧要按同一角度**反向**转回来（见 `_buildPager` 的 RotatedBox），两处必须同源取值，
/// 否则会出现「设备上正了、手机预览里倒了」。
double _verticalExportRotateDeg(DeviceItem device) =>
    device.verticalRotation.toDouble();

/// 角度归一到 [0,360)：负角、720 这类值都能正确落位。
double _normalizeDeg(double degree) => ((degree % 360) + 360) % 360;

/// 是否为奇数个直角（90/270）：这类角度把画面宽高**对调**，
/// 放大系数与展示侧的布局约束都要跟着换。
bool _isQuarterTurn(double degree) => _normalizeDeg(degree) % 180 == 90;

/// 展示侧要反向转回来的**四分之一圈数**（[RotatedBox.quarterTurns] 顺时针计）。
/// 导出转了 deg，展示就转 -deg：`(4 - deg/90) % 4`。
/// 非 90 的倍数（后端给了奇怪角度）时返回 0——布局期旋转只支持直角，
/// 宁可展示不转（用户仍能看清构图），也不要把画面切歪。
int _reverseQuarterTurns(double degree) {
  final normalized = _normalizeDeg(degree);
  if (normalized % 90 != 0) {
    return 0;
  }
  return (4 - (normalized ~/ 90)) % 4;
}

/// 切图过场时长：松手后 Banner 轨道补完剩下那段路要花的时间（对齐小程序 `SLIDE_MS`）。
/// 2026-08-01 由 360ms 收到 300ms —— 现在过场只补「手指没滑完的那一截」，不再是整段路程，
/// 360ms 会显得拖沓。
const Duration _kSlideDuration = Duration(milliseconds: 300);

/// 已经是第一张还往右滑 / 最后一张还往左滑时的阻尼系数：滑得动（有反馈），但明显滑不过去。
const double _kSlideRubber = 3;

/// 「拿起」放大回弹动画时长（对齐小程序 clipPickup 0.34s）。
const Duration _kPickupDuration = Duration(milliseconds: 340);

/// 可视区域圆角（小程序 .edit-clip 40rpx = 20px）。
const double _kClipRadius = 20;

/// 跨页带回上一轮构图（对齐小程序 `pendingProjection.editStates`，2026-08-03）。
///
/// 投屏失败后点「重新投屏」会新建一个 [CastPreviewPage]，[_CastPreviewPageState._states]
/// 随旧页一起销毁——用户得把每张图重新拖一遍。这里在点「开始投屏」时把当轮状态挂到静态槽位，
/// 新页 `initState` 按**图片路径列表完全一致**认领回来。
///
/// 小程序那边是写进 Storage 的 `pendingProjection.editStates`，App 没有这个跨页存储，
/// 用一个进程内静态槽位承载同样的语义（进程重启即失效，正合适：临时文件那时也没了）。
///
/// 路径对不上（「继续投屏」重新选的图）就整份丢弃，绝不会把 A 组图的构图套到 B 组图上；
/// 单张的 `src` 在 [_CastPreviewPageState._enterEdit] 里还会再校验一次。
class _CarriedEdits {
  _CarriedEdits._();

  static List<String> _paths = const <String>[];
  static Map<int, _EditState> _states = const <int, _EditState>{};

  static void save(List<String> paths, Map<int, _EditState> states) {
    _paths = List<String>.from(paths);
    _states = <int, _EditState>{
      for (final e in states.entries) e.key: e.value.copy(),
    };
  }

  /// 认领并清空：只有紧接着的那一次「重新投屏」能拿到，避免久留后串到别的批次。
  static Map<int, _EditState> take(List<String> paths) {
    final matched =
        _paths.length == paths.length &&
        List<int>.generate(paths.length, (i) => i).every(
          (i) => _paths[i] == paths[i],
        );
    final states = matched ? _states : const <int, _EditState>{};
    _paths = const <String>[];
    _states = const <int, _EditState>{};
    return states;
  }
}

class _CastPreviewPageState extends State<CastPreviewPage>
    with TickerProviderStateMixin {
  /// 待投屏原图路径。**全程不改写**：编辑是非破坏性的，烘焙产物只在 [_startCast] 里临时生成，
  /// 记录/图库要用的原图仍是这份（对齐小程序 `_origSrc` 语义）。
  late final List<String> _paths = List<String>.from(widget.imagePaths);

  final PageController _pager = PageController();

  /// 每张图的编辑状态快照（index → 状态），切图存、切回恢复。
  final Map<int, _EditState> _states = <int, _EditState>{};

  /// 每张图的**预览缓存**（index → 切图前烘焙出的成图）：只给底层轮播的过场用，
  /// 不改 [_paths]。点「开始投屏」时指纹仍匹配就直接复用，不重复出图。
  final Map<int, _BakedPreview> _previews = <int, _BakedPreview>{};

  /// 切图在途锁（切之前可能要先烘焙预览缓存，防连续快滑排队出图）。
  bool _switching = false;

  /// 活动指针（按下顺序），用于还原小程序 `e.touches[0] / [1]` 的语义。
  final Map<int, Offset> _pointers = <int, Offset>{};
  final List<int> _pointerOrder = <int>[];

  int _activeIndex = 0;

  /// 当前图的编辑数值真值；null = 编辑层没起来（读图失败等），此时只做普通预览。
  _EditState? _edit;

  /// 当前图的解码结果：**展示与烘焙共用同一份**，避免「预览按 A 尺寸、导出按 B 尺寸」
  /// 这类 EXIF 方向差异导致的静默错位。
  ui.Image? _activeImage;
  String? _activeImageSrc;

  /// enterEdit 防串台序号：异步解码期间用户又切了图，旧流程作废。
  int _editSeq = 0;

  Size? _stageSize;
  bool _editing = false;
  /// Banner 过场进行中：期间不接新手势（此刻 [_edit] 还指着「正在滑走的那张」，
  /// 接下去只会把状态搅乱），落位后由 [_switchImage] 复位。
  bool _sliding = false;
  bool _dragging = false;
  bool _projecting = false;
  _Orientation _orientation = _Orientation.portrait;

  _Mode _mode = _Mode.none;
  Offset? _touchStart;
  double _swipeDx = 0;

  /// Banner 轨道的横向平移量(px)：跟手期间逐帧写入，松手后由 [_slide] 补完剩下那段。
  ///
  /// 用 ValueNotifier 而不是 setState 的字段——手势期每帧都要改，整页 rebuild 太贵；
  /// 只有编辑层外面那层 [Transform.translate] 订阅它。
  /// 底层 [PageView] 同步走 `jumpTo`（见 [_syncPagerToSlide]），邻图才会真从屏幕边缘滑进来。
  final ValueNotifier<double> _slideDx = ValueNotifier<double>(0);
  double _slideFrom = 0;
  double _slideTo = 0;

  Timer? _lpTimer;
  _PinchAnchor? _pinch;
  _DragAnchor? _dragAnchor;

  late final AnimationController _pickup = AnimationController(
    vsync: this,
    duration: _kPickupDuration,
  );

  /// 松手后补完 Banner 过场的驱动器：把 [_slideDx] 从 [_slideFrom] 补到 [_slideTo]。
  late final AnimationController _slide = AnimationController(
    vsync: this,
    duration: _kSlideDuration,
  )..addListener(_onSlideTick);

  /// 「拿起」反馈：1 → 1.05 → 1（对齐小程序 @keyframes clipPickup）。
  late final Animation<double> _pickupScale =
      TweenSequence<double>(<TweenSequenceItem<double>>[
        TweenSequenceItem<double>(
          tween: Tween<double>(
            begin: 1,
            end: 1.05,
          ).chain(CurveTween(curve: Curves.easeOut)),
          weight: 45,
        ),
        TweenSequenceItem<double>(
          tween: Tween<double>(
            begin: 1.05,
            end: 1,
          ).chain(CurveTween(curve: Curves.easeIn)),
          weight: 55,
        ),
      ]).animate(_pickup);

  /// 设备屏幕分辨率 → 取景比例与导出画布尺寸。
  ///
  /// 取 [FrameProtocol.screenTypes]（3.7寸 480×720 / 5.89寸 680×960）——这是权威表。
  /// **不要**用 `FrameScreenTypeDetails.width/height`：那是一组陈旧的错值（416×240 / 600×448）。
  ({int width, int height}) get _deviceSize {
    final screen = FrameProtocol.screenTypes[widget.device.screenType.code];
    final w = screen?.width ?? 0;
    final h = screen?.height ?? 0;
    if (w > 0 && h > 0) {
      return (width: w, height: h);
    }
    return (width: 480, height: 720); // 兜底：3.7 寸
  }

  double get _deviceRatio {
    final size = _deviceSize;
    return size.width / size.height;
  }

  /// 指定取景方向下的**导出旋转角**（度，顺时针）。烘焙、展示反向旋转、缓存标记都必须走这一处：
  /// 分头取值就会出现「设备上正了、手机预览里倒了」。
  ///   · 横向 → [_kLandscapeExportRotateDeg]（270°，App 侧仍写死）；
  ///   · 竖向 → 设备 `verticalRotation`（2026-08-04 新增，未下发即 0 = 不旋转）。
  double _exportRotateDegOf(_Orientation orientation) =>
      orientation == _Orientation.landscape
      ? _kLandscapeExportRotateDeg
      : _verticalExportRotateDeg(widget.device);

  /// 指定取景方向下的可视区域宽高：竖向 = 设备物理分辨率；横向 = 宽高对调。
  Size _viewSize(_Orientation orientation) {
    final dev = _deviceSize;
    return orientation == _Orientation.landscape
        ? Size(dev.height.toDouble(), dev.width.toDouble())
        : Size(dev.width.toDouble(), dev.height.toDouble());
  }

  @override
  void initState() {
    super.initState();
    // 接回上一轮构图：投屏失败点「重新投屏」跳回本页时，底图仍是原图（_paths 全程不改写），
    // 构图还是用户上次构好的那个，不用重新拖一遍（见 [_CarriedEdits]）。
    _states.addAll(_CarriedEdits.take(_paths));
    // 进预览页即预热 seekink 抖动接口 token（对齐小程序 preview.js onLoad 的 prefetchAuthToken）：
    // 用户构图的这几秒先把 token 取回会话缓存，点「开始投屏」出帧零等待；失败静默。
    DitheringApi.prefetchAuthToken();
  }

  @override
  void dispose() {
    _clearLongPress();
    _pickup.dispose();
    _slide
      ..removeListener(_onSlideTick)
      ..dispose();
    _slideDx.dispose();
    _pager.dispose();
    _activeImage?.dispose();
    super.dispose();
  }

  // ── 编辑态几何 ───────────────────────────────────────────

  /// 舞台内「指定方向可视区域比例」的最大居中矩形 = 固定取景框。
  /// 区外内容由 [ClipRRect] 裁掉（对齐小程序 .edit-clip 的 overflow:hidden）。
  Rect _frameFor(Size stage, _Orientation orientation) {
    final view = _viewSize(orientation);
    final ratio = view.width / view.height;
    var fw = stage.width;
    var fh = fw / ratio;
    if (fh > stage.height) {
      fh = stage.height;
      fw = fh * ratio;
    }
    return Rect.fromLTWH(
      (stage.width - fw) / 2,
      (stage.height - fh) / 2,
      fw,
      fh,
    );
  }

  /// 解码图片：**展示与烘焙共用**这一份 ui.Image，天然规避 EXIF 方向导致的两处尺寸不一致。
  Future<ui.Image?> _decode(String path) async {
    try {
      final bytes = await File(path).readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      codec.dispose();
      return frame.image;
    } catch (_) {
      return null;
    }
  }

  /// 进入/重建常驻编辑态：解码当前图 → 摆好「固定取景框 + 铺满该框的图片」。
  /// 已有编辑状态（[_states]）且图片源没变则原样恢复。
  /// 失败不打扰用户：静默停在普通预览，投屏走未编辑链路（coverCropToSize）。
  Future<bool> _enterEdit() async {
    final stage = _stageSize;
    final index = _activeIndex;
    if (stage == null || index < 0 || index >= _paths.length) {
      if (mounted && _editing) {
        setState(() => _editing = false);
      }
      return false;
    }
    final src = _paths[index];
    // 已在编辑同一张图：直接复用当前变换，不重置
    if (_editing && _edit != null && _edit!.src == src) {
      return true;
    }
    final seq = ++_editSeq;

    ui.Image? image;
    if (_activeImage != null && _activeImageSrc == src) {
      image = _activeImage; // 还原原图等场景：同一张图不重复解码
    } else {
      image = await _decode(src);
      if (seq != _editSeq || !mounted) {
        image?.dispose();
        return false;
      }
      final previous = _activeImage;
      _activeImage = image;
      _activeImageSrc = image == null ? null : src;
      // 旧图还可能被本帧的 RawImage 引用着，等这帧过完再释放
      if (previous != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) => previous.dispose());
      }
    }
    if (image == null) {
      if (mounted) {
        setState(() => _editing = false);
      }
      return false;
    }

    // 之前存过状态且图片源没变才恢复，否则从头来
    final saved = _states[index];
    final restored = (saved != null && saved.src == src) ? saved : null;
    final orientation = restored?.orientation ?? _Orientation.portrait;
    final frame = _frameFor(stage, orientation);
    final natW = image.width.toDouble();
    final natH = image.height.toDouble();
    // cover：图片刚好铺满取景框的基准显示尺寸（zoom=1 时的 显示px/原图px）
    final baseScale = math.max(frame.width / natW, frame.height / natH);

    _edit = _EditState(
      src: src,
      natW: natW,
      natH: natH,
      stage: stage,
      orientation: orientation,
      baseScale: baseScale,
      frame: frame,
      zoom: restored?.zoom ?? 1,
      tx: restored?.tx ?? 0,
      ty: restored?.ty ?? 0,
      angle: restored?.angle ?? 0,
    );
    _mode = _Mode.none;
    _clearLongPress();
    setState(() {
      _editing = true;
      _orientation = orientation;
      _dragging = false;
    });
    final g = _edit!;
    _applyEdit(g.zoom, g.tx, g.ty, g.angle);
    _precacheNeighbors(index);
    return true;
  }

  /// 预热相邻两张（对齐小程序 `preview.js _prefetchNeighbors`）。
  ///
  /// 底层 [PageView] 的邻页是**手指开始滑动的那一刻**才建 [Image.file] 的，几 MB 的手机照片
  /// 读盘 + 解码常要一两百毫秒，正好压在 300ms 过场里——用户看到的就是「每切一张都要重新加载
  /// 一遍」：过场里先是一张白卡，落位后图才姗姗补上。提前喂进 ImageCache 后过场直接命中，
  /// 落位零解码。文件缺失/损坏时 onError 静默吞掉：预热失败不该冒泡成未捕获异常，
  /// 真正展示时 `Image.file` 自己的 errorBuilder 还会兜底。
  void _precacheNeighbors(int index) {
    if (!mounted) {
      return; // 页面已卸载：context 失效，precacheImage 会抛
    }
    for (final i in <int>[index - 1, index + 1]) {
      if (i < 0 || i >= _paths.length) {
        continue;
      }
      // 与 _buildPager 同一套取源优先级：预热的才是过场里真正要显示的那张
      final path = _previews[i]?.path ?? _paths[i];
      precacheImage(
        FileImage(File(path)),
        context,
        onError: (error, stackTrace) =>
            debugPrint('[CastPreview] 邻图预热失败（不影响展示）: $error'),
      );
    }
  }

  /// 把当前图的编辑数值快照进 [_states]（整份存下来：烘焙要用 frame/baseScale 等几何量）。
  void _saveEditState() {
    final g = _edit;
    if (g == null) {
      return;
    }
    _states[_activeIndex] = g.copy();
  }

  /// 「竖向 / 横向」：只换取景框（可视区域），图片的位置/大小/角度原地保持不变——
  /// 需求语义是「横竖切换改变的只是可视区域，对图片本身没有改动」。换框后 baseScale 变了，
  /// 用 zoom 反向补偿保住绝对显示尺寸。新框盖不满时**不再自动放大**——2026-07-31 起允许
  /// 自由缩小，露出的地方就是白色画布（见 [_clampTransform]）。
  void _setOrientation(_Orientation orientation) {
    if (orientation == _orientation) {
      return;
    }
    final g = _edit;
    if (g == null) {
      setState(() => _orientation = orientation); // 编辑层没起来：只记 UI 状态
      return;
    }
    final frame = _frameFor(g.stage, orientation);
    final newBaseScale = math.max(frame.width / g.natW, frame.height / g.natH);
    final keepZoom = (g.baseScale * g.zoom) / newBaseScale;
    g.orientation = orientation;
    g.frame = frame;
    g.baseScale = newBaseScale;
    _mode = _Mode.none;
    _clearLongPress();
    setState(() => _orientation = orientation);
    _applyEdit(keepZoom, g.tx, g.ty, g.angle);
  }

  /// 约束一组变换：**只限制极小 / 极大的缩放值**（[_kMinZoomFactor] ~ [_kMaxZoomFactor]），
  /// 不再强制铺满取景框，也不再把平移夹在图片边缘内。
  ///
  /// 2026-07-31 需求第 4 项「想缩小多少就缩小多少，所见即所得」（对齐小程序
  /// `preview.js _clampTransform` 同日改动）。原实现有两道夹取：
  ///   ① zoom ≥「当前角度下 cover 取景框」——用户一缩小就被顶回去，看着像卡住；
  ///   ② 平移不让取景框越出图片——缩到比框小以后这条几何上无解，图片会被钉死在中间。
  /// 两道一起去掉，缩小/平移露出的区域就是白色画布，导出时原样带上（预览与输出一致）。
  ///
  /// [angle] 现在不参与夹取，保留形参是为了让调用点读起来仍是「一整组变换」。
  ({double zoom, double tx, double ty}) _clampTransform(
    double zoom,
    double tx,
    double ty,
    double angle,
  ) {
    final z = zoom.isFinite
        ? zoom.clamp(_kMinZoomFactor, _kMaxZoomFactor).toDouble()
        : 1.0;
    return (
      zoom: z,
      tx: tx.isFinite ? tx : 0.0,
      ty: ty.isFinite ? ty : 0.0,
    );
  }

  /// 应用一组变换：先夹取到合法范围，写回 [_edit]，再重建画面。
  void _applyEdit(double zoom, double tx, double ty, double angle) {
    final g = _edit;
    if (g == null) {
      return;
    }
    final clamped = _clampTransform(zoom, tx, ty, angle);
    g.zoom = clamped.zoom;
    g.tx = clamped.tx;
    g.ty = clamped.ty;
    g.angle = angle;
    setState(() {});
  }

  /// 图右上角悬浮按钮：在当前角度基础上顺时针 +90°。
  /// 只转角度、不再自动补 zoom：转出的白边就是最终输出里的白边（所见即所得）。
  void _rotate90() {
    final g = _edit;
    if (g == null) {
      return;
    }
    _applyEdit(g.zoom, g.tx, g.ty, g.angle + 90);
  }

  // ── 触摸手势（1:1 移植小程序 07-24 的状态机）───────────────
  //  单指：默认判为「左右滑动切图」；若按住几乎不动满 [_kLongPress](0.5s) → 进入拖拽态后单指平移图片。
  //  双指：随时进入缩放 + 旋转（不需长按），与切图/拖拽互不影响。

  void _clearLongPress() {
    _lpTimer?.cancel();
    _lpTimer = null;
  }

  Offset _pointerAt(int slot) => _pointers[_pointerOrder[slot]]!;

  /// 单指横滑到一半又落下第二指：这一路不会再走 [_commitSwipe]，轨道得自己弹回原位，
  /// 否则会歪着停在偏移位置上（2026-08-01）。
  void _beginPinch() {
    _swipeDx = 0;
    _springBackSlide();
    _beginPinchAnchor();
  }

  void _beginPinchAnchor() {
    final g = _edit;
    if (g == null || _pointerOrder.length < 2) {
      return;
    }
    final a = _pointerAt(0);
    final b = _pointerAt(1);
    final dist = (b - a).distance;
    _mode = _Mode.pinch;
    _pinch = _PinchAnchor(
      dist: dist == 0 ? 1 : dist,
      ang: math.atan2(b.dy - a.dy, b.dx - a.dx),
      mid: (a + b) / 2,
      zoom: g.zoom,
      tx: g.tx,
      ty: g.ty,
      angle: g.angle,
    );
  }

  void _beginDrag(Offset origin) {
    final g = _edit;
    if (g == null) {
      return;
    }
    _mode = _Mode.drag;
    _dragAnchor = _DragAnchor(
      origin: origin,
      zoom: g.zoom,
      tx: g.tx,
      ty: g.ty,
      angle: g.angle,
    );
  }

  /// 长按满 [_kLongPress](0.5s)：进入拖拽态，给「拿起」反馈（放大回弹 + 震动，仿苹果相册）。
  void _armDrag() {
    _lpTimer = null;
    final start = _touchStart;
    if (_mode != _Mode.idle || _edit == null || start == null) {
      return;
    }
    _beginDrag(start);
    HapticFeedback.mediumImpact();
    setState(() => _dragging = true);
    _pickup.forward(from: 0);
  }

  void _onPointerDown(PointerDownEvent event) {
    // 过场进行中不接新手势：_edit 还指着「正在滑走的那张」，接下去只会把状态搅乱
    if (_edit == null || _sliding) {
      return;
    }
    _pointers[event.pointer] = event.localPosition;
    _pointerOrder.add(event.pointer);
    if (_pointerOrder.length >= 2) {
      _clearLongPress();
      _beginPinch();
      return;
    }
    _mode = _Mode.idle;
    _touchStart = event.localPosition;
    _swipeDx = 0;
    _clearLongPress();
    _lpTimer = Timer(_kLongPress, _armDrag);
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (_edit == null || _sliding || !_pointers.containsKey(event.pointer)) {
      return;
    }
    _pointers[event.pointer] = event.localPosition;

    // 双指：随时进入 / 保持缩放 + 旋转
    if (_pointerOrder.length >= 2) {
      if (_mode != _Mode.pinch) {
        _clearLongPress();
        _beginPinch(); // 单指途中落下第二指：改记双指基准
        return;
      }
      final p = _pinch;
      if (p == null) {
        return;
      }
      final a = _pointerAt(0);
      final b = _pointerAt(1);
      final raw = (b - a).distance;
      final dist = raw == 0 ? 1.0 : raw;
      final ang = math.atan2(b.dy - a.dy, b.dx - a.dx);
      final mid = (a + b) / 2;
      _applyEdit(
        p.zoom * (dist / p.dist),
        p.tx + (mid.dx - p.mid.dx),
        p.ty + (mid.dy - p.mid.dy),
        p.angle + (ang - p.ang) * 180 / math.pi,
      );
      return;
    }

    final t = event.localPosition;
    final start = _touchStart;
    // 双指抬起一指后仍在移动：以剩余指改记拖拽基准，延续编辑
    if (_mode == _Mode.pinch || start == null) {
      _beginDrag(t);
      return;
    }
    final dx = t.dx - start.dx;
    final dy = t.dy - start.dy;

    if (_mode == _Mode.idle) {
      // 长按还没满就移动了 → 认定为「左右滑动切图」，取消长按计时
      if (math.sqrt(dx * dx + dy * dy) > _kMoveCancelPx) {
        _clearLongPress();
        _mode = _Mode.swipe;
      } else {
        return; // 仍在原地按住，继续等长按
      }
    }

    if (_mode == _Mode.drag) {
      final a = _dragAnchor;
      if (a == null) {
        return;
      }
      _applyEdit(
        a.zoom,
        a.tx + (t.dx - a.origin.dx),
        a.ty + (t.dy - a.origin.dy),
        a.angle,
      );
      return;
    }

    if (_mode == _Mode.swipe) {
      _swipeDx = dx;
      // 跟手：编辑层与底层 PageView 一起随指头平移（2026-08-01，对齐小程序 Banner 轨道）。
      // 此前只记录 dx、画面纹丝不动，松手才播一整段过场——那不是 banner，是跳帧。
      _applySlideOffset(dx);
    }
  }

  /// 跟手平移：滑到头（第一张再往右 / 最后一张再往左）时给阻尼，滑得动但明显滑不过去。
  void _applySlideOffset(double dx) {
    final atHead = dx > 0 && _activeIndex <= 0;
    final atTail = dx < 0 && _activeIndex >= _paths.length - 1;
    _setSlideDx(atHead || atTail ? dx / _kSlideRubber : dx);
  }

  /// 写入平移量并把底层 [PageView] 同步到同一位置。
  /// 编辑层靠 [_slideDx] 的监听者平移，PageView 靠 `jumpTo`——两者必须同步，
  /// 否则滑走的图和滑进来的图会错位。
  void _setSlideDx(double dx) {
    if (_slideDx.value == dx) {
      return;
    }
    _slideDx.value = dx;
    _syncPagerToSlide();
  }

  void _syncPagerToSlide() {
    if (!_pager.hasClients) {
      return;
    }
    final viewport = _pager.position.viewportDimension;
    if (viewport <= 0) {
      return;
    }
    final maxOffset = (_paths.length - 1) * viewport;
    if (maxOffset <= 0) {
      return;
    }
    _pager.jumpTo(
      (_activeIndex * viewport - _slideDx.value).clamp(0.0, maxOffset),
    );
  }

  void _onSlideTick() {
    final t = Curves.easeOut.transform(_slide.value);
    _setSlideDx(_slideFrom + (_slideTo - _slideFrom) * t);
  }

  /// 从当前位置补一段过场到 [target]。返回动画走完的 Future。
  Future<void> _animateSlideTo(double target) {
    _slideFrom = _slideDx.value;
    _slideTo = target;
    if (_slideFrom == _slideTo) {
      return Future<void>.value();
    }
    return _slide.forward(from: 0);
  }

  /// 轨道弹回原位（没滑够阈值 / 已经滑到头）：平滑归零，不要「啪」地跳回去。
  void _springBackSlide() {
    if (_slideDx.value == 0) {
      return;
    }
    _animateSlideTo(0);
  }

  void _onPointerFinish(PointerEvent event) {
    _clearLongPress();
    _pointers.remove(event.pointer);
    _pointerOrder.remove(event.pointer);
    // 还有手指没抬（双指松掉一指）：以剩余单指继续拖拽（已在主动编辑中，不再要求长按）
    if (_pointerOrder.isNotEmpty && _edit != null) {
      _beginDrag(_pointerAt(0));
      return;
    }
    final mode = _mode;
    _mode = _Mode.none;
    _pinch = null;
    _touchStart = null;
    if (_dragging) {
      setState(() => _dragging = false);
    }
    if (mode == _Mode.swipe) {
      _commitSwipe(_swipeDx);
    }
    _swipeDx = 0;
  }

  /// 松手结算：滑够阈值且方向上还有图 → 补完 Banner 过场切过去；否则轨道弹回原位。
  /// 向右滑 → 上一张，向左滑 → 下一张。
  void _commitSwipe(double dx) {
    final target = _activeIndex + (dx > 0 ? -1 : 1);
    final canSwitch =
        _paths.length > 1 &&
        dx.abs() >= _kSwipeCommitPx &&
        target >= 0 &&
        target < _paths.length;
    if (!canSwitch) {
      _springBackSlide(); // 没滑够 / 到头了：平滑弹回
      return;
    }
    _slideToNeighbor(target);
  }

  /// 补完 Banner 过场并落到相邻那张。
  ///
  /// 关键顺序（这三步就是「切换不闪」的全部）：
  ///   ① 轨道补完到 ∓一屏：滑走的是**编辑层此刻正显示的画面**，起手零跳变；
  ///      进场那张由底层 PageView 的相邻页承担，整段过场都在屏上，落位时早已解码完毕；
  ///   ② 过场同时静默烘焙当前构图（不弹「处理中」——那层蒙层本身就是一次闪）；
  ///      烘焙只改当前页的图源，而当前页此刻被编辑层盖着，看不见；
  ///   ③ 过场走完后原地换 [_activeIndex]、平移量归零：进场那张就地变成当前页，
  ///      同一个文件、同一套取景比例、同一个位置，肉眼看不出接缝。
  Future<void> _slideToNeighbor(int target) async {
    if (_switching) {
      return;
    }
    if (!_pager.hasClients || _pager.position.viewportDimension <= 0) {
      await _switchImage(target); // 量不到视口：退回无过场直切，功能不受影响
      return;
    }
    _switching = true;
    _sliding = true;
    _mode = _Mode.none;
    _clearLongPress();
    final viewport = _pager.position.viewportDimension;
    final direction = target > _activeIndex ? 1 : -1;
    // 与过场并行：把当前构图烘焙进预览缓存，滑回来时看到的就是刚构好的画面而不是原图。
    // silent —— 过场已经占满了这 300ms，再压一层「处理中」纯属画蛇添足。
    // 就地吞错（而不是等下面 await 时才抛）：烘焙失败只影响「滑回来看到的是原图」，
    // 绝不能把切图流程卡在 _switching = true 上；不就地挂 catch 还会报未捕获的异步错误。
    final baking = _bakePreviewForActive(silent: true).catchError((
      Object error,
    ) {
      debugPrint('[CastPreview] 过场中的构图烘焙失败，滑回来会退回原图: $error');
    });
    await _animateSlideTo(-direction * viewport);
    await baking;
    _switching = false;
    if (!mounted) {
      return;
    }
    await _switchImage(target);
  }

  /// 切图前把当前图「按取景框内所见」烘焙成**预览缓存**（2026-07-25 修「左右滑动会闪回未裁剪原图」）。
  ///
  /// 过场里露出的底层轮播显示的一直是原图（编辑非破坏性、从不落文件），所以切图瞬间会闪一下
  /// 未裁剪的构图。改为切之前先出一张图存进 [_previews]，轮播优先显示它：
  ///   · 没编辑 / 没动过 → 不烘焙，直接无缝切（原图与编辑层所见本就一致），顺手清掉过期缓存；
  ///   · 编辑过且指纹变了 → 「处理中」遮罩下烘焙一次。
  ///
  /// **缓存不覆盖 [_paths]**（关键）：原图仍是编辑基准，切回来能继续拖；否则横向烘焙图
  /// （竖向文件、内容转过 270°）会被当成新原图，再进编辑层就是躺倒的。
  /// [silent]：不弹「处理中」遮罩。切图过场里调用时必须为 true——
  /// 过场只有 300ms，中间闪一层全屏遮罩正是用户抱怨的「切换闪一下」。
  Future<void> _bakePreviewForActive({bool silent = false}) async {
    final index = _activeIndex;
    final g = _edit;
    if (g == null || g.pristine) {
      if (_previews.remove(index) != null && mounted) {
        setState(() {});
      }
      return;
    }
    final key = _signatureOf(g);
    if (_previews[index]?.key == key) {
      return; // 缓存仍新鲜
    }
    final image = _activeImage;
    if (image == null) {
      return;
    }
    if (!silent) {
      AppLoadingDialog.show(context, AppL10n.of(context).castProcessing);
    }
    try {
      final path = await _bake(g, image);
      if (path != null && mounted) {
        setState(() {
          _previews[index] = _BakedPreview(
            path: path,
            key: key,
            landscape: g.orientation == _Orientation.landscape,
            // 展示要按同一角度反向转回来，所以把生成时用的导出角一并记下（见 _buildPager）
            exportDeg: _exportRotateDegOf(g.orientation),
          );
        });
      }
    } finally {
      if (!silent) {
        // hide 不做 mounted 门控（不依赖 context）：页面被卸载时也要收掉蒙层。
        AppLoadingDialog.hide(context);
      }
    }
  }

  /// 一组编辑状态的指纹：变了才需要重新烘焙（预览缓存与投屏出图复用都靠它判定）。
  String _signatureOf(_EditState g) => [
    g.src,
    g.orientation.name,
    g.zoom.toStringAsFixed(4),
    g.tx.toStringAsFixed(2),
    g.ty.toStringAsFixed(2),
    g.angle.toStringAsFixed(2),
    g.frame.width.toStringAsFixed(2),
    g.baseScale.toStringAsFixed(6),
  ].join('|');

  /// 落到某张图并对它重建编辑层。
  ///
  /// Banner 过场（[_slideToNeighbor]）走完后由它收尾；量不到视口的兜底路径也走这里直切。
  /// 顺序很讲究：先把平移量归零、PageView 就位，再把 `_editing` 置 false 让位给底层页面，
  /// 最后重建编辑层——进场那张在过场里一直在屏上、早已解码，交接期间画面不动。
  Future<void> _switchImage(int index) async {
    if (index < 0 || index >= _paths.length || index == _activeIndex) {
      return;
    }
    _saveEditState();
    _edit = null; // 置空使手势自动失效
    _mode = _Mode.none;
    _clearLongPress();
    _slide.stop();
    _slideDx.value = 0;
    setState(() {
      _activeIndex = index;
      _editing = false; // 编辑层让位，露出底层页面（静态、已解码）
      _sliding = false;
      _dragging = false;
    });
    if (_pager.hasClients) {
      _pager.jumpToPage(index); // 过场已经把画面滑到位，这里只是把控制器对齐，无二次动画
    }
    if (!mounted) {
      return;
    }
    await _enterEdit();
  }

  /// 「原图」：二次确认后清掉当前图的全部编辑，回到最初的图片并重新进入编辑态。
  /// 编辑是非破坏性的（从不落文件），所以还原 = 丢掉这张的编辑状态。
  Future<void> _restoreOrigin() async {
    final l10n = AppL10n.of(context);
    final confirmed = await showAppConfirmDialog(
      context,
      title: l10n.castRestoreTitle,
      message: l10n.castRestoreConfirm,
      icon: Icons.restore_rounded,
      confirmLabel: l10n.castRestore,
    );
    if (confirmed != true || !mounted) {
      return;
    }
    _states.remove(_activeIndex);
    // 预览缓存一并作废，否则切图过场里还会闪出还原前的构图
    _previews.remove(_activeIndex);
    _edit = null;
    _mode = _Mode.none;
    _clearLongPress();
    setState(() {
      _orientation = _Orientation.portrait;
      _dragging = false;
      _editing = false;
    });
    await _enterEdit();
  }

  // ── 开始投屏：按框内所见烘焙 ───────────────────────────────

  /// 把一组编辑状态（取景框内所见：方向 + 平移 + 旋转 + 缩放）一次画布合成，
  /// 烘焙为**竖向设备物理分辨率**的新图（导出铁律见类文档）。失败返回 null 由调用方回退。
  ///
  /// 绘制顺序与小程序 canvas 完全一致（Flutter Canvas 与 CSS/微信 canvas 同为 y 轴向下、
  /// 正角顺时针，矩阵语义可 1:1 照抄）：
  /// `translate(画布中心) → rotate(导出角) → translate(tx*k, ty*k) → rotate(用户角) → scale(s)`
  Future<String?> _bake(_EditState g, ui.Image image) async {
    final dev = _deviceSize;
    final outW = dev.width;
    final outH = dev.height;
    // 导出角：横向固定 270°，竖向取设备 verticalRotation（缺省 0 = 不转）。
    final exportDeg = _exportRotateDegOf(g.orientation);
    final exportRad = exportDeg * math.pi / 180;
    // 取景框 px → 画布 px 的放大系数：只看导出角是否对调轴向——
    // 奇数直角（90/270，横向默认即属此类）时取景框的「宽」对应画布的「高」。
    final k = _isQuarterTurn(exportDeg)
        ? outH / g.frame.width
        : outW / g.frame.width;
    // 原图 px → canvas px：baseScale(显示/原图) × zoom × k
    final s = g.baseScale * g.zoom * k;
    final rad = g.angle * math.pi / 180;

    try {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(
        recorder,
        Rect.fromLTWH(0, 0, outW.toDouble(), outH.toDouble()),
      );
      // jpg 无 alpha 通道，先铺白底，避免透明像素被压成黑色（照片无 alpha，纯属兜底）
      canvas.drawRect(
        Rect.fromLTWH(0, 0, outW.toDouble(), outH.toDouble()),
        Paint()..color = const Color(0xFFFFFFFF),
      );
      canvas.save();
      // 先落到画布中心，再按导出角把整幅构图转过去：此后坐标系就等价于取景框，
      // 图片相对取景框中心的平移(tx,ty)、用户自己的旋转、缩放都能原样套用。
      canvas.translate(outW / 2, outH / 2);
      if (exportRad != 0) {
        canvas.rotate(exportRad);
      }
      canvas.translate(g.tx * k, g.ty * k);
      canvas.rotate(rad);
      canvas.scale(s);
      final w = image.width.toDouble();
      final h = image.height.toDouble();
      canvas.drawImageRect(
        image,
        Rect.fromLTWH(0, 0, w, h),
        Rect.fromLTWH(-w / 2, -h / 2, w, h),
        Paint()
          ..isAntiAlias = true
          ..filterQuality = FilterQuality.high,
      );
      canvas.restore();

      final picture = recorder.endRecording();
      final rendered = await picture.toImage(outW, outH);
      picture.dispose();
      final data = await rendered.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      rendered.dispose();
      if (data == null) {
        return null;
      }
      // dart:ui 的 toByteData 只能出 png/rawRgba，JPEG 编码交给 image 包（在 isolate 里跑）。
      // 按 offset/length 取视图而不是整个 buffer：ByteData 未必从 0 开始。
      return CastImageEditor.encodeRgbaToJpeg(
        rgba: data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        width: outW,
        height: outH,
      );
    } catch (error) {
      debugPrint('[预览] 编辑烘焙失败，该图回退未编辑链路: $error');
      return null;
    }
  }

  /// 取某张图用于烘焙的解码结果：当前图直接复用展示用的那份，其余现解现用完就释放。
  Future<String?> _bakeIndex(int index, _EditState state) async {
    final src = _paths[index];
    if (_activeImage != null && _activeImageSrc == src) {
      return _bake(state, _activeImage!);
    }
    final image = await _decode(src);
    if (image == null) {
      return null;
    }
    try {
      return await _bake(state, image);
    } finally {
      image.dispose();
    }
  }

  /// 投屏前统一出图（串行，避免同时占用大块位图内存）：
  ///   ① 有编辑状态且真的动过 → 按「取景框内所见」烘焙成竖向设备分辨率新图；
  ///   ② 没动过 / 从没看过的图 → [CastImageEditor.coverCropToSize] 按设备比例中心裁切 + 缩放，
  ///      与预览所见（cover 铺满）一致；
  ///   ③ 任一步失败都回退上一级，最差回退原图，**不阻断投屏**（对齐小程序）。
  Future<void> _startCast() async {
    if (_projecting) {
      return; // 投屏中防连点
    }
    if (_paths.isEmpty) {
      AppToast.show(context, AppL10n.of(context).castKeepOnePhoto);
      return;
    }
    setState(() => _projecting = true);
    AppLoadingDialog.show(context, AppL10n.of(context).castProcessing);

    final dev = _deviceSize;
    final outPaths = <String>[];
    try {
      for (var i = 0; i < _paths.length; i++) {
        final src = _paths[i];
        // 当前图优先取活的 _edit（最新手势）；其余取快照
        final state = (i == _activeIndex ? _edit : _states[i]);
        final edited = state != null && state.src == src && !state.pristine;
        String? out;
        if (edited) {
          // 滑动切图时已按同一组几何烘焙过、之后没再动过 → 直接复用，不重复出图
          final cached = _previews[i];
          out = cached != null && cached.key == _signatureOf(state)
              ? cached.path
              : await _bakeIndex(i, state);
        }
        if (out == null) {
          try {
            // 未编辑图走中心裁切，但**旋转角必须与编辑图一致**：都取竖向导出角
            //（设备 verticalRotation，缺省 0 = 不转）。未编辑图必然是竖向取景，
            // 少转这一下就会出现「编辑过的正着、没编辑的倒着」。
            final result = await CastImageEditor.coverCropToSize(
              path: src,
              width: dev.width,
              height: dev.height,
              rotateDegrees: _exportRotateDegOf(_Orientation.portrait).round(),
            );
            out = result?.path;
          } catch (_) {
            out = null;
          }
        }
        outPaths.add(out ?? src);
      }
    } finally {
      // hide 不做 mounted 门控（不依赖 context）：页面被卸载时也要收掉蒙层。
      AppLoadingDialog.hide(context);
    }
    if (!mounted) {
      return;
    }

    // 把当轮构图挂到跨页槽位：投屏失败点「重新投屏」跳回预览页时原样恢复（见 [_CarriedEdits]）。
    // 先把当前图的实时手势快照进 _states，否则带回去的是它上次切图时的旧构图。
    _saveEditState();
    _CarriedEdits.save(_paths, _states);

    // pushReplacement：投屏页返回时直接回到上一页（首页/设备页），
    // 不要退回这个已经用过的预览页（对齐小程序 redirectTo）。
    await Navigator.of(context).pushReplacement(
      AppPageRoute<void>(
        builder: (_) => CastingProgressPage(
          state: widget.state,
          userProductId: widget.device.id,
          // 带上设备对象：投屏页的「继续投屏」要靠它跳回预览页。
          device: widget.device,
          deviceName: widget.device.name,
          imagePaths: outPaths,
          // 投屏记录/图库存的是**原图**（对齐小程序 setUserProductUpload 传 _origSrc）：
          // 烘焙产物只是设备帧的源图，拿它建记录会让图库里全是取景框裁剪后的小图。
          originalPaths: List<String>.from(_paths),
        ),
      ),
    );
  }

  // ── UI ──────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    return FigmaScreen(
      title: l10n.castPreviewTitle,
      scrollable: false,
      bodyPadding: EdgeInsets.zero,
      background: Image.asset('assets/images/bg02.jpg', fit: BoxFit.cover),
      body: Column(
        children: [
          _buildCounter(),
          const SizedBox(height: 24), // .preview-stage margin-top 48rpx
          Expanded(child: _buildStage()),
          const SizedBox(height: 12), // .preview-stage margin-bottom 24rpx
          if (_paths.length > 1) _buildDots(),
          _buildToolBar(),
          _buildGestureTip(),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 23),
            child: FigmaPrimaryButton(
              label: _projecting ? l10n.castCasting : l10n.castStartCasting,
              onPressed: _projecting ? null : _startCast,
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  /// 顶部张数：居中药丸（对齐小程序 .preview-imageCount）。
  Widget _buildCounter() {
    if (_paths.isEmpty) {
      return const SizedBox.shrink();
    }
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 2),
        decoration: BoxDecoration(
          color: const Color(0x142A2B2B),
          borderRadius: BorderRadius.circular(62),
        ),
        child: Text(
          '${_activeIndex + 1}/${_paths.length}',
          style: const TextStyle(
            color: Color(0xCC2A2B2B),
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  /// 舞台：底层 PageView 只负责切图过场，上层是独占触摸的常驻编辑层。
  Widget _buildStage() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 23),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stage = Size(constraints.maxWidth, constraints.maxHeight);
          if (_stageSize != stage) {
            _stageSize = stage;
            // 首帧量到舞台（或尺寸变化）后再建编辑层：几何全依赖舞台尺寸。
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                _enterEdit();
              }
            });
          }
          final g = _edit;
          // 2026-08-01：不再因 _sliding 而摘掉编辑层——过场里滑走的就该是用户此刻所见，
          // 先切成静态图再动正是「切换闪一下」的来源。现在整条编辑层跟着轨道一起平移。
          final editorUp = _editing && g != null;
          return Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              // 底层轮播常驻：跟手期间由它把相邻那张从屏幕边缘送进来。
              // 当前页在编辑层起来时单独藏掉（见 _buildPager），而不是整条 PageView 藏掉——
              // 整条藏了邻图就永远露不出来，那样就还是「松手才跳一下」的老样子。
              Positioned.fill(child: _buildPager(editorUp: editorUp)),
              if (editorUp)
                // 编辑层与右上角转 90° 按钮一起随轨道平移：轨道位移只订阅 _slideDx，
                // 不走 setState，手势期每帧只重建这一层 Transform。
                Positioned.fill(
                  child: ValueListenableBuilder<double>(
                    valueListenable: _slideDx,
                    builder: (context, dx, child) =>
                        Transform.translate(offset: Offset(dx, 0), child: child),
                    child: Stack(
                      children: [
                        Positioned.fill(child: _buildEditLayer(g)),
                        _buildRotateFab(stage, g.frame),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  /// 底层轮播：承载「相邻那张从屏幕边缘滑进来」这件事。触摸全部被上层编辑层接管，
  /// 所以 physics 恒为不可滑——位置由 [_syncPagerToSlide] 用 `jumpTo` 跟着手指/过场同步。
  ///
  /// [editorUp]：编辑层是否正盖在当前页上。为真时**当前页**留空（编辑层已经把它画了），
  /// 避免横向取景框比竖向矮时，框上下露出这里按竖向比例铺的那张图。
  /// 只藏当前页、不藏整条 PageView —— 整条藏了邻图就永远露不出来。
  Widget _buildPager({bool editorUp = false}) {
    if (_paths.isEmpty) {
      return Center(
        child: Text(
          AppL10n.of(context).castNoPhotos,
          style: const TextStyle(color: Color(0xFF9AA1AB), fontSize: 14),
        ),
      );
    }
    return PageView.builder(
      controller: _pager,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _paths.length,
      itemBuilder: (context, index) {
        if (editorUp && index == _activeIndex) {
          return const SizedBox.expand();
        }
        final preview = _previews[index];
        final path = preview?.path ?? _paths[index];
        // 展示框形状只看**取景方向**：有预览缓存就按它的方向铺（横向 = 宽高对调），
        // 与编辑层里的取景框严丝合缝；没有就按设备（竖向）比例铺 ——
        // 未编辑图在编辑层里也正是 cover 铺满竖向框。
        // ⚠️ 别把它和下面的反向旋转混成一件事：框的形状看方向，画面转多少看导出角。
        final ratio = preview != null && preview.landscape
            ? 1 / _deviceRatio
            : _deviceRatio;
        Widget image = Image.file(
          key: ValueKey(path),
          File(path),
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => Center(
            child: Text(
              AppL10n.of(context).castImageLoadFailed,
              style: const TextStyle(color: Color(0xFF828A95), fontSize: 13),
            ),
          ),
        );
        // 成图是「竖向设备分辨率文件 + 内容按导出角转过」，展示要按 -导出角转回来。
        // 横向 270° → quarterTurns 1（历史行为不变）；竖向 2026-08-04 起随设备
        // verticalRotation 走：0 不转（常态）、180 → 2、90 → 3。
        // 用 RotatedBox（布局期旋转、交换约束）而不是 Transform.rotate
        //（后者只在绘制期转，会上下留白、左右被切）。
        final reverseTurns = preview == null
            ? 0
            : _reverseQuarterTurns(preview.exportDeg);
        if (reverseTurns != 0) {
          image = RotatedBox(quarterTurns: reverseTurns, child: image);
        }
        return Center(
          child: AspectRatio(
            aspectRatio: ratio,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(_kClipRadius),
              // 与编辑层取景框、导出画布同为白底（需求第 4 项「所见即所得」）。
              child: ColoredBox(color: const Color(0xFFFFFFFF), child: image),
            ),
          ),
        );
      },
    );
  }

  /// 常驻编辑层：铺满舞台的透明触摸面（[Listener] 独占全部指针），
  /// 内部按 frame 摆一个 overflow:hidden 的可视区域，图片在框下自由变换。
  Widget _buildEditLayer(_EditState g) {
    final image = _activeImage;
    if (image == null) {
      return const SizedBox.shrink();
    }
    final frame = g.frame;
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: _onPointerDown,
      onPointerMove: _onPointerMove,
      onPointerUp: _onPointerFinish,
      onPointerCancel: _onPointerFinish,
      child: Stack(
        children: [
          Positioned(
            left: frame.left,
            top: frame.top,
            width: frame.width,
            height: frame.height,
            child: AnimatedBuilder(
              animation: _pickupScale,
              builder: (context, child) =>
                  Transform.scale(scale: _pickupScale.value, child: child),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(_kClipRadius),
                  // 拖拽进行中加一点浮起阴影，强调「已拿起、可拖动」
                  boxShadow: _dragging
                      ? const [
                          BoxShadow(
                            color: Color(0x4711151C),
                            blurRadius: 24,
                            offset: Offset(0, 9),
                          ),
                        ]
                      : null,
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(_kClipRadius),
                  child: ColoredBox(
                    // 取景框底色必须是**白色**，与 [_bake] 导出前铺的白底一致：
                    // 自由缩小后露出的留白就是最终会写进设备的那块白（需求第 4 项「所见即所得」）。
                    // 原来是浅蓝灰 #E6ECF4，缩小后预览留白与导出留白颜色对不上。
                    color: const Color(0xFFFFFFFF),
                    child: Stack(
                      children: [
                        Positioned(
                          left: frame.width / 2 - g.baseW / 2,
                          top: frame.height / 2 - g.baseH / 2,
                          width: g.baseW,
                          height: g.baseH,
                          child: Transform(
                            alignment: Alignment.center,
                            // 与 CSS `translate(tx,ty) rotate(a) scale(z)` 同序（T·R·S）
                            transform: Matrix4.identity()
                              ..translate(g.tx, g.ty)
                              ..rotateZ(g.angle * math.pi / 180)
                              ..scale(g.zoom),
                            child: RawImage(
                              image: image,
                              width: g.baseW,
                              height: g.baseH,
                              // baseW/baseH 已是 cover 尺寸，直接拉满即可（对齐 scaleToFill）
                              fit: BoxFit.fill,
                              filterQuality: FilterQuality.medium,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 图右上角悬浮：顺时针转 90°（跟随取景框右上角，自身右边缘对齐框内 12px 处）。
  Widget _buildRotateFab(Size stage, Rect frame) {
    return Positioned(
      right: stage.width - (frame.right - 12),
      top: frame.top + 12,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _rotate90,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0x9911151C),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: const Color(0x4DFFFFFF), width: 0.5),
          ),
          child: const Text(
            '↻ 90°',
            style: TextStyle(color: Colors.white, fontSize: 13, height: 1),
          ),
        ),
      ),
    );
  }

  /// 轮播小圆点（多图才显示，仿首页设备列表、尺寸略小）。
  Widget _buildDots() {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List<Widget>.generate(_paths.length, (index) {
          return Container(
            width: 12,
            height: 3,
            margin: EdgeInsets.only(right: index == _paths.length - 1 ? 0 : 8),
            decoration: BoxDecoration(
              color: index == _activeIndex
                  ? const Color(0xFFFF5F1F)
                  : const Color(0xFFD7DCE3),
              borderRadius: BorderRadius.circular(999),
            ),
          );
        }),
      ),
    );
  }

  /// 工具栏：竖向 / 横向 / 原图（对齐小程序 .tool-bar 玻璃卡片 + preview-icon 资源图）。
  Widget _buildToolBar() {
    if (_paths.isEmpty) {
      return const SizedBox.shrink();
    }
    final l10n = AppL10n.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(23, 14, 23, 0),
      child: Container(
        // 卡片自身只留 4（对齐小程序 .tool-bar 8rpx）：高度由 _ToolButton 的点击区撑，
        // 卡片总高与放大点击区之前基本持平。
        padding: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0x66FFFFFF),
          border: Border.all(color: const Color(0xDBFFFFFF)),
          borderRadius: BorderRadius.circular(20),
          boxShadow: const [
            BoxShadow(
              color: Color(0x217991B2),
              blurRadius: 27,
              offset: Offset(0, 12),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _ToolButton(
              label: l10n.castPortrait,
              asset: 'assets/images/preview-icon01.png',
              activeAsset: 'assets/images/preview-icon01-selected.png',
              active: _orientation == _Orientation.portrait,
              onTap: () => _setOrientation(_Orientation.portrait),
            ),
            _ToolButton(
              label: l10n.castLandscape,
              asset: 'assets/images/preview-icon02.png',
              activeAsset: 'assets/images/preview-icon02-selected.png',
              active: _orientation == _Orientation.landscape,
              onTap: () => _setOrientation(_Orientation.landscape),
            ),
            _ToolButton(
              label: l10n.castOriginal,
              asset: 'assets/images/preview-icon03.png',
              activeAsset: 'assets/images/preview-icon03-selected.png',
              // 「原图」是二次确认的还原动作，不是取景方向，永远不高亮
              active: false,
              onTap: _restoreOrigin,
            ),
          ],
        ),
      ),
    );
  }

  /// 手势说明（对齐小程序 .gesture-tip，放竖/横/原下方）。
  Widget _buildGestureTip() {
    if (_paths.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(23, 10, 23, 0),
      child: Text(
        AppL10n.of(context).castEditHint,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Color(0xFF8B9098),
          fontSize: 12,
          height: 1.5,
        ),
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.label,
    required this.asset,
    required this.activeAsset,
    required this.active,
    required this.onTap,
  });

  final String label;
  final String asset;
  final String activeAsset;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = active ? const Color(0xFFFF5F1F) : const Color(0xFF777E88);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        // 点击区就是这个盒子（2026-07-25 用户反馈「点击区域放大一点」，两端同步）：
        // 对齐小程序 .tool 的 padding 20rpx 56rpx = 10×28（图标/文字视觉位置不变）。
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              active ? activeAsset : asset,
              width: 22,
              height: 22,
              errorBuilder: (context, error, stackTrace) =>
                  Icon(Icons.crop_rounded, size: 22, color: color),
            ),
            const SizedBox(height: 7),
            Text(label, style: TextStyle(color: color, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}
