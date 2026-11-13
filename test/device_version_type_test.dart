import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:BoltStar/src/device/frame_device_protocol.dart';
import 'package:BoltStar/src/state.dart';

/// WiFi版 / 蓝牙版只按接口 `versionType` 判断（2026-11-14，同小程序 `broadcast-match.isWifiDevice`）：
/// 设备列表 `getUserProductList` / 详情 `getUserProductDetail` 下发 `versionType`（1 = 蓝牙版，2 = wifi版）。
/// 原来按产品广播 ID（`IJ_*`）认，而设备列表不带 productId / broadcastId，冷启动产品列表没回来就先显示成蓝牙版。
DeviceItem _device({int versionType = 0, String broadcastId = ''}) => DeviceItem(
      id: 'd1',
      name: '',
      kind: '',
      screenType: FrameScreenType.inch589,
      batteryLevel: 0,
      charging: false,
      connected: false,
      role: DeviceRole.owner,
      serialNumber: 'D0:CF:13:F0:2F:F8',
      hardwareVersion: '',
      firmwareVersion: '',
      imageMask: 0,
      currentImageIndex: -1,
      playbackMode: FramePlaybackMode.sequence,
      carouselIntervalSeconds: 0,
      carouselEnabled: false,
      broadcastId: broadcastId,
      versionType: versionType,
    );

void main() {
  test('只认 versionType', () {
    expect(_device(versionType: 2).isWifi, isTrue, reason: '没有 broadcastId 也是 WiFi 版');
    expect(_device(versionType: 1).isWifi, isFalse);
    expect(_device(versionType: 1, broadcastId: 'IJ_*').isWifi, isFalse, reason: 'versionType=1 就是蓝牙版，不看广播 ID');
    expect(_device(versionType: 2, broadcastId: 'EF6-370').isWifi, isTrue);
    expect(_device(broadcastId: 'IJ_*').isWifi, isFalse, reason: '不再按广播 ID 猜');
  });

  test('列表 / 详情解析 versionType', () {
    final source = File('lib/src/state.dart').readAsStringSync().replaceAll(RegExp(r'//[^\n]*'), '');
    expect(source, contains("versionType: _asInt(data['versionType']),"));
    expect(source, contains("if (row.containsKey('versionType')) {"));
    expect(source, contains('bool get isWifi => versionType == versionTypeWifi;'));
  });
}
