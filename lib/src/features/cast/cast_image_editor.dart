import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;
import 'package:image/image.dart' as img;

/// 投屏预览页的**程序化**图片处理，统一导出 **JPEG** 临时文件。
///
/// 只负责两件不需要用户交互的事：
///   ① [coverCropToSize]：**未编辑**的图开始投屏时，按设备分辨率做 aspectFill 中心裁切 + 严格缩放；
///   ② [encodeRgbaToJpeg]：把预览页画布烘焙出的 RGBA 像素编码成 JPEG（`dart:ui` 的
///      `toByteData` 只出 png/rawRgba，JPEG 必须靠 `image` 包）。
///
/// **编辑后的出图不在这里**：2026-07-25 起预览页是常驻编辑层（竖/横取景 + 平移/缩放/旋转），
/// 点「开始投屏」时由 `cast_preview_page.dart` 的 `_bake` 用 `ui.Canvas` 按与小程序 canvas
/// **完全相同的绘制顺序**合成（含横向 270° 铁律），再调 [encodeRgbaToJpeg] 落文件。
/// 交互式裁剪器（image_cropper）与预览态旋转烘焙（旧 `rotate`）随该重构一并下线。
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

  /// 把预览页烘焙出的 **RGBA8888** 像素编码成 JPEG 临时文件，返回文件路径（失败返回 null）。
  ///
  /// [width]×[height] 恒为设备物理分辨率（竖向）——这是「上传图必须正好是设备像素」铁律的落点，
  /// 调用方（`cast_preview_page._bake`）已按取景框把画布尺寸定死，这里只做编码不改尺寸。
  static Future<String?> encodeRgbaToJpeg({
    required Uint8List rgba,
    required int width,
    required int height,
  }) async {
    final encoded = await compute(
      _encodeRgba,
      _RgbaRequest(rgba: rgba, width: width, height: height),
    );
    final result = await _write(encoded);
    return result?.path;
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

class _RgbaRequest {
  const _RgbaRequest({
    required this.rgba,
    required this.width,
    required this.height,
  });

  final Uint8List rgba;
  final int width;
  final int height;
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

/// RGBA8888 → JPEG。`numChannels: 4` 时 `image` 包默认通道序就是 RGBA，
/// 与 `dart:ui` 的 `ImageByteFormat.rawRgba` 一致，不需要额外换序。
_EncodedImage? _encodeRgba(_RgbaRequest req) {
  // Image.fromBytes 收的是整个 ByteBuffer：传进来的若是带偏移的视图，直接取 .buffer 会读到
  // 错误的起始位置（画面整幅错位）。非「从 0 开始且铺满」的一律先拷成独立缓冲区。
  final rgba = req.rgba;
  final source =
      (rgba.offsetInBytes == 0 && rgba.lengthInBytes == rgba.buffer.lengthInBytes)
      ? rgba
      : Uint8List.fromList(rgba);
  final image = img.Image.fromBytes(
    width: req.width,
    height: req.height,
    bytes: source.buffer,
    numChannels: 4,
  );
  final bytes = img.encodeJpg(image, quality: CastImageEditor.exportQuality);
  return _EncodedImage(bytes, req.width, req.height);
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
