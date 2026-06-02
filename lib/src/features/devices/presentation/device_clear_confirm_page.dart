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
              iconAsset: 'assets/images/device-detail-icon05.png',
              fallbackIcon: Icons.cleaning_services_outlined,
              accent: const Color(0xFFFF6A20),
              title: '一键清空',
              message: '将清空设备内所有照片，请谨慎选择是否继续？',
              onCancel: onCancel ?? () => Navigator.maybePop(context),
              onConfirm: onConfirm,
            ),
          ),
        ),
      ],
    );
  }
}
