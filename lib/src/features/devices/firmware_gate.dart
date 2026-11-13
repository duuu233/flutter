import 'dart:async';

import 'package:flutter/material.dart';

import '../../device/ble_controller.dart';
import '../../network/iot/iot_api.dart';
import '../../routes/app_routes.dart';
import '../../shared/l10n/app_l10n.dart';
import '../../shared/widgets/app_dialog.dart';
import '../../state.dart';
import '../wifi/presentation/wifi_ota_page.dart';
import '../wifi/wifi_ota.dart';
import '../wifi/wifi_status.dart';
import 'presentation/ota_upgrade_page.dart';

// 固件升级判断（2026-11-13，产品口径；同小程序 utils/firmware-gate.js）：强制升级 / 强提醒升级的弹框与拦截。
//
// 什么时候判断：
//   · WiFi 版在线才判断，离线（含休眠 / 关机 / 本地模式 / 状态查不到）不判；
//   · 蓝牙版已连接才判断，未连接不判。
// 判断场景：
//   · 设备详情页（蓝牙 DeviceDetailsPage / WiFi WifiDeviceDetailPage）：进入后判断一次，点功能按钮再判断——强制与强提醒都弹；
//   · 设备列表页：蓝牙「投屏」、WiFi「投屏」「轮播设置」——只判强制升级；
//   · 首页「拍照投屏」「相册投屏」——只判强制升级。
// 弹框：
//   · 强制升级：「立即升级 / 取消」，可以取消，但取消后这次操作不继续；再次点击或进入触发判断的场景会再弹；
//   · 强提醒升级（只在详情页判断）：「立即升级 / 取消」，取消后操作照常继续；
//   · 立即升级都进升级页（蓝牙 OtaUpgradePage 自动开始，WiFi WifiOtaPage 步骤页），这次操作不再继续。
// 有没有新版本，与详情页「固件升级」行红点同一套判定：
//   · WiFi：IoT 设备信息 firmwareVersion 对比 newVersionNo（evaluateWifiOta 为 available）；本地有进行中的升级记录不弹；
//   · 蓝牙：当前会话读回的版本对比 newVersionNo，且下载地址是有效 .bin；读不到版本退回后端 isUpdate。
// 升级方式取 DeviceItem.updateType（详情出参 compulsory 优先）：1 = 强制升级，其它 = 强提醒升级。
// 查询失败（网络 / 接口 / 蓝牙读不到）一律放行，不因为查不到把用户挡在门外。

enum FirmwareGateMode { none, force, remind }

/// 升级方式：updateType 1 = 强制，其它 = 强提醒。
FirmwareGateMode firmwareGateModeOf(DeviceItem device) =>
    device.updateType == 1 ? FirmwareGateMode.force : FirmwareGateMode.remind;

/// 由已知事实得出这次要不要弹、弹哪种。
/// [ready]：WiFi 版为「在线」、蓝牙版为「已连接」；[hasUpdate]：与红点同一判定的结果；
/// [inflight]：WiFi 本地有进行中的升级；[forceOnly]：列表页 / 首页只判强制升级。
FirmwareGateMode decideFirmwareGate(
  DeviceItem device, {
  required bool ready,
  required bool hasUpdate,
  bool inflight = false,
  bool forceOnly = false,
}) {
  if (!ready || inflight || !hasUpdate) {
    return FirmwareGateMode.none;
  }
  final mode = firmwareGateModeOf(device);
  if (forceOnly && mode != FirmwareGateMode.force) {
    return FirmwareGateMode.none;
  }
  return mode;
}

/// 蓝牙版当前会话读回的固件版本（同 device_details_page `_liveFirmwareVersion`）：会话不是这台时退回记录里的值。
String bleLiveFirmwareVersion(DeviceItem device) {
  final ble = BleController.instance;
  final live = ble.sessionMatchesSerial(device.serialNumber, screenCode: device.screenCode)
      ? (ble.info?.firmwareVersion ?? '')
      : '';
  return (live.isNotEmpty ? live : device.firmwareVersion).trim();
}

