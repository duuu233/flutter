import 'dart:math' as math;

import 'package:flutter/material.dart';

/// WiFi 配网三页用到的小程序图标，1:1 复刻小程序 `assets/images/` 下同名 SVG：
///   · [WifiProvisionArt]   ← `wifi-provision-art.svg`（600×240，手机 → 相框 → 云）
///   · [WifiSwitchGlyph]    ← `wifi-switch.svg`（48×48，WiFi 名称后的切换图标）
///   · [WifiEyeGlyph]       ← `eye-open.svg` / `eye-closed.svg`（48×48，密码明文 / 密文）
///   · [WifiBadgeGlyph]     ← `badge-wifi.svg`（24×24，WiFi 列表每行前的图标）
///
/// 本仓没有 SVG 依赖，按工具链基线也不为几枚图标引入 flutter_svg，所以按 SVG 里的同一组坐标绘制
/// （同 `device_details_page.dart` 的 `_ScreenSizePainter` 做法）；坐标直接照抄 SVG，改图回小程序那份对。
class WifiProvisionArt extends StatelessWidget {
  const WifiProvisionArt({super.key});

  @override
  Widget build(BuildContext context) {
    // 小程序 600rpx × 240rpx，即 300 × 120 逻辑像素；窄屏按宽度等比缩小
    return const Center(
      child: SizedBox(
        width: 300,
        child: AspectRatio(
          aspectRatio: 600 / 240,
          child: CustomPaint(painter: _ProvisionArtPainter()),
        ),
      ),
    );
  }
}

class WifiSwitchGlyph extends StatelessWidget {
  const WifiSwitchGlyph({super.key, this.size = 22});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(width: size, height: size, child: const CustomPaint(painter: _SwitchPainter()));
  }
}

class WifiEyeGlyph extends StatelessWidget {
  const WifiEyeGlyph({super.key, required this.open, this.size = 20});

  /// true 睁眼（当前明文）/ false 闭眼（当前 ****），同小程序 showPassword 的取图口径。
  final bool open;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(width: size, height: size, child: CustomPaint(painter: _EyePainter(open)));
  }
}

class WifiBadgeGlyph extends StatelessWidget {
  const WifiBadgeGlyph({super.key, this.size = 20});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(width: size, height: size, child: const CustomPaint(painter: _BadgePainter()));
  }
}

/// 视图盒等比缩放到绘制区并居中（相当于 SVG 的 aspectFit），之后坐标按视图盒写。
void _fitViewBox(Canvas canvas, Size size, double width, double height) {
  final scale = math.min(size.width / width, size.height / height);
  canvas.translate((size.width - width * scale) / 2, (size.height - height * scale) / 2);
  canvas.scale(scale);
}

Paint _stroke(Color color, double width) => Paint()
  ..color = color
  ..style = PaintingStyle.stroke
  ..strokeWidth = width
  ..strokeCap = StrokeCap.round
  ..strokeJoin = StrokeJoin.round
  ..isAntiAlias = true;

class _ProvisionArtPainter extends CustomPainter {
  const _ProvisionArtPainter();

  static const Color _line = Color(0xFFFFB48A);
  static const Color _white = Colors.white;

