import 'package:flutter_test/flutter_test.dart';

import 'package:BoltStar/src/device/ble/frame_protocol.dart';

/// 广播厂商数据解析（[FrameProtocol.parseAdvertising]，协议 6.10.7）。
///
/// 布局：Company_ID(2=0xFFFF) + 屏型(1) + Device_ID(6) + 电量(1)。2026-10-22 起只认 6 字节
/// Device_ID，4 字节老格式不再兼容；设备ID按广播原顺序取，且**不受屏型/电量是否认识影响**
///（此前屏型不认识就整条丢弃，EB-169 的 0x04 因此连设备ID一起丢失）。
///
/// 与小程序 `tests/advertising-parse.test.js` 同一组用例，两端结果必须一致。
void main() {
  // 屏型 0x02 = 5.89寸 EF6-589（与设备广播名 EF6-589 对应）
  const screen589 = 0x02;

  // EB-169 实测：第三方蓝牙工具 Manufacturer data <0xFFFF> 0x04370B00D0445A61。
  // 正确设备ID为 37:0B:00:D0:44:5A（产品确认）；手机系统给的蓝牙地址 5A:44:D0:00:0B:37 是它的倒序。
  const eb169 = [0xFF, 0xFF, 0x04, 0x37, 0x0B, 0x00, 0xD0, 0x44, 0x5A, 0x61];

  test('EB-169：屏型 0x04 不认识也解析出设备ID，按广播原顺序', () {
    final parsed = FrameProtocol.parseAdvertising(eb169);
    expect(parsed, isNotNull);
    expect(parsed!.deviceId, '37:0B:00:D0:44:5A');
    expect(parsed.battery, 97);
    expect(parsed.companyMatched, isTrue);
    expect(parsed.screenType, 0, reason: '不认识的屏型记 0，只是不给尺寸/型号');
    expect(parsed.screen, '');
    expect(parsed.model, '');
  });

  test('不带 Company_ID 前缀：恰好 8 字节', () {
    final parsed = FrameProtocol.parseAdvertising(eb169.sublist(2));
    expect(parsed, isNotNull);
    expect(parsed!.deviceId, '37:0B:00:D0:44:5A');
    expect(parsed.battery, 97);
    expect(parsed.companyMatched, isFalse);
  });

  test('已知屏型照常给出尺寸/型号，电量边界 100 合法', () {
    final parsed = FrameProtocol.parseAdvertising([
      0xFF, 0xFF, screen589, 0xE9, 0x48, 0xC2, 0x1E, 0xD4, 0x28, 0x5A,
    ]);
    expect(parsed!.screenType, screen589);
    expect(parsed.model, 'EF6-589');
    expect(parsed.deviceId, 'E9:48:C2:1E:D4:28');
    expect(parsed.battery, 0x5A);

    final full = FrameProtocol.parseAdvertising([
      0xFF, 0xFF, screen589, 0xE9, 0x48, 0xC2, 0x1E, 0xD4, 0x28, 0x64,
    ]);
    expect(full!.battery, 100);
  });

  test('电量非法只置空电量，设备ID照常', () {
    final parsed = FrameProtocol.parseAdvertising([
      0xFF, 0xFF, screen589, 0xE9, 0x48, 0xC2, 0x1E, 0xD4, 0x28, 0x65,
    ]);
    expect(parsed, isNotNull);
    expect(parsed!.battery, isNull, reason: '电量 0x65=101 超出合法范围');
    expect(parsed.deviceId, 'E9:48:C2:1E:D4:28');
  });

  test('4 字节老格式不再解析，避免给出错误的设备ID', () {
    // 带前缀的老包整包 8 字节，与不带前缀的新包等长：以 0xFFFF 开头的必须按带前缀处理、返回 null，
    // 不能被误读成 FF:02:00:C1:B4:59 这种错误ID。
    expect(
      FrameProtocol.parseAdvertising([
        0xFF, 0xFF, screen589, 0x00, 0xC1, 0xB4, 0x59, 0x2E,
      ]),
      isNull,
    );
    expect(
      FrameProtocol.parseAdvertising([screen589, 0x00, 0xC1, 0xB4, 0x59, 0x2E]),
      isNull,
    );
  });

  test('长度不符一律返回 null', () {
    expect(FrameProtocol.parseAdvertising([0xFF, 0xFF, screen589]), isNull);
    expect(FrameProtocol.parseAdvertising([1, 2, 3, 4, 5, 6, 7]), isNull);
    expect(FrameProtocol.parseAdvertising(<int>[]), isNull);
  });
}
