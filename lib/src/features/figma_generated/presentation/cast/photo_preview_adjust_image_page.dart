import 'package:flutter/material.dart';

import '../widgets/figma_common.dart';

class PhotoPreviewAdjustImagePage extends StatelessWidget {
  const PhotoPreviewAdjustImagePage({
    super.key,
    this.onSave,
    this.onStartCasting,
    this.onCrop,
    this.onRotate,
    this.onOriginal,
  });

  final VoidCallback? onSave;
  final VoidCallback? onStartCasting;
  final VoidCallback? onCrop;
  final VoidCallback? onRotate;
  final VoidCallback? onOriginal;

  @override
  Widget build(BuildContext context) {
    return FigmaPhoneFrame(
      child: Stack(
        children: [
          const FigmaPageBackground(),
          Positioned(
            left: 0,
            top: 0,
            width: 375,
            height: 90,
            child: FigmaTopNavigation(
              title: '照片预览',
              trailing: TextButton(
                onPressed: onSave,
                child: const Text(
                  '保存',
                  style: TextStyle(color: Color(0xFF2A2B2B), fontSize: 14),
                ),
              ),
            ),
          ),
          const Positioned(
            left: 152,
            top: 104,
            width: 71,
            height: 30,
            child: _PreviewCounter(label: '2/10'),
          ),
          const Positioned(
            left: 24,
            top: 150,
            width: 327,
            height: 372,
            child: FigmaImagePlaceholder(width: 327, height: 372),
          ),
          Positioned(
            left: 24,
            top: 544,
            width: 327,
            height: 74,
            child: _PhotoToolBar(
              onCrop: onCrop,
              onRotate: onRotate,
              onOriginal: onOriginal,
            ),
          ),
          Positioned(
            left: 24,
            top: 705,
            width: 327,
            height: 56,
            child: FigmaPrimaryButton(label: '开始投屏', onPressed: onStartCasting),
          ),
          const FigmaBottomHomeIndicator(),
        ],
      ),
    );
  }
}

class _PreviewCounter extends StatelessWidget {
  const _PreviewCounter({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Center(
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class _PhotoToolBar extends StatelessWidget {
  const _PhotoToolBar({this.onCrop, this.onRotate, this.onOriginal});

  final VoidCallback? onCrop;
  final VoidCallback? onRotate;
  final VoidCallback? onOriginal;

  @override
  Widget build(BuildContext context) {
    return FigmaGlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _PhotoToolButton(
            icon: Icons.crop_rounded,
            label: '裁剪',
            onTap: onCrop,
          ),
          _PhotoToolButton(
            icon: Icons.rotate_right_rounded,
            label: '旋转',
            onTap: onRotate,
          ),
          _PhotoToolButton(
            icon: Icons.image_outlined,
            label: '原图',
            onTap: onOriginal,
          ),
        ],
      ),
    );
  }
}

class _PhotoToolButton extends StatelessWidget {
  const _PhotoToolButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: SizedBox(
        width: 72,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: const Color(0xFF2A2B2B), size: 22),
            const SizedBox(height: 7),
            Text(label, style: FigmaTextStyles.bodySmall),
          ],
        ),
      ),
    );
  }
}
