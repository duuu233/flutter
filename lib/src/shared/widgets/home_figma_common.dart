import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:BoltStar/src/shared/widgets/figma_common.dart';

const double figmaHomeDesignWidth = 375;
const double figmaHomeDesignHeight = 812;

/// Figma 首页 / 绑定设备流程的公共组件库（非页面）：首页外框、背景、投屏方式
/// 卡片、蓝牙雷达、绑定设备卡片等，被首页及绑定相关页面复用。
class FigmaHomePhoneFrame extends StatelessWidget {
  const FigmaHomePhoneFrame({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.white,
      ),
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        backgroundColor: Colors.white,
        body: LayoutBuilder(
          builder: (context, constraints) {
            final scale = math.max(
              constraints.maxWidth / figmaHomeDesignWidth,
              constraints.maxHeight / figmaHomeDesignHeight,
            );

            return ClipRect(
              child: SizedBox.expand(
                child: OverflowBox(
                  maxWidth: figmaHomeDesignWidth * scale,
                  maxHeight: figmaHomeDesignHeight * scale,
                  child: Transform.scale(
                    scale: scale,
                    child: SizedBox(
                      width: figmaHomeDesignWidth,
                      height: figmaHomeDesignHeight,
                      child: child,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class FigmaHomeBackground extends StatelessWidget {
  const FigmaHomeBackground({super.key});

  @override
  Widget build(BuildContext context) {
    return const Stack(
      children: [
        Positioned.fill(child: ColoredBox(color: Color(0xFFF5F9FF))),
        Positioned(
          left: 0,
          top: 0,
          width: 376,
          height: 812,
          child: FigmaHomeAssetImage(
            assetPath: 'assets/images/home_background.png',
            fallback: FigmaSoftBackground(),
          ),
        ),
        Positioned(
          left: 0,
          top: 0,
          width: 375,
          height: 812,
          child: FigmaHomeAssetImage(
            assetPath: 'assets/images/home_wave_overlay.png',
            fallback: SizedBox.shrink(),
          ),
        ),
      ],
    );
  }
}

class FigmaHomeAssetImage extends StatelessWidget {
  const FigmaHomeAssetImage({
    super.key,
    required this.assetPath,
    required this.fallback,
    this.fit = BoxFit.cover,
  });

  final String assetPath;
  final Widget fallback;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      assetPath,
      fit: fit,
      errorBuilder: (context, error, stackTrace) => fallback,
    );
  }
}

class FigmaSoftBackground extends StatelessWidget {
  const FigmaSoftBackground({super.key});

  @override
  Widget build(BuildContext context) {
    return const CustomPaint(painter: FigmaSoftBackgroundPainter());
  }
}

class FigmaSoftBackgroundPainter extends CustomPainter {
  const FigmaSoftBackgroundPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFEAF4FF), Color(0xFFF8FBFF), Color(0xFFFFF6F0)],
          stops: [0, 0.58, 1],
        ).createShader(rect),
    );

    final haze = Paint()
      ..color = Colors.white.withValues(alpha: 0.44)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 20);
    canvas.drawCircle(const Offset(118, 0), 122, haze);
    canvas.drawCircle(const Offset(58, 277), 176, haze);

    canvas.drawCircle(
      const Offset(366, 184),
      126,
      Paint()
        ..shader =
            RadialGradient(
              colors: [
                const Color(0xFFFFC39A).withValues(alpha: 0.62),
                const Color(0x00FFC39A),
              ],
            ).createShader(
              Rect.fromCircle(center: const Offset(366, 184), radius: 126),
            ),
    );

    final curvePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.62)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1;
    canvas.drawArc(
      const Rect.fromLTWH(-86, -206, 338, 338),
      0.08,
      2.12,
      false,
      curvePaint,
    );
    canvas.drawArc(
      const Rect.fromLTWH(-132, 112, 424, 222),
      3.66,
      1.72,
      false,
      curvePaint,
    );
    canvas.drawArc(
      const Rect.fromLTWH(115, 703, 372, 268),
      3.58,
      1.8,
      false,
      curvePaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class FigmaHomePrimaryButton extends StatelessWidget {
  const FigmaHomePrimaryButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.height = 56,
    this.fontSize = 18,
  });

  final String label;
  final Widget? icon;
  final VoidCallback? onPressed;
  final double height;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final content = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[icon!, const SizedBox(width: 14)],
        Text(
          label,
          style: TextStyle(
            color: Colors.white,
            fontSize: fontSize,
            fontWeight: FontWeight.w500,
            height: 1.2,
            letterSpacing: label.length <= 4 ? 2 : 1,
          ),
        ),
      ],
    );

    return SizedBox(
      height: height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(height / 2),
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFFF7D36), Color(0xFFFF621F)],
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFEB5F1B).withValues(alpha: 0.26),
              blurRadius: 12,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(height / 2),
          child: InkWell(
            borderRadius: BorderRadius.circular(height / 2),
            onTap: onPressed,
            child: Center(child: content),
          ),
        ),
      ),
    );
  }
}

