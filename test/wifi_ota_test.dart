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
}
