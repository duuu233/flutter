import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../serial_match.dart';

/// 本机 BLE「直连缓存」：`0x01 完整 6 字节设备 ID(归一化)` → `本机上次成功连上的 remoteId`。
///
/// 用途：已绑定设备复连时先按缓存的 remoteId 短超时直连，命中即**整段跳过扫描**
/// （见 `BleController.connectBoundDevice` 的快路径）。冷连接的耗时构成里，扫描是
/// 最大的一块——设备刚被 GATT 占过时要好几秒才恢复广播，而 `until` 命中即停也至少要
/// 等到下一个广播包（固件广播间隔约 3s）。直连没有这一段。
/// 对齐小程序 `utils/device-conn-cache.js` + `active-device.tryDirectConnect`（2026-07-21）。
///
/// **为什么存本机、不存后端**：remoteId 是「设备 × 手机」的函数——
/// Android 是射频 MAC（设备重置/隐私随机地址轮换后会变），iOS 是本机系统给外设生成的
/// UUID（换一部手机就不同）。存后端等于把 A 手机的句柄发给 B 手机，B 上拿它直连必然
/// 超时白等，比没有缓存更慢。SharedPreferences 天然按手机隔离，正好匹配这个句柄的语义。
///
/// **键为什么用 0x01 完整 ID**：它既是后端设备记录的稳定身份，也是连上后固件自报的物理身份，
/// 两者必须精确相等才算验身通过（见 `verifiedDeviceSerialMatch`）。用它当键，写入点就能
/// 收敛到「任何一次验身成功的连接」这一处，绑定页/详情页/自动重连三条入口全都覆盖。
///
/// **自愈**：缓存失效（设备重启/换机/地址轮换/离线）时直连快速失败并回落完整扫描；
/// 验身发现串台时删除该键并排除那个 remoteId。只有 0x01 完整 ID 校验通过才会写入。
class BleDirectConnectCache {
  BleDirectConnectCache._();

  static final BleDirectConnectCache instance = BleDirectConnectCache._();

  static const String _storageKey = 'ble_direct_conn_cache';

  /// 最多记住多少台设备。用户手上不会有几十个相框；上限只是防止异常写入把偏好文件撑大。
  /// 超限时丢弃最早写入的那条（插入序即淘汰序）。
  static const int maxEntries = 16;

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
            final serial = normalizeSerial(key);
            final remoteId = value is String ? value.trim() : '';
            if (isCompleteDeviceSerial(serial) && remoteId.isNotEmpty) {
              entries[serial] = remoteId;
            }
          });
        }
      }
    } catch (_) {
      // 读不到就当没有缓存：走完整扫描，功能不缺、只是不省那一次。
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
      // 落盘失败不影响本次连接，内存镜像仍然有效。
    }
  }

  /// 取这台设备上次直连成功的 remoteId；无缓存返回空串。
  Future<String> get(Object? serial) async {
    final key = normalizeSerial(serial);
    if (!isCompleteDeviceSerial(key)) {
      return '';
    }
    final entries = await _load();
    return entries[key] ?? '';
  }

  /// 记住这台设备本次有效的 remoteId（值未变则不写盘）。
  /// 只应在 0x01 完整 ID 验身通过后调用。
  Future<void> put(Object? serial, String remoteId) async {
    final key = normalizeSerial(serial);
    final value = remoteId.trim();
    if (!isCompleteDeviceSerial(key) || value.isEmpty) {
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

  /// 删除这台设备的缓存：直连探测失败、验身发现串台、或删除设备记录时调用。
  Future<void> remove(Object? serial) async {
    final key = normalizeSerial(serial);
    if (key.isEmpty) {
      return;
    }
    final entries = await _load();
    if (entries.remove(key) == null) {
      return;
    }
    await _flush(entries);
  }

  /// 仅供测试：丢弃内存镜像，强制下次从磁盘重读。
  void resetForTest() {
    _entries = null;
  }
}
