import 'package:flutter_test/flutter_test.dart';

import 'package:BoltStar/src/device/ble/device_ble.dart';
import 'package:BoltStar/src/device/ble/frame_protocol.dart';
import 'package:BoltStar/src/features/cast/projection_device.dart';

/// 投屏尺寸取设备列表记录（2026-10-22 同步小程序 `tests/projection-dynamic-resolution.test.js`）。
///
/// 旧实现只认 0x01 型号表：EB-169 这类新尺寸（400×400、屏型不在表里）读出 0×0，
/// 被当成「未连接」报给用户。这里锁住：新尺寸可投、身份必须一致、尺寸/形状问题按配置问题报。
const _serial = '37:0B:00:D0:44:5A';

FrameDeviceInfo _info({
  String deviceId = _serial,
  int screenType = 0x04,
  int width = 0,
  int height = 0,
  int capacity = 0,
  List<int>? mask,
}) => FrameDeviceInfo(
  deviceId: deviceId,
  hwVersion: 0,
  imgMask: mask ?? List<int>.filled(12, 0),
  imgCount: 0,
  battery: 80,
  playMode: 'order',
  intervalSeconds: 0,
  screenType: screenType,
  screen: '',
  model: '',
  capacity: capacity,
  width: width,
  height: height,
  curImgIndex: 0,
);

void main() {
  test('EB-169：用设备列表 400×400；容量未知只用 IMG_MASK 可寻址上限', () {
    final transfer = resolveProjectionTransfer(
      expectedSerial: '370B00D0445A',
      info: _info(),
      deviceWidth: 400,
      deviceHeight: 400,
      shapeType: 1,
    );
    expect(transfer.width, 400);
    expect(transfer.height, 400);
    expect(transfer.capacity, 0, reason: '新尺寸不虚构图片张数');
    expect(transfer.slotLimit, 96);
    expect(transfer.fromDeviceList, isTrue);
    expect((transfer.width * transfer.height + 1) ~/ 2, 80000);
  });

  test('旧机型：设备列表尺寸与 0x01 一致时沿用固件容量', () {
    final transfer = resolveProjectionTransfer(
      expectedSerial: _serial,
      info: _info(screenType: 0x02, width: 680, height: 960, capacity: 51),
      deviceWidth: 680,
      deviceHeight: 960,
    );
    expect(transfer.capacity, 51);
    expect(transfer.slotLimit, 51);
  });

  test('记录没下发宽高：兼容旧的 0x01 型号表', () {
    final transfer = resolveProjectionTransfer(
      expectedSerial: _serial,
      info: _info(screenType: 0x01, width: 480, height: 720, capacity: 95),
    );
    expect(transfer.width, 480);
    expect(transfer.height, 720);
    expect(transfer.fromDeviceList, isFalse);
    expect(transfer.slotLimit, 95);
  });

  test('身份不一致、尺寸无效、圆屏非正方形都按配置问题报，不说成未连接', () {
    void expectConfig(void Function() action) => expect(
      action,
      throwsA(
        isA<FrameBleException>().having(
          (e) => e.kind,
          'kind',
          FrameBleErrorKind.unsupported,
        ),
      ),
    );
    expectConfig(
      () => resolveProjectionTransfer(
        expectedSerial: 'E9:48:C2:1E:D4:28',
        info: _info(),
        deviceWidth: 400,
        deviceHeight: 400,
      ),
    );
    expectConfig(
      () => resolveProjectionTransfer(expectedSerial: _serial, info: _info()),
    );
    expectConfig(
      () => resolveProjectionTransfer(
        expectedSerial: _serial,
        info: _info(),
        deviceWidth: 400,
        deviceHeight: 0,
      ),
    );
    expectConfig(
      () => resolveProjectionTransfer(
        expectedSerial: _serial,
        info: _info(),
        deviceWidth: 400,
        deviceHeight: 480,
        shapeType: 1,
      ),
    );
    expectConfig(
      () => resolveProjectionTransfer(
        expectedSerial: _serial,
        info: _info(mask: const []),
        deviceWidth: 400,
        deviceHeight: 400,
      ),
    );
  });
}
