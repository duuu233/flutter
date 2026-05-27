import 'package:flutter/material.dart';

import 'package:BoltStar/src/shared/widgets/figma_common.dart';
import 'device_details_page.dart';

/// 清空设备内容确认页：二次确认清空设备内的照片，对应 UI 稿「清空设备确认」。
class DeviceClearConfirmPage extends StatelessWidget {
  const DeviceClearConfirmPage({super.key, this.onCancel, this.onConfirm});

  final VoidCallback? onCancel;
  final VoidCallback? onConfirm;

  @override
  Widget build(BuildContext context) {
    return FigmaPhoneFrame(
      child: Stack(
        children: [
          const DeviceDetailsScene(),
          Positioned.fill(
            child: ColoredBox(color: Colors.black.withValues(alpha: 0.32)),
          ),
          Positioned(
            left: 24,
            top: 318,
            width: 327,
            height: 188,
            child: _ConfirmDialogCard(
              title: '一键清空',
              message: '将清空设备内所有照片，请谨慎选择是否继续？',
              onCancel: onCancel ?? () => Navigator.maybePop(context),
              onConfirm: onConfirm,
            ),
          ),
          const FigmaBottomHomeIndicator(),
        ],
      ),
    );
  }
}

class _ConfirmDialogCard extends StatelessWidget {
  const _ConfirmDialogCard({
    required this.title,
    required this.message,
    required this.onCancel,
    required this.onConfirm,
  });

  final String title;
  final String message;
  final VoidCallback onCancel;
  final VoidCallback? onConfirm;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 22, 24, 20),
        child: Column(
          children: [
            Text(title, style: FigmaTextStyles.pageHeading),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: FigmaTextStyles.bodySmall.copyWith(fontSize: 14),
            ),
            const Spacer(),
            Row(
              children: [
                Expanded(
                  child: FigmaSecondaryButton(
                    label: '取消',
                    height: 48,
                    onPressed: onCancel,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FigmaPrimaryButton(
                    label: '确认',
                    height: 48,
                    onPressed: onConfirm,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
