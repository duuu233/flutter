import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:BoltStar/src/device/device_identity_registry.dart';

/// 身份登记表是 `connectBoundDevice` 身份闸的最后一档兜底来源。
/// 写错的代价分两头：**漏**（好设备被报「请删除后重新绑定」、连扫描都不发起）、
/// **串**（把短 ID 或别台的 ID 当成身份喂给身份闸）。两头都要测。
///
/// 对齐小程序 `utils/device-identity.js` 与 `tests/active-device-identity.test.js`。
void main() {
  const recordA = '1001';
  const recordB = '1002';
  const serialA = 'E9:48:C2:1E:D4:28';
  const serialB = 'E9:48:C2:1E:D4:29';

  final registry = DeviceIdentityRegistry.instance;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    registry.resetForTest();
  });

  group('DeviceIdentityRegistry', () {
    test('登记后能按后端记录主键取回，取回值为归一化写法', () async {
      await registry.remember(recordA, serialA);
      expect(await registry.recall(recordA), serialA);
      // 固件 0x01 自报的是裸 hex，后端下发的是冒号格式，两种写法必须登记成同一条。
      registry.resetForTest();
      await registry.remember(recordB, 'e948c21ed429');
      expect(await registry.recall(recordB), serialB);
    });

    test('主键是 int 还是 String 都得命中同一条（后端 JSON 两种都出现过）', () async {
      await registry.remember(1001, serialA);
      expect(await registry.recall('1001'), serialA);
    });

    test('未登记返回空串——调用方据此继续按「记录自身」判定，不得臆造身份', () async {
      expect(await registry.recall(recordA), '');
      expect(await registry.recall(''), '');
      expect(await registry.recall(null), '');
    });

    test('只收完整 6 字节 ID：广播 4 字节短 ID / 全 0 / 全 F / 非法值一律不进表', () async {
      await registry.remember(recordA, 'C21ED428'); // 广播短 ID
      await registry.remember(recordA, '000000000000');
      await registry.remember(recordA, 'FFFFFFFFFFFF');
      await registry.remember(recordA, 'not-a-serial');
      await registry.remember(recordA, '');
      await registry.remember(recordA, null);
      // 一条都不该写进去：把短 ID 升格成身份正是跨型号串台的来源。
      expect(await registry.recall(recordA), '');
    });

    test('空主键不登记（扫描结果等没有后端主键的记录不参与登记表）', () async {
      await registry.remember('', serialA);
      await registry.remember(null, serialA);
      expect(await registry.recall(''), '');
    });

    test('不同记录各存各的，互不覆盖', () async {
      await registry.remember(recordA, serialA);
      await registry.remember(recordB, serialB);
      expect(await registry.recall(recordA), serialA);
      expect(await registry.recall(recordB), serialB);
    });

    test('同一条重复登记为新值时以最后一次为准', () async {
      await registry.remember(recordA, serialA);
      await registry.remember(recordA, serialB);
      expect(await registry.recall(recordA), serialB);
    });

    test('解绑 forget 只清这一条，后端主键复用时不会把旧身份带回来', () async {
      await registry.remember(recordA, serialA);
      await registry.remember(recordB, serialB);
      await registry.forget(recordA);
      expect(await registry.recall(recordA), '');
      expect(await registry.recall(recordB), serialB);
    });

    test('退出登录 clear 整表清空（下一位用户的设备与这批主键无关）', () async {
      await registry.remember(recordA, serialA);
      await registry.remember(recordB, serialB);
      await registry.clear();
      expect(await registry.recall(recordA), '');
      expect(await registry.recall(recordB), '');
    });

    test('跨启动保留：重新从磁盘读回仍在', () async {
      await registry.remember(recordA, serialA);
      registry.resetForTest(); // 模拟冷启动，强制从 SharedPreferences 重读
      expect(await registry.recall(recordA), serialA);
    });

    test('磁盘脏数据读回时过滤掉：短 ID / 空值不得复活', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'device_identity_map':
            '{"1001":"C21ED428","1002":"E9:48:C2:1E:D4:29","1003":""}',
      });
      registry.resetForTest();
      expect(await registry.recall('1001'), ''); // 短 ID 被过滤
      expect(await registry.recall('1002'), serialB); // 合法值保留
      expect(await registry.recall('1003'), '');
    });

    test('存储损坏不抛错，且不影响后续写入', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'device_identity_map': 'not-json',
      });
      registry.resetForTest();
      expect(await registry.recall(recordA), '');
      await registry.remember(recordA, serialA);
      expect(await registry.recall(recordA), serialA);
    });
  });
}
