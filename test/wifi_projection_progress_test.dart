import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:BoltStar/src/features/wifi/wifi_projection.dart';
import 'package:BoltStar/src/network/iot/iot_client.dart';
import 'package:BoltStar/src/shared/l10n/app_l10n.dart';
import 'package:BoltStar/src/state.dart' show AppLanguage;

/// WiFi 投屏进度条（2026-10-29 同步小程序 `tests/wifi-projection.test.js`）：上传折算到前半段，
/// 处理阶段按时间渐近爬向 99、只增不减、不到 100；100% 只在接口返回 SENT / UPLOADED 时给出。
void main() {
  test('处理阶段从 50 起只增不减，永不到 100', () {
    var last = WifiProjection.uploadShare;
    for (final ms in [0, 200, 1000, 3000, 8000, 60000]) {
      final value = WifiProjection.processingProgress(WifiProjection.uploadShare, ms);
      expect(value, greaterThanOrEqualTo(last));
      expect(value, lessThan(100));
      last = value;
    }
    expect(WifiProjection.processingProgress(50, 1000), 63);
    expect(WifiProjection.processingProgress(50, 3000), 80);
  });

  test('接口 status 归一', () {
    expect(WifiProjection.resultStatus({'status': 'DOWNLOADING'}, true), 'SENT');
    expect(WifiProjection.resultStatus({'status': 'FAILED'}, true), 'FAILED');
    expect(WifiProjection.resultStatus(const {}, false), 'UPLOADED');
  });

  group('幂等键 Idempotency-Key（2026-11-13）', () {
    test('UUID v4 形状、互不相同、≤ 64 字符', () {
      final keys = List.generate(200, (_) => WifiProjection.newPlayKey());
      final pattern = RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$');
      expect(keys.every(pattern.hasMatch), isTrue);
      expect(keys.toSet().length, keys.length);
      expect(keys.every((key) => key.length <= 64), isTrue);
    });

    test('4090：同一键首次请求还在处理中，可重试', () {
      try {
        parseIotResponse(200, {'code': 4090, 'msg': 'in progress'}, l10n: const AppL10n(AppLanguage.zh));
        fail('应抛 IotException');
      } on IotException catch (error) {
        expect(error.code, 4090);
        expect(error.message, '处理中，请稍后重试');
        expect(error.isRetryable, isTrue);
      }
    });

    test('批量投屏每张图一个新键（不是一批共用一个）；重试同一张同样刷屏方式复用；Header 带、不进表单', () {
      final page = File('lib/src/features/wifi/presentation/wifi_cast_result_page.dart').readAsStringSync();
      expect(page.contains("_playKeys.putIfAbsent('\$index:\$refresh', WifiProjection.newPlayKey)"), isTrue,
          reason: '键按「图片序号 + 是否刷屏」存，每张图各生成一个');
      expect(page.contains('final Map<String, String> _playKeys = {};'), isTrue, reason: '随页面实例新建：新进入结果页全部新键');
      expect(page.contains('idempotencyKey: idempotencyKey,'), isTrue);
      final api = File('lib/src/network/iot/iot_api.dart').readAsStringSync();
      expect(api.contains("headers: {if (idempotencyKey.isNotEmpty) 'Idempotency-Key': idempotencyKey},"), isTrue);
      final client = File('lib/src/network/iot/iot_client.dart').readAsStringSync();
      expect(client.contains('..headers.addAll(_headers(headers))'), isTrue);
    });
  });

  test('步骤卡只在单张投屏显示，批量照原样不显示（2026-11-13）', () {
    final page = File('lib/src/features/wifi/presentation/wifi_cast_result_page.dart').readAsStringSync();
    expect(RegExp(r'if \(total <= 1\) \.\.\.\[\s*const SizedBox\(height: 14\),\s*_buildSteps\(l10n\),\s*\],').hasMatch(page), isTrue);
    expect('_buildSteps(l10n)'.allMatches(page).length, 1, reason: '只有一处渲染步骤卡');
  });
}
