import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../api_session.dart';
import 'iot_client.dart';

/// 连接状态事件。[reconnect]=true 表示这是断线后重连成功：断线期间的推送会丢，
/// 页面据此用 REST 补查一次状态（投屏状态、在线状态等）。
class IotWsState {
  const IotWsState(this.state, {this.reconnect = false, this.reason = ''});

  /// idle / connecting / open / closed
  final String state;
  final bool reconnect;

  /// closed 的原因：unauthorized（401，重连无用）/ unavailable（503）/ closed / no-token / manual
  final String reason;
}

/// IoT 服务 WebSocket 推送客户端（WiFi 版设备：play.result / device.status / ota.result /
/// notification.new），同步小程序 `utils/iot-ws.js`。
///
/// 接口文档口径：
///   · 地址 [IotConfig.wsUrl]；握手鉴权读 Header `userToken`（与 HTTP 同一个登录 token）。
///     握手失败不会建立连接：401 = 需要重新登录，503 = 老服务暂时不可用、稍后重试；
///   · 客户端发 subscribe / unsubscribe（按 deviceNo）与 ping；**订阅成功后才收得到该设备的推送**；
///   · 服务端 90 秒收不到任何消息会断开，这里每 30 秒发一次 ping；
///   · 断线重连按 1s、2s、4s… 指数退避、上限 30s；断线期间的事件会丢（见 [IotWsState.reconnect]）。
///
/// 单例、按需连接：只有调用 [connect] / [subscribe] 才会建连（蓝牙版用户用不到它）。
/// 已订阅的设备在重连后自动重新订阅。退出登录 / 登录失效时 [PhotoFrameState] 调 [close]。
class IotWs {
  IotWs._();

  static final IotWs instance = IotWs._();

  static const Duration _heartbeat = Duration(seconds: 30);
  static const int _retryBaseMs = 1000;
  static const int _retryMaxMs = 30000;

  WebSocket? _socket;
  bool _opening = false;
  String _state = 'idle';
  bool _wanted = false; // 调用方要求保持连接：为 true 时断线自动重连
  bool _everOpened = false;
  int _retryAttempt = 0;
  int _generation = 0; // close() / 新连接时自增，作废旧连接的晚到回调
  Timer? _retryTimer;
  Timer? _heartbeatTimer;
  AppLifecycleListener? _lifecycle;
  final Set<String> _subscriptions = <String>{};

  final StreamController<Map<String, dynamic>> _messages =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<IotWsState> _states = StreamController<IotWsState>.broadcast();

  /// 全部推送消息（`{ type, deviceNo, ... }`），按 `type` 自行过滤。
  Stream<Map<String, dynamic>> get messages => _messages.stream;

  /// 某一类推送（如 `play.result`、`device.status`）。
  Stream<Map<String, dynamic>> on(String type) =>
      _messages.stream.where((message) => message['type'] == type);

  Stream<IotWsState> get states => _states.stream;

  String get state => _state;

  List<String> get subscriptions => List.unmodifiable(_subscriptions);

  void _setState(String next, {bool reconnect = false, String reason = ''}) {
    _state = next;
    _states.add(IotWsState(next, reconnect: reconnect, reason: reason));
  }

  bool _send(Map<String, Object?> message) {
    final socket = _socket;
    if (_state != 'open' || socket == null) {
      return false;
    }
    try {
      socket.add(jsonEncode(message));
      return true;
    } catch (_) {
      return false;
    }
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(_heartbeat, (_) => _send({'type': 'ping'}));
  }

  /// 握手被拒的原因只能从异常文案里认（dart:io 为「…HTTP status code: 401」）。
  static String _classify(Object? error) {
    final text = '${error ?? ''}';
    if (RegExp(r'\b401\b').hasMatch(text)) return 'unauthorized';
    if (RegExp(r'\b503\b').hasMatch(text)) return 'unavailable';
    return 'closed';
  }

