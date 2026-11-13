import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:BoltStar/src/device/frame_device_protocol.dart';
import 'package:BoltStar/src/features/devices/firmware_gate.dart';
import 'package:BoltStar/src/state.dart';

/// 固件升级提醒（2026-11-13 产品改口：强制升级整套去掉，只保留强提醒 / 弱提示；同小程序 tests/firmware-gate.test.js）。
///
/// ① 升级类型：updateType 2 = 强提醒弹（1 原强制按强提醒），3 弱提示 / 4 不提示及其它不弹（只亮红点）；
/// ② 弹的前提：WiFi 在线 / 蓝牙已连接（ready）、红点亮（hasUpdate），有进行中的升级不弹；
/// ③ 强提醒每台设备每次启动只弹一次，取消后不再弹，重新打开 App 再弹；
/// ④ 接入位置：只在两个详情页进入后判断；功能按钮、我的设备、首页都不判，loading 现查、本地缓存、升级完成更新缓存一并去掉。
DeviceItem _device({int updateType = 0, int isUpdate = 0, String url = 'https://oss/fw.bin', String broadcastId = 'EF6-370'}) =>
    DeviceItem(
      id: 'd1',
      name: '',
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
      broadcastId: broadcastId,
      isUpdate: isUpdate,
      newVersionNo: '0.6.2',
      downloadPath: url,
      updateType: updateType,
    );

String _strip(String source) => source.replaceAll(RegExp(r'//[^\n]*'), '');

void main() {
  test('升级类型：只有强提醒弹', () {
    expect(firmwareGateModeOf(_device(updateType: 2)), FirmwareGateMode.remind);
    expect(firmwareGateModeOf(_device(updateType: 1)), FirmwareGateMode.remind, reason: '原强制升级：后台已隐藏，存量数据按强提醒');
    expect(firmwareGateModeOf(_device(updateType: 3)), FirmwareGateMode.none, reason: '弱提示：只亮红点');
    expect(firmwareGateModeOf(_device(updateType: 4)), FirmwareGateMode.none, reason: '不提示');
    expect(firmwareGateModeOf(_device()), FirmwareGateMode.none, reason: '没给不弹');
    expect(FirmwareGateMode.values.map((mode) => mode.name), ['none', 'remind'], reason: '强制升级已去掉');
  });

  test('弹的前提与判定', () {
    final remind = _device(updateType: 2);
    expect(decideFirmwareGate(remind, ready: true, hasUpdate: true), FirmwareGateMode.remind);
    expect(decideFirmwareGate(remind, ready: false, hasUpdate: true), FirmwareGateMode.none, reason: '离线 / 未连接不判');
    expect(decideFirmwareGate(remind, ready: true, hasUpdate: false), FirmwareGateMode.none, reason: '红点不亮不弹');
    expect(decideFirmwareGate(remind, ready: true, hasUpdate: true, inflight: true), FirmwareGateMode.none, reason: '进行中的升级不弹');
    expect(decideFirmwareGate(_device(updateType: 3), ready: true, hasUpdate: true), FirmwareGateMode.none, reason: '弱提示红点亮也不弹');
    final wifi = _device(broadcastId: 'IJ_*');
    expect(wifiFirmwareHasUpdate(wifi, '0.6.1'), isTrue);
    expect(wifiFirmwareHasUpdate(wifi, '0.6.2'), isFalse);
    expect(wifiFirmwareHasUpdate(wifi, ''), isFalse, reason: 'WiFi 读不到当前版本 = 无法判断');
  });

  test('强提醒每次启动只弹一次', () {
    FirmwareRemindSession.reset();
    expect(FirmwareRemindSession.take('d2'), isTrue);
    expect(FirmwareRemindSession.take('d2'), isFalse, reason: '取消后本次启动不再弹');
    expect(FirmwareRemindSession.take('d3'), isTrue, reason: '按设备计');
    FirmwareRemindSession.reset();
    expect(FirmwareRemindSession.take('d2'), isTrue, reason: '重新打开 App 再提醒');
  });

  test('接入位置：只在详情页进入后', () {
    String read(String path) => _strip(File(path).readAsStringSync());
    final state = read('lib/src/state.dart');
    expect(state.contains("data['compulsory'], data['updateType'], data['upgradeType'], data['forceType']"), isTrue,
        reason: '详情出参 compulsory 优先');
    expect(state.contains('device.updateType = detail.updateType;'), isTrue, reason: '刷新详情时带回升级类型');

    final ble = read('lib/src/features/devices/presentation/device_details_page.dart');
    expect(ble.contains('_checkFirmwareOnEnter();'), isTrue, reason: '进入后判断一次');
    expect(ble.contains('unawaited(checkFirmwareGateOnEnter(context, state, device, ready: true, hasUpdate: _hasFirmwareUpdate(device, true)));'),
        isTrue, reason: '判定用红点结果');
    expect(ble.contains('onEditName: () => _renameDevice(context),'), isTrue);
    expect(ble.contains('onCarouselSettings: widget.onCarouselSettings,') && ble.contains('onClearDevice: widget.onClearDevice,'), isTrue);

    final wifi = read('lib/src/features/wifi/presentation/wifi_device_detail_page.dart');
    expect(wifi.contains('unawaited(_checkFirmwareOnEnter('), isTrue);
    expect(wifi.contains('await checkFirmwareGateOnEnter(context, widget.state, device,'), isTrue, reason: 'WiFi 详情进入时判断');
    expect(wifi.contains("onCast: () => TapGuard.run(this, 'projection', () => startWifiCast(context, widget.state, device)),"), isTrue);

    for (final (name, source) in [('蓝牙详情', ble), ('WiFi 详情', wifi)]) {
      expect(RegExp(r'_gated\(|_firmwareGate\(|forceOnly').hasMatch(source), isFalse, reason: '$name：功能按钮不再判断');
    }
    for (final path in [
      'lib/src/features/devices/presentation/devices_page.dart',
      'lib/src/features/wifi/wifi_cast_entry.dart',
      'lib/src/features/home/presentation/home_page.dart',
      'lib/src/features/devices/presentation/ota_upgrade_page.dart',
      'lib/src/features/wifi/presentation/wifi_ota_page.dart',
    ]) {
      expect(RegExp(r'firmware_gate|guardFirmwareAction|forceUpgradeCheck|markUpgraded').hasMatch(read(path)), isFalse,
          reason: '$path：不再判断 / 不再写缓存');
    }
    final gate = read('lib/src/features/devices/firmware_gate.dart');
    expect(RegExp(r'AppLoadingDialog|SharedPreferences|fw_gate_cache').hasMatch(gate), isFalse, reason: '不再 loading 现查、不再本地缓存');
  });
}
