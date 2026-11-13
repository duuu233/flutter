import 'dart:io';

import 'package:BoltStar/src/features/wifi/wifi_fpga.dart';
import 'package:BoltStar/src/features/wifi/wifi_ota.dart';
import 'package:BoltStar/src/features/wifi/wifi_share.dart';
import 'package:BoltStar/src/network/iot/iot_client.dart';
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

  group('渲染固件管理（2026-11-13）', () {
    test('只有 fpga16 才算；列表去掉未启用、按权重排、简介字段兜底；接口未开放', () {
      expect(isFpgaRenderMode(' FPGA16 '), isTrue);
      expect(isFpgaRenderMode('esp32'), isFalse);
      expect(isFpgaRenderMode(null), isFalse);
      final list = normalizeWifiFpgaVersions([
        {'id': 1, 'versionNumber': 'v1.01', 'verify': 1, 'grade': 1, 'downloadPath': 'https://a/f.bin', 'versionDesc': '一'},
        {'id': 2, 'versionNumber': 'v1.02', 'verify': 0, 'grade': 9},
        {'id': 3, 'versionNumber': 'v1.03', 'grade': 5, 'remark': '三'},
        {'id': 4, 'versionNumber': ''},
      ]);
      expect(list.map((e) => [e.version, e.intro]).toList(), [
        ['v1.03', '三'],
        ['v1.01', '一'],
      ]);
      expect(list.last.hasValidUrl, isTrue);
      expect(list.first.hasValidUrl, isFalse);
      expect(wifiFpgaListApiReady(), isFalse, reason: '用户端列表接口待后端提供');
    });

    test('本地记录带 otaType 与简介；旧记录缺省为 main', () async {
      SharedPreferences.setMockInitialValues({});
      await WifiOtaStore.save('AABBCCDDEEFF', 'f1', version: 'v1.02', otaType: kWifiOtaTypeFpga, intro: '修复闪烁');
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

    test('接入位置：设备信息页按渲染模式显示入口，安装复用升级页并传 type=fpga', () {
      String read(String path) => File(path).readAsStringSync();
      final info = read('lib/src/features/wifi/presentation/wifi_device_info_page.dart');
      expect(info.contains('isFpgaRenderMode(renderMode)'), isTrue);
      expect(info.contains("ValueKey('wifi-fpga-entry')"), isTrue);
      final ota = read('lib/src/features/wifi/presentation/wifi_ota_page.dart');
      expect(ota.contains('type: _otaType'), isTrue, reason: '复用 /api/device/ota，type 跟着模式');
      expect(ota.contains('otaType: _otaType, intro: _intro'), isTrue, reason: '本地记录带类型');
      expect(ota.contains('_otaType = record.otaType;'), isTrue, reason: '重进按记录选文字');
      final list = read('lib/src/features/wifi/presentation/wifi_fpga_page.dart');
      expect(list.contains('WifiOtaPage(state: widget.state, deviceId: widget.deviceId, fpgaTarget: target)'), isTrue);
    });
  });
}
