import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';

/// 设备分享卡片封面（2026-11-04 同小程序 `utils/share-card.js`）：微信小程序卡片的封面不再用固定的设备图，
/// 改为画一张 5:4 的封面：暖白 → 浅蓝渐变底 + 右上橙光 / 左下蓝光；左上橙色浅底标签「设备共享邀请」；
/// 左边机型设备图（带淡橙投影），右边设备名（粗体，最多两行省略）+「WiFi版 · 尺寸」；底部橙色渐变按钮「点击接受邀请」。
/// 配色与页面一致（橙 #ff9140 → #ff6a20，正文 #2a2d32，次要 #8b9098）。
///
/// 逻辑尺寸 500×400，导出 ×[_scale]。微信 App 分享小程序卡片的 hdImageData 上限 128KB：
/// 画不出来（设备图解码失败只画文字；绘制 / 编码异常）或 PNG 超限时返回 null，调用方退回原来的设备图，不发截图。
abstract final class WifiShareCard {
  static const double width = 500;
  static const double height = 400;
  static const double _scale = 1.2;
  static const int _maxBytes = 127 * 1024;

  static const double _pad = 36;
  static const double _iconY = 104;
  static const double _iconSize = 152;
  static const double _textX = _pad + _iconSize + 26;
  static const double _textWidth = width - _textX - _pad;

  static const Color _orange = Color(0xFFFF6A20);
  static const Color _orangeLight = Color(0xFFFF9140);
  static const Color _text = Color(0xFF2A2D32);
  static const Color _sub = Color(0xFF8B9098);

  /// [tag]「设备共享邀请」、[button]「点击接受邀请」、[spec]「WiFi版 · 尺寸」由调用方按语种给。
  static Future<Uint8List?> render({
    required String name,
    required String spec,
    required String tag,
    required String button,
    required String thumbAsset,
  }) async {
    try {
      ui.Image? thumb;
      try {
        final data = await rootBundle.load(thumbAsset);
        final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
        thumb = (await codec.getNextFrame()).image;
      } catch (error) {
        debugPrint('[分享卡片] 设备图解码失败，只画文字 $thumbAsset $error');
      }
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.scale(_scale);
      _draw(canvas, name: name.trim().isNotEmpty ? name.trim() : '--', spec: spec, tag: tag, button: button, thumb: thumb);
      final image = await recorder.endRecording().toImage((width * _scale).round(), (height * _scale).round());
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) {
        return null;
      }
      final png = bytes.buffer.asUint8List();
      if (png.length > _maxBytes) {
        debugPrint('[分享卡片] 封面 ${png.length} 字节超过微信上限，改用设备图');
        return null;
      }
      return png;
    } catch (error) {
      debugPrint('[分享卡片] 生成失败，改用设备图 $error');
      return null;
    }
  }

  static void _glow(Canvas canvas, Offset center, double radius, Color color) {
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, width, height),
      Paint()..shader = ui.Gradient.radial(center, radius, [color, color.withValues(alpha: 0)]),
    );
  }

  static TextPainter _paragraph(String text, double size, Color color, {bool bold = false, int maxLines = 1, TextAlign align = TextAlign.left}) {
    return TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: color, fontSize: size, fontWeight: bold ? FontWeight.w700 : FontWeight.w400, height: 1.3),
      ),
      textDirection: TextDirection.ltr,
      textAlign: align,
      maxLines: maxLines,
      ellipsis: '…',
    );
  }

  static void _draw(
    Canvas canvas, {
    required String name,
    required String spec,
    required String tag,
    required String button,
    ui.Image? thumb,
  }) {
    // 底：暖白 → 浅蓝，右上一团橙色光、左下一团蓝色光
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, width, height),
      Paint()
        ..shader = ui.Gradient.linear(Offset.zero, const Offset(width, height), const [Color(0xFFFFF6EE), Color(0xFFE8F2FF)]),
    );
    _glow(canvas, const Offset(width - 30, 20), 240, const Color(0x3DFF9140));
    _glow(canvas, const Offset(0, height), 220, const Color(0x296EA5FF));

    // 左上标签
    final tagText = _paragraph(tag, 20, _orange, bold: true)..layout();
    final tagRect = RRect.fromRectAndRadius(Rect.fromLTWH(_pad, 36, tagText.width + 36, 40), const Radius.circular(20));
    canvas.drawRRect(tagRect, Paint()..color = const Color(0x1FFF6A20));
    tagText.paint(canvas, Offset(_pad + 18, 36 + (40 - tagText.height) / 2));

    // 设备图，下方一层淡橙色投影
    if (thumb != null) {
      const iconRect = Rect.fromLTWH(_pad, _iconY, _iconSize, _iconSize);
      canvas.drawRRect(
        RRect.fromRectAndRadius(iconRect.shift(const Offset(0, 10)).deflate(10), const Radius.circular(24)),
        Paint()
          ..color = const Color(0x38FF6A20)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14),
      );
      paintImage(canvas: canvas, rect: iconRect, image: thumb, fit: BoxFit.contain, filterQuality: FilterQuality.medium);
    }

    // 设备名（最多两行）+ 规格，整体与设备图垂直居中
    final nameText = _paragraph(name, 38, _text, bold: true, maxLines: 2)..layout(maxWidth: _textWidth);
    final specText = _paragraph(spec, 24, _sub)..layout(maxWidth: _textWidth);
    const gap = 14.0;
    final blockHeight = nameText.height + gap + specText.height;
    final top = _iconY + _iconSize / 2 - blockHeight / 2;
    nameText.paint(canvas, Offset(_textX, top));
    specText.paint(canvas, Offset(_textX, top + nameText.height + gap));

    // 底部按钮
    const buttonRect = Rect.fromLTWH(_pad, 304, width - _pad * 2, 64);
    canvas.drawRRect(
      RRect.fromRectAndRadius(buttonRect, const Radius.circular(32)),
      Paint()..shader = ui.Gradient.linear(buttonRect.topCenter, buttonRect.bottomCenter, const [_orangeLight, _orange]),
    );
    final buttonText = _paragraph(button, 28, const Color(0xFFFFFFFF), bold: true, align: TextAlign.center)
      ..layout(minWidth: buttonRect.width, maxWidth: buttonRect.width);
    buttonText.paint(canvas, Offset(buttonRect.left, buttonRect.top + (buttonRect.height - buttonText.height) / 2));
  }
}
