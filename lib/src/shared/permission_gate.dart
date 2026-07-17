import 'package:flutter/material.dart';

import '../native_device_api.dart';
import 'l10n/app_l10n.dart';

/// 运行时权限门卫：在进入相册 / 蓝牙设备操作**之前**先完成系统授权。
///
/// 产品要求（2026-07 反馈）：
/// 1. 相册必须先授权再访问——Android 13+ 的系统选择器本身不要求权限，
///    也照样要先弹授权框；未授权不得进入相册。
/// 2. 授权框要先于「设备操作」（扫描/连接的 loading、雷达动画）单独出现，二者不同屏。
/// 3. 用户拒绝时弹「去设置」引导框；在系统设置里手动关闭后再次使用，
///    这里会重新弹系统授权框（每次都按当前真实状态请求，同拍照的行为）。
class PermissionGate {
  PermissionGate._();

  /// 相册（照片/媒体）权限。已授权直接放行；未授权先弹系统授权框；
  /// 拒绝后弹「去设置」引导并返回 false（调用方中止进相册）。
  static Future<bool> ensurePhotoAccess(BuildContext context) async {
    DevicePermissionStatus status;
    try {
      // 原生层已授权时直接返回现状（不弹窗），未授权则拉起系统授权框。
      status = await NativeDeviceApi.requestPhotoPermission();
    } catch (_) {
      // 通道不可用（iOS 未注册 / 桌面端 / 测试环境）不拦截：
      // 交给系统相册选择器自身的权限机制，不能让这些平台选不了图。
      return true;
    }
    if (status.photoPermissionGranted) {
      return true;
    }
    if (context.mounted) {
      final l10n = AppL10n.of(context);
      await showPermissionGuideDialog(
        context,
        title: l10n.permPhotoTitle,
        message: l10n.permPhotoMessage,
        actionLabel: l10n.bindGoSettings,
        onAction: NativeDeviceApi.openAppSettings,
      );
    }
    return false;
  }

  /// 蓝牙权限（Android 12+「附近设备」；Android 11- 含定位）+ 蓝牙开关。
  ///
  /// 供「连接 / 投屏自动连接」等设备操作在弹 loading **之前**调用：
  /// 授权框先单独出现，全就绪才开始设备操作；拒绝 / 蓝牙未开则弹引导框并返回 false。
  /// （绑定流程页有自己的分阶段处理，见 bind_device_flow.dart。）
  static Future<bool> ensureBleReady(BuildContext context) async {
    // requestBluetoothPermissions 内部已兜异常（通道缺失返回全 false）。
    final status = await NativeDeviceApi.requestBluetoothPermissions();
    if (!context.mounted) {
      return false;
    }
    final l10n = AppL10n.of(context);
    if (!status.bluetoothPermissionGranted) {
      await showPermissionGuideDialog(
        context,
        title: l10n.bindBtPermissionTitle,
        message: l10n.permBleConnectMessage,
        actionLabel: l10n.bindGoSettings,
        onAction: NativeDeviceApi.openAppSettings,
      );
      return false;
    }
    if (!status.bluetoothEnabled) {
      await showPermissionGuideDialog(
        context,
        title: l10n.bindBtOffTitle,
        message: l10n.permBtOffConnectMessage,
        actionLabel: l10n.bindGoOpenBt,
        onAction: NativeDeviceApi.openBluetoothSettings,
      );
      return false;
    }
    return true;
  }
}

/// 权限被拒 / 蓝牙未开的引导弹窗：「取消 / 去设置（或去打开蓝牙）」。
Future<void> showPermissionGuideDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String actionLabel,
  required Future<void> Function() onAction,
}) async {
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: Text(AppL10n.of(dialogContext).cancel),
        ),
        TextButton(
          onPressed: () async {
            Navigator.of(dialogContext).pop();
            try {
              await onAction();
            } catch (_) {
              // 打开系统设置失败不阻断（如 iOS 通道未实现），用户可手动去设置。
            }
          },
          child: Text(actionLabel),
        ),
      ],
    ),
  );
}
