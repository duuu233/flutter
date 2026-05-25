import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const double figmaDesignWidth = 375;
const double figmaDesignHeight = 812;

class FigmaPhoneFrame extends StatelessWidget {
  const FigmaPhoneFrame({super.key, required this.child});

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
        backgroundColor: const Color(0xFFF2F5FC),
        body: LayoutBuilder(
          builder: (context, constraints) {
            final scale = math.min(
              constraints.maxWidth / figmaDesignWidth,
              constraints.maxHeight / figmaDesignHeight,
            );

            return Center(
              child: Transform.scale(
                scale: scale,
                child: SizedBox(
                  width: figmaDesignWidth,
                  height: figmaDesignHeight,
                  child: child,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class FigmaPageBackground extends StatelessWidget {
  const FigmaPageBackground({super.key});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const Positioned.fill(child: ColoredBox(color: Color(0xFFF2F5FC))),
        const Positioned(
          left: 0,
          top: 0,
          width: 375,
          height: 401,
          child: FigmaImagePlaceholder(width: 375, height: 401),
        ),
        Positioned(
          left: 0,
          top: 401,
          width: 375,
          height: 411,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.94),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(28),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class FigmaImagePlaceholder extends StatelessWidget {
  const FigmaImagePlaceholder({
    super.key,
    required this.width,
    required this.height,
    this.borderRadius = 16,
    this.label = 'Image Placeholder',
  });

  final double width;
  final double height;
  final double borderRadius;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.grey[300],
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Color(0xFF737373),
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

class FigmaTopNavigation extends StatelessWidget {
  const FigmaTopNavigation({
    super.key,
    required this.title,
    this.onBack,
    this.showBack = true,
    this.trailing,
  });

  final String title;
  final VoidCallback? onBack;
  final bool showBack;
  final Widget? trailing;

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
          if (showBack)
            Positioned(
              left: 22,
              top: 46,
              width: 34,
              height: 34,
              child: FigmaRoundIconButton(
                icon: Icons.chevron_left_rounded,
                onTap: onBack ?? () => Navigator.maybePop(context),
              ),
            ),
          Positioned(
            left: 80,
            top: 47,
            width: 215,
            height: 24,
            child: Center(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: FigmaTextStyles.navigationTitle,
              ),
            ),
          ),
          if (trailing != null)
            Positioned(right: 18, top: 46, height: 34, child: trailing!),
        ],
      ),
    );
  }
}

class FigmaStatusBar extends StatelessWidget {
  const FigmaStatusBar({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: Stack(
        children: [
          const Positioned(
            left: 21,
            top: 12,
            width: 54,
            height: 21,
            child: Center(
              child: Text(
                '9:41',
                style: TextStyle(
                  color: Color(0xFF111111),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  height: 1,
                ),
              ),
            ),
          ),
          const Positioned(
            right: 14,
            top: 16,
            child: Row(
              children: [
                Icon(Icons.signal_cellular_alt_rounded, size: 16),
                SizedBox(width: 4),
                Icon(Icons.wifi_rounded, size: 16),
                SizedBox(width: 4),
                Icon(Icons.battery_full_rounded, size: 21),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class FigmaRoundIconButton extends StatelessWidget {
  const FigmaRoundIconButton({super.key, required this.icon, this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.78),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Icon(icon, color: const Color(0xFF2A2B2B), size: 22),
      ),
    );
  }
}

class FigmaPrimaryButton extends StatelessWidget {
  const FigmaPrimaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.height = 56,
  });

  final String label;
  final VoidCallback? onPressed;
  final double height;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return SizedBox(
      height: height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: enabled ? null : const Color(0xFFE2E2E2),
          borderRadius: BorderRadius.circular(16),
          gradient: enabled
              ? const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFFFF7D36), Color(0xFFFF621F)],
                )
              : null,
          boxShadow: enabled
              ? [
                  BoxShadow(
                    color: const Color(0xFFEB5F1B).withValues(alpha: 0.22),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onPressed,
            child: Center(
              child: Text(
                label,
                style: FigmaTextStyles.primaryButton.copyWith(
                  color: enabled ? Colors.white : const Color(0x992A2B2B),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class FigmaSecondaryButton extends StatelessWidget {
  const FigmaSecondaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.height = 56,
  });

  final String label;
  final VoidCallback? onPressed;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onPressed,
          child: Center(
            child: Text(label, style: FigmaTextStyles.secondaryButton),
          ),
        ),
      ),
    );
  }
}

class FigmaBottomHomeIndicator extends StatelessWidget {
  const FigmaBottomHomeIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 120,
      bottom: 8,
      width: 135,
      height: 5,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.86),
          borderRadius: BorderRadius.circular(100),
        ),
      ),
    );
  }
}

