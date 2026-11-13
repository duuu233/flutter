import '../../network/boltfox_api.dart';
import '../../network/api_rows.dart';

// WiFi 版「渲染固件管理」（2026-11-13，同小程序 utils/fpga-firmware.js）：只有产品渲染模式 = fpga16 的设备才有（目前只有 10.1 寸）。
//
//   · 设备详情 → 设备信息 → 「渲染固件管理」：列出后台「FPGA版本」里启用的版本（版本号、简介、安装），未启用的不显示；
//   · 点「安装」进安装步骤页 = WifiOtaPage(fpgaTarget: 该版本)：版式、进度条、四步状态全部复用，只改文字、带出简介；
//   · 下发复用 POST /api/device/ota，type=fpga、version = FPGA 目标版本、url = 该版本固件地址；
//     返回值、进度字段、四步交互、本地进行中记录（ota_inflight:{deviceNo}）都与固件升级一致，不单独判断状态。
//
// ⚠️ 用户端列出 FPGA 版本的接口后端还没提供（2026-11-13 核对 Swagger 只有后台 /ZoneAdmin/ProductVersionFpga/*）。
//    接口路径集中在 [kWifiFpgaListApi] 一处，后端给出后填上即可；为空时列表页显示「版本列表暂未开放」，不发请求。
//    简介字段后台也还没有，按 [kWifiFpgaIntroFields] 依次兜底，后端定了字段名后放到第一个。

const String kWifiFpgaListApi = ''; // 例：'/Client/Product/getProductVersionFpgaList'（入参 productId）——待后端提供
const List<String> kWifiFpgaIntroFields = ['versionDesc', 'description', 'desc', 'intro', 'remark', 'upgradeTips', 'content'];
const String kWifiOtaTypeFpga = 'fpga';

bool isFpgaRenderMode(Object? renderMode) => '${renderMode ?? ''}'.trim().toLowerCase() == 'fpga16';

bool wifiFpgaListApiReady() => kWifiFpgaListApi.isNotEmpty;

class WifiFpgaVersion {
  const WifiFpgaVersion({required this.id, required this.version, this.intro = '', this.url = '', this.grade = 0});

  final String id;
  final String version;
  final String intro;
  final String url;
  final int grade;

  bool get hasValidUrl => RegExp(r'^https?://\S+$', caseSensitive: false).hasMatch(url.trim());
}

String _text(Object? value) => value == null ? '' : '$value'.trim();

String wifiFpgaIntroOf(Map row) {
  for (final key in kWifiFpgaIntroFields) {
    final value = _text(row[key]);
    if (value.isNotEmpty) {
      return value;
    }
  }
  return '';
}

/// 接口行 → [WifiFpgaVersion]；未启用（verify 明确不为 1）的去掉，按权重从大到小。
List<WifiFpgaVersion> normalizeWifiFpgaVersions(Iterable<Object?> rows) {
  final list = <WifiFpgaVersion>[];
  for (final raw in rows) {
    if (raw is! Map) {
      continue;
    }
    final version = _text(raw['versionNumber'] ?? raw['version']);
    final verify = raw['verify'];
    if (version.isEmpty || (verify != null && '$verify'.trim() != '1')) {
      continue;
    }
    list.add(WifiFpgaVersion(
      id: _text(raw['id']).isNotEmpty ? _text(raw['id']) : version,
      version: version,
      intro: wifiFpgaIntroOf(raw),
      url: _text(raw['downloadPath'] ?? raw['url']),
      grade: int.tryParse(_text(raw['grade'])) ?? 0,
    ));
  }
  list.sort((a, b) => b.grade.compareTo(a.grade));
  return list;
}

/// 拉某产品启用的 FPGA 版本；接口未配置时返回 pending=true。
Future<({bool pending, List<WifiFpgaVersion> list})> fetchWifiFpgaVersions(Object productId) async {
  if (!wifiFpgaListApiReady()) {
    return (pending: true, list: const <WifiFpgaVersion>[]);
  }
  final data = await BoltFoxApi.getFpgaVersionList(kWifiFpgaListApi, productId: productId);
  final rows = data is List ? data.cast<Object?>() : extractApiRows(data);
  return (pending: false, list: normalizeWifiFpgaVersions(rows));
}
