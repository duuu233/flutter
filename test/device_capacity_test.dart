import 'package:flutter_test/flutter_test.dart';

import 'package:BoltStar/src/device/ble/frame_protocol.dart';
import 'package:BoltStar/src/features/cast/projection_device.dart';

/// 设备最多可存张数（规格书 v1.6 §5.2，2026-10-23 同步小程序 `tests/device-capacity.test.js`）：
/// EF6-370 95、EF6-589 51、EB-169 25、EC-370 11。
///
/// 锁住：先按机型（broadcastId）、认不出再按屏型；EC-370 屏型同报 0x01 也要给 11；
/// EB-169 的 0x04 读得出 25；都认不出给 0，不拿旧机型容量猜；投屏选槽按机型容量。
const _serial = '37:0B:00:D0:44:5A';

List<int> _firmware(int screenType) {
  final b = List<int>.filled(28, 0);
  b.setAll(0, [0x37, 0x0B, 0x00, 0xD0, 0x44, 0x5A]);
  b[8] = 0x07; // 已存 3 张
  b[26] = screenType;
  return b;
}

void main() {
  test('机型优先，其次屏型；都认不出为 0', () {
    expect(FrameProtocol.capacityOf('EC-370', 0x01), 11);
    expect(FrameProtocol.capacityOf('ec-370-ABCD', 0x01), 11);
    expect(FrameProtocol.capacityOf('EB-169', 0x04), 25);
    expect(FrameProtocol.capacityOf('EF6-370', 0x01), 95);
    expect(FrameProtocol.capacityOf('EF6-589', 0x02), 51);
    expect(FrameProtocol.capacityOf('EC-370', 0x09), 11);
    expect(FrameProtocol.capacityOf('', 0x01), 95);
    expect(FrameProtocol.capacityOf(null, 0x02), 51);
    expect(FrameProtocol.capacityOf('', 0x04), 25);
    expect(FrameProtocol.capacityOf('', 0x03), 0, reason: '7.3寸占位无容量');
    expect(FrameProtocol.capacityOf('', 0x09), 0, reason: '不认识的屏型不猜');
    expect(FrameProtocol.capacityOf('37:0B:00:D0:44:5A', 0x04), 25);
  });

  test('0x01 解析：EB-169 的 0x04 读得出容量，不给尺寸', () {
    final info = FrameProtocol.parseDeviceInfo(_firmware(0x04));
    expect(info.capacity, 25);
    expect(info.width, 0);
    expect(info.imgCount, 3);
    expect(FrameProtocol.parseDeviceInfo(_firmware(0x01)).capacity, 95);
    expect(FrameProtocol.parseDeviceInfo(_firmware(0x09)).capacity, 0);
  });

  test('投屏选槽：EC-370 按机型 11，EB-169 按机型 25', () {
    final ec = resolveProjectionTransfer(
      expectedSerial: _serial,
      info: FrameProtocol.parseDeviceInfo(_firmware(0x01)),
      deviceWidth: 480,
      deviceHeight: 720,
      broadcastId: 'EC-370',
    );
    expect(ec.capacity, 11);
    expect(ec.slotLimit, 11);
    final eb = resolveProjectionTransfer(
      expectedSerial: _serial,
      info: FrameProtocol.parseDeviceInfo(_firmware(0x04)),
      deviceWidth: 400,
      deviceHeight: 400,
      shapeType: 1,
      broadcastId: 'EB-169',
    );
    expect(eb.capacity, 25);
    expect(eb.slotLimit, 25);
  });
}
