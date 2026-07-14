import 'package:flutter/material.dart';

import 'package:BoltStar/src/shared/widgets/app_widgets.dart';
import 'package:BoltStar/src/shared/widgets/figma_common.dart';
import '../../../state.dart';
import 'device_details_page.dart';

/// 清空设备内容确认页：两步二次确认清空设备内的照片，对应小程序 `detail.js` 的
/// `delete-warn`(第一步警示「同时清空图库」) → `delete`(第二步确认) 两级弹窗。
///
/// 第二步确认后调用 `state.clearDeviceMemory`（设备优先 BLE 0x12 + `clearUserProductImg`），
/// 成功后返回详情页。
class DeviceClearConfirmPage extends StatefulWidget {
  const DeviceClearConfirmPage({super.key, required this.state, this.onCancel});

  final PhotoFrameState state;
  final VoidCallback? onCancel;

  @override
  State<DeviceClearConfirmPage> createState() => _DeviceClearConfirmPageState();
}

class _DeviceClearConfirmPageState extends State<DeviceClearConfirmPage> {
  // 1=第一步警示；2=第二步确认。
  int _step = 1;
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final isStep1 = _step == 1;
    return Stack(
      children: [
        FigmaScreen(
          title: '设备详情',
          body: DeviceDetailsBody(state: widget.state),
        ),
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
              message: isStep1
                  ? '将清空设备内所有照片，同时清空图库，请谨慎选择是否继续？'
                  : '我已阅读并了解此操作的结果，确认清空设备与图库内的全部照片。',
              onCancel: widget.onCancel ?? () => Navigator.maybePop(context),
              onConfirm: () {
                if (isStep1) {
                  setState(() => _step = 2);
                } else {
                  _confirm(context);
                }
              },
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _confirm(BuildContext context) async {
    if (_busy) {
      return;
    }
    setState(() => _busy = true);
    AppLoadingDialog.show(context, '清空中');
    final feedback = await widget.state.clearDeviceMemory(
      widget.state.selectedDevice.id,
    );
    if (!context.mounted) {
      return;
    }
    AppLoadingDialog.hide(context);
    setState(() => _busy = false);
    if (feedback.success) {
      AppToast.show(context, '已清空');
      // 仅清空成功后返回设备详情；失败保留二次确认页供用户重试。
      Navigator.of(context).maybePop();
    } else {
      AppToast.warn(context, feedback.message);
    }
  }
}
