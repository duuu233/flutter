import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:image_cropper/image_cropper.dart';

import 'package:BoltStar/src/shared/widgets/app_widgets.dart';
import 'package:BoltStar/src/shared/widgets/figma_common.dart';
import '../../../device/ble/frame_protocol.dart';
// `screenType.code` 是 FrameScreenTypeDetails 扩展方法：扩展必须导入其定义库才能用。
import '../../../device/frame_device_protocol.dart';
import '../../../shared/l10n/app_l10n.dart';
import '../../../state.dart';
import '../cast_image_editor.dart';
import 'casting_progress_page.dart';

/// 投屏预览页。功能对齐小程序 `photo-album/subpackages/projection/preview`，
/// 但**实现方式取原生最优解**（见下）。
///
/// 选好图后先进这一页：左右滑动预览每张、可**裁剪 / 旋转 / 还原原图**，确认后再开始投屏。
///
/// ## 与小程序的实现差异（有意为之）
/// 小程序用 canvas + touch 事件**手搓**了一整套裁剪框（拖拽/四角缩放/九宫格/离屏导出，783 行）——
/// 那是被微信小程序沙箱逼出来的。App 直接用**原生裁剪器**（`image_cropper`：
/// Android = Yalantis uCrop，iOS = TOCropViewController）：手势更跟手、自带旋转与网格、
/// 能锁定宽高比并直接导出 JPEG，代码量和 bug 面都小一个量级。
///
/// ## 功能上必须对齐小程序的地方（不要凭感觉改）
/// - **裁剪框锁定设备宽高比**（3.7寸 480×720 → 2:3；5.89寸 680×960 → 17:24）。裁出来的就是设备上显示的样子。
/// - 图片一律按**设备比例**的框 **aspectFill 铺满**展示 —— 预览所见 = 投屏所得。
/// - **点「开始投屏」时每张图统一按设备分辨率做中心裁切 + 严格缩放**
///   （[CastImageEditor.coverCropToSize]）：小程序的 canvas 导出画布就是设备像素尺寸，
///   传给后端转码的源图恒为 480×720 / 680×960。裁剪产物（比例已对）经中心裁切等于
///   无操作、只做缩放；旋转产物/未编辑图则先裁比例再缩放——单点收口，
///   传给后端的图**永远是设备尺寸**，转码零缩放不变形（2026-07-17 对齐修复）。
/// - 旋转是**预览态效果**，直到「保存」或进入裁剪时才真正烘焙进图片；烘焙失败必须留在编辑态。
/// - 编辑态下「开始投屏」按钮置灰：必须先保存或还原退出编辑。
class CastPreviewPage extends StatefulWidget {
  const CastPreviewPage({
    super.key,
    this.state,
    required this.device,
    required this.imagePaths,
    this.recastImgBle,
    this.recastUpirId,
    this.recastImgUrl,
  });

  /// 投屏目标设备。裁剪比例取它的屏幕分辨率。
  final DeviceItem device;

  /// 用于投屏完成后把真机最新内存同步回设备列表/详情。
  final PhotoFrameState? state;

  /// 待投屏的本地原图路径（已由 CastPhotoPicker 降采样到长边 1920）。
  final List<String> imagePaths;

  /// 从投屏记录进入时携带的原设备帧。用户未编辑图片时可继续直传；
  /// 一旦裁剪或旋转，必须改走普通上传/转码，保证投出去的是最后保存的图片。
  final String? recastImgBle;
  final Object? recastUpirId;
  final String? recastImgUrl;

  @override
  State<CastPreviewPage> createState() => _CastPreviewPageState();
}

/// 预览页里的一张待投屏照片。
class _PreviewPhoto {
  _PreviewPhoto(this.originalPath) : path = originalPath;

  /// 最初选中的原图，供「原图」还原（对齐小程序 `_origSrc`）。
  final String originalPath;

  /// 当前生效的图片路径。编辑过则是导出的临时 JPEG。
  String path;

  /// 编辑后的真实像素宽高；0 = 没编辑过（对齐小程序 `cropW`/`cropH`）。
  int editedWidth = 0;
  int editedHeight = 0;

  bool get edited => editedWidth > 0 && editedHeight > 0;

  void restoreOriginal() {
    path = originalPath;
    editedWidth = 0;
    editedHeight = 0;
  }

  void applyEdit(String newPath, int width, int height) {
    path = newPath;
    editedWidth = width;
    editedHeight = height;
  }
}

enum _Tool { none, crop, rotate, origin }