class FigmaHomeBottomNav extends StatelessWidget {
  const FigmaHomeBottomNav({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 327,
      height: 56,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.74),
        borderRadius: BorderRadius.circular(35),
        border: Border.all(color: Colors.white.withValues(alpha: 0.55)),
      ),
      child: const Row(
        children: [
          Expanded(
            child: _BottomNavItem(
              icon: Icons.home_rounded,
              label: '首页',
              color: Color(0xFFFF6A24),
            ),
          ),
          Expanded(
            child: _BottomNavItem(
              icon: Icons.person_outline_rounded,
              label: '我的',
              color: Color(0xFF7A7D80),
            ),
          ),
        ],
      ),
    );
  }
}

class _BottomNavItem extends StatelessWidget {
  const _BottomNavItem({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, color: color, size: 28),
        const SizedBox(height: 1),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.w400,
            height: 1.2,
          ),
        ),
      ],
    );
  }
}

class FigmaCastMethodCard extends StatelessWidget {
  const FigmaCastMethodCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.assetPath,
    required this.accentColor,
    required this.backgroundColor,
    required this.fallbackIcon,
    this.onTap,
  });

  final String title;
  final String subtitle;
  final String assetPath;
  final Color accentColor;
  final Color backgroundColor;
  final Widget fallbackIcon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: 158,
        height: 155,
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withValues(alpha: 0.7)),
        ),
        child: Stack(
          children: [
            Positioned(
              left: 34,
              top: 22,
              width: 55,
              height: 55,
              child: FigmaHomeAssetImage(
                assetPath: assetPath,
                fallback: fallbackIcon,
                fit: BoxFit.contain,
              ),
            ),
            Positioned(
              left: 13,
              top: 100,
              child: Text(title, style: FigmaHomeTextStyles.cardTitle),
            ),
            Positioned(
              left: 13,
              top: 126,
              child: Text(subtitle, style: FigmaHomeTextStyles.cardSubtitle),
            ),
            Positioned(
              right: 25,
              bottom: 22,
              width: 36,
              height: 36,
              child: _RoundArrow(accentColor: accentColor),
            ),
          ],
        ),
      ),
    );
  }
}

class FigmaCastMethodRow extends StatelessWidget {
  const FigmaCastMethodRow({
    super.key,
    required this.title,
    required this.subtitle,
    required this.assetPath,
    required this.accentColor,
    required this.fallbackIcon,
    this.onTap,
  });

  final String title;
  final String subtitle;
  final String assetPath;
  final Color accentColor;
  final Widget fallbackIcon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: 327,
        height: 61,
        padding: const EdgeInsets.fromLTRB(12, 8, 18, 8),
        decoration: BoxDecoration(
          color: const Color(0xFFF5F6F8),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 48,
              height: 48,
              child: FigmaHomeAssetImage(
                assetPath: assetPath,
                fallback: fallbackIcon,
                fit: BoxFit.contain,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: FigmaHomeTextStyles.sheetOptionTitle),
                  const SizedBox(height: 2),
                  Text(subtitle, style: FigmaHomeTextStyles.sheetOptionBody),
                ],
              ),
            ),
            SizedBox(
              width: 36,
              height: 36,
              child: _RoundArrow(accentColor: accentColor),
            ),
          ],
        ),
      ),
    );
  }
}

class FigmaCameraFallbackIcon extends StatelessWidget {
  const FigmaCameraFallbackIcon({super.key, this.size = 55});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: const Color(0xFFFFF0E8),
        borderRadius: BorderRadius.circular(size * 0.28),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFF6A24).withValues(alpha: 0.18),
            blurRadius: 14,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: const Icon(
        Icons.photo_camera_rounded,
        color: Color(0xFFFF6A24),
        size: 30,
      ),
    );
  }
}

class FigmaAlbumFallbackIcon extends StatelessWidget {
  const FigmaAlbumFallbackIcon({super.key, this.size = 55});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: const Color(0xFFE7F2FF),
        borderRadius: BorderRadius.circular(size * 0.28),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF287BFF).withValues(alpha: 0.18),
            blurRadius: 14,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: const Icon(
        Icons.photo_library_rounded,
        color: Color(0xFF287BFF),
        size: 30,
      ),
    );
  }
}

class FigmaBluetoothRadar extends StatelessWidget {
  const FigmaBluetoothRadar({
    super.key,
    this.state = FigmaRadarState.searching,
    this.dimmed = false,
  });

  final FigmaRadarState state;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final badgeColor = state == FigmaRadarState.found
        ? const Color(0xFF25B34B)
        : const Color(0xFFE5483D);
    final showBadge = state != FigmaRadarState.searching;

