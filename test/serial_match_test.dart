import 'package:flutter_test/flutter_test.dart';

import 'package:BoltStar/src/device/serial_match.dart';

/// serial_match 的规则微妙且历史上真出过串台事故（EF6-370 被误认成 EF6-589，
/// 见 serial_match.dart 头注复盘），用单测把 2026-07-09 收紧后的全部分支钉死：
/// 归一化 / 等长即否 / 前后缀锚定 / <8 位即否 / 型号一票否决。
void main() {
  group('normalizeSerial', () {
    test('去分隔符（: - 空格）并大写', () {
      expect(normalizeSerial('e9:48:c2:1e:d4:28'), 'E948C21ED428');
      expect(normalizeSerial('e9-48-c2-1e-d4-28'), 'E948C21ED428');
      expect(normalizeSerial('e9 48 c2 1e d4 28'), 'E948C21ED428');
      expect(normalizeSerial('E948C21ED428'), 'E948C21ED428');
    });

    test('null / 非字符串安全处理', () {
      expect(normalizeSerial(null), '');
      expect(normalizeSerial(123456), '123456');
    });
  });

  group('serialsMatch', () {
    test('归一化后完全相等 → 同一台（后端 6 字节 vs 固件 6 字节）', () {
      expect(serialsMatch('E9:48:C2:1E:D4:28', 'e948c21ed428'), isTrue);
    });

    test('任一侧为空 → 否', () {
      expect(serialsMatch('', 'E948C21ED428'), isFalse);
      expect(serialsMatch('E948C21ED428', null), isFalse);
      expect(serialsMatch('', ''), isFalse);
    });

    test('长度相同但不相等 → 一定是两台设备，直接否', () {
      expect(serialsMatch('E948C21ED428', 'E948C21ED429'), isFalse);
      // 4 字节 vs 4 字节同长不等也否。
      expect(serialsMatch('1ED428AA', '1ED428BB'), isFalse);
    });

    test('长度不同：短的是长的前缀 → 同一台（广播 4 字节锚定头部）', () {
      expect(serialsMatch('E948C21E', 'E948C21ED428'), isTrue);
      expect(serialsMatch('E9:48:C2:1E', 'e9-48-c2-1e-d4-28'), isTrue);
    });

    test('长度不同：短的是长的后缀 → 同一台（广播 4 字节锚定尾部）', () {
      expect(serialsMatch('C21ED428', 'E948C21ED428'), isTrue);
    });

    test('长度不同：短串只出现在中段 → 否（串台事故的根因场景）', () {
      // 收紧前用任意位置 contains，两台设备序列号中段偶然重叠 4 字节
      // 就会被误判成同一台（EF6-370 串到 EF6-589）。
      expect(serialsMatch('48C21ED4', 'E948C21ED428'), isFalse);
    });

    test('短串不足 8 个 hex（4 字节）→ 否（太短不足以锚定身份）', () {
      expect(serialsMatch('E948C2', 'E948C21ED428'), isFalse);
      expect(serialsMatch('E9', 'E948C21ED428'), isFalse);
    });
  });

  group('完整设备身份校验', () {
    const fullA = 'E948C21ED428';
    const fullB = 'E448C21ED428';
    const sharedShort = 'C21ED428';

    test('两组都含相同短 ID，但完整 ID 不同 → 不是同一台', () {
      expect(
        serialSetsMatch([sharedShort, fullA], [sharedShort, fullB]),
        isFalse,
      );
    });

    test('后端完整 ID 必须与 0x01 完整 ID 精确相等', () {
      expect(verifiedDeviceSerialMatch(fullA, fullA), isTrue);
      expect(verifiedDeviceSerialMatch(fullA, fullB), isFalse);
      expect(verifiedDeviceSerialMatch(fullA, sharedShort), isFalse);
    });

    test('后端只有短 ID 时保留旧设备兼容', () {
      expect(verifiedDeviceSerialMatch(sharedShort, fullA), isTrue);
    });

    test('完整后端 ID 不得仅凭会话广播短 ID 复用', () {
      expect(sessionSerialsMatch([sharedShort], fullA), isFalse);
      expect(sessionSerialsMatch([sharedShort, fullA], fullA), isTrue);
      expect(sessionSerialsMatch([sharedShort, fullB], fullA), isFalse);
    });
  });

  group('sameScreenCode', () {
    test('两侧都已知且相同 → 同型号', () {
      expect(sameScreenCode(0x01, 0x01), isTrue);
      expect(sameScreenCode(0x02, 0x02), isTrue);
    });

    test('两侧都已知且不同 → 一票否决', () {
      expect(sameScreenCode(0x01, 0x02), isFalse);
      expect(sameScreenCode(0x03, 0x02), isFalse);
    });

    test('任一侧未知(0) → 不阻断（回退纯序列号匹配）', () {
      expect(sameScreenCode(0, 0x02), isTrue);
      expect(sameScreenCode(0x01, 0), isTrue);
      expect(sameScreenCode(0, 0), isTrue);
    });
  });
}
