import 'package:flutter/material.dart';

class AtmosphereBackground extends StatelessWidget {
  const AtmosphereBackground({super.key});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFFF7EDE2),
                  Color(0xFFF2E2D1),
                  Color(0xFFEADCCA),
                ],
              ),
            ),
          ),
          const Positioned(
            top: -120,
            left: -80,
            child: _GlowOrb(size: 260, color: Color(0xFFB8D8D8)),
          ),
          const Positioned(
            top: 100,
            right: -40,
            child: _GlowOrb(size: 190, color: Color(0xFFF2CC8F)),
          ),
          const Positioned(
            bottom: 120,
            left: -30,
            child: _GlowOrb(size: 200, color: Color(0xFFD4A373)),
          ),
        ],
      ),
    );
  }
}

class _GlowOrb extends StatelessWidget {
  const _GlowOrb({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            color.withValues(alpha: 0.34),
            color.withValues(alpha: 0.04),
            Colors.transparent,
          ],
        ),
      ),
    );
  }
}
