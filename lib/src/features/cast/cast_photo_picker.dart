import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../shared/l10n/app_l10n.dart';
import '../../shared/permission_gate.dart';
import '../../state.dart';

/// 投屏选图的统一入口：**在选图阶段就把原图降采样**，再交给投屏链路上传。
///
/// ## 为什么必须在这里压
///
/// 投屏耗时的大头是「原图上传 + 后端转码」，不是 BLE 图传。手机相机一张照片动辄 4~12MB，
/// 而后端最终只会把它压成设备分辨率的六色帧（480×720 或 680×960）——上传原图纯属白费流量和时间，
/// 弱网下能多花几十秒。
///
/// 小程序在 `result.js` 里就是这么做的（2026-07-16 起：长边超过设备长边才压，压到设备长边 1 倍、quality 90），
/// App 在原生选图层先把长边控制到最大设备的 2 倍（选图时还不知投给哪台设备，先取上界兜住）；
/// 真实投屏服务再对超过 400KB 的产物按**当前设备长边 1 倍、质量 90**做第二道兜底（对齐小程序）。
/// 接口里的 `isCompress=1` 只控制后端存储图，不能减少手机实际上传的字节数。
///
/// ## 为什么在 image_picker 层压，而不是选完再压
///
/// [ImagePicker] 的 `maxWidth/maxHeight/imageQuality` 是**平台原生实现**的：
/// Android 走 BitmapFactory 的 inSampleSize 降采样（解码时就只解一部分像素，不会先解全图再缩），
/// iOS 走 CoreGraphics。既比「先解码成 Dart 侧 Image 再缩」快得多，也不占 Dart 堆内存。
/// 顺带还统一转成 JPEG，绕开 iPhone 默认 HEIC 后端不一定认的问题。
///
/// 所以这里不需要额外引入 `flutter_image_compress` 之类的依赖——原生能力已经够用。
///
/// ## 尺寸怎么定
///
/// [_maxLongEdge] = 1920 = 最大设备长边(5.89寸 = 960) × 2。保留 2 倍过采样，
/// 后端缩到设备分辨率再做抖动(dither)量化时细节完全无损；再往下压才会开始影响抖动质量。
/// （同小程序的取值逻辑，只是小程序按当前设备算，我们取两种机型的上界，选图时还不知道投给哪台。）
class CastPhotoPicker {
  CastPhotoPicker._();

  /// 降采样后的长边上限（像素）。两种机型长边分别是 720 / 960，取 960×2。
  static const double _maxLongEdge = 1920;

  /// JPEG 重编码质量。90 对后端的六色量化来说绰绰有余。
  static const int _quality = 90;

  /// 单批投屏张数上限（对齐小程序 `media.chooseFromAlbum(count:5)`）。
  static const int maxBatch = 5;

  static final ImagePicker _picker = ImagePicker();

  /// 拍照。返回本地文件路径（用户取消返回空列表）。
  static Future<List<String>> takePhoto() async {
    final file = await _picker.pickImage(
      source: ImageSource.camera,
      // maxWidth/maxHeight 一起给 = 按长边等比缩进 1920×1920 的框，横竖图都覆盖。
      maxWidth: _maxLongEdge,
      maxHeight: _maxLongEdge,
      imageQuality: _quality,
    );
    return file == null ? const [] : [file.path];
  }

  /// 从相册多选（最多 [maxBatch] 张）。返回本地文件路径（用户取消/未授权返回空列表）。
  ///
  /// 进相册前先过 [PermissionGate.ensurePhotoAccess]：Android 13+ 的系统选择器
  /// 本身不要求权限也能打开相册，但产品要求必须先经用户授权（拒绝弹「去设置」引导）。
  /// 全部投屏选图入口统一走这里，权限门槛只需守这一处。
  /// [limit]：本次最多可选张数，缺省 [maxBatch]。AI 对话的图文多模态一次最多 4 张，
  /// 且要按「已选了几张」动态收紧，所以开放为参数（会被夹到 1..[maxBatch]）。
  static Future<List<String>> pickFromAlbum(
    BuildContext context, {
    int? limit,
  }) async {
    if (!await PermissionGate.ensurePhotoAccess(context)) {
      return const [];
    }
    final files = await _picker.pickMultiImage(
      limit: (limit ?? maxBatch).clamp(1, maxBatch),
      maxWidth: _maxLongEdge,
      maxHeight: _maxLongEdge,
      imageQuality: _quality,
    );
    return files.map((file) => file.path).toList();
  }

