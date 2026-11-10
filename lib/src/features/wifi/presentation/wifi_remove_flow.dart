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

/// WiFi 版「解除绑定 / 删除设备 / 一键清空」（2026-10-29，同小程序 wifi-detail；弹窗与蓝牙版 [startUnbindDeviceFlow] /
/// [startDeleteDeviceFlow] / [startClearDeviceFlow] 同款：解绑一次确认，删除与清空两道确认）。WiFi 版设备端不存图片，
/// 联网下的投屏和轮播都靠云端照片，所以「删图片」只处理云端，不需要连接设备：
///   · 解除绑定（所有人都有）：只删自己那条设备记录，照片保留；不调 restore-builtin；
///   · 删除设备（仅所有者）：[_wipePhotos] 三步 → ④ delUserProduct。服务端口径：所有者删除时分享成员的记录与照片一并删除；
///   · 一键清空（2026-11-09，仅所有者，同小程序）：[_wipePhotos] 三步，设备记录保留；
///   · [_wipePhotos]：① clearUserProductImg 清这台设备的相册记录 → ② IoT photo/delete all=true 删全部云端 bin
///     → ③ IoT restore-builtin 恢复设备内置图片（2026-11-06，renderMode 同投屏，取不到不传）。
///     ①② 失败就停下；③ 返回 status 只有 SENT / SKIPPED，都继续、不重试；出错只有 401（登录失效，接口层已引导重登）
///     和 403（无权限：设备已删，顺序有问题）停下，4000 / 5000 / 网络等其余错误照常继续。

bool _busy = false;

const String _deleteIcon = 'assets/images/device-detail-icon06.png';
const String _clearIcon = 'assets/images/device-detail-icon05.png';

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
    // ①②③ 清照片（记录 + 云端 + 恢复内置图片）
    if (!await _wipePhotos(context, state, device, '[WiFi删除设备]', l10n.devDeleting)) {
      return;
    }
    if (!context.mounted) {
      return;
    }
    // ④ 删设备记录
    await _removeRecord(context, state, device.id, l10n.devDeleting, successToast: l10n.devDeviceDeleted);
  } finally {
    _busy = false;
  }
}

/// 一键清空（2026-11-09，仅所有者；入口与两级确认同蓝牙版，文案按 WiFi 版改：清的是云端照片并恢复内置图片）。
/// 做删除设备的前三步，设备记录保留；不要求设备在线、不连蓝牙。成功提示「已清空」后调 [onCleared]（详情页重查轮播标记：
/// 照片删了，服务端会把轮播里对应的图移掉）。
Future<void> startWifiClearFlow(
  BuildContext context,
  PhotoFrameState state,
  DeviceItem device, {
  VoidCallback? onCleared,
}) async {
  if (_busy) {
    return;
  }
  _busy = true;
  try {
    final l10n = AppL10n.of(context);
    final step1 = await showAppConfirmDialog(
      context,
      iconAsset: _clearIcon,
      icon: Icons.cleaning_services_outlined,
      title: l10n.devClearAll,
      message: l10n.wifiClearStep1Message,
      cancelLabel: l10n.devThinkAgain,
      confirmLabel: l10n.continueLabel,
    );
    if (step1 != true || !context.mounted) {
      return;
    }
    final step2 = await showAppConfirmDialog(
      context,
      iconAsset: _clearIcon,
      icon: Icons.cleaning_services_outlined,
      title: l10n.devClearAll,
      message: l10n.wifiClearStep2Message,
      confirmLabel: l10n.devConfirm,
    );
    if (step2 != true || !context.mounted) {
      return;
    }
    final ok = await _wipePhotos(context, state, device, '[WiFi一键清空]', l10n.devClearing);
    if (!ok || !context.mounted) {
      return;
    }
    AppToast.show(context, l10n.devCleared);
    onCleared?.call();
  } finally {
    _busy = false;
  }
}

/// 清掉这台设备的照片（删除设备与一键清空共用，同小程序 wipePhotos）：
/// ① 老服务清相册记录 → ② IoT 删全部云端 bin → ③ IoT 恢复内置图片。蒙层 loading 在这里开关。
/// 返回 true 可以继续；false 已停下（需要提示的已提示）。
Future<bool> _wipePhotos(
  BuildContext context,
  PhotoFrameState state,
  DeviceItem device,
  String tag,
  String loadingText,
) async {
  final l10n = AppL10n.of(context);
  AppLoadingDialog.show(context, loadingText);
  String failure = '';
  var stopped = false;
  try {
    // ① 老服务清这台设备的相册记录（含级联删投屏记录）
    try {
      await BoltFoxApi.clearUserProductImg(device.id);
    } catch (error) {
      failure = error is ApiException && error.message.isNotEmpty ? error.message : '$error';
      stopped = true;
    }
    // ② IoT 删该设备全部云端 bin（V1.4 更新说明九 all=true；设备离线照删）
    if (!stopped) {
      try {
        final res = await IotApi.deletePhotos({'deviceNo': device.serialNumber, 'all': true});
        debugPrint('$tag 云端图片删除返回 $res');
      } catch (error) {
        debugPrint('$tag 云端图片删除失败 $error');
        failure = l10n.wifiCloudPhotosDeleteFailed(error is IotException ? error.message : '$error');
        stopped = true;
      }
    }
    // ③ IoT 恢复设备内置图片（2026-11-06）：SENT / SKIPPED 都继续；只有 401 / 403 停下
    if (!stopped) {
      try {
        final renderMode = await state.resolveRenderMode(device);
        final res = await IotApi.restoreBuiltin(device.serialNumber, renderMode: renderMode);
        debugPrint('$tag 恢复内置图片返回 ${res['status']} $res');
      } catch (error) {
        final code = error is IotException ? error.numericCode : null;
        debugPrint('$tag 恢复内置图片失败 ${code ?? ''} $error');
        if (code == 401 || code == 403) {
          stopped = true;
          // 401 接口层已引导重登，不另提示
          if (code == 403) {
            failure = l10n.wifiRestoreBuiltinFailed((error as IotException).message);
          }
        }
      }
    }
  } finally {
    AppLoadingDialog.hide(context);
  }
  if (stopped && failure.isNotEmpty && context.mounted) {
    AppToast.warn(context, failure);
  }
  return !stopped;
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