class _CastPreviewPageState extends State<CastPreviewPage> {
  late final List<_PreviewPhoto> _photos = widget.imagePaths
      .map(_PreviewPhoto.new)
      .toList();

  final PageController _pager = PageController();

  int _activeIndex = 0;
  _Tool _tool = _Tool.none;
  bool _editing = false;

  /// 预览态旋转角（0/90/180/270）。「保存」或进入裁剪时才烘焙进图片。
  int _rotation = 0;

  _PreviewPhoto get _active => _photos[_activeIndex];

  /// 设备屏幕分辨率 → 裁剪锁定的宽高比。
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

  @override
  void dispose() {
    _pager.dispose();
    super.dispose();
  }

  /// 切换图片即视为换了一张：退出编辑态并重置旋转（对齐小程序 onSwiperChange）。
  void _onPageChanged(int index) {
    setState(() {
      _activeIndex = index;
      _tool = _Tool.none;
      _editing = false;
      _rotation = 0;
    });
  }

  // ── 工具栏 ───────────────────────────────────────────────

  Future<void> _selectTool(_Tool tool) async {
    switch (tool) {
      case _Tool.crop:
        await _crop();
      case _Tool.rotate:
        // 旋转是预览态可视效果（暂不写入图片），点一次 +90°。
        setState(() {
          _tool = _Tool.rotate;
          _editing = true;
          _rotation = (_rotation + 90) % 360;
        });
      case _Tool.origin:
        await _restoreOrigin();
      case _Tool.none:
        break;
    }
  }

