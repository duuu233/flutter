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
/// - **长按 1s 才拖拽**（[_kLongPress]，仿苹果相册长按取图）：单指按住几乎不动满 1s → 震动 +
///   「拿起」放大回弹动画，此后单指移动才平移图片；按住期间位移超 [_kMoveCancelPx] 判为切图滑动。
/// - **双指缩放 + 旋转**随时可用，不需长按；右上角悬浮按钮每点一次顺时针 +90°。
/// - **左右滑动切图**：松手时按横向位移方向提交（[_kSwipeCommitPx]），PageView 只负责过场动画——
///   触摸全部由上层 [Listener] 独占后在 JS 同款状态机里分流（小程序那边 swiper 无法与
///   「同一根手指长按后转拖拽」共存，App 照抄这个取舍以保证两端手感一致）。
///
/// ## 导出铁律（改这里前先读完，错了不报错、设备直接花屏）
/// 两种取景方向**恒导出竖向设备物理分辨率**（480×720 / 680×960）：
/// - 竖向：画布坐标系直接对应取景框，放大系数 `k = outW / frameW`；
/// - 横向：把框内所见整幅转 **[_kExportRotateDeg] = 270°** 再画进**竖向**画布
///   （90° 进竖向 + 180° 真机倒置校正，2026-07-20 结论），`k = outH / frameW`。
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
/// [landscape] 决定展示时要不要把「竖向文件、内容转过 270°」的成图反向转正。
class _BakedPreview {
  const _BakedPreview({
    required this.path,
    required this.key,
    required this.landscape,
  });

  final String path;

  /// 生成它时的编辑指纹，用于判断缓存是否仍新鲜。
  final String key;
  final bool landscape;
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

/// 长按进入拖拽所需时长（对齐小程序 LONG_PRESS_MS）。
/// 2026-07-25：2s 太久（按着像没反应），两端同步改 1s；改这里记得同步 `castEditHint` 文案。
const Duration _kLongPress = Duration(milliseconds: 1000);

/// 长按判定的位移容差(px)：按住期间移动超过它即认定用户在左右滑动切图，取消长按计时。
const double _kMoveCancelPx = 12;

/// 左右滑动切图的提交阈值(px)：单指横向滑动累计超过它，松手切到上一张/下一张。
const double _kSwipeCommitPx = 50;

/// 编辑态里图片相对「铺满取景框(cover)」还能再放大的上限倍数。
const double _kMaxZoomFactor = 8;

/// 横向导出时整幅构图的旋转量（度，顺时针）：90°（横转竖）+ 180°（真机倒置校正）。
/// **唯一真源**，别在别处另写角度。
const double _kExportRotateDeg = 270;
const double _kExportRotateRad = _kExportRotateDeg * math.pi / 180;

/// 切图过场时长（对齐小程序 swiper duration=300ms）。
const Duration _kSlideDuration = Duration(milliseconds: 300);

/// 「拿起」放大回弹动画时长（对齐小程序 clipPickup 0.34s）。
const Duration _kPickupDuration = Duration(milliseconds: 340);

/// 可视区域圆角（小程序 .edit-clip 40rpx = 20px）。
const double _kClipRadius = 20;

class _CastPreviewPageState extends State<CastPreviewPage>
    with SingleTickerProviderStateMixin {
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
  bool _sliding = false;
  bool _dragging = false;
  bool _projecting = false;
  _Orientation _orientation = _Orientation.portrait;

  _Mode _mode = _Mode.none;
  Offset? _touchStart;
  double _swipeDx = 0;
  Timer? _lpTimer;
  _PinchAnchor? _pinch;
  _DragAnchor? _dragAnchor;

  late final AnimationController _pickup = AnimationController(
    vsync: this,
    duration: _kPickupDuration,
  );

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
    // 进预览页即预热 seekink 抖动接口 token（对齐小程序 preview.js onLoad 的 prefetchAuthToken）：
    // 用户构图的这几秒先把 token 取回会话缓存，点「开始投屏」出帧零等待；失败静默。
    DitheringApi.prefetchAuthToken();
  }

