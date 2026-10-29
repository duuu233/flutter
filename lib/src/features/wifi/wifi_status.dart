import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../device/wifi/broadcast_match.dart';
import '../../network/iot/iot_api.dart';
import '../../shared/l10n/app_l10n.dart';
import '../../shared/widgets/app_toast.dart';
import '../../state.dart';
import 'wifi_l10n.dart';

/// WiFi 版设备的云端状态：loading 查询中 / online 在线 / sleeping 休眠中 / shutdown 已关机 / offline 离线 /
/// unknown 查不到（403 未绑定、503、网络失败等）。同小程序 `utils/wifi-status.js`：
///   · 休眠中（休眠状态对接说明）：接口与 WS 新增 status=ONLINE / OFFLINE / SLEEPING，SLEEPING 时 online=false；
///     旧服务端没有 status 时按 online 回退。休眠中设备收不到指令（接口仍回 4041），入口提示「设备休眠中，唤醒后可操作」；
///   · 已关机（V1.4 更新说明三）：status=SHUTDOWN（灰色「已关机」），开机重新登录后恢复 ONLINE。
///     优先级 ONLINE > SHUTDOWN > SLEEPING > OFFLINE 由服务端算好，前端照抄。
///   · 本地模式（2026-10-29 前端对接变更说明）：设备切到 TF 卡本地播放后 status=LOCAL_TF（online=false），
///     显示「本地模式」，远程操作一律提示「当前设备状态：本地模式，请恢复设备网络再试」；恢复只能在设备端重新入网。
///     优先级 ONLINE > SHUTDOWN > LOCAL_TF > SLEEPING > OFFLINE。同一文档：不认识的新状态值按「状态未知」降级。
enum WifiOnlineStatus { loading, online, sleeping, shutdown, local, offline, unknown }

/// 休眠中蓝（同小程序 `.is-sleeping`）。
const Color kWifiSleepBlue = Color(0xFF2F80ED);

/// 本地模式紫（同小程序 `.is-local`）。
const Color kWifiLocalPurple = Color(0xFF8E5BD9);

/// 接口 / WS 返回 → online / sleeping / shutdown / local / offline / unknown：认 status；
/// 没有 status（旧服务端）按 online 回退；有但不认识按「状态未知」降级（2026-10-29 对接文档一.4）。
WifiOnlineStatus wifiDeviceState(Map<String, dynamic>? info) {
  final status = '${info?['status'] ?? ''}'.trim().toUpperCase();
  switch (status) {
    case 'ONLINE':
      return WifiOnlineStatus.online;
    case 'SLEEPING':
      return WifiOnlineStatus.sleeping;
    case 'SHUTDOWN':
      return WifiOnlineStatus.shutdown;
    case 'OFFLINE':
      return WifiOnlineStatus.offline;
    case 'LOCAL_TF':
      return WifiOnlineStatus.local;
  }
  if (status.isNotEmpty) {
    return WifiOnlineStatus.unknown;
  }
  return info?['online'] == true ? WifiOnlineStatus.online : WifiOnlineStatus.offline;
}

/// 不能操作时的提示（本地模式 / 休眠 / 关机 / 离线）；其余返回空串。
String wifiBlockedTip(AppL10n l10n, WifiOnlineStatus status) => switch (status) {
  WifiOnlineStatus.local => l10n.wifiLocalTip,
  WifiOnlineStatus.sleeping => l10n.wifiSleepingTip,
  WifiOnlineStatus.shutdown => l10n.wifiShutdownTip,
  WifiOnlineStatus.offline => l10n.wifiOfflineTip,
  _ => '',
};

/// 一台 WiFi 版设备的云端状态（不走蓝牙：在线 / 信号 / 电量都来自 IoT GET /api/device/info）。
@immutable
class WifiDeviceStatus {
  const WifiDeviceStatus(this.status, {this.signalBars = 0, this.battery, this.info = const {}});

  static const WifiDeviceStatus loading = WifiDeviceStatus(WifiOnlineStatus.loading);
  static const WifiDeviceStatus unknown = WifiDeviceStatus(WifiOnlineStatus.unknown);

