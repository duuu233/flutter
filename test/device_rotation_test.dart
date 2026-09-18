import 'package:BoltStar/src/features/cast/device_rotation.dart';
import 'package:flutter_test/flutter_test.dart';

/// 两个导出角的取值口径，与小程序 `utils/device-rotation.js` 同源。
///
/// 守住的是最容易错的那条：**两个方向的缺省值不一样**（横向 270、竖向 0），
/// 而且 **0 是合法角度**，不能和「接口没给」混为一谈。
void main() {
  group('横向角 rotationDegree', () {
    test('后台配了多少就用多少', () {
      // 2026-09-18 这台产品后台配的就是 90——App 原来写死 270，正好差 180。
      expect(DeviceRotation.landscapeDegreeFrom({'rotationDegree': 90}), 90);
      expect(DeviceRotation.landscapeDegreeFrom({'rotationDegree': 180}), 180);
    });

    test('0 是合法角度，不能被当成缺失顶回 270', () {
      expect(DeviceRotation.landscapeDegreeFrom({'rotationDegree': 0}), 0);
      expect(DeviceRotation.landscapeDegreeFrom({'rotationDegree': '0'}), 0);
    });

    test('缺失 / null / 空串 / 解不出数字 → 270（历史行为）', () {
      expect(DeviceRotation.landscapeDegreeFrom({}), 270);
      expect(DeviceRotation.landscapeDegreeFrom({'rotationDegree': null}), 270);
      expect(DeviceRotation.landscapeDegreeFrom({'rotationDegree': ''}), 270);
      expect(DeviceRotation.landscapeDegreeFrom({'rotationDegree': 'abc'}), 270);
    });

    test('字符串与小数按数字解', () {
      expect(DeviceRotation.landscapeDegreeFrom({'rotationDegree': '90'}), 90);
      expect(DeviceRotation.landscapeDegreeFrom({'rotationDegree': 89.6}), 90);
    });
  });

  group('竖向角 verticalRotation', () {
    test('后台配了多少就用多少', () {
      expect(DeviceRotation.verticalDegreeFrom({'verticalRotation': 180}), 180);
    });

    test('缺失 → 0（不旋转），不是 270', () {
      expect(DeviceRotation.verticalDegreeFrom({}), 0);
      expect(DeviceRotation.verticalDegreeFrom({'verticalRotation': ''}), 0);
    });

    test('兼容名按顺序命中，空值跳过', () {
      expect(
        DeviceRotation.verticalDegreeFrom({
          'verticalRotation': null,
          'verticalRotationDegree': 90,
        }),
        90,
      );
      expect(
        DeviceRotation.verticalDegreeFrom({'verticalrotation': '180'}),
        180,
      );
      // 正式名优先：三个都给时以 verticalRotation 为准。
      expect(
        DeviceRotation.verticalDegreeFrom({
          'verticalRotation': 180,
          'verticalRotationDegree': 90,
          'verticalrotation': 0,
        }),
        180,
      );
    });
  });

  group('键在不在（详情接口合并用）', () {
    test('值为 0 也算「给了」', () {
      expect(DeviceRotation.hasLandscapeKey({'rotationDegree': 0}), isTrue);
      expect(DeviceRotation.hasVerticalKey({'verticalRotation': 0}), isTrue);
    });

    test('键不在就是没给——此时不能覆盖列表已经拿到的角度', () {
      expect(DeviceRotation.hasLandscapeKey({'verticalRotation': 0}), isFalse);
      expect(DeviceRotation.hasVerticalKey({'rotationDegree': 0}), isFalse);
    });
  });
}
