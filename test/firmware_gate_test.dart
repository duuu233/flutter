import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:BoltStar/src/device/frame_device_protocol.dart';
import 'package:BoltStar/src/features/devices/firmware_gate.dart';
import 'package:BoltStar/src/state.dart';

/// 固件强制升级 / 强提醒升级判断（2026-11-13，同小程序 tests/firmware-gate.test.js）。
///
/// ① 升级类型：updateType 1 = 强制、2 = 强提醒，3 弱提示 / 4 不提示及其它不弹（只亮红点，改动前逻辑）；
/// ② 判断前提：WiFi 在线 / 蓝牙已连接才判（ready），有进行中的升级不弹，列表页 / 首页只判强制（forceOnly）；
/// ③ 有没有新版本与详情页红点同一判定（蓝牙读不到版本退回 isUpdate、包必须是 .bin；WiFi 读不到版本不弹）；
/// ⑤ 同日产品复核：强提醒只在进入详情页时弹、每次启动一次；详情页按钮只判强制；列表页 / 首页每次启动第一次
///    loading 现查并写本地缓存，之后按缓存判断；升级完成缓存改成无需升级。
/// ④ 接入位置：两个详情页（进入后 + 功能按钮）、我的设备投屏 / 轮播设置、首页拍照 / 相册投屏。
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
  TestWidgetsFlutterBinding.ensureInitialized();

  test('升级类型取后台 compulsory：1 强制、2 强提醒，3 / 4 不弹', () {
    expect(firmwareGateModeOf(_device(updateType: 1)), FirmwareGateMode.force);
    expect(firmwareGateModeOf(_device(updateType: 2)), FirmwareGateMode.remind);
    expect(firmwareGateModeOf(_device(updateType: 3)), FirmwareGateMode.none, reason: '弱提示：只亮红点');
    expect(firmwareGateModeOf(_device(updateType: 4)), FirmwareGateMode.none, reason: '不提示');
    expect(firmwareGateModeOf(_device()), FirmwareGateMode.none, reason: '没给不弹');
    expect(decideFirmwareGate(_device(updateType: 3), ready: true, hasUpdate: true), FirmwareGateMode.none,
        reason: '弱提示红点亮也不弹');
  });

  test('本地缓存：本次启动查过才用，升级完成改成无需升级；强提醒每次启动一次', () async {
    SharedPreferences.setMockInitialValues({});
    FirmwareGateCache.resetSession();
    expect(await FirmwareGateCache.cached('d1'), isNull, reason: '没查过：现查');
    await FirmwareGateCache.remember('d1', FirmwareGateMode.force, '0.6.2');
    expect(await FirmwareGateCache.cached('d1'), (FirmwareGateMode.force, '0.6.2'));
    await FirmwareGateCache.markUpgraded('d1');
    expect((await FirmwareGateCache.cached('d1'))!.$1, FirmwareGateMode.none, reason: '升级完成不再弹');
    FirmwareGateCache.resetSession();
    expect(await FirmwareGateCache.cached('d1'), isNull, reason: '重新打开 App：第一次点重新现查');
    expect(FirmwareGateCache.takeRemind('d2'), isTrue);
    expect(FirmwareGateCache.takeRemind('d2'), isFalse, reason: '强提醒本次启动只弹一次');
    FirmwareGateCache.resetSession();
    expect(FirmwareGateCache.takeRemind('d2'), isTrue, reason: '重新打开 App 再提醒');
  });

  test('判断前提：未就绪 / 无新版本 / 进行中不弹；列表页首页只判强制', () {
    final force = _device(updateType: 1);
    final remind = _device(updateType: 2);
    expect(decideFirmwareGate(force, ready: true, hasUpdate: true), FirmwareGateMode.force);
    expect(decideFirmwareGate(force, ready: false, hasUpdate: true), FirmwareGateMode.none, reason: '离线 / 未连接不判');
    expect(decideFirmwareGate(force, ready: true, hasUpdate: false), FirmwareGateMode.none, reason: '红点不亮不弹');
    expect(decideFirmwareGate(force, ready: true, hasUpdate: true, inflight: true), FirmwareGateMode.none, reason: '进行中的升级不弹');
    expect(decideFirmwareGate(remind, ready: true, hasUpdate: true), FirmwareGateMode.remind);
    expect(decideFirmwareGate(remind, ready: true, hasUpdate: true, forceOnly: true), FirmwareGateMode.none, reason: '列表页 / 首页不弹强提醒');
    expect(decideFirmwareGate(force, ready: true, hasUpdate: true, forceOnly: true), FirmwareGateMode.force);
  });

  test('有没有新版本：与红点同一判定', () {
    expect(bleFirmwareHasUpdate(_device(), '0.6.1'), isTrue);
    expect(bleFirmwareHasUpdate(_device(), '0.6.2'), isFalse, reason: '版本相同');
    expect(bleFirmwareHasUpdate(_device(url: 'https://oss/fw.zip'), '0.6.1'), isFalse, reason: '不是 .bin 不弹');
    expect(bleFirmwareHasUpdate(_device(isUpdate: 1), ''), isTrue, reason: '读不到版本退回 isUpdate');
    expect(bleFirmwareHasUpdate(_device(), ''), isFalse);
    final wifi = _device(broadcastId: 'IJ_*');
    expect(wifiFirmwareHasUpdate(wifi, '0.6.1'), isTrue);
    expect(wifiFirmwareHasUpdate(wifi, '0.6.2'), isFalse);
    expect(wifiFirmwareHasUpdate(wifi, ''), isFalse, reason: 'WiFi 读不到当前版本 = 无法判断');
  });

  test('接入位置', () {
    String read(String path) => _strip(File(path).readAsStringSync());
    final state = read('lib/src/state.dart');
    expect(state.contains("data['compulsory'], data['updateType'], data['upgradeType'], data['forceType']"), isTrue,
        reason: '详情出参 compulsory 优先');
    expect(state.contains('device.updateType = detail.updateType;'), isTrue, reason: '刷新详情时带回升级方式');

    final ble = read('lib/src/features/devices/presentation/device_details_page.dart');
    expect(ble.contains('onEditName: _gated('), isTrue);
    expect(ble.contains('onCarouselSettings: _gated(widget.onCarouselSettings),'), isTrue);
    expect(ble.contains('onClearDevice: _gated(widget.onClearDevice),'), isTrue);
    expect(ble.contains('onUnbindDevice: widget.onUnbindDevice,') && ble.contains('onDeleteDevice: widget.onDeleteDevice,'), isTrue,
        reason: '解除绑定 / 删除设备不判断');
    expect(RegExp(r'await _firmwareGate\(\)[\s\S]*?_pickCastSource\(context\)').hasMatch(ble), isTrue, reason: '投屏连上之后判断');
    expect(ble.contains('_checkFirmwareOnEnter();'), isTrue, reason: '进入后判断一次');
    expect(ble.contains('hasUpdate: _hasFirmwareUpdate(device, connected)'), isTrue, reason: '判定用红点结果');
    expect(ble.contains('hasUpdate: _hasFirmwareUpdate(device, connected), forceOnly: true'), isTrue, reason: '按钮只判强制');
    expect(ble.contains('unawaited(checkFirmwareGateOnEnter(context, state, device,'), isTrue, reason: '进入时强制 + 强提醒');

    final wifi = read('lib/src/features/wifi/presentation/wifi_device_detail_page.dart');
    for (final gated in [
      // 2026-11-13：设备信息改为 await 返回后重算优雅刷新红点，固件升级判断照旧包在 _gated 里
      '_gated(() async {\n              await Navigator.of(context).push<void>(\n                AppPageRoute(builder: (_) => WifiDeviceInfoPage(',
      '_gated(_openMessages)',
      '_gated(() => _openTf(',
      '_gated(() => _push(WifiSharePage(',
      'onTap: _gated(() => startWifiClearFlow(',
      'onSlideshow: _gated(() => openWifiSlideshow(',
    ]) {
      expect(wifi.contains(gated), isTrue, reason: gated);
    }
    expect(RegExp(r"TapGuard\.run\(this, 'projection', \(\) async \{\s*if \(await _firmwareGate\(\)").hasMatch(wifi), isTrue);
    expect(wifi.contains('unawaited(_checkFirmwareOnEnter('), isTrue);
    expect(wifi.contains('onTap: () => startWifiUnbindFlow('), isTrue, reason: '解除绑定不判断');
    expect(wifi.contains('hasUpdate: hasUpdate, forceOnly: true'), isTrue, reason: 'WiFi 详情按钮只判强制');
    expect(wifi.contains('await checkFirmwareGateOnEnter(context, widget.state, device,'), isTrue, reason: 'WiFi 详情进入时强制 + 强提醒');
    expect(read('lib/src/features/devices/presentation/ota_upgrade_page.dart').contains('unawaited(FirmwareGateCache.markUpgraded(widget.deviceId));'),
        isTrue, reason: '蓝牙升级成功：更新缓存');
    expect(RegExp(r'if \(!_fpga\) \{\s*unawaited\(FirmwareGateCache\.markUpgraded\(widget\.deviceId\)\);')
        .hasMatch(read('lib/src/features/wifi/presentation/wifi_ota_page.dart')), isTrue, reason: 'WiFi 主固件升级完成：更新缓存');
    final gate = read('lib/src/features/devices/firmware_gate.dart');
    expect(RegExp(r'if \(hit == null\) \{[\s\S]*?AppLoadingDialog\.show\(context\);[\s\S]*?FirmwareGateCache\.remember\(').hasMatch(gate), isTrue,
        reason: '列表页 / 首页：没查过才 loading 现查并写缓存');

    final list = read('lib/src/features/devices/presentation/devices_page.dart');
    expect('forceUpgradeCheck: true'.allMatches(list).length, 2, reason: '我的设备 WiFi 投屏 / 轮播设置');
    expect(RegExp(r'_ensureConnected\(context, deviceId\)[\s\S]*?guardFirmwareAction\(context, state,[\s\S]*?_pickCastSource').hasMatch(list),
        isTrue, reason: '我的设备蓝牙投屏：连上之后判断');
    final entry = read('lib/src/features/wifi/wifi_cast_entry.dart');
    expect('if (forceUpgradeCheck && (!await guardFirmwareAction(context, state, device)'.allMatches(entry).length, 2);

    final home = read('lib/src/features/home/presentation/home_page.dart');
    expect(RegExp(r'ensureWifiDeviceOnline[\s\S]*?guardFirmwareAction\(context, widget\.state, activeDevice, online: activeDevice\.isWifi\)[\s\S]*?CastPhotoPicker')
        .hasMatch(home), isTrue, reason: '首页拍照 / 相册投屏：在线 / 连上之后判断');
  });
}