  final WifiOnlineStatus status;

  /// 信号格 0~4（离线 / 未知为 0）。
  final int signalBars;

  /// 电量 0~100（离线 / 未知 / 读不到为 null）。
  final int? battery;

  /// 设备信息原文（详情页展示影子字段用）。
  final Map<String, dynamic> info;

  bool get online => status == WifiOnlineStatus.online;

  Map<String, dynamic> get shadow {
    final raw = info['shadow'];
    return raw is Map ? raw.map((k, v) => MapEntry(k.toString(), v)) : const <String, dynamic>{};
  }

  /// 设备信息 → 卡片状态（与小程序 `utils/wifi-status.js statusFields` 同口径）：只有在线才显示信号与电量。
  factory WifiDeviceStatus.fromInfo(Map<String, dynamic> info) {
    final state = wifiDeviceState(info);
    final online = state == WifiOnlineStatus.online;
    final shadowRaw = info['shadow'];
    final shadow = shadowRaw is Map ? shadowRaw : const {};
    return WifiDeviceStatus(
      state,
      signalBars: online ? rssiToBars(num.tryParse('${shadow['wifiRssi'] ?? ''}')) : 0,
      battery: online ? normalizeBattery(shadow['battery']) : null,
      info: info,
    );
  }

  /// 电量归一：0~100 的数字（四舍五入），其余为 null。0% 是合法值。
  static int? normalizeBattery(Object? value) {
    final number = num.tryParse('${value ?? ''}');
    if (number == null || number < 0 || number > 100) {
      return null;
    }
    return number.round();
  }

  String text(AppL10n l10n) => switch (status) {
    WifiOnlineStatus.loading => l10n.wifiStatusLoading,
    WifiOnlineStatus.online => l10n.wifiStatusOnline,
    WifiOnlineStatus.sleeping => l10n.wifiStatusSleeping,
    WifiOnlineStatus.shutdown => l10n.wifiStatusShutdown,
    WifiOnlineStatus.local => l10n.wifiStatusLocal,
    WifiOnlineStatus.offline => l10n.wifiStatusOffline,
    WifiOnlineStatus.unknown => l10n.wifiStatusUnknown,
  };
}

/// WiFi 版设备状态的全局缓存：我的设备、首页设备卡、详情页共用。
///
/// 重新进页面先沿用上一次查到的状态（避免每次都闪「查询中」），查询回来再替换；
/// 每台各自带序号，旧请求晚到不覆盖新结果；失败显示「状态未知」，不弹错误。
class WifiStatusStore extends ChangeNotifier {
  WifiStatusStore._();

  static final WifiStatusStore instance = WifiStatusStore._();

  final Map<String, WifiDeviceStatus> _byId = <String, WifiDeviceStatus>{};
  final Map<String, int> _seq = <String, int>{};

  /// 某台的状态；还没查过为「查询中」。
  WifiDeviceStatus of(String deviceId) => _byId[deviceId] ?? WifiDeviceStatus.loading;

  /// 重查一台。[showLoading]=true 时先置「查询中」（「刷新状态」按钮），否则沿用上一次的结果。
  Future<WifiDeviceStatus> refresh(DeviceItem device, {bool showLoading = false}) async {
    final key = device.id;
    final seq = (_seq[key] ?? 0) + 1;
    _seq[key] = seq;
    if (showLoading || !_byId.containsKey(key)) {
      _byId[key] = WifiDeviceStatus.loading;
      notifyListeners();
    }
    WifiDeviceStatus next;
    try {
      next = WifiDeviceStatus.fromInfo(await IotApi.getDeviceInfo(device.serialNumber));
    } catch (error) {
      debugPrint('[WiFi状态] 查询失败 ${device.id} $error');
      next = WifiDeviceStatus.unknown;
    }
    if (_seq[key] == seq) {
      _byId[key] = next;
      notifyListeners();
    }
    return next;
  }

