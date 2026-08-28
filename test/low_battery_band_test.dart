import 'package:flutter_test/flutter_test.dart';
import 'package:BoltStar/src/shared/widgets/low_battery_tip.dart';

/// 低电量提醒的分档（2026-08-21 同步小程序 `utils/low-battery.js`）。
///
/// 与小程序 `tests/low-battery-tip.test.js` 是同一组判据：
/// - `10 ≥ 电量 > 3` → 第一段文案（放到光线明亮处、减少操作频次）；
/// - `电量 ≤ 3`（含 0）→ 第二段文案（即将关机，去阳光/明亮处光能充电）；
/// - `>10` 或电量未知 → 不提醒（没有判据就不报警）。
///
/// ⚠️ 3% 归到第二档：需求原文是「10%~4%」与「3% 以下」，字面上 3% 落在两档中间的缝里，
/// 第一档明确到 4% 为止，所以 3% 只能归下面那档（弹窗文案本身也写着「低于3%」）。
void main() {
  group('lowBatteryBandFor', () {
    test('电量健康不提醒', () {
      expect(lowBatteryBandFor(100), LowBatteryBand.none);
      expect(lowBatteryBandFor(11), LowBatteryBand.none);
    });

    test('10% ~ 4% 走第一档', () {
      expect(lowBatteryBandFor(10), LowBatteryBand.low);
      expect(lowBatteryBandFor(7), LowBatteryBand.low);
      expect(lowBatteryBandFor(4), LowBatteryBand.low);
    });

    test('3% 及以下走第二档（含 0）', () {
      expect(lowBatteryBandFor(3), LowBatteryBand.critical);
      expect(lowBatteryBandFor(1), LowBatteryBand.critical);
      expect(lowBatteryBandFor(0), LowBatteryBand.critical);
    });

    test('电量未知或非法值一律不提醒', () {
      expect(lowBatteryBandFor(null), LowBatteryBand.none);
      expect(lowBatteryBandFor(-1), LowBatteryBand.none);
      expect(lowBatteryBandFor(255), LowBatteryBand.none);
    });
  });
}