  /// 裁剪：打开**原生裁剪器**，宽高比锁死为设备屏幕比例。
  ///
  /// 进入前先把已选旋转烘焙进图片（否则「先旋转再裁剪」会把旋转丢掉，对齐小程序 enterCrop）。
  /// 原生裁剪器自己带旋转/网格/回弹，导出直接是 JPEG。
  Future<void> _crop() async {
    // 烘焙失败就别开裁剪器了：那样裁的是**没转过**的图，用户的旋转会被静默吞掉。
    if (!await _bakeRotation() || !mounted) {
      return;
    }
    final size = _deviceSize;

    CroppedFile? cropped;
    try {
      cropped = await ImageCropper().cropImage(
        sourcePath: _active.path,
        // 锁定设备宽高比：裁出来的就是设备上显示的样子。
        aspectRatio: CropAspectRatio(
          ratioX: size.width.toDouble(),
          ratioY: size.height.toDouble(),
        ),
        // 长边限幅（对齐小程序 MAX_EDGE=2000）：足够覆盖任何相框分辨率，又不至于过大拖慢上传。
        maxWidth: CastImageEditor.maxEdge,
        maxHeight: CastImageEditor.maxEdge,
        compressFormat: ImageCompressFormat.jpg,
        compressQuality: CastImageEditor.exportQuality,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: AppL10n.of(context).castCrop,
            toolbarColor: const Color(0xFF111111),
            toolbarWidgetColor: Colors.white,
            activeControlsWidgetColor: const Color(0xFFFF5F1F),
            lockAspectRatio: true,
          ),
          IOSUiSettings(
            title: AppL10n.of(context).castCrop,
            aspectRatioLockEnabled: true,
          ),
        ],
      );
    } catch (_) {
      cropped = null;
    }
    if (!mounted || cropped == null) {
      return; // 用户取消，或裁剪器异常：保持原样
    }

    // 裁剪器只给路径，尺寸得自己读（用于预览时按裁剪后比例铺满）。
    final size2 = await _readImageSize(cropped.path);
    if (!mounted) {
      return;
    }
    setState(() {
      _active.applyEdit(
        cropped!.path,
        size2?.width ?? size.width,
        size2?.height ?? size.height,
      );
      _tool = _Tool.none;
      _editing = false;
      _rotation = 0;
    });
    AppToast.show(context, AppL10n.of(context).castSaved);
  }

  /// 读图片像素尺寸。用 Flutter 自带的解码器（原生、快），不必为这点事再动 image 包。
  Future<({int width, int height})?> _readImageSize(String path) async {
    try {
      // 只读图片头信息拿宽高（ImageDescriptor），不解码像素：原来
      // decodeImageFromList 会把整张位图解出来（1920 长边 ≈ 8~16MB 瞬时分配）
      // 又立刻 dispose，纯浪费。
      final bytes = await File(path).readAsBytes();
      final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      final descriptor = await ui.ImageDescriptor.encoded(buffer);
      final result = (width: descriptor.width, height: descriptor.height);
      descriptor.dispose();
      buffer.dispose();
      return result;
    } catch (_) {
      return null;
    }
  }

  /// 「保存」：把预览态的旋转真正烘焙进图片（对齐小程序 savePhoto 的旋转分支）。
  /// 裁剪走的是原生裁剪器，确认即落盘，不经过这里。
  Future<void> _save() async {
    // 烘焙失败就留在编辑态（旋转角还在，预览里也还转着），让用户能重试。
    // 这里若照样退出编辑态 + 提示「已保存」，投出去的就是没转过的图。
    if (!await _bakeRotation() || !mounted) {
      return;
    }
    setState(() {
      _tool = _Tool.none;
      _editing = false;
    });
    AppToast.show(context, AppL10n.of(context).castSaved);
  }

  /// 把当前预览态旋转角真正绘制进图片并导出（rotation=0 时是空操作，直接算成功）。
  /// 对齐小程序 bakeRotation。
  ///
  /// 返回**是否烘焙成功**：失败时 [_rotation] 原样保留（预览里还转着），调用方必须就地中止，
  /// 不能继续往下走 —— 否则旋转会被静默丢掉，而用户以为已经生效了。
  Future<bool> _bakeRotation() async {
    final angle = ((_rotation % 360) + 360) % 360;
    if (angle == 0) {
      return true;
    }
    AppLoadingDialog.show(context, AppL10n.of(context).castProcessing);
    CastEditResult? result;
    try {
      result = await CastImageEditor.rotate(path: _active.path, degrees: angle);
    } catch (_) {
      result = null;
    } finally {
      // hide 不做 mounted 门控（不依赖 context）：页面被卸载时也要收掉蒙层。
      AppLoadingDialog.hide(context);
    }
    if (!mounted) {
      return false;
    }
    if (result == null) {
      AppToast.show(context, AppL10n.of(context).castRotateFailed);
      return false;
    }
    final edit = result;
    setState(() {
      _active.applyEdit(edit.path, edit.width, edit.height);
      _rotation = 0;
    });
    return true;
  }

  /// 「原图」：二次确认后还原到最初的图片。对齐小程序 restoreOrigin。
  Future<void> _restoreOrigin() async {
    final l10n = AppL10n.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.castRestoreTitle),
        content: Text(l10n.castRestoreConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFFF5F1F),
            ),
            child: Text(l10n.castRestore),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    setState(() {
      _active.restoreOriginal();
      _tool = _Tool.none;
      _editing = false;
      _rotation = 0;
    });
  }

  // ── 开始投屏 ─────────────────────────────────────────────

  /// 开始投屏前，把每张图统一处理成**设备像素尺寸**（中心裁切 + 严格缩放），再进投屏页。
  ///
  /// 这一步不能省：预览里图是按设备比例铺满（中心裁切）显示的，如果把别的比例/尺寸的图
  /// 传给后端，转码时会**压变形**或引入多余缩放，与用户看到的预览不符。
  /// 对齐小程序 confirmProjection → coverCropUnedited / canvas 导出：小程序传给后端的
  /// 源图恒为设备分辨率（480×720 / 680×960），App 此处单点收口保证一致
  /// （裁剪产物比例已对，中心裁切等于无操作、只做缩放）。
  Future<void> _startCast() async {
    if (_editing) {
      return; // 编辑态按钮置灰
    }
    if (_photos.isEmpty) {
      AppToast.show(context, AppL10n.of(context).castKeepOnePhoto);
      return;
    }

    final directRecast =
        _photos.length == 1 &&
        !_photos.single.edited &&
        widget.recastImgBle != null &&
        widget.recastImgBle!.isNotEmpty;

    AppLoadingDialog.show(context, AppL10n.of(context).castProcessing);
    final paths = <String>[];
    final size = _deviceSize;
    try {
      for (final photo in directRecast ? const <_PreviewPhoto>[] : _photos) {
        try {
          final result = await CastImageEditor.coverCropToSize(
            path: photo.path,
            width: size.width,
            height: size.height,
          );
          // 处理失败不阻断投屏，回退原图（对齐小程序：任一张失败都 resolve 原图）。
          paths.add(result?.path ?? photo.path);
        } catch (_) {
          paths.add(photo.path);
        }
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
      MaterialPageRoute<void>(
        builder: (_) => CastingProgressPage(
          state: widget.state,
          userProductId: widget.device.id,
          // 带上设备对象：投屏页的「继续投屏」要靠它跳回预览页。
          device: widget.device,
          deviceName: widget.device.name,
          // 直传记录也保留预览图路径，失败后点「重新投屏」才能重新进入裁剪页。
          imagePaths: directRecast ? [_photos.single.path] : paths,
          recastImgBle: directRecast ? widget.recastImgBle : null,
          recastUpirId: directRecast ? widget.recastUpirId : null,
          recastImgUrl: directRecast ? widget.recastImgUrl : null,
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
          Expanded(child: _buildStage()),
          _buildToolBar(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: FigmaPrimaryButton(
              label: l10n.castStartCasting,
              onPressed: _editing ? null : _startCast,
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  /// 顶部：`n/总数` + 编辑态才出现的「保存」。
  Widget _buildCounter() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(23, 4, 23, 8),
      child: Row(
        children: [
          Text(
            '${_activeIndex + 1}/${_photos.length}',
            style: const TextStyle(
              color: Color(0xFF2A2D32),
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          const Spacer(),
          if (_editing)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _save,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: Text(
                  AppL10n.of(context).castSave,
                  style: const TextStyle(
                    color: Color(0xFFFF5F1F),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// 舞台：图片轮播。每张都按**设备比例**的框 aspectFill 铺满 —— 预览所见 = 投屏所得。
  ///
  /// 画框恒取设备比例（而不是「编辑后的比例」）：设备上显示出来就是这个形状，
  /// 投屏前的中心裁切也是按它裁的（[_startCast]）。只旋转过、比例还不是设备比例的图，
  /// 在这里被 aspectFill 中心裁切成什么样，投出去就是什么样。
  ///
  /// 旋转用 [RotatedBox] 而不是 `Transform.rotate`：后者只在**绘制期**转、不动布局，
  /// 转 90° 会让图在框里上下留白、左右被切掉；[RotatedBox] 在**布局期**转（交换子节点约束），
  /// 子节点按交换后的尺寸 aspectFill，转完正好铺满框 —— 这才等于烘焙后的真实结果。
  Widget _buildStage() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 23),
      child: PageView.builder(
        controller: _pager,
        onPageChanged: _onPageChanged,
        physics: const BouncingScrollPhysics(),
        itemCount: _photos.length,
        itemBuilder: (context, index) {
          final photo = _photos[index];
          // 旋转只作用于当前页（对齐小程序：只有 activeIndex 那张带 transform）。
          final rotation = index == _activeIndex ? _rotation : 0;
          return Center(
            child: AspectRatio(
              aspectRatio: _deviceRatio,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: RotatedBox(
                  // _rotation 恒为 90 的整数倍；顺时针，与 img.copyRotate 一致。
                  quarterTurns: rotation ~/ 90,
                  child: Image.file(
                    // key 带上路径：编辑会导出**新文件名**，换 key 强制重建、不吃旧缓存。
                    key: ValueKey(photo.path),
                    File(photo.path),
                    fit: BoxFit.cover, // aspectFill
                    // 预览区≈屏宽，按物理像素解码：源图长边虽已限 1920，仍能省约一半
                    // 位图内存（PageView 预热相邻页时最多 3 张同驻）；裁剪走原生裁剪器
                    // 读原文件，不受此影响。
                    cacheWidth:
                        (MediaQuery.sizeOf(context).width *
                                MediaQuery.devicePixelRatioOf(context))
                            .round(),
                    errorBuilder: (context, error, stackTrace) => ColoredBox(
                      color: const Color(0x11000000),
                      child: Center(
                        child: Text(
                          AppL10n.of(context).castImageLoadFailed,
                          style: const TextStyle(
                            color: Color(0xFF828A95),
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// 底部工具栏：裁剪 / 旋转 / 原图（对齐小程序 .tool-bar）。
  Widget _buildToolBar() {
    final l10n = AppL10n.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 23, vertical: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _ToolButton(
            label: l10n.castCrop,
            icon: Icons.crop_rounded,
            active: _tool == _Tool.crop,
            onTap: () => _selectTool(_Tool.crop),
          ),
          _ToolButton(
            label: l10n.castRotate,
            icon: Icons.rotate_right_rounded,
            active: _tool == _Tool.rotate,
            onTap: () => _selectTool(_Tool.rotate),
          ),
          _ToolButton(
            label: l10n.castOriginal,
            icon: Icons.image_outlined,
            active: _tool == _Tool.origin,
            onTap: () => _selectTool(_Tool.origin),
          ),
        ],
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.label,
    required this.icon,
    required this.active,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = active ? const Color(0xFFFF5F1F) : const Color(0xFF777E88);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 24, color: color),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: active ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
