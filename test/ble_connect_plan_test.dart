import 'package:flutter_test/flutter_test.dart';

import 'package:BoltStar/src/device/ble/device_ble.dart';

/// 建连预算（[BleConnectPlan]）的不变量。
///
/// 这几条锁的都是「改一个数字就会悄悄破坏」的性质：预算表是按占空比推出来的
/// （常规定向连接 ≈50% vs autoConnect ≈0.9%，见 [BleConnectPlan] 头注释），
/// 而占空比这件事看不见摸不着，很容易在下一轮"顺手调一下超时"时被抹掉。
void main() {
  const tiers = <BleConnectPlan>[
    BleConnectPlan.normal,
    BleConnectPlan.weak,
    BleConnectPlan.veryWeak,
  ];

  group('BleConnectPlan 各档预算', () {
    test('每一档都至少留了一种建连手段', () {
      for (final plan in <BleConnectPlan>[...tiers, BleConnectPlan.probe]) {
        expect(
          plan.directTimeouts.isNotEmpty || plan.usesAutoConnect,
          isTrue,
          reason: '${plan.label} 一种建连手段都不剩 = 什么都没试就报失败',
        );
      }
    });

    test('用户可感知的总预算夹在 22s 内', () {
      for (final plan in tiers) {
        expect(
          plan.worstCase.inSeconds,
          lessThanOrEqualTo(22),
          reason: '${plan.label} 的最坏耗时超过用户能忍的 loading 时长',
        );
      }
    });

    test('信号越弱，常规定向连接的窗口越长（弱信号只能靠多覆盖广播事件来补）', () {
      Duration directTotal(BleConnectPlan plan) => plan.directTimeouts.fold(
        Duration.zero,
        (sum, item) => sum + item,
      );

      expect(
        directTotal(BleConnectPlan.veryWeak),
        greaterThan(directTotal(BleConnectPlan.weak)),
      );
      // 极弱档必须真的发起常规定向连接：曾经它是空阶梯（直接上 autoConnect），
      // 而 autoConnect 的占空比只有 ≈0.9%，等于把预算花在几乎不监听的机制上。
      expect(BleConnectPlan.veryWeak.directTimeouts, isNotEmpty);
    });

    test('autoConnect 只是末位兜底，不许拿走任一档的大头', () {
      for (final plan in tiers) {
        expect(
          plan.autoConnectBudget * 2,
          lessThan(plan.worstCase),
          reason: '${plan.label} 把一半以上的预算给了 ≈0.9% 占空比的机制',
        );
      }
    });

    test('快路径是「赌一把」：一档短超时、绝不兜底', () {
      expect(BleConnectPlan.probe.directTimeouts.length, 1);
      expect(BleConnectPlan.probe.usesAutoConnect, isFalse);
      expect(
        BleConnectPlan.probe.directTimeouts.single,
        FrameBleClient.directConnectProbeTimeout,
      );
    });

    test('旧分配保持原样，用来做对照实验（改了就不叫对照了）', () {
      expect(BleConnectPlan.legacyWeak.directTimeouts, const [
        Duration(seconds: 5),
      ]);
      expect(
        BleConnectPlan.legacyWeak.autoConnectBudget,
        const Duration(seconds: 15),
      );
      expect(BleConnectPlan.legacyVeryWeak.directTimeouts, isEmpty);
      expect(
        BleConnectPlan.legacyVeryWeak.autoConnectBudget,
        const Duration(seconds: 20),
      );
    });
  });
}
