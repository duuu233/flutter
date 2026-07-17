import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;
import 'package:image/image.dart' as img;

/// 投屏预览页的**程序化**图片处理，统一导出 **JPEG** 临时文件。
///
/// 只负责两件不需要用户交互的事：
///   ① [rotate]：工具栏「旋转」按钮的即时 90° 旋转；
///   ② [coverCropToSize]：开始投屏时按设备分辨率做的 aspectFill 中心裁切 + 严格缩放。
///
/// **交互式裁剪不在这里** —— 那个交给原生裁剪器（`image_cropper`：Android=uCrop / iOS=TOCropViewController）。
/// 小程序是用 canvas + touch 事件手搓的裁剪框，那是被微信沙箱逼的；App 没必要照抄这个实现方式。
///
/// ## 为什么必须导出 JPEG
/// 小程序 2026-07-13 专门把导出格式从 png 改成了 jpg：png 是同画质 jpg 的 5~10 倍体积
/// （长边 2000 的照片常到 5MB+），而这个导出文件正是投屏要上传给后端转码的源图——
/// 真机 trace 里 uploadConvertMs 高达 5.7s，几乎全耗在传这个大 png 上。
/// 后端拿到后还要缩到设备分辨率（480×720 / 680×960）并量化成六色，q=92 对最终成像完全无损。
///
/// Flutter 侧 `dart:ui` 的 `toByteData` **只支持 png**，所以必须靠 `image` 包做 JPEG 编码。
///
/// ## 为什么全部丢进 isolate
/// 解码 + 重编码一张 1920px 的照片在 Dart 侧要几百毫秒，跑在 UI isolate 上会明显掉帧。
/// 全部走 [compute]，页面只显示「处理中」遮罩。
class CastImageEditor {
  CastImageEditor._();

  /// 导出 JPEG 质量（对齐小程序 EXPORT_QUALITY = 0.92）。
  static const int exportQuality = 92;

  /// 输出长边限幅（对齐小程序 MAX_EDGE）：2000px 足够覆盖任何相框分辨率，又不至于画布过大。
  static const int maxEdge = 2000;

  /// 把 [degrees]（90 / 180 / 270）真正绘制进图片并导出新文件。
  /// [degrees] 为 0 时原样返回。对齐小程序 `bakeRotation`。
  static Future<CastEditResult?> rotate({
    required String path,
    required int degrees,
  }) async {
    final angle = ((degrees % 360) + 360) % 360;
    if (angle == 0) {
      return null;
    }
    final bytes = await File(path).readAsBytes();
    final result = await compute(
      _rotate,
      _RotateRequest(bytes: bytes, degrees: angle),
    );
    return _write(result);
  }

  /// 按设备分辨率 [width]×[height] 做 **aspectFill 中心裁切 + 严格缩放**并导出新文件。
  ///
  /// 对齐小程序 `coverCropOne` / canvas 裁剪导出：小程序的导出画布**就是设备像素尺寸**
  /// （3.7寸 480×720 / 5.89寸 680×960），传给后端转码的源图恒为设备分辨率。
  /// 之前 App 只裁到设备**比例**、分辨率保持源图（长边限 2000）——传给后端的图尺寸
  /// 与小程序不一致（2026-07-17 修复）。现在：先中心裁切到设备比例，再无论大小
  /// **严格缩放到 width×height**（小图放大，与 canvas 固定尺寸绘制一致），
  /// 后端按同尺寸转码零缩放、预览所见即设备所得，上传体积也更小更快。
  static Future<CastEditResult?> coverCropToSize({
    required String path,
    required int width,
    required int height,
  }) async {
    final bytes = await File(path).readAsBytes();
    final result = await compute(
      _coverCrop,
      _CoverCropRequest(bytes: bytes, width: width, height: height),
    );
    return _write(result);
  }