    return Opacity(
      opacity: dimmed ? 0.56 : 1,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: const Size(270, 270),
            painter: const _RadarRingsPainter(),
          ),
          Container(
            width: 61,
            height: 61,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFFFF9759), Color(0xFFFF5E20)],
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFEB5F1B).withValues(alpha: 0.20),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: const Icon(
              Icons.bluetooth_rounded,
              color: Colors.white,
              size: 34,
            ),
          ),
          if (showBadge)
            Positioned(
              left: 151,
              top: 151,
              width: 25,
              height: 25,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 5,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Icon(
                  state == FigmaRadarState.found
                      ? Icons.check_rounded
                      : Icons.close_rounded,
                  color: badgeColor,
                  size: 20,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class FigmaBindDeviceTopBar extends StatelessWidget {
  const FigmaBindDeviceTopBar({super.key, this.onBack});

  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 375,
      height: 90,
      child: Stack(
        children: [
          const Positioned(
            left: 0,
            top: 0,
            width: 375,
            child: FigmaStatusBar(),
          ),
          Positioned(
            left: 22,
            top: 46,
            width: 34,
            height: 34,
            child: Material(
              color: Colors.white.withValues(alpha: 0.45),
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onBack ?? () => Navigator.maybePop(context),
                child: const Icon(
                  Icons.arrow_back_rounded,
                  color: Color(0xFF2A2B2B),
                  size: 20,
                ),
              ),
            ),
          ),
          const Positioned(
            left: 80,
            top: 51,
            width: 215,
            child: Center(
              child: Text('绑定设备', style: FigmaHomeTextStyles.navTitle),
            ),
          ),
        ],
      ),
    );
  }
}

class FigmaBindDeviceCard extends StatelessWidget {
  const FigmaBindDeviceCard({
    super.key,
    required this.name,
    required this.iconColor,
    required this.iconBackground,
    this.selected = false,
    this.onTap,
  });

  final String name;
  final Color iconColor;
  final Color iconBackground;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: 327,
        height: 64,
        padding: const EdgeInsets.fromLTRB(20, 8, 18, 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: selected ? 0.76 : 0.58),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? const Color(0xFFFF6A24) : Colors.white,
            width: selected ? 1 : 0.8,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: iconBackground,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(Icons.videocam_outlined, color: iconColor, size: 26),
            ),
            const SizedBox(width: 20),
            Expanded(child: Text(name, style: FigmaHomeTextStyles.deviceName)),
            Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: selected ? const Color(0xFFFF7D36) : Colors.transparent,
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected
                      ? const Color(0xFFFF7D36)
                      : const Color(0xFFB7BBC0),
                  width: selected ? 0 : 1,
                ),
              ),
              child: selected
                  ? const Icon(
                      Icons.check_rounded,
                      color: Colors.white,
                      size: 22,
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

class FigmaHomeTextStyles {
  const FigmaHomeTextStyles._();

  static const navTitle = TextStyle(
    color: Color(0xFF2A2B2B),
    fontSize: 17,
    fontWeight: FontWeight.w600,
    height: 1.2,
  );

  static const sectionTitle = TextStyle(
    color: Color(0xFF2A2B2B),
    fontSize: 17,
    fontWeight: FontWeight.w600,
    height: 1.2,
  );

  static const cardTitle = TextStyle(
    color: Color(0xFF2A2B2B),
    fontSize: 18,
    fontWeight: FontWeight.w600,
    height: 1.2,
  );

  static const cardSubtitle = TextStyle(
    color: Color(0x992A2B2B),
    fontSize: 12,
    fontWeight: FontWeight.w400,
    height: 1.2,
  );

  static const deviceName = TextStyle(
    color: Color(0xFF2A2B2B),
    fontSize: 16,
    fontWeight: FontWeight.w600,
    height: 1.2,
  );

  static const sheetTitle = TextStyle(
    color: Color(0xFF2A2B2B),
    fontSize: 22,
    fontWeight: FontWeight.w600,
    height: 1.2,
  );

  static const sheetOptionTitle = TextStyle(
    color: Color(0xFF2A2B2B),
    fontSize: 16,
    fontWeight: FontWeight.w600,
    height: 1.15,
  );

  static const sheetOptionBody = TextStyle(
    color: Color(0x992A2B2B),
    fontSize: 12,
    fontWeight: FontWeight.w400,
    height: 1.2,
  );
}

class _RoundArrow extends StatelessWidget {
  const _RoundArrow({required this.accentColor});

  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withValues(alpha: 0.95),
        boxShadow: [
          BoxShadow(
            color: accentColor.withValues(alpha: 0.12),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Icon(Icons.arrow_forward_rounded, color: accentColor, size: 22),
    );
  }
}

class _RadarRingsPainter extends CustomPainter {
  const _RadarRingsPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    for (final radius in <double>[64, 88, 112]) {
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = Colors.white.withValues(alpha: 0.76),
      );
    }
    canvas.drawCircle(
      center,
      60,
      Paint()..color = const Color(0xFFFFE8D9).withValues(alpha: 0.38),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
