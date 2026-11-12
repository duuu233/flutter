import 'dart:async';

import 'package:flutter/foundation.dart';

/// 联调日志（2026-11-12，同小程序 `utils/debug-log.js`）：每个页面左下角一颗「日志 N」小药丸
/// （[DebugLogOverlay]，挂在 `MaterialApp.builder` 上，所有页面都有），点开看、一键复制、清空。
///
/// 来源：
///   · `main()` 最先 [install]：接管全局 [debugPrint]，控制台照常输出的同时记一份——项目里已有的
///     `[WiFi分享]`、`[WiFi投屏]`、`[HTTP]` 等日志不用改就都能看到（Flutter 框架报错也走 debugPrint）；
///   · IoT 请求 `[IoT]`、长连接 `[WS]` 各记一行摘要（`iot_client.dart` / `iot_ws.dart`）；
///   · 路由观察者记一行「页面 → 路由」（[DebugLogRouteObserver]）。
/// 只在内存里留最近 [limit] 行，不落盘；token、密码类字段在入库前统一打码（[redact]）。
///
/// 开关 [enabled]：默认开（2026-11-12 改，同花盆APP；iOS 测试走 Archive / TestFlight 是 release 包，原先默认关时看不到浮窗）。
/// 正式上架包打包加 `--dart-define=APP_DEBUG_TOOLS=false` 关掉（整套不收集、不显示）。
class DebugLog extends ChangeNotifier {
  DebugLog._();

  static final DebugLog instance = DebugLog._();

  static const bool enabled = bool.fromEnvironment(
    'APP_DEBUG_TOOLS',
    defaultValue: true,
  );

  static const int limit = 500;
  static const int maxLine = 2000;

  /// 记一行联调日志（开关关着时什么都不做）。已 [install] 时经 debugPrint 记入，控制台同时可见。
  static void log(String line) {
    if (enabled) {
      debugPrint(line);
    }
  }

  final List<DebugLogLine> _lines = <DebugLogLine>[];
  int _seq = 0;
  bool _installed = false;
  bool _notifyScheduled = false;

  List<DebugLogLine> get lines => List<DebugLogLine>.unmodifiable(_lines);

  int get count => _lines.length;

  String get text => _lines.map((line) => line.text).join('\n');

  /// 接管 [debugPrint]：原样输出，同时记一份。只装一次；开关关着时不装。
  void install() {
    if (_installed || !enabled) {
      return;
    }
    _installed = true;
    final original = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      original(message, wrapWidth: wrapWidth);
      add(message ?? '');
    };
  }

  /// 记一行。超长截断，入库前打码。
  void add(String message) {
    if (!enabled) {
      return;
    }
    var text = message;
    if (text.length > maxLine) {
      text = '${text.substring(0, maxLine)}…（截断，共 ${text.length} 字）';
    }
    _seq += 1;
    _lines.add(DebugLogLine(_seq, '${_timeText(DateTime.now())} ${redact(text)}'));
    if (_lines.length > limit) {
      _lines.removeRange(0, _lines.length - limit);
    }
    _scheduleNotify();
  }

  void clear() {
    _lines.clear();
    _scheduleNotify();
  }

  /// 日志可能在 build 期间产生（页面 build 里打的 debugPrint），不能同步通知浮窗 setState：
  /// 合并到微任务里统一通知一次。
  void _scheduleNotify() {
    if (_notifyScheduled) {
      return;
    }
    _notifyScheduled = true;
    scheduleMicrotask(() {
      _notifyScheduled = false;
      notifyListeners();
    });
  }

  /// 测试用：清空并重置序号。
  @visibleForTesting
  void resetForTest() {
    _lines.clear();
    _seq = 0;
  }

  static String _two(int n) => n.toString().padLeft(2, '0');

  static String _timeText(DateTime now) =>
      '${_two(now.hour)}:${_two(now.minute)}:${_two(now.second)}.${now.millisecond.toString().padLeft(3, '0')}';

  // token / 密码类字段打码（与小程序同一套规则）：JSON 字符串值（"pwd":"a,b c" 整段到右引号）、JSON 非字符串值、
  // query / 文本（userToken=xx、token: xx）、Header（Bearer xx）都认；键名含 token 的（aiToken 等）一并打码。
  static const String _keys = r'[A-Za-z]*token|Authorization|Authentication|pwd|password|passwd|secret';
  static final RegExp _jsonString = RegExp(
    r'("(?:' + _keys + r')"\s*:\s*")(?:\\.|[^"\\])*"',
    caseSensitive: false,
  );
  static final RegExp _jsonOther = RegExp(
    r'("(?:' + _keys + r')"\s*:\s*)(?!["\s])[^,}\]\s]+',
    caseSensitive: false,
  );
  static final RegExp _plain = RegExp(
    r'(\b(?:' + _keys + r')\s*[=:]\s*)(?!["\s*])(?:Bearer\s+)?[^&\s,"' "'" r'}]+',
    caseSensitive: false,
  );
  static final RegExp _bearer = RegExp(r'Bearer\s+(?!\*\*\*)[A-Za-z0-9._\-]+');

  static String redact(String text) => text
      .replaceAllMapped(_jsonString, (m) => '${m[1]}***"')
      .replaceAllMapped(_jsonOther, (m) => '${m[1]}***')
      .replaceAllMapped(_plain, (m) => '${m[1]}***')
      .replaceAll(_bearer, 'Bearer ***');
}

class DebugLogLine {
  const DebugLogLine(this.id, this.text);

  final int id;
  final String text;
}
