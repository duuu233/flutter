import 'dart:io';

import 'package:BoltStar/src/features/wifi/wifi_fpga.dart';
import 'package:BoltStar/src/features/wifi/wifi_ota.dart';
import 'package:BoltStar/src/features/wifi/wifi_share.dart';
import 'package:BoltStar/src/network/iot/iot_client.dart';
import 'package:BoltStar/src/state.dart';
import 'package:BoltStar/src/device/frame_device_protocol.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// WiFi 版固件升级（2026-11-02，同小程序 tests/wifi-ota.test.js 的口径）。
void main() {
  group('步骤展示', () {
    test('SENT / DOWNLOADING / FLASHING 当前步转圈，之前打勾', () {
      expect(otaStepsFor('SENT').steps, [
        WifiOtaStepState.loading,
        WifiOtaStepState.pending,
        WifiOtaStepState.pending,
        WifiOtaStepState.pending,
      ]);
      final flashing = otaStepsFor('flashing');
      expect(flashing.phase, WifiOtaViewPhase.running);
      expect(flashing.steps, [
        WifiOtaStepState.done,
        WifiOtaStepState.done,
        WifiOtaStepState.loading,
        WifiOtaStepState.pending,
      ]);
    });

    test('VERIFYING 四步全勾，是步骤页的成功终点但不是终态', () {
      final view = otaStepsFor('VERIFYING');
      expect(view.phase, WifiOtaViewPhase.verifying);
      expect(view.steps, everyElement(WifiOtaStepState.done));
      expect(isOtaFinal('VERIFYING'), isFalse);
      expect(isOtaFinal('SUCCESS'), isTrue);
    });

    test('FAILED / TIMEOUT 在最后到达的那一步打叉', () {
      final failed = otaStepsFor('FAILED', 1);
      expect(failed.phase, WifiOtaViewPhase.failed);
      expect(failed.failedStep, 1);
      expect(failed.steps, [
        WifiOtaStepState.done,
        WifiOtaStepState.fail,
        WifiOtaStepState.pending,
        WifiOtaStepState.pending,
      ]);
      expect(otaStepsFor('TIMEOUT').failedStep, 0, reason: '没到过任何一步按第 1 步');
      expect(isOtaTimeout('timeout'), isTrue);
    });

    test('不认识的值（含 UPLOADED）停在已到达的一步转圈', () {
      final view = otaStepsFor('UPLOADED', 2);
      expect(view.phase, WifiOtaViewPhase.unknown);
      expect(view.steps[2], WifiOtaStepState.loading);
      expect(otaStepIndex('UPLOADED'), -1);
    });
  });

  group('进度条（2026-11-12）', () {
    test('progress：数字 / 数字串取整夹到 0~100，null / 缺省 / 非数字为不上报', () {
      expect(parseOtaProgress(40), 40);
      expect(parseOtaProgress('60'), 60);
      expect(parseOtaProgress(130), 100);
      expect(parseOtaProgress(null), isNull);
      expect(parseOtaProgress('abc'), isNull);
    });

    test('上限：没收到停 19；收到 20/40/60/80 走到下一档减 1（80 之后 98）；状态不放开分档；无数值进入写入 98；VERIFYING 100', () {
      expect(otaProgressCap('SENT', null), 19);
      expect(otaProgressCap('DOWNLOADING', 20), 39);
      expect(otaProgressCap('DOWNLOADING', 40), 59);
      expect(otaProgressCap('DOWNLOADING', 60), 79);
      expect(otaProgressCap('DOWNLOADING', 80), 98);
      expect(otaProgressCap('DOWNLOADING', null), 19, reason: '进入下载但 20 还没到：仍停 19 等 20');
      expect(otaProgressCap('FLASHING', 40), 59, reason: '写入阶段也要等 60：状态不放开分档');
      expect(otaProgressCap('FLASHING', 60), 79, reason: '79 等 80');
      expect(otaProgressCap('FLASHING', 80), 98);
      expect(otaProgressCap('FLASHING', null), 98, reason: '没有任何数值就进入写入：固件不上报');
      expect(otaProgressCap('VERIFYING', 80), 100);
      expect(otaProgressCap('SUCCESS', null), 100);
    });

    test('进度文案取当前那一步：转圈 / 打叉的那一步，全勾为最后一步', () {
      expect(otaActiveStep(otaStepsFor('DOWNLOADING')), 1);
      expect(otaActiveStep(otaStepsFor('VERIFYING')), 3);
      expect(otaActiveStep(otaStepsFor('TIMEOUT', 2)), 2);
    });

    test('本地记录保存收到过的最大进度，偶发的 null 不覆盖', () async {
      SharedPreferences.setMockInitialValues({});
      await WifiOtaStore.save('AABBCCDDEEFF', 'm1');
      var result = await WifiOtaStore.refresh('AABBCCDDEEFF', getStatus: (_) async => {'status': 'DOWNLOADING', 'progress': 40});
      expect(result.record?.progress, 40);
      result = await WifiOtaStore.refresh('AABBCCDDEEFF', getStatus: (_) async => {'status': 'DOWNLOADING', 'progress': null});
      expect(result.record?.progress, 40);
      expect((await WifiOtaStore.read('AABBCCDDEEFF'))?.progress, 40);
    });
  });

  group('版本比较', () {
    test('x.y.z 目标更高才算有新版本，包地址须 http(s)', () {
      expect(evaluateWifiOta('1.0.2', '1.0.10', 'https://oss/a.bin').state, WifiOtaCheckState.available);
      expect(evaluateWifiOta('v1.2.0', '1.2.0', 'https://oss/a.bin').state, WifiOtaCheckState.latest);
      expect(evaluateWifiOta('1.3', '1.2.9', 'https://oss/a.bin').state, WifiOtaCheckState.latest);
      expect(evaluateWifiOta('1.0.0', '1.1.0', 'ftp://x').state, WifiOtaCheckState.invalid);
    });

    test('目标为空 → 已是最新；当前读不到或旧格式 → 无法判断；目标非 x.y.z → 不相同即有新版本', () {
      expect(evaluateWifiOta('1.0.0', '', '').state, WifiOtaCheckState.latest);
      expect(evaluateWifiOta('', '1.1.0', 'https://a').state, WifiOtaCheckState.unknown);
      expect(evaluateWifiOta('M H:3 F:0.6.1', '1.1.0', 'https://a').state, WifiOtaCheckState.unknown);
      expect(evaluateWifiOta('1.0.0', 'V2-beta', 'https://a').state, WifiOtaCheckState.available);
    });

    test('当前固件版本取 firmwareVersion，没有再取 shadow.version', () {
      expect(wifiFirmwareVersion({'firmwareVersion': ' 1.2.3 '}), '1.2.3');
      expect(wifiFirmwareVersion({'shadow': {'version': '1.0.1'}}), '1.0.1');
      expect(wifiFirmwareVersion(null), '');
    });
  });

  test('已有升级任务：4045 一律是；4000 文案为空或提到升级 / 进行中才算', () {
    IotException error(Object code, [String message = '']) => IotException(
      code: code,
      message: 'x',
      action: IotErrorAction.none,
      serverMessage: message,
    );
    expect(isWifiOtaBusyError(error(4045)), isTrue);
    expect(isWifiOtaBusyError(error(4000)), isTrue);
    expect(isWifiOtaBusyError(error(4000, '已有升级任务进行中')), isTrue);
    expect(isWifiOtaBusyError(error('4000', 'url 格式不正确')), isFalse);
    expect(isWifiOtaBusyError(error(4041)), isFalse);
    expect(isWifiOtaBusyError(Exception('x')), isFalse);
  });

  group('本地进行中记录', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('按设备存 ota 类型记录，类型不对不认', () async {
      await WifiOtaStore.save('AA:BB:CC:DD:EE:FF', 'm1', version: '1.1.0', baseVersion: '1.0.0');
      final record = await WifiOtaStore.read('aabbccddeeff');
      expect(record?.msgid, 'm1');
      expect(record?.status, 'SENT');
      expect(record?.lastStep, 0);
      expect(WifiOtaStore.storageKey('aa:bb:cc:dd:ee:ff'), 'ota_inflight:AABBCCDDEEFF');
      SharedPreferences.setMockInitialValues({'ota_inflight:AABBCCDDEEFF': '{"type":"play","msgid":"x"}'});
      expect(await WifiOtaStore.read('AABBCCDDEEFF'), isNull);
    });

    test('核对：进行中更新状态与到过的最远一步；终态清记录；4044 清记录；查询失败保留', () async {
      await WifiOtaStore.save('AABBCCDDEEFF', 'm1');
      var result = await WifiOtaStore.refresh('AABBCCDDEEFF', getStatus: (_) async => {'status': 'FLASHING'});
      expect(result.record?.status, 'FLASHING');
      expect(result.record?.lastStep, 2);
      result = await WifiOtaStore.refresh('AABBCCDDEEFF', getStatus: (_) async => throw Exception('net'));
      expect(result.record, isNotNull, reason: '网络失败保留记录');
      result = await WifiOtaStore.refresh('AABBCCDDEEFF', getStatus: (_) async => {'status': 'SUCCESS'});
      expect(result.record, isNull);
      expect(await WifiOtaStore.read('AABBCCDDEEFF'), isNull);

      await WifiOtaStore.save('AABBCCDDEEFF', 'm2');
      result = await WifiOtaStore.refresh(
        'AABBCCDDEEFF',
        getStatus: (_) async => throw IotException(code: 4044, message: 'x', action: IotErrorAction.none),
      );
      expect(result.expired, isTrue);
      expect(await WifiOtaStore.read('AABBCCDDEEFF'), isNull);
    });
  });

  test('分享成员加入时间只取 joinTime（同小程序 2026-10-29）', () {
    expect(WifiShareMember.fromRow({'userProductId': 1, 'joinTime': '2026-10-29 10:00', 'createTime': 'x'}).joinedAt, '2026-10-29 10:00');
    expect(WifiShareMember.fromRow({'userProductId': 1, 'createTime': '2026-10-01'}).joinedAt, '');
  });

  group('优雅刷新升级（2026-11-13，原名渲染固件管理）', () {
    test('只有 fpga16 才算', () {
      expect(isFpgaRenderMode(' FPGA16 '), isTrue);
      expect(isFpgaRenderMode('esp32'), isFalse);
      expect(isFpgaRenderMode(null), isFalse);
    });

    // 2026-11-14 有意改口径：优雅刷新不做红点——原「本机看过就不亮 / 版本比较 / 看过的版本缓存」各条撤掉，
    // 只留最新版本取自设备详情；「不再显示红点、不再记看过的版本」由下面「接入位置」守
    test('最新版本来自设备详情', () {
      DeviceItem device({String version = '1.0.3', String url = 'https://oss/f.bin'}) => DeviceItem(
        id: 'd1',
        name: '',
        kind: '',
        screenType: FrameScreenType.inch589,
        batteryLevel: 0,
        charging: false,
        connected: false,
        role: DeviceRole.owner,
        serialNumber: 'AA:BB:CC:DD:EE:FF',
        hardwareVersion: '',
        firmwareVersion: '',
        imageMask: 0,
        currentImageIndex: -1,
        playbackMode: FramePlaybackMode.sequence,
        carouselIntervalSeconds: 0,
        carouselEnabled: false,
        fpgaVersionNo: version,
        fpgaDownloadPath: url,
        fpgaUpgradeTips: '修复闪烁',
      );
      expect(wifiFpgaLatestOf(device())?.intro, '修复闪烁', reason: '版本说明取 upgradeTipsFpga');
      expect(wifiFpgaLatestOf(device(version: '')), isNull);
      expect(wifiFpgaLatestOf(device())!.hasValidUrl, isTrue);
      expect(wifiFpgaLatestOf(device(url: 'ftp://x'))!.hasValidUrl, isFalse);
    });

    test('本地记录带 otaType 与版本说明；旧记录缺省为 main', () async {
      SharedPreferences.setMockInitialValues({});
      await WifiOtaStore.save('AABBCCDDEEFF', 'f1', version: '1.0.3', otaType: kWifiOtaTypeFpga, intro: '修复闪烁');
      var record = await WifiOtaStore.read('AABBCCDDEEFF');
      expect(record?.otaType, kWifiOtaTypeFpga);
      expect(record?.intro, '修复闪烁');
      final result = await WifiOtaStore.refresh('AABBCCDDEEFF', getStatus: (_) async => {'status': 'DOWNLOADING', 'progress': 20});
      expect(result.record?.otaType, kWifiOtaTypeFpga, reason: '刷新状态后类型保留');
      SharedPreferences.setMockInitialValues({'ota_inflight:AABBCCDDEEFF': '{"type":"ota","msgid":"m"}'});
      record = await WifiOtaStore.read('AABBCCDDEEFF');
      expect(record?.otaType, kWifiOtaTypeMain);
      expect(record!.toJson().containsKey('otaType'), isFalse);
    });

    test('4047 = 今日升级次数已达上限', () {
      IotException err(Object code) => IotException(code: code, message: 'x', action: IotErrorAction.none);
      expect(isWifiFpgaLimitError(err(4047)), isTrue);
      expect(isWifiFpgaLimitError(err('4047')), isTrue);
      expect(isWifiFpgaLimitError(err(4045)), isFalse);
      expect(isWifiFpgaLimitError(Exception('x')), isFalse);
    });

    test('接入位置：没有版本列表；入口直接进安装页；不做红点；不显示设备版本号；4047 单独提示', () {
      String read(String path) => File(path).readAsStringSync();
      expect(File('lib/src/features/wifi/presentation/wifi_fpga_page.dart').existsSync(), isFalse, reason: '版本列表页已去掉');
      final state = read('lib/src/state.dart');
      expect(state.contains("data['newVersionNoFpga']") && state.contains("data['upgradeTipsFpga']"), isTrue);
      expect(state.contains('device.fpgaVersionNo = detail.fpgaVersionNo;'), isTrue, reason: '刷新详情时带回最新版本');
      final info = read('lib/src/features/wifi/presentation/wifi_device_info_page.dart');
      expect(info.contains('isFpgaRenderMode(renderMode)'), isTrue);
      expect(info.contains("ValueKey('wifi-fpga-entry')"), isTrue);
      expect(info.contains("ValueKey('wifi-fpga-dot')") || info.contains('wifiFpgaHasNew'), isFalse, reason: '入口不做红点');
      expect(info.contains('WifiOtaPage(state: widget.state, deviceId: widget.deviceId, fpga: true)'), isTrue);
      expect(info.contains('fpgaVersion\''), isFalse, reason: '不显示设备 FPGA 版本号');
      // 2026-11-14：入口不等网络——用详情页解析过的渲染模式进页即显示，不随信息行加载态隐藏；文字与上面标签同样式
      expect(info.contains('widget.state.cachedRenderMode(widget.deviceId)'), isTrue);
      expect(info.contains('if (_fpga) ...['), isTrue);
      expect(info.contains('_fpga && status.status != WifiOnlineStatus.loading'), isFalse);
      expect(state.contains('_renderModes[device.id] = mode;'), isTrue, reason: '解析过的渲染模式按设备记一份');
      final detail = read('lib/src/features/wifi/presentation/wifi_device_detail_page.dart');
      expect(detail.contains("ValueKey('wifi-info-dot')") || detail.contains('wifiFpgaHasNew'), isFalse, reason: '「设备信息」不做红点');
      expect(detail.contains('widget.state.resolveRenderMode(_device)'), isTrue, reason: '详情页先解析渲染模式，设备信息页入口进页即显示');
      final ota = read('lib/src/features/wifi/presentation/wifi_ota_page.dart');
      expect(ota.contains('type: _otaType'), isTrue, reason: '复用 /api/device/ota，type 跟着模式');
      expect(ota.contains('otaType: _otaType, intro: _intro'), isTrue, reason: '本地记录带类型');
      expect(ota.contains('_otaType = record.otaType;'), isTrue, reason: '重进按记录选文字');
      expect(ota.contains('WifiFpgaSeenStore'), isFalse, reason: '不再记看过的版本');
      expect(ota.contains('if (!_fpga) _VersionRow(label: l10n.wifiOtaCurrentVersion'), isTrue);
      expect(ota.contains('if (isWifiFpgaLimitError(error))'), isTrue, reason: '下发 4047 单独提示');
      expect(ota.contains("ValueKey('wifi-fpga-intro')"), isTrue, reason: '显示版本说明');
      expect(RegExp(r"if \(!_fpga\) \.\.\.\[\s*Image\.asset\(\s*art,\s*key: const ValueKey\('wifi-ota-art'\)").hasMatch(ota), isTrue,
          reason: '优雅刷新升级不显示顶部图标（2026-11-14），固件升级照旧');
    });
  });
}
