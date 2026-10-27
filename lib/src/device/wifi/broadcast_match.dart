/// 蓝牙广播名 ↔ 后台产品广播 ID（产品列表 `broadcastId`）的匹配规则（WiFi 版接入，同步小程序
/// `utils/broadcast-match.js`，改一端必须同步另一端）。
///
/// 后台配置两种写法：
///   · 蓝牙版：固定广播名，如 `EF6-370`、`EB-169`；
///   · WiFi 版：带 `*` 的模板，如 `IJ_*`。按 `*` 拆成前缀 / 后缀，广播名前后缀都对上、且被 `*`
///     替换的中间部分**正好 12 位**才算命中，中间这 12 位就是设备 deviceNo（= MQTT clientid，
///     例 `IJ_E348C21ED428` → `E348C21ED428`）。
///
/// 只认广播名，不依赖 MAC（iOS 拿不到 MAC）。大小写不敏感；deviceNo 统一转大写。
///
/// 内置 WiFi 模板 `IJ_*`：WiFi 前缀按对接约定固定为 `IJ_`。广播名合这个模板的一律认作 WiFi 设备，
/// 不看后台把广播 ID 写成 `IJ_*`、`IJ_` 还是别的——写成不带 `*` 的 `IJ_` 时，蓝牙版的包含匹配会把它
/// 当蓝牙设备，既不查规格、也拦不住未知设备。后台另配的其它 `*` 模板照样生效（先于内置模板）。
///
/// ⚠️ 蓝牙版沿用「包含匹配」（广播名里含该广播 ID 即命中），与扫描白名单、搜索列表尺寸
/// （[ProductBroadcastId.sizeModelOfScan]）同一口径。WiFi 模板不参与包含匹配。
library;

/// 设备记录 / 扫描结果的通信类型。
enum CommType { wifi, ble }

/// WiFi 模板命中结果：命中的模板与解析出的 12 位 deviceNo（不带冒号）。
typedef WifiMatch = ({String broadcastId, String wifiDeviceNo});

abstract final class BroadcastMatch {
  static const int wifiDeviceNoLength = 12;
  static final RegExp _wifiDeviceNo = RegExp(r'^[0-9A-Z]{12}$');

  static const String builtinWifiTemplate = 'IJ_*';

  static String _normalize(Object? value) =>
      (value ?? '').toString().trim().toUpperCase();

  /// 是否为 WiFi 模板（含 `*`）。扫描白名单的包含匹配要跳过这类 ID。
  static bool isWildcard(String broadcastId) =>
      _normalize(broadcastId).contains('*');

  /// 单条模板匹配：命中返回 12 位 deviceNo，否则空串。模板里多于一个 `*` 视为配置错误，不匹配。
  static String matchWildcard(String name, String broadcastId) {
    final parts = _normalize(broadcastId).split('*');
    if (parts.length != 2) {
      return '';
    }
    final text = _normalize(name);
    final prefix = parts[0];
    final suffix = parts[1];
    if (text.length != prefix.length + suffix.length + wifiDeviceNoLength) {
      return '';
    }
    if (!text.startsWith(prefix) || !text.endsWith(suffix)) {
      return '';
    }
    final middle = text.substring(prefix.length, text.length - suffix.length);
    return _wifiDeviceNo.hasMatch(middle) ? middle : '';
  }

  /// WiFi 设备识别：先按后台配置的 `*` 模板，再按内置 `IJ_*`。[names] 为广播里能拿到的名字
  /// （platformName / advName），命中返回 [WifiMatch]，否则 null。
  static WifiMatch? wifiMatch(Iterable<String> names, Iterable<String> broadcastIds) {
    final templates = [
      ...broadcastIds.map(_normalize).where(isWildcard),
      builtinWifiTemplate,
    ];
    final candidates = names.where((name) => name.trim().isNotEmpty).toList();
    for (final template in templates) {
      for (final name in candidates) {
        final deviceNo = matchWildcard(name, template);
        if (deviceNo.isNotEmpty) {
          return (broadcastId: template, wifiDeviceNo: deviceNo);
        }
      }
    }
    return null;
  }

  /// 已绑定设备记录是不是 WiFi 版（我的设备分组、首页、投屏入口用）：看所属产品的 broadcastId——
  /// WiFi 产品后台配的是带 `*` 的模板（如 `IJ_*`），也认写成 `IJ_` 前缀的；蓝牙版是固定广播名。
  static bool isWifiBroadcastId(String broadcastId) {
    final id = _normalize(broadcastId);
    return id.isNotEmpty &&
        (isWildcard(id) || id.startsWith(builtinWifiTemplate.replaceAll('*', '')));
  }
}

/// 信号强度 → 信号格数（仿 iPhone 信号格：满格 4 格、最弱 1 格、未知 0 格全灰），与小程序
/// `utils/signal.js` 同一组门槛（与 [BleController.rssiToSignalLevel] 的文字档位一致）：
///   ≥ -55dBm → 4 格；≥ -67 → 3 格；≥ -78 → 2 格；更弱 → 1 格；缺省(0) / 非法(≥0) → 0 格。
/// 蓝牙广播 RSSI（搜索设备列表）和设备扫到的 WiFi RSSI（WiFi 列表）都按这一套显示。
int rssiToBars(num? rssi) {
  if (rssi == null || rssi == 0 || rssi >= 0) {
    return 0;
  }
  if (rssi >= -55) return 4;
  if (rssi >= -67) return 3;
  if (rssi >= -78) return 2;
  return 1;
}