class FigmaGlassCard extends StatelessWidget {
  const FigmaGlassCard({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
    this.borderRadius = 20,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: Colors.white.withValues(alpha: 0.86)),
      ),
      child: child,
    );
  }
}

class FigmaAccountFormCard extends StatelessWidget {
  const FigmaAccountFormCard({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return FigmaGlassCard(child: Column(children: children));
  }
}

class FigmaAccountField extends StatelessWidget {
  const FigmaAccountField({
    super.key,
    required this.label,
    required this.controller,
    required this.hintText,
    this.keyboardType,
    this.obscureText = false,
    this.readOnly = false,
    this.errorText,
  });

  final String label;
  final TextEditingController controller;
  final String hintText;
  final TextInputType? keyboardType;
  final bool obscureText;
  final bool readOnly;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: errorText == null ? 61 : 78,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 18, 0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              children: [
                Text(label, style: FigmaTextStyles.formLabel),
                const SizedBox(width: 16),
                Expanded(
                  child: TextField(
                    controller: controller,
                    textAlign: TextAlign.right,
                    readOnly: readOnly,
                    keyboardType: keyboardType,
                    obscureText: obscureText,
                    cursorColor: const Color(0xFFEB5F1B),
                    style: FigmaTextStyles.formValue,
                    decoration: InputDecoration(
                      isCollapsed: true,
                      border: InputBorder.none,
                      hintText: hintText,
                      hintStyle: FigmaTextStyles.formHint,
                    ),
                  ),
                ),
              ],
            ),
            if (errorText != null) ...[
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  const Icon(
                    Icons.error_outline_rounded,
                    size: 14,
                    color: Color(0xFFFF5C35),
                  ),
                  const SizedBox(width: 5),
                  Text(errorText!, style: FigmaTextStyles.formError),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class FigmaVerificationField extends StatelessWidget {
  const FigmaVerificationField({
    super.key,
    required this.controller,
    required this.onGetCode,
    this.countdownLabel,
  });

  final TextEditingController controller;
  final VoidCallback? onGetCode;
  final String? countdownLabel;

  @override
  Widget build(BuildContext context) {
    final label = countdownLabel ?? '获取验证码';
    final disabled = countdownLabel != null;

    return SizedBox(
      height: 61,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 18, 0),
        child: Row(
          children: [
            Text('验证码', style: FigmaTextStyles.formLabel),
            const SizedBox(width: 16),
            Expanded(
              child: TextField(
                controller: controller,
                textAlign: TextAlign.right,
                keyboardType: TextInputType.number,
                cursorColor: const Color(0xFFEB5F1B),
                style: FigmaTextStyles.formValue,
                decoration: const InputDecoration(
                  isCollapsed: true,
                  border: InputBorder.none,
                  hintText: '请输入验证码',
                  hintStyle: TextStyle(
                    color: Color(0x662A2B2B),
                    fontSize: 14,
                    height: 1.2,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: disabled ? null : onGetCode,
              child: Container(
                height: 28,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: disabled
                        ? const Color(0x332A2B2B)
                        : const Color(0xFFEB5F1B),
                  ),
                ),
                child: Text(
                  label,
                  style: FigmaTextStyles.codeButton.copyWith(
                    color: disabled
                        ? const Color(0x662A2B2B)
                        : const Color(0xFFEB5F1B),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class FigmaFormDivider extends StatelessWidget {
  const FigmaFormDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 20),
      child: Divider(
        height: 1,
        thickness: 1,
        color: const Color(0xFF2A2B2B).withValues(alpha: 0.08),
      ),
    );
  }
}

class FigmaInfoRow extends StatelessWidget {
  const FigmaInfoRow({
    super.key,
    required this.label,
    required this.value,
    this.icon,
    this.onTap,
    this.danger = false,
  });

  final String label;
  final String value;
  final IconData? icon;
  final VoidCallback? onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        height: 60,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              if (icon != null) ...[
                Icon(
                  icon,
                  size: 20,
                  color: danger
                      ? const Color(0xFFEB5F1B)
                      : const Color(0x992A2B2B),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Text(
                  label,
                  style: FigmaTextStyles.formLabel.copyWith(
                    color: danger
                        ? const Color(0xFFEB5F1B)
                        : const Color(0xFF2A2B2B),
                  ),
                ),
              ),
              Flexible(
                child: Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: FigmaTextStyles.formHint.copyWith(
                    color: danger
                        ? const Color(0xFFEB5F1B)
                        : const Color(0x992A2B2B),
                  ),
                ),
              ),
              if (onTap != null) ...[
                const SizedBox(width: 6),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: Color(0x992A2B2B),
                  size: 18,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

enum FigmaRadarState { searching, found, notFound }

class FigmaDeviceRadar extends StatefulWidget {
  const FigmaDeviceRadar({
    super.key,
    this.state = FigmaRadarState.searching,
    this.animate = false,
  });

  final FigmaRadarState state;
  final bool animate;

  @override
  State<FigmaDeviceRadar> createState() => _FigmaDeviceRadarState();
}

class _FigmaDeviceRadarState extends State<FigmaDeviceRadar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
    if (widget.animate) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant FigmaDeviceRadar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animate && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.animate && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return CustomPaint(
          painter: _FigmaDeviceRadarPainter(
            state: widget.state,
            progress: widget.animate ? _controller.value : 0,
          ),
          child: Center(
            child: Container(
              width: 62,
              height: 62,
              decoration: const BoxDecoration(
                color: Color(0xFFFFF4EC),
                shape: BoxShape.circle,
              ),
              child: Icon(
                widget.state == FigmaRadarState.found
                    ? Icons.check_rounded
                    : widget.state == FigmaRadarState.notFound
                    ? Icons.close_rounded
                    : Icons.bluetooth_searching_rounded,
                color: const Color(0xFFFF6A24),
                size: 30,
              ),
            ),
          ),
        );
      },
    );
  }
}

class FigmaDeviceListCard extends StatelessWidget {
  const FigmaDeviceListCard({
    super.key,
    required this.name,
    this.selected = false,
    this.onTap,
  });

  final String name;
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
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected
                ? const Color(0xFFFF6A24)
                : Colors.white.withValues(alpha: 0.76),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: const Color(0xFFFFF4EC),
                borderRadius: BorderRadius.circular(13),
              ),
              child: const Icon(
                Icons.photo_library_outlined,
                color: Color(0xFFFF6A24),
                size: 26,
              ),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: FigmaTextStyles.deviceName,
              ),
            ),
            Icon(
              selected
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_unchecked_rounded,
              color: selected
                  ? const Color(0xFFFF6A24)
                  : const Color(0x332A2B2B),
              size: 26,
            ),
          ],
        ),
      ),
    );
  }
}

