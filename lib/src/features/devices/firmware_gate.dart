import 'dart:async';

import 'package:flutter/material.dart';

import '../../routes/app_routes.dart';
import '../../shared/l10n/app_l10n.dart';
import '../../shared/widgets/app_dialog.dart';
import '../../state.dart';
import '../wifi/presentation/wifi_ota_page.dart';
import '../wifi/wifi_ota.dart';
import 'presentation/ota_upgrade_page.dart';

// 固件升级提醒（2026-11-13 产品改口，同小程序 utils/firmware-gate.js；取代同日早些时候的「强制升级 / 强提醒」两套判断）：
// 强制升级整套去掉——首页、列表页、设备详情页都不拦截；首页 / 列表页点击时的 loading 现查与本地缓存一并去掉。
// 只保留「强提醒升级」与「弱提示升级」：
//
// 升级类型取后台「升级类型」compulsory（归一到 DeviceItem.updateType）：
//   2 = 强提示升级（强提醒）：「固件升级」红点（用户主动点）+ 进入设备详情页弹提示框；
//       取消后不再弹，关闭 / 重启 App（本次启动的内存记录丢失）后再进入才再弹；
//   3 = 弱提示升级：只亮红点，用户主动点去升级；4 = 不提示升级 / 没给：同改动前，只按版本亮红点；
//   1 = 原强制升级：后台已隐藏该选项，存量数据按强提醒处理。
// 弹的前提：WiFi 版在线、蓝牙版已连接，且详情页「固件升级」行红点亮（有新版本，WiFi 有进行中的升级不亮）。
// 弹框「立即升级 / 取消」：立即升级进升级页（蓝牙 OtaUpgradePage 自动开始，WiFi WifiOtaPage 步骤页）；取消照常留在详情页。

enum FirmwareGateMode { none, remind }

/// 升级类型：2 强提醒（1 原强制按强提醒）弹；3 弱提示、4 不提示及其它都不弹。
FirmwareGateMode firmwareGateModeOf(DeviceItem device) => switch (device.updateType) {
      1 || 2 => FirmwareGateMode.remind,
      _ => FirmwareGateMode.none,
    };

/// 本次启动已提醒过的设备（内存，App 关闭 / 重启后清空，再进入详情页再弹）。
abstract final class FirmwareRemindSession {
  static final Set<String> _reminded = {};

  /// 强提醒本次启动是否还没弹过（第一次调用返回 true 并记下）。
  static bool take(String deviceId) => _reminded.add(deviceId);

  /// 模拟重新打开 App（测试用）。
  @visibleForTesting
  static void reset() => _reminded.clear();
}

/// 由已知事实得出要不要弹。
/// [ready]：WiFi 版为「在线」、蓝牙版为「已连接」；[hasUpdate]：与红点同一判定的结果；[inflight]：WiFi 本地有进行中的升级。
FirmwareGateMode decideFirmwareGate(
  DeviceItem device, {
  required bool ready,
  required bool hasUpdate,
  bool inflight = false,
}) {
  if (!ready || inflight || !hasUpdate) {
    return FirmwareGateMode.none;
  }
  return firmwareGateModeOf(device);
}

/// WiFi 版有没有新版本（同 WiFi 详情红点；在线前提由调用方保证）。
bool wifiFirmwareHasUpdate(DeviceItem device, String firmwareVersion) =>
    evaluateWifiOta(firmwareVersion, device.newVersionNo, device.downloadPath).state == WifiOtaCheckState.available;

/// 弹强提醒。返回 true = 取消 / 不用弹（留在当前页），false = 去升级了。
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
  final latest = device.newVersionNo.trim();
  final version = latest.isNotEmpty ? latest : l10n.otaGateNewVersion;
  final confirmed = await showAppConfirmDialog(
    context,
    title: l10n.otaFirmwareUpgrade,
    message: l10n.otaGateRemindMessage(version),
    icon: Icons.system_update_alt_rounded,
    cancelLabel: l10n.cancel,
    confirmLabel: l10n.otaUpgradeNowAction,
  );
  if (confirmed == true) {
    if (context.mounted) {
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
  return true;
}

/// 详情页进入时判断一次：强提醒每台设备每次启动只弹一次。返回值同 [showFirmwareGateDialog]。
Future<bool> checkFirmwareGateOnEnter(
  BuildContext context,
  PhotoFrameState state,
  DeviceItem device, {
  required bool ready,
  required bool hasUpdate,
  bool inflight = false,
}) async {
  final mode = decideFirmwareGate(device, ready: ready, hasUpdate: hasUpdate, inflight: inflight);
  if (mode == FirmwareGateMode.none || !FirmwareRemindSession.take(device.id) || !context.mounted) {
    return true;
  }
  return showFirmwareGateDialog(context, state, device, mode);
}