  /// 重查列表里全部 WiFi 版设备（各自独立，不互相等）。[deviceNos] 给了只查这几台（不带冒号的 deviceNo，推送用）。
  void refreshAll(Iterable<DeviceItem> devices, {Set<String>? deviceNos}) {
    for (final device in devices) {
      if (device.isWifi && (deviceNos == null || deviceNos.contains(IotApi.plainDeviceNo(device.serialNumber)))) {
        refresh(device);
      }
    }
  }

  /// 换账号时清空（状态属于上一个账号的设备）。
  void clear() {
    _byId.clear();
    _seq.clear();
    notifyListeners();
  }
}

/// 投屏入口用：确认 WiFi 版设备在线才往下走。明确离线 / 休眠 / 关机时提示并返回 false；
/// 查不到（503 / 网络等）放行，由投屏接口裁决（离线回 4041）。
Future<bool> ensureWifiDeviceOnline(BuildContext context, DeviceItem device) async {
  WifiOnlineStatus state;
  try {
    state = wifiDeviceState(await IotApi.getDeviceOnline(device.serialNumber));
  } catch (_) {
    return true;
  }
  if (!context.mounted) {
    return false;
  }
  final tip = wifiBlockedTip(AppL10n.of(context), state);
  if (tip.isNotEmpty) {
    AppToast.warn(context, tip);
    return false;
  }
  return true;
}

/// 接口回 4041 时补查一次在线状态：休眠中 / 已关机的设备也回 4041，此时改成对应提示；查不到返回离线提示。
Future<String> wifiOfflineTipFor(AppL10n l10n, String deviceNo) async {
  try {
    final tip = wifiBlockedTip(l10n, wifiDeviceState(await IotApi.getDeviceOnline(deviceNo)));
    return tip.isNotEmpty ? tip : l10n.wifiOfflineTip;
  } catch (_) {
    return l10n.wifiOfflineTip;
  }
}

/// 投屏严格口径（2026-10-29 同小程序 `projectBlockedTip`：我的相册再次投屏、预览页「开始投屏」）：
/// 只放行在线；离线 / 本地模式 / 查不到（状态未知）一律「设备不在线」，休眠 / 关机沿用各自提示。
/// 返回给用户看的提示，可投时返回空串。
Future<String> wifiProjectBlockedTip(AppL10n l10n, DeviceItem device) async {
  WifiOnlineStatus state;
  try {
    state = wifiDeviceState(await IotApi.getDeviceOnline(device.serialNumber));
  } catch (_) {
    state = WifiOnlineStatus.unknown;
  }
  return switch (state) {
    WifiOnlineStatus.online => '',
    WifiOnlineStatus.sleeping || WifiOnlineStatus.shutdown => wifiBlockedTip(l10n, state),
    _ => l10n.wifiNotOnlineTip,
  };
}

/// 保存类操作前查一次（轮播保存，2026-10-29）：明确不可操作给对应提示；查不到返回空串，交给接口裁决。
Future<String> wifiQueryBlockedTip(AppL10n l10n, String deviceNo) async {
  try {
    return wifiBlockedTip(l10n, wifiDeviceState(await IotApi.getDeviceOnline(deviceNo)));
  } catch (_) {
    return '';
  }
}

/// 选择投屏设备列表（AI 生图、官方图库，2026-10-29 同小程序 `filterPickable`）：WiFi 版查一次状态，
/// 离线 / 本地模式 / 状态未知的不进列表；休眠 / 关机保留（点了沿用原提示），蓝牙版原样保留。
Future<List<DeviceItem>> filterPickableDevices(List<DeviceItem> devices) async {
  const hidden = {WifiOnlineStatus.offline, WifiOnlineStatus.local, WifiOnlineStatus.unknown};
  final keep = await Future.wait(
    devices.map((device) async {
      if (!device.isWifi) {
        return true;
      }
      final status = await WifiStatusStore.instance.refresh(device);
      return !hidden.contains(status.status);
    }),
  );
  return [for (var i = 0; i < devices.length; i++) if (keep[i]) devices[i]];
}