  /// 「选择投屏方式」底部弹层（拍照 / 相册），返回用户选择的来源（取消返回 null）。
  ///
  /// 卡片式设计，与首页「选择投屏方式」弹层、小程序 `.media-sheet` 同款。
  /// 设备列表 / 设备详情 / 投屏结果页「继续投屏」三处共用同一弹层，
  /// 取代各自手搓的 `ListTile` 版（那版与设计稿不一致）。
  static Future<ImageSourceType?> chooseSource(BuildContext context) {
    return showModalBottomSheet<ImageSourceType>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => const _CastMethodSheet(),
    );
  }
}

/// 「选择投屏方式」弹层（拍照 / 相册 + 取消），点选后以 [ImageSourceType] 弹栈返回。
class _CastMethodSheet extends StatelessWidget {
  const _CastMethodSheet();

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.cresMethodTitle,
                style: const TextStyle(
                  color: Color(0xFF2A2B2B),
                  fontSize: 20,
                  fontWeight: FontWeight.w500,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 25),
              _CastSheetRow(
                title: l10n.cresMethodCamera,
                subtitle: l10n.cresMethodCameraDesc,
                isCamera: true,
                artAsset: 'assets/images/home-media-mini01.png',
                arrowAsset: 'assets/images/home-camera-card-right-icon.png',
                onTap: () => Navigator.of(context).pop(ImageSourceType.camera),
              ),
              // 小程序 .media-option margin-bottom: 20rpx = 10。
              const SizedBox(height: 10),
              _CastSheetRow(
                title: l10n.cresMethodAlbum,
                subtitle: l10n.cresMethodAlbumDesc,
                isCamera: false,
                artAsset: 'assets/images/home-media-mini02.png',
                arrowAsset: 'assets/images/home-album-card-right-icon.png',
                onTap: () => Navigator.of(context).pop(ImageSourceType.album),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: Material(
                  color: const Color(0xFFEDEDED),
                  borderRadius: BorderRadius.circular(28),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(28),
                    onTap: () => Navigator.maybePop(context),
                    child: Center(
                      child: Text(
                        l10n.cancel,
                        style: const TextStyle(
                          color: Color(0xFF2A2D32),
                          fontSize: 18,
                          fontWeight: FontWeight.w500,
                          height: 1.2,
                        ),
                      ),
                    ),
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

/// 「选择投屏方式」弹层里的单行（拍照 / 相册）。卡片：白灰底 #f8f9fb / 圆角 14 / 高 64。
class _CastSheetRow extends StatelessWidget {
  const _CastSheetRow({
    required this.title,
    required this.subtitle,
    required this.isCamera,
    required this.artAsset,
    required this.arrowAsset,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final bool isCamera;
  final String artAsset;
  final String arrowAsset;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: double.infinity,
        height: 64,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFF8F9FB),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Image.asset(
              artAsset,
              width: 49,
              height: 48,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) => Icon(
                isCamera
                    ? Icons.photo_camera_rounded
                    : Icons.photo_library_rounded,
                color: isCamera
                    ? const Color(0xFFFF6A24)
                    : const Color(0xFF287BFF),
                size: 34,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Color(0xFF2A2D32),
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: Color(0xFF858B96),
                      fontSize: 11,
                      height: 1.2,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Image.asset(
              arrowAsset,
              width: 59,
              height: 59,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) => Icon(
                Icons.arrow_forward_rounded,
                color: isCamera
                    ? const Color(0xFFFF6A24)
                    : const Color(0xFF287BFF),
                size: 24,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
