import 'package:flutter/material.dart';

import 'package:BoltStar/src/shared/widgets/figma_common.dart';
import '../../../shared/l10n/app_l10n.dart';

/// 照片预览-裁剪调整页：投屏前调整照片显示区域，对应 UI 稿「照片预览-调整」。
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
    final l10n = AppL10n.of(context);
    return FigmaScreen(
      title: l10n.cresPreviewTitle,
      scrollable: false,
      trailing: TextButton(
        onPressed: onSave,
        child: Text(
          l10n.cresSave,
          style: const TextStyle(color: Color(0xFF2A2B2B), fontSize: 14),
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          Expanded(
            child: Stack(
              children: const [
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Color(0xFFD9D9D9),
                      borderRadius: BorderRadius.all(Radius.circular(16)),
                    ),
                    child: Center(
                      child: Text(
                        'Image Placeholder',
                        style: TextStyle(
                          color: Color(0xFF737373),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.topCenter,
                  child: Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: SizedBox(
                      width: 71,
                      height: 30,
                      child: _PreviewCounter(label: '2/10'),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 74,
            child: _PhotoToolBar(
              onCrop: onCrop,
              onRotate: onRotate,
              onOriginal: onOriginal,
            ),
          ),
        ],
      ),
      bottom: FigmaPrimaryButton(
        label: l10n.cresStartCast,
        onPressed: onStartCasting,
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
    final l10n = AppL10n.of(context);
    return FigmaGlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _PhotoToolButton(
            icon: Icons.crop_rounded,
            label: l10n.cresCrop,
            onTap: onCrop,
          ),
          _PhotoToolButton(
            icon: Icons.rotate_right_rounded,
            label: l10n.cresRotate,
            onTap: onRotate,
          ),
          _PhotoToolButton(
            icon: Icons.image_outlined,
            label: l10n.cresOriginal,
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