class FigmaProgressBar extends StatelessWidget {
  const FigmaProgressBar({
    super.key,
    required this.progress,
    required this.label,
  });

  final double progress;
  final String label;

  @override
  Widget build(BuildContext context) {
    final value = progress.clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            height: 8,
            child: Stack(
              children: [
                const Positioned.fill(
                  child: ColoredBox(color: Color(0xFFE8E8E8)),
                ),
                FractionallySizedBox(
                  widthFactor: value,
                  child: const ColoredBox(color: Color(0xFFEB5F1B)),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(label, style: FigmaTextStyles.bodySmall),
      ],
    );
  }
}

class FigmaCastResultIcon extends StatelessWidget {
  const FigmaCastResultIcon({super.key, required this.success});

  final bool success;

  @override
  Widget build(BuildContext context) {
    final color = success ? const Color(0xFF1AC27F) : const Color(0xFFFF6A24);
    return Container(
      width: 116,
      height: 116,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: 0.13),
      ),
      child: Center(
        child: Container(
          width: 76,
          height: 76,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withValues(alpha: 0.18),
          ),
          child: Icon(
            success ? Icons.check_rounded : Icons.close_rounded,
            color: color,
            size: 38,
          ),
        ),
      ),
    );
  }
}

class FigmaTextStyles {
  const FigmaTextStyles._();