  void _scheduleReconnect() {
    if (!_wanted || _retryTimer != null) {
      return;
    }
    final wait = math.min(_retryBaseMs * (1 << math.min(_retryAttempt, 5)), _retryMaxMs);
    _retryAttempt++;
    _retryTimer = Timer(Duration(milliseconds: wait), () {
      _retryTimer = null;
      _open();
    });
  }

  void _handleClosed(int generation, Object? reason) {
    if (generation != _generation) {
      return; // 已被 close() 或新连接替换的旧连接，忽略
    }
    _socket = null;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    final kind = _classify(reason);
    if (kind == 'unauthorized') {
      // 401：token 失效，重连也没用；登录态由 HTTP 层（IotClient 的 401）统一引导重登
      _wanted = false;
      _setState('closed', reason: kind);
      return;
    }
    _scheduleReconnect();
    _setState('closed', reason: kind);
  }

  void _hookLifecycle() {
    // 回到前台：后台期间系统可能已把连接断掉，不必等退避计时，立刻重连
    _lifecycle ??= AppLifecycleListener(
      onResume: () {
        if (_wanted && _socket == null && !_opening) {
          _retryTimer?.cancel();
          _retryTimer = null;
          _retryAttempt = 0;
          _open();
        }
      },
    );
  }

  Future<void> _open() async {
    if (_socket != null || _opening) {
      return;
    }
    final token = ApiSession.instance.userToken;
    if (token.isEmpty) {
      _wanted = false;
      _setState('closed', reason: 'no-token');
      return;
    }
    final generation = ++_generation;
    _opening = true;
    _setState('connecting');
    WebSocket socket;
    try {
      socket = await WebSocket.connect(IotConfig.wsUrl, headers: {'userToken': token});
    } catch (error) {
      _opening = false;
      _handleClosed(generation, error);
      return;
    }
    _opening = false;
    if (generation != _generation) {
      // 连接期间被 close()：这条连接不要了
      unawaited(socket.close());
      return;
    }
    _socket = socket;
    final reconnect = _everOpened;
    _everOpened = true;
    _retryAttempt = 0;
    _startHeartbeat();
    _setState('open', reconnect: reconnect);
    for (final deviceNo in _subscriptions) {
      _send({'type': 'subscribe', 'deviceNo': deviceNo});
    }
    socket.listen(
      (data) {
        if (generation != _generation || data is! String) {
          return;
        }
        Object? decoded;
        try {
          decoded = jsonDecode(data);
        } catch (_) {
          return;
        }
        if (decoded is Map && decoded['type'] != null) {
          _messages.add(decoded.map((k, v) => MapEntry(k.toString(), v)));
        }
      },
      onError: (Object error) => _handleClosed(generation, error),
      onDone: () => _handleClosed(generation, socket.closeReason ?? socket.closeCode),
      cancelOnError: true,
    );
  }

  /// 要求保持连接：已连 / 连接中直接返回；断线后自动重连，直到 [close]。
  void connect() {
    _wanted = true;
    _hookLifecycle();
    unawaited(_open());
  }

  /// 主动断开并清空订阅（退出登录、登录失效）。
  void close() {
    _wanted = false;
    _generation++;
    _retryTimer?.cancel();
    _retryTimer = null;
    _retryAttempt = 0;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _subscriptions.clear();
    _everOpened = false;
    final socket = _socket;
    _socket = null;
    if (socket != null) {
      unawaited(socket.close().catchError((_) {}));
      _setState('closed', reason: 'manual');
    }
  }

  /// 订阅某台设备的推送：记下来（重连后自动补订），已连上就立即发；未连则顺带发起连接。
  void subscribe(String deviceNo) {
    final id = deviceNo.trim();
    if (id.isEmpty) {
      return;
    }
    _subscriptions.add(id);
    if (!_send({'type': 'subscribe', 'deviceNo': id})) {
      connect();
    }
  }

  void unsubscribe(String deviceNo) {
    final id = deviceNo.trim();
    if (id.isEmpty) {
      return;
    }
    _subscriptions.remove(id);
    _send({'type': 'unsubscribe', 'deviceNo': id});
  }
}
