import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:BoltStar/src/shared/debug_log.dart';

/// 联调日志（2026-11-12，同小程序 `utils/debug-log.js` + `components/debug-log`）：
/// 接管 debugPrint 记最近 500 行、入库前打码；左下角「日志 N」浮窗挂在 MaterialApp.builder 上；
/// IoT / WS / HTTP 各记一行摘要；分享页把「分享设备」置灰的原因写进日志。
void main() {
  final log = DebugLog.instance;

  setUp(log.resetForTest);

  test('测试环境（非 release）默认打开', () {
    expect(DebugLog.enabled, isTrue);
  });

  test('打码：JSON 字符串 / 非字符串、query、Bearer 与小程序同口径', () {
    expect(
      DebugLog.redact('{"userToken":"abc","pwd":"a,b c","n":1}'),
      '{"userToken":"***","pwd":"***","n":1}',
    );
    expect(DebugLog.redact('{"aiToken": 12345, "x": 2}'), '{"aiToken": ***, "x": 2}');
    expect(DebugLog.redact('GET /a?userToken=xyz&b=1'), 'GET /a?userToken=***&b=1');
    expect(DebugLog.redact('Authorization: Bearer abc.def-1'), 'Authorization: ***');
    expect(DebugLog.redact('header Bearer abc.def'), 'header Bearer ***');
    expect(DebugLog.redact('{"password":"p@ss"}'), '{"password":"***"}');
    expect(DebugLog.redact('[WiFi分享] 可以分享 设备 E348 产品 3'), '[WiFi分享] 可以分享 设备 E348 产品 3');
  });

  test('只留最近 500 行，超长截断，记录前打码', () {
    for (var i = 0; i < DebugLog.limit + 10; i++) {
      log.add('line $i');
    }
    expect(log.count, DebugLog.limit);
    expect(log.lines.first.text, endsWith(' line 10'));
    expect(log.lines.last.text, endsWith(' line ${DebugLog.limit + 9}'));

    log.add('x' * (DebugLog.maxLine + 5));
    expect(log.lines.last.text, contains('…（截断，共 ${DebugLog.maxLine + 5} 字）'));

    log.add('token=secret123');
    expect(log.lines.last.text, endsWith(' token=***'));
    expect(log.text, isNot(contains('secret123')));

    log.clear();
    expect(log.count, 0);
  });

  test('接管 debugPrint：原样输出并记一份；通知合并到微任务', () async {
    final saved = debugPrint;
    final printed = <String?>[];
    debugPrint = (String? message, {int? wrapWidth}) => printed.add(message);
    addTearDown(() => debugPrint = saved);

    var notified = 0;
    void listener() => notified++;
    log.addListener(listener);
    addTearDown(() => log.removeListener(listener));

    log.install();
    debugPrint('[WiFi分享] 测试一行');
    DebugLog.log('[IoT] GET /api/device/info → 成功 1ms 返回 {}');
    expect(printed, ['[WiFi分享] 测试一行', '[IoT] GET /api/device/info → 成功 1ms 返回 {}']);
    expect(log.lines.map((line) => line.text.substring(13)), [
      '[WiFi分享] 测试一行',
      '[IoT] GET /api/device/info → 成功 1ms 返回 {}',
    ]);
    expect(notified, 0, reason: '同步阶段不通知（可能在 build 里）');
    await Future<void>.delayed(Duration.zero);
    expect(notified, 1, reason: '同一轮多行只通知一次');
  });

  String read(String path) => File(path).readAsStringSync().replaceAll(RegExp(r'//[^\n]*'), '');

  test('挂载：main 最先 install，浮窗挂在 MaterialApp.builder，路由观察者只在开着时挂', () {
    final main = read('lib/main.dart');
    expect(main.indexOf('DebugLog.instance.install()'), lessThan(main.indexOf('_installCrashHandlers()')));
    final app = read('lib/src/app/bolt_star_app.dart');
    expect(app, contains('child: DebugLogOverlay('));
    expect(app, contains('if (DebugLog.enabled) _debugLogRouteObserver'));
    final overlay = read('lib/src/shared/widgets/debug_log_overlay.dart');
    expect(overlay, contains("'日志 \$count'"));
    expect(overlay, contains("_action('复制', onCopy)"));
    expect(overlay, contains("_action('清空', onClear)"));
    expect(overlay, contains('bottom: safeBottom + 110'));
    expect(overlay, contains('if (!DebugLog.enabled) {\n      return widget.child;'));
  });

  test('网络层摘要：HTTP 随开关打，IoT 每次请求一行，WS 状态 / 收发（心跳不记）', () {
    final api = read('lib/src/network/api_client.dart');
    expect(api, contains('kDebugMode || DebugLog.enabled'));
    expect(api, isNot(contains('if (!kDebugMode) return;')));
    final iot = read('lib/src/network/iot/iot_client.dart');
    expect(RegExp(r"_trace\('GET'").allMatches(iot).length, 2);
    expect(RegExp(r"_trace\('POST'").allMatches(iot).length, 2);
    expect(RegExp(r"_trace\('上传'").allMatches(iot).length, 2);
    final ws = read('lib/src/network/iot/iot_ws.dart');
    expect(ws, contains("DebugLog.log('[WS] 状态 → "));
    expect(ws, contains("message['type'] != 'ping'"));
    expect(ws, contains("decoded['type'] != 'pong'"));
  });

  test('分享页：置灰原因逐条写进日志（2026-11-12 起分享 H5 链接，不再依赖小程序原始 ID）', () {
    final share = read('lib/src/features/wifi/presentation/wifi_share_page.dart');
    expect(share, isNot(contains('WECHAT_MINI_PROGRAM_USERNAME')));
    expect(share, contains('WifiShareLink.h5Url('));
    expect(share, contains("'[WiFi分享] 分享按钮置灰：\${blockers.join('；')}'"));
    final blocked = share.substring(share.indexOf('if (!_canShare) {'));
    expect(blocked.indexOf('_logShareState();'), lessThan(blocked.indexOf('wifiShareUnavailable')));
  });
}