  static const navigationTitle = TextStyle(
    color: Color(0xFF2A2B2B),
    fontSize: 16,
    fontWeight: FontWeight.w500,
    height: 1.4,
  );

  static const pageHeading = TextStyle(
    color: Color(0xFF2A2B2B),
    fontSize: 20,
    fontWeight: FontWeight.w500,
    height: 1.45,
  );

  static const bodySmall = TextStyle(
    color: Color(0x992A2B2B),
    fontSize: 12,
    fontWeight: FontWeight.w400,
    height: 1.45,
  );

  static const formLabel = TextStyle(
    color: Color(0xFF2A2B2B),
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 1.4,
  );

  static const formValue = TextStyle(
    color: Color(0xFF2A2B2B),
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 1.4,
  );

  static const formHint = TextStyle(
    color: Color(0x662A2B2B),
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 1.4,
  );

  static const formError = TextStyle(
    color: Color(0xFFFF5C35),
    fontSize: 12,
    fontWeight: FontWeight.w400,
    height: 1.4,
  );

  static const codeButton = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w400,
    height: 1.2,
  );

  static const primaryButton = TextStyle(
    color: Colors.white,
    fontSize: 18,
    fontWeight: FontWeight.w400,
    height: 1.2,
    letterSpacing: 2,
  );

  static const secondaryButton = TextStyle(
    color: Color(0xFF2A2B2B),
    fontSize: 18,
    fontWeight: FontWeight.w400,
    height: 1.2,
    letterSpacing: 2,
  );

  static const deviceName = TextStyle(
    color: Color(0xFF2A2B2B),
    fontSize: 14,
    fontWeight: FontWeight.w500,
    height: 1.4,
  );
}

class _FigmaDeviceRadarPainter extends CustomPainter {
  const _FigmaDeviceRadarPainter({required this.state, required this.progress});

  final FigmaRadarState state;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final pulse = progress * 28;
    final color = state == FigmaRadarState.notFound
        ? const Color(0xFFFF8868)
        : const Color(0xFFFFA063);

    for (final radius in <double>[38, 64, 86]) {
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = color.withValues(alpha: 0.22),
      );
    }

    if (progress > 0) {
      canvas.drawCircle(
        center,
        92 + pulse,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = color.withValues(alpha: 0.22 * (1 - progress)),
      );
    }

    canvas.drawCircle(
      center,
      61,
      Paint()..color = const Color(0xFFFFEAD9).withValues(alpha: 0.82),
    );
    canvas.drawCircle(
      center,
      39,
      Paint()..color = Colors.white.withValues(alpha: 0.96),
    );

    if (state == FigmaRadarState.found) {
      canvas.drawCircle(
        center + const Offset(45, 43),
        10,
        Paint()..color = const Color(0xFFFF6A24),
      );
    } else if (state == FigmaRadarState.notFound) {
      canvas.drawCircle(
        center + const Offset(45, 43),
        10,
        Paint()..color = const Color(0xFFFF6A24),
      );
      final crossPaint = Paint()
        ..color = Colors.white
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(
        center + const Offset(41, 39),
        center + const Offset(49, 47),
        crossPaint,
      );
      canvas.drawLine(
        center + const Offset(49, 39),
        center + const Offset(41, 47),
        crossPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _FigmaDeviceRadarPainter oldDelegate) {
    return oldDelegate.state != state || oldDelegate.progress != progress;
  }
}
