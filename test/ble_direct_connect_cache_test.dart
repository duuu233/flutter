import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:BoltStar/src/device/ble/ble_direct_connect_cache.dart';

/// 直连缓存是「跳过整段扫描」这条快路径的唯一输入，写错的代价是**串台**：
/// 拿 B 的句柄去连 A。所以这里既测省时间的正路，也测「脏数据一律拒绝」。
void main() {
  const serialA = 'E948C21ED428';
  const serialB = 'E948C21ED429';
  const remoteA = 'AA:BB:CC:DD:EE:01';
  const remoteB = 'AA:BB:CC:DD:EE:02';

  final cache = BleDirectConnectCache.instance;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    cache.resetForTest();
  });

  group('BleDirectConnectCache', () {
    test('记住并取回 remoteId，键按归一化匹配', () async {
      await cache.put(serialA, remoteA);
      expect(await cache.get(serialA), remoteA);
      // 后端记录是 `E9:48:...` 冒号格式、固件 0x01 自报是裸 hex，两种写法必须命中同一条。
      expect(await cache.get('e9:48:c2:1e:d4:28'), remoteA);
    });

    test('不同设备各存各的，互不覆盖', () async {
      await cache.put(serialA, remoteA);
      await cache.put(serialB, remoteB);
      expect(await cache.get(serialA), remoteA);
      expect(await cache.get(serialB), remoteB);
    });

    test('未命中返回空串（调用方据此走完整扫描）', () async {
      expect(await cache.get(serialA), '');
    });

    test('只认完整 6 字节 ID：广播短 ID / 全 0 / 全 F 一律不写', () async {
      await cache.put('C21ED428', remoteA); // 广播 4 字节短 ID
      await cache.put('000000000000', remoteA);
      await cache.put('FFFFFFFFFFFF', remoteA);
      expect(await cache.get('C21ED428'), '');
      expect(await cache.get('000000000000'), '');
      expect(await cache.get('FFFFFFFFFFFF'), '');
    });

    test('空 remoteId 不写（否则下次会拿空句柄去连）', () async {
      await cache.put(serialA, '   ');
      expect(await cache.get(serialA), '');
    });

    test('remove 后回到未命中', () async {
      await cache.put(serialA, remoteA);
      await cache.remove(serialA);
      expect(await cache.get(serialA), '');
    });

    test('同一设备换了句柄以最新一次为准', () async {
      await cache.put(serialA, remoteA);
      await cache.put(serialA, remoteB);
      expect(await cache.get(serialA), remoteB);
    });

    test('落盘后新进程能读回（重启 App 仍走快路径）', () async {
      await cache.put(serialA, remoteA);
      cache.resetForTest(); // 丢内存镜像，模拟冷启动
      expect(await cache.get(serialA), remoteA);
    });

    test('磁盘上的脏数据在读回时被过滤，不会喂给建连', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'ble_direct_conn_cache':
            '{"$serialA":"$remoteA","C21ED428":"$remoteB","$serialB":""}',
      });
      cache.resetForTest();
      expect(await cache.get(serialA), remoteA);
      expect(await cache.get('C21ED428'), '');
      expect(await cache.get(serialB), '');
    });

    test('损坏的存储不抛错，只是当作没有缓存', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'ble_direct_conn_cache': 'not-json',
      });
      cache.resetForTest();
      expect(await cache.get(serialA), '');
      // 依然可写可读：坏数据不能把这条路永久废掉。
      await cache.put(serialA, remoteA);
      expect(await cache.get(serialA), remoteA);
    });

    test('超过上限时淘汰最早写入的那条', () async {
      for (var i = 0; i < BleDirectConnectCache.maxEntries + 2; i += 1) {
        final serial = 'E948C21E${i.toRadixString(16).padLeft(4, '0')}'
            .toUpperCase();
        await cache.put(serial, 'AA:BB:CC:DD:EE:${i.toString().padLeft(2, '0')}');
      }
      expect(await cache.get('E948C21E0000'), ''); // 最早的两条被挤掉
      expect(await cache.get('E948C21E0001'), '');
      expect(await cache.get('E948C21E0002'), isNotEmpty);
      cache.resetForTest();
      expect(await cache.get('E948C21E0000'), '');
    });
  });
}
