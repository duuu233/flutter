import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'serial_match.dart';

/// 设备稳定身份登记表：`后端设备记录主键(userProductId)` → `完整 6 字节 Device_ID`。
/// 移植自小程序 `utils/device-identity.js`（2026-07-30），对齐
/// `photo-album/docs/architecture/device-identity-and-connection.md`「身份补齐来源」。
///
/// **为什么需要它**：`connectBoundDevice` 的第一行就是身份闸——
/// `isCompleteDeviceSerial(serial)` 不过就直接返回「请删除后重新绑定」，**连扫描都不发起**。
/// 这道闸本身是对的（缺完整 ID 时用短 ID/名称/尺寸兜底连接必然串台），错的是
/// 「设备明明有完整 ID，只是这一刻没人把它交到调用方手上」。
///
/// Flutter 侧的漏口在 `refreshDevices`：设备列表整体替换，`_carryOverBleFields` 搬的是
/// 电量/固件/播放模式，**唯独不搬 `serialNumber`**。所以只要某次列表接口返回的行缺
/// `deviceId`（后端抖动、历史短 ID 记录），此前 0x01 验身拿到的完整 ID 就当场丢失，
/// 之后这台好设备的每一次连接都会被身份闸拦下——一整类「连不上」，与射频毫无关系。
/// 小程序 2026-07-30 已用同一张表修掉，其变更记录里明写「Flutter 未同步」。
///
/// **取值顺序固定，登记表只作最后兜底、永不反向覆盖后端最新值**：
/// ```text
/// 记录自身的完整 ID  >  本地上一版记录（_carryOverBleFields）  >  登记表
/// ```
///
/// **只收完整 6 字节 ID**：广播 4 字节短 ID、BLE 临时句柄一律不进表，否则等于把
/// 「只能筛候选的短 ID」升格成身份，正是 EF6-370 串到 EF6-589 那类故障的来源。
///
/// **键只取记录自己的主键**，不接受调用方传进来的「另一台的 id」——那等于用登记表制造串台。
///
/// **存本机**：`userProductId` 是后端主键，换账号后与新用户无关，故退出登录整表清空
/// （`clear`）、解绑单条清除（`forget`），避免主键复用把旧身份带回来。
class DeviceIdentityRegistry {
  DeviceIdentityRegistry._();

  static final DeviceIdentityRegistry instance = DeviceIdentityRegistry._();

  static const String _storageKey = 'device_identity_map';

  /// 上限只是防止异常写入把偏好文件撑大；超限丢弃最早写入的那条。
  static const int maxEntries = 64;

  /// 内存镜像。null = 尚未从磁盘读回。
  Map<String, String>? _entries;

  Future<Map<String, String>> _load() async {
    final cached = _entries;
    if (cached != null) {
      return cached;
    }
    final entries = <String, String>{};
    try {
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getString(_storageKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          decoded.forEach((key, value) {
            final id = '$key'.trim();
            final serial = value is String ? canonicalDeviceSerial(value) : '';
            // 磁盘脏数据（历史短 ID / 全 0 / 非法格式）读回时一并过滤：
            // 表里只能有完整 6 字节 ID，否则兜底反而会把串台身份喂给身份闸。
            if (id.isNotEmpty && serial.isNotEmpty) {
              entries[id] = serial;
            }
          });
        }
      }
    } catch (_) {
      // 偏好不可用/存储损坏：降级为纯内存，功能不缺，只是不跨启动保留。
    }
    _entries = entries;
    return entries;
  }

  Future<void> _flush(Map<String, String> entries) async {
    try {
      final sp = await SharedPreferences.getInstance();
      if (entries.isEmpty) {
        await sp.remove(_storageKey);
        return;
      }
      await sp.setString(_storageKey, jsonEncode(entries));
    } catch (_) {
      // 落盘失败不影响本次会话：内存镜像仍可用。
    }
  }

  /// 取这台后端记录已登记的完整 ID（`AA:BB:CC:DD:EE:FF`）；没有返回空串。
  Future<String> recall(Object? recordId) async {
    final key = '${recordId ?? ''}'.trim();
    if (key.isEmpty) {
      return '';
    }
    final entries = await _load();
    return entries[key] ?? '';
  }

  /// 登记这台后端记录的完整 ID。不完整一律忽略；值未变不写盘。
  ///
  /// 调用时机（与小程序一致）：设备列表接口返回记录时、连接后 0x01 验身通过时。
  Future<void> remember(Object? recordId, Object? serial) async {
    final key = '${recordId ?? ''}'.trim();
    final value = canonicalDeviceSerial(serial);
    if (key.isEmpty || value.isEmpty) {
      return;
    }
    final entries = await _load();
    if (entries[key] == value) {
      return;
    }
    entries[key] = value;
    while (entries.length > maxEntries) {
      entries.remove(entries.keys.first);
    }
    await _flush(entries);
  }

  /// 解绑设备时清掉，避免后端主键复用时把旧身份带回来。
  Future<void> forget(Object? recordId) async {
    final key = '${recordId ?? ''}'.trim();
    if (key.isEmpty) {
      return;
    }
    final entries = await _load();
    if (entries.remove(key) == null) {
      return;
    }
    await _flush(entries);
  }

  /// 退出登录 / 注销：整表清空（下一位用户的设备与这批 userProductId 无关）。
  Future<void> clear() async {
    _entries = <String, String>{};
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.remove(_storageKey);
    } catch (_) {
      // 清不掉不影响使用：内存已空，且 recall 只在记录自身缺 ID 时才被采纳。
    }
  }

  /// 仅供测试：丢弃内存镜像，强制下次从磁盘重读。
  void resetForTest() {
    _entries = null;
  }
}
