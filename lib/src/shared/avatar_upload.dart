import 'dart:io';

import 'package:image/image.dart' as img;

/// 头像上传前的统一预处理，首页 `_changeAvatar` 与「账户资料」`_pickAvatar` 两个入口共用。
///
/// 历史教训：首页入口曾直接传相机原图（4~12MB），弱网上传几十秒；且原图解码后是
/// 数十 MB 位图瞬间进内存（4000×3000 ≈ 48MB），是低端机 OOM/掉帧的确定来源。
/// 两个入口必须保持同一行为：pickImage 原生降采样到 [maxEdge] + 兜底压到 [maxBytes]。
abstract final class AvatarUpload {
  /// 头像文件体积上限：100KB。头像最终只在 ≤64lp 的圆圈里展示，100KB 绰绰有余。
  static const int maxBytes = 100 * 1024;

  /// 头像像素长边上限：512px 在 3x 屏的 64lp 头像上仍然过采样 2 倍以上。
  static const double maxEdge = 512;

  /// 兜底压缩：pickImage 原生降采样后一般已 <100KB，超限时用 image 包按质量阶梯重编码。
  /// 压缩失败（格式不支持等）退回原文件——上传慢总好过不能换头像。
  static Future<String> ensureUnderLimit(String path) async {
    try {
      final source = File(path);
      if (await source.length() <= maxBytes) {
        return path;
      }
      final decoded = img.decodeImage(await source.readAsBytes());
      if (decoded == null) {
        return path;
      }
      var frame = decoded;
      if (frame.width > maxEdge || frame.height > maxEdge) {
        frame = frame.width >= frame.height
            ? img.copyResize(frame, width: maxEdge.toInt())
            : img.copyResize(frame, height: maxEdge.toInt());
      }
      List<int> bytes = img.encodeJpg(frame, quality: 80);
      for (final quality in const [70, 60, 50, 40]) {
        if (bytes.length <= maxBytes) {
          break;
        }
        bytes = img.encodeJpg(frame, quality: quality);
      }
      final out = File('${source.parent.path}/boltstar_avatar_upload.jpg');
      await out.writeAsBytes(bytes, flush: true);
      return out.path;
    } catch (_) {
      return path;
    }
  }
}
