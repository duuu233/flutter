import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../device/ble_controller.dart';
import '../../network/iot/iot_api.dart';
import '../../routes/app_routes.dart';
import '../../shared/l10n/app_l10n.dart';
import '../../shared/widgets/app_dialog.dart';
import '../../shared/widgets/app_widgets.dart';
import '../../state.dart';
import '../wifi/presentation/wifi_ota_page.dart';
import '../wifi/wifi_ota.dart';
import '../wifi/wifi_status.dart';
import 'presentation/ota_upgrade_page.dart';

// 固件升级判断（2026-11-13，产品口径；同日按产品复核改；同小程序 utils/firmware-gate.js）：强制升级 / 强提醒升级的弹框与拦截。
//
// 升级类型取后台「升级类型」compulsory（归一到 DeviceItem.updateType）：
//   1 = 强制升级、2 = 强提示升级（强提醒）、3 = 弱提示升级、4 = 不提示升级。只有 1、2 弹框；
//   3、4 照改动前只亮「固件升级」红点、用户自己点去升级。红点不分类型，1、2 也照样亮。
// 什么时候判断：WiFi 版在线才判断（离线 / 休眠 / 本地模式 / 查不到不判）；蓝牙版已连接才判断。
// 强提醒升级：只在进入设备详情页时弹，每台设备每次启动 App 只弹一次（取消后本次不再提醒，重新打开 App 才再提醒）；
//   详情页的功能按钮、列表页、首页都不弹强提醒。
// 强制升级：
//   · 设备详情页：进入时弹；取消后点任意功能按钮都再弹，且这次操作不继续；
//   · 列表页（蓝牙「投屏」，WiFi「投屏」「轮播设置」）、首页（拍照 / 相册投屏）：点击时弹，取消后这次操作不继续，再点再弹。
//     本次启动第一次点某台设备时显示 loading 现查一次（设备详情 + 当前固件版本），结果存本地缓存（[FirmwareGateCache]）；
//     之后再点直接按缓存判断，不再请求接口。详情页进入时的判定也写进缓存；升级完成（蓝牙 OtaUpgradePage 成功、
//     WiFi 主固件升级走到设备重启确认）后把缓存改成「无需升级」。
// 弹框：「立即升级 / 取消」；立即升级都进升级页（蓝牙 OtaUpgradePage 自动开始，WiFi WifiOtaPage 步骤页），这次操作不再继续。
// 有没有新版本，与详情页「固件升级」行红点同一套判定：
//   · WiFi：IoT 设备信息 firmwareVersion 对比 newVersionNo（evaluateWifiOta 为 available）；本地有进行中的升级记录不弹；
//   · 蓝牙：当前会话读回的版本对比 newVersionNo，且下载地址是有效 .bin；读不到版本退回后端 isUpdate。
// 查询失败（网络 / 接口 / 蓝牙读不到）一律放行，不因为查不到把用户挡在门外。

enum FirmwareGateMode { none, force, remind }

/// 升级类型：1 = 强制、2 = 强提示（强提醒）；3 弱提示、4 不提示及其它都不弹。
FirmwareGateMode firmwareGateModeOf(DeviceItem device) => switch (device.updateType) {
      1 => FirmwareGateMode.force,
      2 => FirmwareGateMode.remind,
      _ => FirmwareGateMode.none,
    };

/// 判定结果的本地缓存（SharedPreferences `fw_gate_cache`，按设备 id）与本次启动的状态。
/// 本次启动查过才用缓存（[cached]），没查过返回 null 由调用方现查；强提醒本次启动弹过的设备记在 [_reminded]。
abstract final class FirmwareGateCache {
  static const String key = 'fw_gate_cache';
  static final Set<String> _verified = {};
  static final Set<String> _reminded = {};

  static Future<Map<String, dynamic>> _read() async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(key);
      final value = raw == null ? null : jsonDecode(raw);
      return value is Map<String, dynamic> ? value : <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  /// 记下这台设备的判定结果，并算作本次启动已查过。
  static Future<void> remember(String deviceId, FirmwareGateMode mode, String version) async {
    if (deviceId.isEmpty) {
      return;
    }
    _verified.add(deviceId);
    try {
      final cache = await _read();
      cache[deviceId] = {'mode': mode.name, 'version': version, 'at': DateTime.now().millisecondsSinceEpoch};
      await (await SharedPreferences.getInstance()).setString(key, jsonEncode(cache));
    } catch (_) {
      // 存不了下次启动再现查
    }
  }

  /// 升级完成：缓存改成无需升级。
  static Future<void> markUpgraded(String deviceId) => remember(deviceId, FirmwareGateMode.none, '');

  /// 本次启动查过才返回缓存的判定（mode, version）；没查过返回 null。
  static Future<(FirmwareGateMode, String)?> cached(String deviceId) async {
    if (!_verified.contains(deviceId)) {
      return null;
    }
    final entry = (await _read())[deviceId];
    if (entry is! Map) {
      return null;
    }
    final mode = FirmwareGateMode.values.firstWhere((item) => item.name == entry['mode'], orElse: () => FirmwareGateMode.none);
    return (mode, '${entry['version'] ?? ''}');
  }

