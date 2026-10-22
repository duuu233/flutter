import 'package:flutter_test/flutter_test.dart';

import 'package:BoltStar/src/device/device_thumb.dart';
import 'package:BoltStar/src/device/frame_device_protocol.dart';
import 'package:BoltStar/src/state.dart';

/// 设备图按机型区分 + 新机型不参与型号防串台（2026-10-22 同步小程序）。
///
/// 与小程序 `tests/device-thumb.test.js` 同口径：EB-169（圆屏）→ circle、EC-370 → rectangle、
/// 其余与认不出的 → 原图；已绑定记录看 broadcastId，搜索结果看广播名，用户起的名字不参与。
DeviceItem _device({
  int width = 0,
  int height = 0,
  String broadcastId = '',
  int? shapeType,
  String name = '',
}) => DeviceItem(
  id: 'd1',
  name: name,
  kind: '',
  screenType: FrameScreenType.inch589,
  batteryLevel: 0,
  charging: false,
  connected: false,
  role: DeviceRole.owner,
  serialNumber: '37:0B:00:D0:44:5A',
  hardwareVersion: '',
  firmwareVersion: '',
  imageMask: 0,
  currentImageIndex: -1,
  playbackMode: FramePlaybackMode.sequence,
  carouselIntervalSeconds: 0,
  carouselEnabled: false,
  screenWidth: width,
  screenHeight: height,
  broadcastId: broadcastId,
  shapeType: shapeType,
);

void main() {
  test('已绑定记录：broadcastId 决定机型，大小写与首尾空格不影响', () {
    expect(
      DeviceThumb.ofRecord(broadcastId: 'EB-169'),
      DeviceThumb.roundAsset,
    );
    expect(
      DeviceThumb.ofRecord(broadcastId: 'eb-169 '),
      DeviceThumb.roundAsset,
    );
    expect(
      DeviceThumb.ofRecord(broadcastId: 'EC-370'),
      DeviceThumb.rectangleAsset,
    );
    // EF6-370 与 EC-370 只差前缀，老机型不能被认成新机型
    expect(
      DeviceThumb.ofRecord(broadcastId: 'EF6-370'),
      DeviceThumb.defaultAsset,
    );
    expect(DeviceThumb.ofRecord(broadcastId: ''), DeviceThumb.defaultAsset);
  });

  test('broadcastId 缺失时 shapeType=1 按圆屏兜底；认得出机型就不看形状', () {
    expect(
      DeviceThumb.ofRecord(broadcastId: '', shapeType: 1),
      DeviceThumb.roundAsset,
    );
    expect(
      DeviceThumb.ofRecord(broadcastId: '', shapeType: 0),
      DeviceThumb.defaultAsset,
    );
    expect(
      DeviceThumb.ofRecord(broadcastId: 'EC-370', shapeType: 1),
      DeviceThumb.rectangleAsset,
    );
  });

  test('搜索结果按广播名包含匹配；记录的用户名字不参与', () {
    expect(DeviceThumb.ofScanName('EB-169-5A44'), DeviceThumb.roundAsset);
    expect(DeviceThumb.ofScanName(' ec-370'), DeviceThumb.rectangleAsset);
    expect(DeviceThumb.ofScanName('EF6-589'), DeviceThumb.defaultAsset);
    expect(
      _device(name: 'EB-169').thumbAsset,
      DeviceThumb.defaultAsset,
      reason: '已绑定设备的名字是用户起的，改名不能改变设备图',
    );
    expect(_device(broadcastId: 'EB-169').thumbAsset, DeviceThumb.roundAsset);
  });

  test('screenCode：旧机型尺寸给码，新尺寸给 0 不参与型号否决，未下发保持旧行为', () {
    expect(
      _device(width: 480, height: 720).screenCode,
      0x02,
      reason: 'screenType 仍是记录上的值（这里构造为 5.89 寸）',
    );
    expect(_device(width: 720, height: 480).screenCode, 0x02);
    expect(_device(width: 680, height: 960).screenCode, 0x02);
    expect(
      _device(width: 400, height: 400).screenCode,
      0,
      reason: 'EB-169 400×400 不能被回落的 5.89 寸码挡在门外',
    );
    expect(_device().screenCode, 0x02, reason: '后端没下发宽高时沿用原行为');
  });
}