  /// 把 isolate 产出的 JPEG 字节落成临时文件。
  static Future<CastEditResult?> _write(_EncodedImage? encoded) async {
    if (encoded == null) {
      return null;
    }
    final name = 'cast_edit_${DateTime.now().microsecondsSinceEpoch}.jpg';
    final file = File('${Directory.systemTemp.path}/$name');
    await file.writeAsBytes(encoded.bytes, flush: true);
    return CastEditResult(
      path: file.path,
      width: encoded.width,
      height: encoded.height,
    );
  }
}

/// 一次编辑的产物：导出的临时文件 + 它的真实像素尺寸。
class CastEditResult {
  const CastEditResult({
    required this.path,
    required this.width,
    required this.height,
  });

  final String path;
  final int width;
  final int height;
}

// ── 以下都在 isolate 里跑（compute 的入口必须是顶层/静态函数，参数必须可跨 isolate 传递）──

class _EncodedImage {
  const _EncodedImage(this.bytes, this.width, this.height);

  final Uint8List bytes;
  final int width;
  final int height;
}

class _RotateRequest {
  const _RotateRequest({required this.bytes, required this.degrees});

  final Uint8List bytes;
  final int degrees;
}

class _CoverCropRequest {
  const _CoverCropRequest({
    required this.bytes,
    required this.width,
    required this.height,
  });

  final Uint8List bytes;
  final int width;
  final int height;
}

_EncodedImage? _rotate(_RotateRequest req) {
  final decoded = img.decodeImage(req.bytes);
  if (decoded == null) {
    return null;
  }
  // copyRotate 是顺时针角度，与小程序 canvas 的 ctx.rotate(正角=顺时针) 一致。
  final rotated = img.copyRotate(decoded, angle: req.degrees);
  return _encode(rotated);
}

_EncodedImage? _coverCrop(_CoverCropRequest req) {
  final decoded = img.decodeImage(req.bytes);
  if (decoded == null) {
    return null;
  }
  final ratio = req.width / req.height;
  final srcRatio = decoded.width / decoded.height;
  int w;
  int h;
  if (srcRatio > ratio) {
    // 原图更宽：以高为准，左右各裁掉一些。
    h = decoded.height;
    w = (h * ratio).round();
  } else {
    // 原图更高：以宽为准，上下各裁掉一些。
    w = decoded.width;
    h = (w / ratio).round();
  }
  w = w.clamp(1, decoded.width);
  h = h.clamp(1, decoded.height);
  final x = ((decoded.width - w) / 2).round();
  final y = ((decoded.height - h) / 2).round();
  final cropped = img.copyCrop(decoded, x: x, y: y, width: w, height: h);
  // 严格缩放到设备像素尺寸（对齐小程序：canvas 画布 = 设备分辨率，小图同样被
  // 绘制放大到画布尺寸）。cubic 插值兼顾缩小与放大的画质。
  final sized = (cropped.width == req.width && cropped.height == req.height)
      ? cropped
      : img.copyResize(
          cropped,
          width: req.width,
          height: req.height,
          interpolation: img.Interpolation.cubic,
        );
  final bytes = img.encodeJpg(sized, quality: CastImageEditor.exportQuality);
  return _EncodedImage(bytes, sized.width, sized.height);
}

/// 长边限幅到 [CastImageEditor.maxEdge] 后编码成 JPEG。
_EncodedImage _encode(img.Image source) {
  var out = source;
  final longEdge = out.width > out.height ? out.width : out.height;
  if (longEdge > CastImageEditor.maxEdge) {
    final k = CastImageEditor.maxEdge / longEdge;
    out = img.copyResize(
      out,
      width: (out.width * k).round().clamp(1, CastImageEditor.maxEdge),
      height: (out.height * k).round().clamp(1, CastImageEditor.maxEdge),
    );
  }
  final bytes = img.encodeJpg(out, quality: CastImageEditor.exportQuality);
  return _EncodedImage(bytes, out.width, out.height);
}
