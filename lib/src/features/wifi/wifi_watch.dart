import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../network/iot/iot_api.dart';
import '../../network/iot/iot_ws.dart';
import '../../state.dart';

/// WiFi 版设备状态推送订阅，同步小程序 `utils/wifi-watch.js`（首页设备卡 / 我的设备列表共用；WiFi 设备详情页沿用自己的订阅）。
/// 结论见小程序 docs「WiFi版状态刷新分析」：用订阅长连接 + 补查，不做定时轮询。
///
/// 页面用法：`WifiWatch(onChange)` 得到一个订阅器；
///   · [update]：页面显示 / 设备列表刷新后传当前的设备，按 deviceNo（去冒号）订阅 WiFi 版，多余的退订；
///   · [stop]：页面隐藏 / 销毁时退订、摘掉监听（隐藏的页面不跟着刷新，也不占着订阅）；
///   · onChange(deviceNos)：页面据此调 IoT 设备信息接口重查这些设备：
///       - 收到 WS device.status（上下线 / 关机 / 对账离线，只推信号不带电量）→ 只重查这一台；
///       - 长连接断线后重连成功（如熄屏回前台，[IotWs] 回前台立即重连）→ 断线期间的推送会丢，全部重查一次。
/// 订阅归属：只退订自己订阅的；某台设备已被别处（如 WiFi 详情页）订阅时不重复订阅，也不替它退订。
/// 电量只在设备心跳（600 秒）时更新、推送不带电量：停留在页面期间电量不会自己变，需后端心跳时也推送。
/// 进后台（2026-10-29 同小程序 onHide 含进后台）：App 切到后台时退订，回前台按上次的设备重新订阅并全部重查一次；
/// 页面已 [stop] 的不受影响。
class WifiWatch {
  WifiWatch(this.onChange);

  final void Function(Set<String> deviceNos) onChange;

  final List<String> _watching = <String>[];
  final List<String> _owned = <String>[];
  final List<StreamSubscription<Object>> _subs = <StreamSubscription<Object>>[];

  /// 页面在用（[update] 之后、[stop] 之前）时跟随 App 前后台；后台期间只记设备，回前台再订。
  AppLifecycleListener? _lifecycle;
  List<DeviceItem> _lastDevices = const [];
  bool _active = false;
  bool _background = false;

  void _ensureLifecycle() {
    _lifecycle ??= AppLifecycleListener(
      onStateChange: (state) {
        if (!_active) {
          return;
        }
        if (state == AppLifecycleState.paused && !_background) {
          _background = true;
          _release();
        } else if (state == AppLifecycleState.resumed && _background) {
          _background = false;
          update(_lastDevices);
          if (_watching.isNotEmpty) {
            _notify(_watching.toSet(), 'resume');
          }
        }
      },
    );
  }

  /// 退订自己订阅的、摘掉监听，但保留 [_lastDevices]（进后台用）。
  void _release() {
    for (final deviceNo in _owned) {
      IotWs.instance.unsubscribe(deviceNo);
    }
    _owned.clear();
    _watching.clear();
    _unlisten();
  }

  void _notify(Set<String> deviceNos, String reason) {
    final what = switch (reason) {
      'push' => '收到状态推送，重查',
      'resume' => '回到前台，全部重查',
      _ => '长连接重连，全部重查',
    };
    debugPrint('[WiFi订阅] $what ${deviceNos.join(',')}');
    try {
      onChange(deviceNos);
    } catch (error) {
      debugPrint('[WiFi订阅] 刷新回调出错 $error');
    }
  }

  void _listen() {
    if (_subs.isNotEmpty) {
      return;
    }
    final ws = IotWs.instance;
    _subs
      ..add(
        ws.on('device.status').listen((event) {
          final deviceNo = IotApi.plainDeviceNo(event['deviceNo']);
          if (deviceNo.isNotEmpty && _watching.contains(deviceNo)) {
            _notify({deviceNo}, 'push');
          }
        }),
      )
      ..add(
        ws.states.listen((event) {
          if (event.state == 'open' && event.reconnect && _watching.isNotEmpty) {
            _notify(_watching.toSet(), 'reconnect');
          }
        }),
      );
  }

  void _unlisten() {
    for (final sub in _subs) {
      unawaited(sub.cancel());
    }
    _subs.clear();
  }

  /// 传当前页面上的设备（只订阅其中的 WiFi 版）。
  void update(Iterable<DeviceItem> devices) {
    _lastDevices = devices.toList();
    _active = true;
    _ensureLifecycle();
    if (_background) {
      return; // 后台期间只记设备，回前台再订
    }
    final next = <String>[];
    for (final device in devices) {
      final deviceNo = device.isWifi ? IotApi.plainDeviceNo(device.serialNumber) : '';
      if (deviceNo.isNotEmpty && !next.contains(deviceNo)) {
        next.add(deviceNo);
      }
    }
    final ws = IotWs.instance;
    for (final deviceNo in _owned.where((id) => !next.contains(id)).toList()) {
      ws.unsubscribe(deviceNo);
      _owned.remove(deviceNo);
    }
    _watching
      ..clear()
      ..addAll(next);
    if (next.isEmpty) {
      // 没有 WiFi 设备（纯蓝牙版用户）：不订阅、不建长连接
      _unlisten();
      return;
    }
    _listen();
    final subscribed = ws.subscriptions;
    for (final deviceNo in next) {
      if (!_owned.contains(deviceNo) && !subscribed.contains(deviceNo)) {
        ws.subscribe(deviceNo); // 未连接时会顺带建连
        _owned.add(deviceNo);
      }
    }
  }

  void stop() {
    _active = false;
    _background = false;
    _lastDevices = const [];
    _lifecycle?.dispose();
    _lifecycle = null;
    _release();
  }
}