  /// `#halo`：径向渐变 #FF7A3A 18% → 0，半径即圆半径。
  void _halo(Canvas canvas, Offset center, double radius) {
    final rect = Rect.fromCircle(center: center, radius: radius);
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0x2EFF7A3A), Color(0x00FF7A3A)],
        ).createShader(rect),
    );
  }

  /// `#orb`：线性渐变左上 #FF9A5A → 右下 #FF5A1E（objectBoundingBox 0,0 → 1,1）。
  void _orb(Canvas canvas, Offset center, double radius) {
    final rect = Rect.fromCircle(center: center, radius: radius);
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFF9A5A), Color(0xFFFF5A1E)],
        ).createShader(rect),
    );
  }

  /// 点线：stroke-dasharray="2 14" + 圆头，即每 16 一个长 2 的圆头短划。
  void _dots(Canvas canvas, double from, double to, double y) {
    final paint = _stroke(_line, 5);
    for (var x = from; x <= to; x += 16) {
      final end = x + 2 > to ? to : x + 2;
      if (end > x) {
        canvas.drawLine(Offset(x, y), Offset(end, y), paint);
      } else {
        canvas.drawCircle(Offset(x, y), 2.5, Paint()..color = _line);
      }
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    _fitViewBox(canvas, size, 600, 240);

    // 连线：手机 → 设备（蓝牙下发配置）→ 云（设备经 WiFi 上云）
    _dots(canvas, 152, 232, 120);
    _dots(canvas, 368, 448, 120);
    final arrow = _stroke(_line, 5);
    canvas.drawPath(Path()..moveTo(220, 110)..lineTo(232, 120)..lineTo(220, 130), arrow);
    canvas.drawPath(Path()..moveTo(436, 110)..lineTo(448, 120)..lineTo(436, 130), arrow);

    // 手机
    _halo(canvas, const Offset(92, 120), 88);
    _orb(canvas, const Offset(92, 120), 56);
    canvas.drawRRect(
      RRect.fromRectAndRadius(const Rect.fromLTWH(74, 92, 36, 58), const Radius.circular(7)),
      _stroke(_white, 5),
    );
    canvas.drawLine(const Offset(86, 140), const Offset(98, 140), _stroke(_white, 5));

    // 相框设备（主角，稍大）
    _halo(canvas, const Offset(300, 120), 108);
    _orb(canvas, const Offset(300, 120), 66);
    canvas.drawRRect(
      RRect.fromRectAndRadius(const Rect.fromLTWH(268, 94, 64, 52), const Radius.circular(7)),
      _stroke(_white, 5),
    );
    canvas.drawPath(
      Path()
        ..moveTo(276, 136)
        ..lineTo(292, 119)
        ..lineTo(304, 130)
        ..lineTo(313, 122)
        ..lineTo(324, 136),
      _stroke(_white, 4.5),
    );
    canvas.drawCircle(const Offset(314, 108), 5, Paint()..color = _white);
    canvas.drawLine(const Offset(290, 158), const Offset(310, 158), _stroke(_white, 5));

    // 云
    _halo(canvas, const Offset(508, 120), 88);
    _orb(canvas, const Offset(508, 120), 56);
    canvas.drawPath(
      Path()
        ..moveTo(486, 139)
        ..lineTo(531, 139)
        ..cubicTo(539.3, 139, 546, 132.3, 546, 124)
        ..cubicTo(546, 116.4, 540.4, 110.1, 533.1, 109.1)
        ..cubicTo(531, 99.8, 522.7, 93, 512.8, 93)
        ..cubicTo(503.6, 93, 495.8, 98.9, 493.1, 107.2)
        ..cubicTo(484.5, 107.9, 478, 115, 478, 123.6)
        ..cubicTo(478, 131, 482, 137.4, 486, 139)
        ..close(),
      _stroke(_white, 5),
    );
    canvas.drawPath(
      Path()
        ..moveTo(500, 125.5)
        ..cubicTo(504.9, 120.8, 512.6, 120.8, 517.5, 125.5),
      _stroke(_white, 4.5),
    );
    canvas.drawCircle(const Offset(508.8, 131.5), 3.4, Paint()..color = _white);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _SwitchPainter extends CustomPainter {
  const _SwitchPainter();

  @override
  void paint(Canvas canvas, Size size) {
    _fitViewBox(canvas, size, 48, 48);
    canvas.drawPath(
      Path()
        ..moveTo(10, 17)
        ..lineTo(36, 17)
        ..moveTo(36, 17)
        ..lineTo(29, 10)
        ..moveTo(38, 31)
        ..lineTo(12, 31)
        ..moveTo(12, 31)
        ..lineTo(19, 38),
      _stroke(const Color(0xFFFF6A20), 3.5),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _EyePainter extends CustomPainter {
  const _EyePainter(this.open);

  final bool open;

  @override
  void paint(Canvas canvas, Size size) {
    _fitViewBox(canvas, size, 48, 48);
    final paint = _stroke(const Color(0xFF8B9098), 3.2);
    if (open) {
      canvas.drawPath(
        Path()
          ..moveTo(4, 24)
          ..cubicTo(8.5, 15.5, 15.6, 11, 24, 11)
          ..cubicTo(32.4, 11, 39.5, 15.5, 44, 24)
          ..cubicTo(39.5, 32.5, 32.4, 37, 24, 37)
          ..cubicTo(15.6, 37, 8.5, 32.5, 4, 24)
          ..close(),
        paint,
      );
      canvas.drawCircle(const Offset(24, 24), 6.5, paint);
      return;
    }
    canvas.drawPath(
      Path()
        ..moveTo(5, 19)
        ..cubicTo(9.5, 26, 16, 30, 24, 30)
        ..cubicTo(32, 30, 38.5, 26, 43, 19),
      paint,
    );
    canvas.drawPath(
      Path()
        ..moveTo(13.5, 26.5)
        ..lineTo(10, 32)
        ..moveTo(24, 30)
        ..lineTo(24, 36.5)
        ..moveTo(34.5, 26.5)
        ..lineTo(38, 32),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _EyePainter oldDelegate) => oldDelegate.open != open;
}

class _BadgePainter extends CustomPainter {
  const _BadgePainter();

  static const Color _green = Color(0xFF0E9F87);

  @override
  void paint(Canvas canvas, Size size) {
    _fitViewBox(canvas, size, 24, 24);
    final paint = _stroke(_green, 2.4);
    canvas.drawPath(Path()..moveTo(2.5, 9.2)..cubicTo(7.9, 4.4, 16.1, 4.4, 21.5, 9.2), paint);
    canvas.drawPath(Path()..moveTo(6, 12.9)..cubicTo(9.4, 10, 14.6, 10, 18, 12.9), paint);
    canvas.drawPath(Path()..moveTo(9.4, 16.5)..cubicTo(10.9, 15.3, 13.1, 15.3, 14.6, 16.5), paint);
    canvas.drawCircle(const Offset(12, 19.8), 1.7, Paint()..color = _green);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
