import 'package:flutter/material.dart';

import 'package:BoltStar/src/shared/widgets/figma_common.dart';
import '../../../state.dart';
import 'device_details_page.dart';

/// 清空设备内容确认页：二次确认清空设备内的照片，对应 UI 稿「清空设备确认」。
///
/// 确认后调用 `state.clearDeviceMemory`（→ `clearUserProductImg`），成功后返回详情页。
class DeviceClearConfirmPage extends StatelessWidget {
  const DeviceClearConfirmPage({super.key, required this.state, this.onCancel});

  final PhotoFrameState state;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        FigmaScreen(title: '设备详情', body: DeviceDetailsBody(state: state)),
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
              onConfirm: () => _confirm(context),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _confirm(BuildContext context) async {
    final feedback = await state.clearDeviceMemory(state.selectedDevice.id);
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(feedback.message)));
    // 清空完成后返回设备详情。
    Navigator.of(context).maybePop();
  }
}
