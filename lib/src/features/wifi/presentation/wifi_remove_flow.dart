import 'package:flutter/material.dart';

import '../../../network/api_exception.dart';
import '../../../network/boltfox_api.dart';
import '../../../network/iot/iot_api.dart';
import '../../../network/iot/iot_client.dart';
import '../../../shared/l10n/app_l10n.dart';
import '../../../shared/widgets/app_dialog.dart';
import '../../../shared/widgets/app_toast.dart';
import '../../../shared/widgets/app_widgets.dart';
import '../../../state.dart';
import '../wifi_l10n.dart';

/// WiFi 版「解除绑定 / 删除设备」（2026-10-29，同小程序 wifi-detail；弹窗与蓝牙版 [startUnbindDeviceFlow] /
/// [startDeleteDeviceFlow] 同款：解绑一次确认，删除两道确认）。WiFi 版设备端不存图片，联网下的投屏和轮播都靠云端照片，
/// 所以「先删图片」只处理云端，不需要连接设备：
///   · 解除绑定（所有人都有，成员只有这一项）：只删自己那条设备记录，照片保留；
///   · 删除设备（仅所有者）：① clearUserProductImg 清这台设备的相册记录 → ② IoT photo/delete all=true 删全部云端 bin
///     → ③ delUserProduct。任一步失败就停下，不删设备。服务端口径：所有者删除时分享成员的记录与照片一并删除。

bool _busy = false;

const String _deleteIcon = 'assets/images/device-detail-icon06.png';

Future<void> startWifiUnbindFlow(BuildContext context, PhotoFrameState state, DeviceItem device) async {
  if (_busy) {
    return;
  }
  _busy = true;
  try {
    final l10n = AppL10n.of(context);
    final confirmed = await showAppConfirmDialog(
      context,
      iconAsset: _deleteIcon,
      icon: Icons.link_off_rounded,
      tone: AppDialogTone.danger,
      title: l10n.devUnbindDevice,
      message: l10n.wifiUnbindMessage,
      confirmLabel: l10n.devConfirm,
    );
    if (confirmed != true || !context.mounted) {
      return;
    }
    await _removeRecord(context, state, device.id, l10n.devUnbinding);
  } finally {
    _busy = false;
  }
}

Future<void> startWifiDeleteFlow(BuildContext context, PhotoFrameState state, DeviceItem device) async {
  if (_busy) {
    return;
  }
  _busy = true;
  try {
    final l10n = AppL10n.of(context);
    final step1 = await showAppConfirmDialog(
      context,
      iconAsset: _deleteIcon,
      icon: Icons.delete_outline_rounded,
      tone: AppDialogTone.danger,
      title: l10n.devDeleteDevice,
      message: l10n.wifiDeleteDeviceMessage,
      confirmLabel: l10n.continueLabel,
    );
    if (step1 != true || !context.mounted) {
      return;
    }
    final step2 = await showAppConfirmDialog(
      context,
      iconAsset: _deleteIcon,
      icon: Icons.delete_outline_rounded,
      tone: AppDialogTone.danger,
      title: l10n.devDeleteDeviceConfirmTitle,
      message: l10n.devDeleteDeviceConfirmMessage,
      confirmLabel: l10n.devConfirm,
    );
    if (step2 != true || !context.mounted) {
      return;
    }
    // ①② 先删图片（只处理云端）
    AppLoadingDialog.show(context, l10n.devDeleting);
    String failure = '';
    try {
      await BoltFoxApi.clearUserProductImg(device.id);
      try {
        final res = await IotApi.deletePhotos({'deviceNo': device.serialNumber, 'all': true});
        debugPrint('[WiFi删除设备] 云端图片删除返回 $res');
      } catch (error) {
        debugPrint('[WiFi删除设备] 云端图片删除失败 $error');
        failure = l10n.wifiCloudDeleteFailed(error is IotException ? error.message : '$error');
      }
    } catch (error) {
      failure = error is ApiException && error.message.isNotEmpty ? error.message : '$error';
    } finally {
      AppLoadingDialog.hide(context);
    }
    if (!context.mounted) {
      return;
    }
    if (failure.isNotEmpty) {
      AppToast.warn(context, failure);
      return;
    }
    // ③ 删设备记录
    await _removeRecord(context, state, device.id, l10n.devDeleting, successToast: l10n.devDeviceDeleted);
  } finally {
    _busy = false;
  }
}

/// 删设备记录：蒙层 loading → state.deleteDevice → 成功详情页出栈回设备列表。
Future<void> _removeRecord(
  BuildContext context,
  PhotoFrameState state,
  String deviceId,
  String loadingText, {
  String? successToast,
}) async {
  AppLoadingDialog.show(context, loadingText);
  final navigator = Navigator.of(context);
  final ActionFeedback feedback;
  try {
    feedback = await state.deleteDevice(deviceId);
  } finally {
    AppLoadingDialog.hide(context);
  }
  if (!context.mounted) {
    return;
  }
  if (!feedback.success) {
    AppToast.warn(context, feedback.message);
    return;
  }
  if (successToast != null) {
    AppToast.show(context, successToast);
  }
  navigator.pop();
}
