import 'package:flutter/material.dart';

import 'package:BoltStar/src/shared/widgets/figma_common.dart';
import 'device_details_page.dart';

/// 删除设备确认页：二次确认解绑 / 删除设备，对应 UI 稿「删除设备确认」。
class DeviceDeleteConfirmPage extends StatelessWidget {
  const DeviceDeleteConfirmPage({super.key, this.onCancel, this.onConfirm});

  final VoidCallback? onCancel;
  final VoidCallback? onConfirm;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const FigmaScreen(title: '设备详情', body: DeviceDetailsBody()),
        Positioned.fill(
          child: ColoredBox(color: Colors.black.withValues(alpha: 0.4)),
        ),
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: DeviceConfirmDialog(
              iconAsset: 'assets/images/device-detail-icon06.png',
              fallbackIcon: Icons.delete_outline_rounded,
              accent: const Color(0xFFFF3045),
              title: '删除设备',
              message: '删除后将解除与该相框设备的绑定，后续使用需重新添加设备。',
              onCancel: onCancel ?? () => Navigator.maybePop(context),
              onConfirm: onConfirm,
            ),
          ),
        ),
      ],
    );
  }
}
