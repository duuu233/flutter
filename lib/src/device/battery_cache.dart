import 'dart:async';

/// 一次有效的设备电量读数。
///
/// 电量 0 是合法值；是否“已读取过”由 [updatedAt] 表示，不能再用 `value > 0`
/// 判断，否则真机 0% 会被错误地替换成旧值或默认值。
class DeviceBatteryReading {
  const DeviceBatteryReading({required this.value, required this.updatedAt});

  final int value;
  final DateTime updatedAt;
}

/// 设备电量的短时缓存与并发读取合并。
///
/// 对齐小程序 `utils/battery.js`：
/// - 同一物理设备 15 秒内直接复用最近有效值；
/// - 超过 TTL 后读取真机，失败或返回非法值时保留旧值；
/// - 同一设备并发刷新只发起一次 BLE 读取；
/// - 从未成功读取过时返回 null，由页面显示 `--`。
class DeviceBatteryCache {
  DeviceBatteryCache({
    this.ttl = const Duration(seconds: 15),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final Duration ttl;
  final DateTime Function() _now;
  final Map<String, DeviceBatteryReading> _values =
      <String, DeviceBatteryReading>{};
  final Map<String, Future<DeviceBatteryReading?>> _inFlight =
      <String, Future<DeviceBatteryReading?>>{};
  int _generation = 0;

  DeviceBatteryReading? peek(String key) => _values[key];

  void remember(String key, DeviceBatteryReading reading) {
    if (key.isEmpty || !_isValid(reading.value)) {
      return;
    }
    final current = _values[key];
    if (current == null || !reading.updatedAt.isBefore(current.updatedAt)) {
      _values[key] = reading;
    }
  }

  Future<DeviceBatteryReading?> readLatest({
    required String key,
    required Future<int> Function() read,
    DeviceBatteryReading? fallback,
    bool force = false,
  }) {
    if (key.isEmpty) {
      return Future<DeviceBatteryReading?>.value(fallback);
    }
    if (fallback != null) {
      remember(key, fallback);
    }
    final cached = _values[key];
    if (!force && cached != null && _now().difference(cached.updatedAt) < ttl) {
      return Future<DeviceBatteryReading?>.value(cached);
    }
    final running = _inFlight[key];
    if (running != null) {
      return running;
    }

    final future = _readAndRemember(
      key: key,
      read: read,
      generation: _generation,
    );
    _inFlight[key] = future;
    future.whenComplete(() {
      if (identical(_inFlight[key], future)) {
        _inFlight.remove(key);
      }
    });
    return future;
  }

  Future<DeviceBatteryReading?> _readAndRemember({
    required String key,
    required Future<int> Function() read,
    required int generation,
  }) async {
    try {
      final value = await read();
      if (generation != _generation) {
        return null;
      }
      if (!_isValid(value)) {
        return _values[key];
      }
      final reading = DeviceBatteryReading(value: value, updatedAt: _now());
      _values[key] = reading;
      return reading;
    } catch (_) {
      return _values[key];
    }
  }

  void clear() {
    _generation += 1;
    _values.clear();
    _inFlight.clear();
  }

  static bool _isValid(int value) => value >= 0 && value <= 100;
}
