import 'package:shared_preferences/shared_preferences.dart';

import '../../network/iot/iot_api.dart';
import '../../network/iot/iot_client.dart';
import '../../state.dart';

// WiFi 版「优雅刷新升级」（2026-11-13，原名渲染固件管理；同小程序 utils/fpga-firmware.js）：只有产品渲染模式 = fpga16 的设备才有（目前只有 10.1 寸）。
//
//   · 最新版本只读设备详情（getUserProductDetail）：newVersionNoFpga / downloadPathFpga / upgradeTipsFpga（版本说明），
//     映射在 DeviceItem.fpgaVersionNo / fpgaDownloadPath / fpgaUpgradeTips；不做版本列表（产品改为红点提醒）。
//   · 红点：本地缓存「看过的版本号」fpga_seen:{deviceNo}。最新版本存在、下载地址有效，且缓存为空或最新版本更高 → 亮红点：
//     WiFi 详情「设备信息」行、设备信息页「优雅刷新升级」行；进入优雅刷新升级页（看到了版本）就记下版本号，红点消失。
//     缓存只在本机，重装 / 换手机会再提醒一次（产品接受）。
//   · 点「优雅刷新升级」直接进安装步骤页 = WifiOtaPage(fpga: true)：版式、进度条、四步状态全部复用，只改文字并显示版本说明；
//     下发复用 POST /api/device/ota，type=fpga、version = 最新版本、url = fpgaDownloadPath。
//   · 设备不上报 FPGA 版本（ota/status 的 baseVersion 为 null），不显示设备当前版本；
//   · 下发返回 4047 = 今日升级次数已达上限（[isWifiFpgaLimitError]），提示 wifiFpgaLimit。

const String kWifiOtaTypeFpga = 'fpga';

bool isFpgaRenderMode(Object? renderMode) => '${renderMode ?? ''}'.trim().toLowerCase() == 'fpga16';

/// 4047：POST /api/device/ota（type=fpga）当日升级次数已达上限（2026-11-13 服务端新增）。
const int kWifiFpgaLimitCode = 4047;

bool isWifiFpgaLimitError(Object error) => error is IotException && int.tryParse('${error.code}') == kWifiFpgaLimitCode;

/// 设备详情里的最新优雅刷新版本。
class WifiFpgaVersion {
  const WifiFpgaVersion({required this.version, this.url = '', this.intro = ''});

  final String version;
  final String url;

  /// 版本说明（upgradeTipsFpga）。
  final String intro;

  bool get hasValidUrl => RegExp(r'^https?://\S+$', caseSensitive: false).hasMatch(url.trim());
}

/// 没有版本号返回 null。
WifiFpgaVersion? wifiFpgaLatestOf(DeviceItem device) {
  final version = device.fpgaVersionNo.trim();
  if (version.isEmpty) {
    return null;
  }
  return WifiFpgaVersion(version: version, url: device.fpgaDownloadPath.trim(), intro: device.fpgaUpgradeTips.trim());
}

List<int>? _versionParts(String value) {
  final match = RegExp(r'^[vV]?(\d+(?:\.\d+){0,3})$').firstMatch(value.trim());
  return match?.group(1)!.split('.').map(int.parse).toList();
}

/// 版本比较：都是 x.y.z（可带 v）按数字段比；否则不区分大小写比较，不同即算更新。[seen] 为空算新。
bool isWifiFpgaNewer(String latest, String seen) {
  if (seen.trim().isEmpty) {
    return true;
  }
  final a = _versionParts(latest);
  final b = _versionParts(seen);
  if (a != null && b != null) {
    final length = a.length > b.length ? a.length : b.length;
    for (var i = 0; i < length; i++) {
      final x = i < a.length ? a[i] : 0;
      final y = i < b.length ? b[i] : 0;
      if (x != y) {
        return x > y;
      }
    }
    return false;
  }
  return latest.trim().toLowerCase() != seen.trim().toLowerCase();
}

/// 本机看过的优雅刷新版本号（fpga_seen:{deviceNo}，同小程序）。
abstract final class WifiFpgaSeenStore {
  static String key(String deviceNo) => 'fpga_seen:${IotApi.plainDeviceNo(deviceNo)}';

  static Future<String> read(String deviceNo) async {
    if (IotApi.plainDeviceNo(deviceNo).isEmpty) {
      return '';
    }
    try {
      final sp = await SharedPreferences.getInstance();
      return (sp.getString(key(deviceNo)) ?? '').trim();
    } catch (_) {
      return '';
    }
  }

  static Future<void> mark(String deviceNo, String version) async {
    if (IotApi.plainDeviceNo(deviceNo).isEmpty || version.trim().isEmpty) {
      return;
    }
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(key(deviceNo), version.trim());
    } catch (_) {
      // 存不了下次还会亮红点
    }
  }
}

/// 要不要亮红点：fpga16 设备（renderMode 由调用方查好）、有最新版本且下载地址有效、比本机看过的版本新。
Future<bool> wifiFpgaHasNew(DeviceItem device, String renderMode) async {
  if (!isFpgaRenderMode(renderMode)) {
    return false;
  }
  final latest = wifiFpgaLatestOf(device);
  if (latest == null || !latest.hasValidUrl) {
    return false;
  }
  return isWifiFpgaNewer(latest.version, await WifiFpgaSeenStore.read(device.serialNumber));
}
