import '../../network/iot/iot_client.dart';
import '../../state.dart';

// WiFi 版「优雅刷新升级」（2026-11-13，原名渲染固件管理；同小程序 utils/fpga-firmware.js）：只有产品渲染模式 = fpga16 的设备才有（目前只有 10.1 寸）。
//
//   · 最新版本只读设备详情（getUserProductDetail）：newVersionNoFpga / downloadPathFpga / upgradeTipsFpga（版本说明），
//     映射在 DeviceItem.fpgaVersionNo / fpgaDownloadPath / fpgaUpgradeTips；不做版本列表。
//   · 不做红点（2026-11-14 产品要求）：原「看过的版本号」本地缓存 fpga_seen 与 WiFi 详情「设备信息」、设备信息页入口两处红点一并去掉。
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
