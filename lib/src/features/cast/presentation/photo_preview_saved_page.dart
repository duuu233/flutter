import 'package:flutter/material.dart';

import 'package:BoltStar/src/shared/widgets/figma_common.dart';
import '../../../shared/l10n/app_l10n.dart';

/// 照片预览-已保存页：展示已保存的照片预览，对应 UI 稿「照片预览-已保存」。
class PhotoPreviewSavedPage extends StatelessWidget {
  const PhotoPreviewSavedPage({
    super.key,
    this.onStartCasting,
    this.onCrop,
    this.onRotate,
    this.onOriginal,
  });

  final VoidCallback? onStartCasting;
  final VoidCallback? onCrop;
  final VoidCallback? onRotate;
  final VoidCallback? onOriginal;

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    return FigmaScreen(
      title: l10n.cresPreviewTitle,
      scrollable: false,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 4),
          // 计数胶囊（小程序 .preview-imageCount：浅灰底、居中）。
          const Center(child: _PreviewCounter(label: '1/2')),
          const SizedBox(height: 14),
          Expanded(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xFFE6ECF4),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Center(
                child: Text(
                  l10n.cresImagePlaceholder,
                  style: const TextStyle(color: Color(0xFF9AA1AB), fontSize: 14),
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          _PhotoToolBar(
            onCrop: onCrop,
            onRotate: onRotate,
            onOriginal: onOriginal,
          ),
        ],
      ),
      bottom: FigmaPrimaryButton(label: l10n.cresStartCast, onPressed: onStartCasting),
    );
  }
}

/// 计数胶囊（小程序 `.preview-imageCount`）：rgba(42,43,43,0.08) 底，文字 0.8。
class _PreviewCounter extends StatelessWidget {
  const _PreviewCounter({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF2A2B2B).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: const Color(0xFF2A2B2B).withValues(alpha: 0.8),
          fontSize: 15,
          fontWeight: FontWeight.w600,
          height: 1.2,
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
    final l10n = AppL10n.of(context);
    return FigmaGlassCard(
      borderRadius: 20,
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _PhotoToolButton(
            iconAsset: 'assets/images/preview-icon01.png',
            fallbackIcon: Icons.crop_rounded,
            label: l10n.cresCrop,
            onTap: onCrop,
          ),
          _PhotoToolButton(
            iconAsset: 'assets/images/preview-icon02.png',
            fallbackIcon: Icons.rotate_right_rounded,
            label: l10n.cresRotate,
            onTap: onRotate,
          ),
          _PhotoToolButton(
            iconAsset: 'assets/images/preview-icon03.png',
            fallbackIcon: Icons.image_outlined,
            label: l10n.cresOriginal,
            onTap: onOriginal,
          ),
        ],
      ),
    );
  }
}

/// 工具按钮（小程序 `.tool`）：图标 44rpx≈22 + 文案 24rpx≈12 / #777e88。
class _PhotoToolButton extends StatelessWidget {
  const _PhotoToolButton({
    required this.iconAsset,
    required this.fallbackIcon,
    required this.label,
    required this.onTap,
  });

  final String iconAsset;
  final IconData fallbackIcon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        width: 72,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset(
              iconAsset,
              width: 22,
              height: 22,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) =>
                  Icon(fallbackIcon, color: const Color(0xFF777E88), size: 22),
            ),
            const SizedBox(height: 7),
            Text(
              label,
              style: const TextStyle(
                color: Color(0xFF777E88),
                fontSize: 12,
                height: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