/// 蓝牙版有没有可用的新版本（同 device_details_page `_hasFirmwareUpdate`；已连接前提由调用方保证）。
bool bleFirmwareHasUpdate(DeviceItem device, String currentVersion) {
  final verdict = evaluateFirmwareUpdate(device, currentVersion: currentVersion);
  if (verdict == FirmwareUpdateVerdict.unknown) {
    return device.hasFirmwareUpdate;
  }
  return verdict == FirmwareUpdateVerdict.update;
}

/// WiFi 版有没有新版本（同 WiFi 详情红点；在线前提由调用方保证）。
bool wifiFirmwareHasUpdate(DeviceItem device, String firmwareVersion) =>
    evaluateWifiOta(firmwareVersion, device.newVersionNo, device.downloadPath).state == WifiOtaCheckState.available;

/// 按 [mode] 弹框。返回这次操作是否继续：强制升级取消 / 去升级了 → false；强提醒取消 → true。
Future<bool> showFirmwareGateDialog(
  BuildContext context,
  PhotoFrameState state,
  DeviceItem device,
  FirmwareGateMode mode,
) async {
  if (mode == FirmwareGateMode.none) {
    return true;
  }
  final l10n = AppL10n.of(context);
  final force = mode == FirmwareGateMode.force;
  final version = device.newVersionNo.trim().isNotEmpty ? device.newVersionNo.trim() : l10n.otaGateNewVersion;
  final confirmed = await showAppConfirmDialog(
    context,
    title: l10n.otaFirmwareUpgrade,
    message: force ? l10n.otaGateForceMessage(version) : l10n.otaGateRemindMessage(version),
    icon: Icons.system_update_alt_rounded,
    cancelLabel: l10n.cancel,
    confirmLabel: l10n.otaUpgradeNowAction,
  );
  if (confirmed == true) {
    if (context.mounted) {
      // 不等升级页关闭：这次操作不再继续
      unawaited(Navigator.of(context).push<void>(
        AppPageRoute(
          builder: (_) => device.isWifi
              ? WifiOtaPage(state: state, deviceId: device.id)
              : OtaUpgradePage(state: state, deviceId: device.id, autoStart: true),
        ),
      ));
    }
    return false;
  }
  return !force;
}

/// 列表页 / 首页：现查一遍再判断（只判强制升级）。返回这次操作是否继续。
Future<bool> guardFirmwareAction(BuildContext context, PhotoFrameState state, DeviceItem device) async {
  try {
    final bool hasUpdate;
    final DeviceItem target;
    if (device.isWifi) {
      final deviceNo = IotApi.plainDeviceNo(device.serialNumber);
      if (deviceNo.isEmpty || await WifiOtaStore.read(deviceNo) != null) {
        return true;
      }
      final status = await WifiStatusStore.instance.refresh(device);
      if (!status.online) {
        return true;
      }
      final fresh = await state.fetchDeviceFirmwareInfo(device.id);
      if (fresh == null) {
        return true;
      }
      hasUpdate = wifiFirmwareHasUpdate(fresh, wifiFirmwareVersion(status.info));
      target = fresh;
    } else {
      if (!state.isDeviceActuallyConnected(device.id)) {
        return true;
      }
      // 当前版本：本次会话没读过 0x03 时补读一次（读不到退回 isUpdate）
      await state.refreshConnectedDeviceInfo(device.id, includeFirmwareVersion: true);
      final fresh = await state.fetchDeviceFirmwareInfo(device.id);
      if (fresh == null) {
        return true;
      }
      hasUpdate = bleFirmwareHasUpdate(fresh, bleLiveFirmwareVersion(fresh));
      target = fresh;
    }
    final mode = decideFirmwareGate(target, ready: true, hasUpdate: hasUpdate, forceOnly: true);
    if (mode == FirmwareGateMode.none || !context.mounted) {
      return true;
    }
    debugPrint('[固件升级] 拦截 ${target.isWifi ? 'WiFi' : '蓝牙'} ${target.id} $mode → ${target.newVersionNo}');
    return await showFirmwareGateDialog(context, state, target, mode);
  } catch (error) {
    debugPrint('[固件升级] 判断失败，放行 $error');
    return true;
  }
}
