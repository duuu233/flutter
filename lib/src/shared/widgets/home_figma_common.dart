import 'package:flutter/material.dart';

import 'package:BoltStar/src/shared/widgets/figma_common.dart';

import '../l10n/app_l10n.dart';

/// Figma 首页 / 绑定设备流程的公共组件库（非页面）：投屏方式卡片、蓝牙雷达、
/// 绑定设备卡片等通用控件，被首页及绑定相关页面复用。
///
/// ⚠️ 2026-08-21 删掉了 `FigmaHomeBackground`：它是**全项目没人用**的死类，
/// 而且引用的 `home_background.png` / `home_wave_overlay.png` **两张图从来就不在仓库里**
/// （靠 errorBuilder 兜着才没炸）。页面背景统一走 `FigmaScreenBackground`（bg02.jpg）。
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
    this.fontWeight = FontWeight.w500,
  });

  final String label;
  final Widget? icon;
  final VoidCallback? onPressed;
  final double height;
  final double fontSize;
  final FontWeight fontWeight;

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
            fontWeight: fontWeight,
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
        // 撑满父容器（页面自带边距）：写死 327 在 ≤320dp 宽屏/分屏会横向溢出。
        width: double.infinity,
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

class FigmaBindDeviceCard extends StatelessWidget {
  const FigmaBindDeviceCard({
    super.key,
    required this.name,
    this.subtitle = '',
    this.deviceId = '',
    this.selected = false,
    this.onTap,
    this.onLongPress,
  });

  final String name;

  /// 副标题：尺寸 · 电量XX% · 信号XX（对齐小程序 `nearby-sub`）。空串则不显示。
  final String subtitle;

  /// 设备ID（广播 Device_ID 归一化后的 8 位十六进制）。空串则不显示。
  /// 为什么要单独一行而不是拼进 subtitle：同型号设备默认名相同（默认名=产品广播名），
  /// 绑定前这是唯一能区分两台的标识；而 subtitle 在英文下本就已被 ellipsis 截断
  /// （"5.89in · Battery 88% · Signal Excellent" 已超出可用宽度），拼进去等于直接被截没。
  final String deviceId;
  final bool selected;
  final VoidCallback? onTap;

  /// 长按：进入该设备的硬件联调调试台（对齐小程序 `bindlongpress="openDebug"`）。
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        // 撑满父容器（页面自带边距）：写死 327 在 ≤320dp 宽屏/分屏会横向溢出。
        width: double.infinity,
        // 64 → 82：加了「设备ID」第三行后，内容高度 = 名称 19.2 + 3 + 副标题 14.4 + 3 + ID 14.4
        // ≈ 54px，而 64 减去上下各 8 的 padding 只剩 48px，会稳定触发 RenderFlex 溢出黄条。
        // 82 - 16 = 66px 可用，留出余量给字体缩放。
        height: 82,
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
            // 设备图统一用首页那张 home-icon02（2026-07-20 补齐本页：首页/设备列表/设备详情
            // 已在 2026-07-19 统一，搜索设备列表是漏掉的最后一处）。
            // 该图四角 alpha=0 自带圆角，所以**不加底色容器**——加了会在四角露出色晕。
            // 原实现更离谱：不是资源图而是 Material 的 videocam 字形，还按列表下标染成橙/绿/蓝，
            // 同一列表里几台设备图标颜色各不相同，与首页毫无关系。
            Image.asset(
              'assets/images/home-device-thumb.png',
              width: 48,
              height: 48,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) {
                return const Icon(
                  Icons.photo_library_outlined,
                  color: Color(0xFFEB5F1B),
                  size: 26,
                );
              },
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: FigmaHomeTextStyles.deviceName,
                  ),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: FigmaHomeTextStyles.cardSubtitle,
                    ),
                  ],
                  if (deviceId.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      '${AppL10n.of(context).devDeviceId} $deviceId',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: FigmaHomeTextStyles.cardSubtitle,
                    ),
                  ],
                ],
              ),
            ),
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
