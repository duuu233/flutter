import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute, debugPrint;
import 'package:image/image.dart' as img;

/// AI 图文多模态**上传前**把本机照片压到目标体积。对齐小程序 `utils/media.js compressToTarget`
/// （2026-07-27 用户要求「用户发送本机照片需要压缩大小目标 100KB」）。
///
/// ## ⚠️ 别和 `CastImageEditor` 搞混，两者目标相反
/// - 投屏那套（`cast_image_editor.dart coverCropToSize`）：缩到**设备物理分辨率**，为的是
///   **保画质**——后端要按它量化成六色帧，细节全靠这张图；不看体积。
/// - 这一套：压到**目标字节数**，为的是**省流量 / 加快上传**——AI 只需要看清内容，不上屏。
///
/// ## 策略：先缩分辨率，再逐档降质
/// 长边先封顶 [_maxLongEdge]（AI 视觉分析用不到 4000px 的原图），这一步通常就把体积拉到目标附近，
/// 而且比一味降 quality 画质更好——降质会糊掉文字/细节，AI 反而看不清。之后按 [_qualitySteps]
/// 逐档降质，走到 [_qualityFloorIndex] 之后每轮再砍一半分辨率（对付高清大图 / 细节极多的照片）。
///
/// ## 兜底
/// 解码失败 / 压完反而更大 / 抛异常，**一律回原图**，绝不因为压缩失败发不出图
/// ——图片发不出去比图片大得多更糟。
///
/// ## 为什么走 isolate
/// 解码 + 重编码一张高清照片在 Dart 侧要几百毫秒，跑在 UI isolate 上会明显掉帧
/// （与 `CastImageEditor` 同一理由）。全部丢进 [compute]，页面上只是缩略图转着圈。
class AiImageCompress {
  AiImageCompress._();

  /// 目标体积：100KB（2026-07-27 用户指定）。
  static const int targetBytes = 100 * 1024;

  static const int _maxLongEdge = 1600;
  static const List<int> _qualitySteps = [80, 62, 48, 36, 26];
  static const int _qualityFloorIndex = 2;

  /// 把 [path] 压到 [target] 字节以内，返回**可用于上传的路径**（外加像素尺寸，见
  /// [AiCompressedImage.width]）。
  ///
  /// 达不到目标时返回「已压到最小的那一版」；真的一点都压不动（或压完更大）才返回原路径。
  /// 调用方无需判断成败，直接拿 [AiCompressedImage.path] 上传。
  static Future<AiCompressedImage> toTarget(
    String path, {
    int target = targetBytes,
  }) async {
    final file = File(path);
    // 给初值而不是靠 try 里赋值 + catch 里 return 去满足「确定已赋值」——读起来省心，代价可忽略
    var sourceBytes = 0;
    var bytes = Uint8List(0);
    try {
      sourceBytes = await file.length();
      // 本来就够小：不动它，别白丢一道质（这条路径不解码，所以拿不到尺寸）
      if (sourceBytes <= target) {
        return AiCompressedImage(path: path);
      }
      bytes = await file.readAsBytes();
    } catch (error) {
      debugPrint('[BoltStar] 待发图读取失败，用原图上传：$error');
      return AiCompressedImage(path: path);
    }

    _CompressResult? best;
    try {
      best = await compute(
        _compressToTarget,
        _CompressRequest(bytes: bytes, target: target),
      );
    } catch (error) {
      debugPrint('[BoltStar] 待发图压缩失败，用原图上传：$error');
      return AiCompressedImage(path: path);
    }
    // 压完反而更大 / 压不动：用原图，别赌（尺寸还是可以带出来，占位比例用得上）
    if (best == null || best.bytes.length >= sourceBytes) {
      debugPrint('[BoltStar] 待发图未压缩（原图 ${(sourceBytes / 1024).round()}KB）');
      return AiCompressedImage(
        path: path,
        width: best?.width ?? 0,
        height: best?.height ?? 0,
      );
    }

    try {
      final name = 'ai_upload_${DateTime.now().microsecondsSinceEpoch}.jpg';
      final out = File('${Directory.systemTemp.path}/$name');
      await out.writeAsBytes(best.bytes, flush: true);
      debugPrint(
        '[BoltStar] 待发图压缩：${(sourceBytes / 1024).round()}KB → '
        '${(best.bytes.length / 1024).round()}KB '
        '(${best.width}×${best.height}, q=${best.quality})',
      );
      return AiCompressedImage(
        path: out.path,
        width: best.width,
        height: best.height,
      );
    } catch (error) {
      debugPrint('[BoltStar] 压缩结果落盘失败，用原图上传：$error');
      return AiCompressedImage(path: path);
    }
  }
}

/// [AiImageCompress.toTarget] 的产物：要上传的文件 + 像素尺寸。
///
/// 尺寸是**顺手带出来的**（压缩必然要解码一次，白拿），用来给用户图片气泡预占高宽
/// （见 `ai_chat_page` 的占位比例）。0 表示未知 —— 原图本来就够小时不解码，
/// 这时气泡退回默认比例、等图加载完再校正。
class AiCompressedImage {
  const AiCompressedImage({required this.path, this.width = 0, this.height = 0});

  final String path;
  final int width;
  final int height;
}

class _CompressRequest {
  const _CompressRequest({required this.bytes, required this.target});

  final Uint8List bytes;
  final int target;
}

class _CompressResult {
  const _CompressResult({
    required this.bytes,
    required this.width,
    required this.height,
    required this.quality,
  });

  final Uint8List bytes;
  final int width;
  final int height;
  final int quality;
}

/// isolate 入口：逐档压缩直到 ≤ target，返回**最小的那一版**（一档都没成功则 null）。
_CompressResult? _compressToTarget(_CompressRequest req) {
  final decoded = img.decodeImage(req.bytes);
  if (decoded == null) {
    return null;
  }

  var width = decoded.width;
  var height = decoded.height;
  final longEdge = width > height ? width : height;
  if (longEdge > AiImageCompress._maxLongEdge) {
    final ratio = AiImageCompress._maxLongEdge / longEdge;
    width = (width * ratio).round().clamp(1, decoded.width);
    height = (height * ratio).round().clamp(1, decoded.height);
  }

  _CompressResult? best;
  for (var i = 0; i < AiImageCompress._qualitySteps.length; i++) {
    final quality = AiImageCompress._qualitySteps[i];
    final sized = (width == decoded.width && height == decoded.height)
        ? decoded
        : img.copyResize(
            decoded,
            width: width,
            height: height,
            interpolation: img.Interpolation.average,
          );
    final encoded = Uint8List.fromList(img.encodeJpg(sized, quality: quality));
    if (best == null || encoded.length < best.bytes.length) {
      best = _CompressResult(
        bytes: encoded,
        width: sized.width,
        height: sized.height,
        quality: quality,
      );
    }
    if (encoded.length <= req.target) {
      break;
    }
    // 降质已到底还压不下来（多为高清照片 / 细节极多）→ 再砍一半分辨率继续试
    if (i >= AiImageCompress._qualityFloorIndex) {
      width = (width / 2).round().clamp(1, decoded.width);
      height = (height / 2).round().clamp(1, decoded.height);
    }
  }
  return best;
}