  @override
  void dispose() {
    _clearLongPress();
    _pickup.dispose();
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
    return true;
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
  /// 用 zoom 反向补偿保住绝对显示尺寸；[_clampTransform] 会在新框盖不满时自动把 zoom 顶上去。
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

  /// 约束一组变换：① zoom 不小于「当前角度下铺满取景框」所需最小值（旋转后也不露白边），
  /// 且不超过上限；② 平移不让取景框越出图片（把屏幕平移量转到图片本地坐标再夹取）。
  ({double zoom, double tx, double ty}) _clampTransform(
    double zoom,
    double tx,
    double ty,
    double angle,
  ) {
    final g = _edit!;
    final rad = angle * math.pi / 180;
    final cosT = math.cos(rad);
    final sinT = math.sin(rad);
    final c = cosT.abs();
    final s = sinT.abs();
    final fw = g.frame.width;
    final fh = g.frame.height;
    // 旋转 angle 后，图片(baseW×baseH×zoom)要包住轴对齐的取景框(fw×fh)所需的最小 zoom
    final minZoom = math.max(
      (fw * c + fh * s) / g.baseW,
      (fw * s + fh * c) / g.baseH,
    );
    var z = math.max(zoom, minZoom);
    z = math.min(z, minZoom * _kMaxZoomFactor);
    final w = g.baseW * z;
    final h = g.baseH * z;
    // 取景框旋转到图片本地坐标后的半宽/半高
    final hx = (fw / 2) * c + (fh / 2) * s;
    final hy = (fw / 2) * s + (fh / 2) * c;
    // 屏幕平移(tx,ty) → 图片本地平移(lox,loy)
    var lox = tx * cosT + ty * sinT;
    var loy = -tx * sinT + ty * cosT;
    final maxLox = math.max(0.0, w / 2 - hx);
    final maxLoy = math.max(0.0, h / 2 - hy);
    lox = lox.clamp(-maxLox, maxLox).toDouble();
    loy = loy.clamp(-maxLoy, maxLoy).toDouble();
    // 本地平移 → 屏幕平移
    return (zoom: z, tx: lox * cosT - loy * sinT, ty: lox * sinT + loy * cosT);
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
  /// 夹取会自动把 zoom 提到「转 90° 后仍铺满取景框」所需值，不露白边。
  void _rotate90() {
    final g = _edit;
    if (g == null) {
      return;
    }
    _applyEdit(g.zoom, g.tx, g.ty, g.angle + 90);
  }

  // ── 触摸手势（1:1 移植小程序 07-24 的状态机）───────────────
  //  单指：默认判为「左右滑动切图」；若按住几乎不动满 2s → 进入拖拽态后单指平移图片。
  //  双指：随时进入缩放 + 旋转（不需长按），与切图/拖拽互不影响。

  void _clearLongPress() {
    _lpTimer?.cancel();
    _lpTimer = null;
  }

  Offset _pointerAt(int slot) => _pointers[_pointerOrder[slot]]!;

  void _beginPinch() {
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

  /// 长按满 1s：进入拖拽态，给「拿起」反馈（放大回弹 + 震动，仿苹果相册）。
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
    if (_edit == null) {
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
    if (_edit == null || !_pointers.containsKey(event.pointer)) {
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
      _swipeDx = dx; // 只记录，松手时按方向切图（PageView 负责滑动过场）
    }
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

  /// 松手时按横向滑动量切到上/下一张；向右滑 → 上一张，向左滑 → 下一张。
  /// 2026-07-25：切之前先把当前图烘焙进预览缓存，过场里显示的就是刚构好的图（见 [_bakePreviewForActive]）。
  void _commitSwipe(double dx) {
    if (_paths.length <= 1 || dx.abs() < _kSwipeCommitPx) {
      return;
    }
    final target = _activeIndex + (dx > 0 ? -1 : 1);
    if (target < 0 || target >= _paths.length) {
      return;
    }
    _switchWithBake(target);
  }

  /// 烘焙（如需要）后再切图。烘焙期间加在途锁，避免连续快滑排队出图。
  Future<void> _switchWithBake(int index) async {
    if (_switching) {
      return;
    }
    _switching = true;
    try {
      await _bakePreviewForActive();
    } finally {
      _switching = false;
    }
    if (!mounted) {
      return;
    }
    await _switchImage(index);
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
  Future<void> _bakePreviewForActive() async {
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
    AppLoadingDialog.show(context, AppL10n.of(context).castProcessing);
    try {
      final path = await _bake(g, image);
      if (path != null && mounted) {
        setState(() {
          _previews[index] = _BakedPreview(
            path: path,
            key: key,
            landscape: g.orientation == _Orientation.landscape,
          );
        });
      }
    } finally {
      // hide 不做 mounted 门控（不依赖 context）：页面被卸载时也要收掉蒙层。
      AppLoadingDialog.hide(context);
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

  /// 切换到某张图：先存当前图的编辑状态（只记变换+方向，不落文件），
  /// 过场期间隐藏编辑层露出 PageView 做轮播动画，动画结束再对新图重建编辑层。
  Future<void> _switchImage(int index) async {
    if (index < 0 || index >= _paths.length || index == _activeIndex) {
      return;
    }
    _saveEditState();
    _edit = null; // 置空使手势自动失效
    _mode = _Mode.none;
    _clearLongPress();
    setState(() {
      _activeIndex = index;
      _editing = false; // 过场期间隐藏编辑层
      _sliding = true;
      _dragging = false;
    });
    if (_pager.hasClients) {
      await _pager.animateToPage(
        index,
        duration: _kSlideDuration,
        curve: Curves.easeOut,
      );
    }
    if (!mounted) {
      return;
    }
    setState(() => _sliding = false);
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
  /// `translate(画布中心) → [横向: rotate(270°)] → translate(tx*k, ty*k) → rotate(用户角) → scale(s)`
  Future<String?> _bake(_EditState g, ui.Image image) async {
    final dev = _deviceSize;
    final outW = dev.width;
    final outH = dev.height;
    final landscape = g.orientation == _Orientation.landscape;
    // 取景框 px → 画布 px 的放大系数：横向时取景框的「宽」对应画布的「高」
    final k = landscape ? outH / g.frame.width : outW / g.frame.width;
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
      // 先落到画布中心（横向再把整幅构图转 270°）：此后坐标系就等价于取景框，
      // 图片相对取景框中心的平移(tx,ty)、用户自己的旋转、缩放都能原样套用。
      canvas.translate(outW / 2, outH / 2);
      if (landscape) {
        canvas.rotate(_kExportRotateRad);
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
            final result = await CastImageEditor.coverCropToSize(
              path: src,
              width: dev.width,
              height: dev.height,
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
      background: Image.asset('assets/images/bg01.png', fit: BoxFit.cover),
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
          final editorUp = _editing && !_sliding && g != null;
          return Stack(
            children: [
              // 编辑层起来时把底层轮播整条藏掉（2026-07-25，对齐小程序 .preview-swiper.is-hidden）：
              // 横向取景框比竖向矮，不藏的话框上下会露出底层那张按竖向比例铺的图。
              // 用 Visibility(maintain*) 而不是从树上摘掉——摘掉会断开 PageController、
              // 图片也要重新解码，切图过场会闪。
              Positioned.fill(
                child: Visibility(
                  visible: !editorUp,
                  maintainState: true,
                  maintainAnimation: true,
                  maintainSize: true,
                  child: _buildPager(),
                ),
              ),
              if (editorUp) ...[
                Positioned.fill(child: _buildEditLayer(g)),
                _buildRotateFab(stage, g.frame),
              ],
            ],
          );
        },
      ),
    );
  }

  /// 底层轮播：只做切图过场动画，触摸全部被上层编辑层接管，
  /// 所以 physics 恒为不可滑（对齐小程序「swiper 只负责过场、切图由 _commitSwipe 提交」的取舍）。
  Widget _buildPager() {
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
        final preview = _previews[index];
        final path = preview?.path ?? _paths[index];
        // 有预览缓存就按它的取景方向铺（横向 = 宽高对调），与编辑层里的取景框严丝合缝；
        // 没有就按设备（竖向）比例铺 —— 未编辑图在编辑层里也正是 cover 铺满竖向框。
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
        if (preview != null && preview.landscape) {
          // 横向成图是「竖向设备分辨率文件 + 内容顺时针转过 270°」，展示要转回来：
          // -270° ≡ 顺时针 90° = quarterTurns 1。用 RotatedBox（布局期旋转、交换约束）
          // 而不是 Transform.rotate（只在绘制期转，会上下留白左右被切）。
          image = RotatedBox(quarterTurns: 1, child: image);
        }
        return Center(
          child: AspectRatio(
            aspectRatio: ratio,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(_kClipRadius),
              child: ColoredBox(color: const Color(0xFFE6ECF4), child: image),
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
                    color: const Color(0xFFE6ECF4),
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