  /// 强提醒本次启动是否还没弹过（第一次调用返回 true 并记下）。
  static bool takeRemind(String deviceId) => _reminded.add(deviceId);

  /// 模拟重新打开 App（测试用）。
  @visibleForTesting
  static void resetSession() {
    _verified.clear();
    _reminded.clear();
  }
}

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
  if (mode == FirmwareGateMode.none || (forceOnly && mode != FirmwareGateMode.force)) {
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
  FirmwareGateMode mode, {
  String? versionOverride,
}) async {
  if (mode == FirmwareGateMode.none) {
    return true;
  }
  final l10n = AppL10n.of(context);
  final force = mode == FirmwareGateMode.force;
  final latest = versionOverride ?? device.newVersionNo;
  final version = latest.trim().isNotEmpty ? latest.trim() : l10n.otaGateNewVersion;
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

/// 详情页进入时判断一次（强制 + 强提醒）：结果写进缓存；强制照弹，强提醒每台设备每次启动只弹一次。
/// 返回这次是否继续（同 [showFirmwareGateDialog]）。
Future<bool> checkFirmwareGateOnEnter(
  BuildContext context,
  PhotoFrameState state,
  DeviceItem device, {
  required bool ready,
  required bool hasUpdate,
  bool inflight = false,
}) async {
  final mode = decideFirmwareGate(device, ready: ready, hasUpdate: hasUpdate, inflight: inflight);
  if (ready) {
    unawaited(FirmwareGateCache.remember(device.id, mode, device.newVersionNo.trim()));
  }
  if (mode == FirmwareGateMode.remind && !FirmwareGateCache.takeRemind(device.id)) {
    return true;
  }
  if (mode == FirmwareGateMode.none || !context.mounted) {
    return true;
  }
  return showFirmwareGateDialog(context, state, device, mode);
}

/// 列表页 / 首页（只判强制升级）。本次启动没查过这台：显示 loading 现查一遍并写缓存；查过了直接按缓存判断，不再请求接口。
/// [online]：调用方已确认 WiFi 在线（首页），不看本地状态。返回这次操作是否继续。
Future<bool> guardFirmwareAction(BuildContext context, PhotoFrameState state, DeviceItem device, {bool online = false}) async {
  try {
    if (device.isWifi) {
      final deviceNo = IotApi.plainDeviceNo(device.serialNumber);
      if (deviceNo.isEmpty || await WifiOtaStore.read(deviceNo) != null) {
        return true;
      }
      final known = WifiStatusStore.instance.of(device.id).status;
      // 列表里已知不在线的不判（还在查 / 查不到的交给现查那一步）
      if (!online && known != WifiOnlineStatus.online && known != WifiOnlineStatus.loading && known != WifiOnlineStatus.unknown) {
        return true;
      }
    } else if (!state.isDeviceActuallyConnected(device.id)) {
      return true;
    }
    var hit = await FirmwareGateCache.cached(device.id);
    var target = device;
    if (hit == null) {
      if (!context.mounted) {
        return true;
      }
      AppLoadingDialog.show(context);
      try {
        final fetched = await _fetchFirmwareGate(state, device);
        if (fetched == null) {
          return true;
        }
        target = fetched.$1;
        hit = (fetched.$2, target.newVersionNo.trim());
        await FirmwareGateCache.remember(device.id, hit.$1, hit.$2);
      } finally {
        AppLoadingDialog.hideIfAny();
      }
    }
    final mode = hit.$1;
    if (mode != FirmwareGateMode.force || !context.mounted) {
      return true;
    }
    debugPrint('[固件升级] 拦截 ${target.isWifi ? 'WiFi' : '蓝牙'} ${target.id} $mode → ${hit.$2}');
    return await showFirmwareGateDialog(context, state, target, mode, versionOverride: hit.$2);
  } catch (error) {
    debugPrint('[固件升级] 判断失败，放行 $error');
    return true;
  }
}

/// 现查：WiFi 查 IoT 设备信息（在线 + 当前版本），蓝牙读当前版本；再拉设备详情拿最新版本与升级类型。
/// 不在线 / 查不到返回 null（不判、不写缓存）；返回（最新设备记录, 不带 forceOnly 的判定）。
Future<(DeviceItem, FirmwareGateMode)?> _fetchFirmwareGate(PhotoFrameState state, DeviceItem device) async {
  if (device.isWifi) {
    final status = await WifiStatusStore.instance.refresh(device);
    if (!status.online) {
      return null;
    }
    final fresh = await state.fetchDeviceFirmwareInfo(device.id);
    if (fresh == null) {
      return null;
    }
    return (fresh, decideFirmwareGate(fresh, ready: true, hasUpdate: wifiFirmwareHasUpdate(fresh, wifiFirmwareVersion(status.info))));
  }
  // 当前版本：本次会话没读过 0x03 时补读一次（读不到退回 isUpdate）
  await state.refreshConnectedDeviceInfo(device.id, includeFirmwareVersion: true);
  final fresh = await state.fetchDeviceFirmwareInfo(device.id);
  if (fresh == null) {
    return null;
  }
  return (fresh, decideFirmwareGate(fresh, ready: true, hasUpdate: bleFirmwareHasUpdate(fresh, bleLiveFirmwareVersion(fresh))));
}
