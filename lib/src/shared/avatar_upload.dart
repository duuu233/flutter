import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:image/image.dart' as img;

/// 头像上传前的统一预处理，首页 `_changeAvatar` 与「账户资料」`_pickAvatar` 两个入口共用。
///
/// 历史教训：首页入口曾直接传相机原图（4~12MB），弱网上传几十秒；且原图解码后是
/// 数十 MB 位图瞬间进内存（4000×3000 ≈ 48MB），是低端机 OOM/掉帧的确定来源。
/// 两个入口必须保持同一行为：pickImage 原生降采样到 [maxEdge] + 兜底压到 [maxBytes]。
///
/// 实际链路（两个入口一致）：
/// `pickImage(maxWidth/maxHeight: 512, imageQuality: 85)` 先由**平台原生解码器**降采样，
/// 通常出来就已经是几十 KB；[ensureUnderLimit] 只在仍然超限时才二次编码。
/// 所以「4MB 的原图能正常上传」并不代表没压缩——它在到达这里之前就被降过采样了。
abstract final class AvatarUpload {
  /// 头像文件体积上限：100KB。头像最终只在 ≤64lp 的圆圈里展示，100KB 绰绰有余。
  static const int maxBytes = 100 * 1024;

  /// 头像像素长边上限：512px 在 3x 屏的 64lp 头像上仍然过采样 2 倍以上。
  static const double maxEdge = 512;

  /// 兜底压缩：pickImage 原生降采样后一般已 <100KB，超限时用 image 包按质量阶梯重编码。
  /// 压缩失败（格式不支持等）退回原文件——上传慢总好过不能换头像，但会打日志，
  /// 免得「以为压了、其实没压」这种情况再次只能靠人工抓包才发现。
  static Future<String> ensureUnderLimit(String path) async {
    final source = File(path);
    final int originalBytes;
    try {
      originalBytes = await source.length();
    } catch (error) {
      debugPrint('[AvatarUpload] 读取源文件失败，按原图上传：$error');
      return path;
    }
    if (originalBytes <= maxBytes) {
      debugPrint(
        '[AvatarUpload] 无需压缩：${_kb(originalBytes)}（上限 ${_kb(maxBytes)}）',
      );
      return path;
    }

    try {
      final decoded = img.decodeImage(await source.readAsBytes());
      if (decoded == null) {
        // 典型是 HEIC/HEIF 等 image 包不认的格式（平台选图器没有转码时会发生）。
        debugPrint(
          '[AvatarUpload] ⚠️ 解码失败（格式不支持？），按原图上传：${_kb(originalBytes)}',
        );
        return path;
      }

      var frame = _fit(decoded, maxEdge.toInt());
      List<int> bytes = img.encodeJpg(frame, quality: 80);
      for (final quality in const [70, 60, 50, 40]) {
        if (bytes.length <= maxBytes) {
          break;
        }
        bytes = img.encodeJpg(frame, quality: quality);
      }
      // 质量阶梯走完仍超限（超长图 / 极端噪声图）：继续对半降边长再压。
      // 原来到此就直接写出一个仍然超限的文件，等于上限形同虚设。
      // 复压沿用阶梯最低的 40，不要回到 70——那是往回加质量，可能怎么降边长都压不下去。
      var edge = maxEdge.toInt();
      while (bytes.length > maxBytes && edge > 64) {
        edge = edge ~/ 2;
        frame = _fit(frame, edge);
        bytes = img.encodeJpg(frame, quality: 40);
      }

      // 输出文件名带时间戳：原来固定叫 boltstar_avatar_upload.jpg，连续换头像会
      // 复用同一路径，中途失败还会留下一个半截文件被当成新头像传上去。
      //
      // ⚠️ 不要在这里"顺手清掉上一次的产物"：`profile_page` 保存成功后会把这个路径
      // 留在 `_savedAvatarPath` 上继续本地回显（避免网络头像下载间隙里头像"消失"）。
      // 扫目录删同名前缀的文件，会把另一个还挂在栈上的页面正在显示的图删掉。
      // 产物本身 ≤100KB 且落在选图器的缓存目录，交给系统回收即可。
      final stamp = DateTime.now().microsecondsSinceEpoch;
      final out = File('${source.parent.path}/boltstar_avatar_$stamp.jpg');
      await out.writeAsBytes(bytes, flush: true);
      debugPrint(
        '[AvatarUpload] 已压缩：${_kb(originalBytes)} → ${_kb(bytes.length)}'
        '（${frame.width}×${frame.height}，上限 ${_kb(maxBytes)}）',
      );
      return out.path;
    } catch (error) {
      debugPrint('[AvatarUpload] ⚠️ 压缩异常，按原图上传（${_kb(originalBytes)}）：$error');
      return path;
    }
  }

  /// 等比缩到长边不超过 [edge]；已经够小则原样返回（不做无谓的重采样）。
  static img.Image _fit(img.Image frame, int edge) {
    if (frame.width <= edge && frame.height <= edge) {
      return frame;
    }
    return frame.width >= frame.height
        ? img.copyResize(frame, width: edge)
        : img.copyResize(frame, height: edge);
  }

  static String _kb(int bytes) => '${(bytes / 1024).toStringAsFixed(1)}KB';
}
