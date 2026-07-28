import 'dart:async';

import 'package:BoltStar/src/device/battery_cache.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late DateTime now;
  late DeviceBatteryCache cache;

  setUp(() {
    now = DateTime.utc(2026, 7, 28, 10);
    cache = DeviceBatteryCache(now: () => now);
  });

  test('15 秒内复用有效值且 0% 也是合法电量', () async {
    var reads = 0;
    Future<int> read() async {
      reads += 1;
      return 0;
    }

    final first = await cache.readLatest(key: 'DEVICE-A', read: read);
    now = now.add(const Duration(seconds: 14));
    final second = await cache.readLatest(key: 'DEVICE-A', read: read);

    expect(first?.value, 0);
    expect(second?.value, 0);
    expect(reads, 1);
  });

  test('超过 TTL 后刷新，失败保留最近一次有效值', () async {
    cache.remember('DEVICE-A', DeviceBatteryReading(value: 42, updatedAt: now));
    now = now.add(const Duration(seconds: 15));

    final reading = await cache.readLatest(
      key: 'DEVICE-A',
      read: () => Future<int>.error(StateError('offline')),
    );

    expect(reading?.value, 42);
    expect(reading?.updatedAt, DateTime.utc(2026, 7, 28, 10));
  });

  test('同一设备的并发刷新共享一次读取', () async {
    final completer = Completer<int>();
    var reads = 0;
    Future<int> read() {
      reads += 1;
      return completer.future;
    }

    final first = cache.readLatest(key: 'DEVICE-A', read: read);
    final second = cache.readLatest(key: 'DEVICE-A', read: read);
    expect(reads, 1);

    completer.complete(76);
    final values = await Future.wait([first, second]);

    expect(values.map((item) => item?.value), everyElement(76));
    expect(reads, 1);
  });

  test('从未成功读取且本次失败时返回 null', () async {
    final reading = await cache.readLatest(
      key: 'DEVICE-A',
      read: () => Future<int>.error(StateError('offline')),
    );

    expect(reading, isNull);
  });

  test('清空后忽略清空前仍在途的读取结果', () async {
    final completer = Completer<int>();
    final running = cache.readLatest(
      key: 'DEVICE-A',
      read: () => completer.future,
    );
    cache.clear();
    completer.complete(88);

    expect(await running, isNull);
    expect(cache.peek('DEVICE-A'), isNull);
  });
}
