import 'package:flutter/material.dart';

import 'package:BoltStar/src/shared/widgets/figma_common.dart';
import '../../../state.dart';
import '../../../shared/l10n/app_l10n.dart';
import 'device_details_page.dart';

/// 删除设备确认页：二次确认解绑 / 删除设备，对应 UI 稿「删除设备确认」。
///
/// 确认后调用 `state.deleteDevice`（→ `delUserProduct`），成功后退回设备列表。
class DeviceDeleteConfirmPage extends StatelessWidget {
  const DeviceDeleteConfirmPage({
    super.key,
    required this.state,
    this.onCancel,
  });

  final PhotoFrameState state;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        FigmaScreen(
          title: '设备详情',
          body: DeviceDetailsBody(state: state),
        ),
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
              title: AppL10n.of(context).devDeleteDevice,
              message: AppL10n.of(context).devDeleteDeviceMessage,
              onCancel: onCancel ?? () => Navigator.maybePop(context),
              onConfirm: () => _confirm(context),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _confirm(BuildContext context) async {
    final navigator = Navigator.of(context);
    final deviceId = state.selectedDevice.id;
    final feedback = await state.deleteDevice(deviceId);
    if (!context.mounted) {
      return;
    }
    if (feedback.success) {
      // 关闭确认页与详情页，回到设备列表。
      navigator.pop();
      navigator.pop();
    } else {
      AppToast.warn(context, feedback.message);
    }
  }
}
