import 'package:flutter_test/flutter_test.dart';

import 'package:BoltStar/src/device/ble/frame_protocol.dart';

/// 广播厂商数据解析（[FrameProtocol.parseAdvertising]，协议 6.10.7）。
///
/// 2026-08-04：Device_ID 由 4 字节扩到 6 字节（完整 MAC），灰度期新老固件并存，
/// 解析必须两种布局都认。锁成回归用例的原因：把 Device_ID 的第 5 个字节当电量时，
/// **校验碰巧通过就会静默给出错误的设备ID + 错误的电量**，没有任何报错，线上极难发现。
///
/// 与小程序 `tests/advertising-parse.test.js` 同一组用例，两端结果必须一致。
void main() {
  // 屏型 0x02 = 5.89寸 EF6-589（与设备广播名 EF6-589 对应）
  const screen589 = 0x02;
  const screen370 = 0x01;

  test('老固件：Company_ID + 屏型 + 4 字节 ID + 电量', () {
    // 取自真机抓包：<FFFF> 0200 C1B4 592E（设备名 EF6-589、电量 0x2E=46%）
    final parsed = FrameProtocol.parseAdvertising([
      0xFF, 0xFF, screen589, 0x00, 0xC1, 0xB4, 0x59, 0x2E,
    ]);

    expect(parsed, isNotNull);
    expect(parsed!.screenType, screen589);
    expect(parsed.model, 'EF6-589');
    expect(parsed.deviceId, '00:C1:B4:59');
    expect(parsed.battery, 46);
    // 4 字节不是完整身份，展示层据此知道它还不能与详情页对齐
    expect(parsed.deviceIdComplete, isFalse);
  });

  test('新固件：Company_ID + 屏型 + 6 字节 ID + 电量', () {
    final parsed = FrameProtocol.parseAdvertising([
      0xFF, 0xFF, screen589, 0xE9, 0x48, 0xC2, 0x1E, 0xD4, 0x28, 0x5A,
    ]);

    expect(parsed, isNotNull);
    expect(parsed!.deviceId, 'E9:48:C2:1E:D4:28');
    expect(parsed.battery, 0x5A); // 90%
    expect(parsed.deviceIdComplete, isTrue);
  });

  test('新旧两种布局都解得通时，绝不回退老版（否则静默给出错值）', () {
    // 若回退成 4 字节布局，会把 ID 第 5 字节(0x28=40)当电量、校验还能通过，
    // 悄悄给出 deviceId=E9:48:C2:1E、battery=40，全错且无任何报错。
    final parsed = FrameProtocol.parseAdvertising([
      0xFF, 0xFF, screen589, 0xE9, 0x48, 0xC2, 0x1E, 0x28, 0x99, 0x5A,
    ]);

    expect(parsed, isNotNull);
    expect(parsed!.deviceId, 'E9:48:C2:1E:28:99');
    expect(parsed.battery, 0x5A);
  });

  test('不带 Company_ID 前缀的平台同样支持两种长度', () {
    final old = FrameProtocol.parseAdvertising([
      screen370, 0x00, 0xC1, 0xB4, 0x59, 0x2E,
    ]);
    expect(old, isNotNull);
    expect(old!.model, 'EF6-370');
    expect(old.deviceId, '00:C1:B4:59');
    expect(old.deviceIdComplete, isFalse);

    final fresh = FrameProtocol.parseAdvertising([
      screen370, 0xE9, 0x48, 0xC2, 0x1E, 0xD4, 0x28, 0x64,
    ]);
    expect(fresh, isNotNull);
    expect(fresh!.deviceId, 'E9:48:C2:1E:D4:28');
    expect(fresh.battery, 100); // 0x64，边界值合法
    expect(fresh.deviceIdComplete, isTrue);
  });

  test('优选布局解不通时才回退老布局，并带上 layoutFallback 标记', () {
    // 2026-08-11：固件把广播 ID 换成 6 字节后，若字段顺序与我们的假设不同，
    // 按新布局取到的「电量」会落在 ID 的字节上（这里 0xFF=255 > 100）→ 整条广播作废，
    // 设备在列表里连屏型/电量都没有，也排不进候选。现在改为：优选布局解不通才回退。
    final parsed = FrameProtocol.parseAdvertising([
      0xFF, 0xFF, screen589, 0x00, 0xC1, 0xB4, 0x59, 0x2E, 0x99, 0xFF,
    ]);

    expect(parsed, isNotNull, reason: '优选布局解不通不该整条丢弃');
    expect(parsed!.deviceId, '00:C1:B4:59');
    expect(parsed.battery, 46);
    expect(parsed.deviceIdComplete, isFalse);
    expect(parsed.deviceIdLayoutFallback, isTrue);

    // 正常解得通的那条不许带回退标记
    final normal = FrameProtocol.parseAdvertising([
      0xFF, 0xFF, screen589, 0xE9, 0x48, 0xC2, 0x1E, 0xD4, 0x28, 0x5A,
    ]);
    expect(normal!.deviceIdLayoutFallback, isFalse);
  });

  test('厂商数据带 0xFFFF Company_ID 时置 companyMatched（扫描白名单与兜底候选都靠它）', () {
    final withCompany = FrameProtocol.parseAdvertising([
      0xFF, 0xFF, screen589, 0xE9, 0x48, 0xC2, 0x1E, 0xD4, 0x28, 0x5A,
    ]);
    expect(withCompany!.companyMatched, isTrue);

    final without = FrameProtocol.parseAdvertising([
      screen370, 0x00, 0xC1, 0xB4, 0x59, 0x2E,
    ]);
    expect(without!.companyMatched, isFalse);
  });

  test('非相框广播返回 null（屏型不认识 / 电量非法 / 长度不够）', () {
    expect(
      FrameProtocol.parseAdvertising([
        0xFF, 0xFF, 0x09, 0x01, 0x02, 0x03, 0x04, 0x05,
      ]),
      isNull,
    );
    expect(
      FrameProtocol.parseAdvertising([
        0xFF, 0xFF, screen589, 0x00, 0xC1, 0xB4, 0x59, 0x65,
      ]),
      isNull,
      reason: '电量 0x65=101 超出合法范围，不是本产品广播',
    );
    expect(FrameProtocol.parseAdvertising([0xFF, 0xFF, screen589]), isNull);
    expect(FrameProtocol.parseAdvertising(<int>[]), isNull);
  });
}
