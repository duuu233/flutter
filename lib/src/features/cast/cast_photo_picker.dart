import 'package:image_picker/image_picker.dart';

/// 投屏选图的统一入口：**在选图阶段就把原图降采样**，再交给投屏链路上传。
///
/// ## 为什么必须在这里压
///
/// 投屏耗时的大头是「原图上传 + 后端转码」，不是 BLE 图传。手机相机一张照片动辄 4~12MB，
/// 而后端最终只会把它压成设备分辨率的六色帧（480×720 或 680×960）——上传原图纯属白费流量和时间，
/// 弱网下能多花几十秒。
///
/// 小程序在 `result.js` 里就是这么做的（>400KB 才压，长边压到设备长边的 2 倍，quality 80），
/// App 之前**完全没做这一步**，直接把原图往后端怼（后端的 `isCompress` 参数根本不存在，
/// 传了也被忽略，指望不上）。
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

  /// 从相册多选（最多 [maxBatch] 张）。返回本地文件路径（用户取消返回空列表）。
  static Future<List<String>> pickFromAlbum() async {
    final files = await _picker.pickMultiImage(
      limit: maxBatch,
      maxWidth: _maxLongEdge,
      maxHeight: _maxLongEdge,
      imageQuality: _quality,
    );
    return files.map((file) => file.path).toList();
  }
}
