import 'dart:async';

import '../../network/iot/iot_api.dart';
import '../../network/iot/iot_client.dart';
import '../../shared/l10n/app_l10n.dart';
import 'wifi_l10n.dart';

/// WiFi 版 TF 卡（2026-10-29，同小程序 `utils/wifi-tf.js`，依据 docs 前端对接变更说明）的纯逻辑：
/// 详情页 TF 卡行、TF 卡设置页共用。TF 卡播放与 App 投屏互斥：开启后设备切到本地模式（status=LOCAL_TF）并断开云端，
/// 恢复只能在设备端重新入网，协议没有远程切回指令。开关不存本地：开 = 设备当前是本地模式，设备重新入网后自然回到关闭。
/// 本期不做 TF 卡清除（clean-tf）。

/// 等 command.result 的超时（文档 2.3 建议 30 秒）。
const Duration kWifiTfResultTimeout = Duration(seconds: 30);

enum WifiTfState { absent, present, unknown }

/// 影子里的 tfUsed / tfTotal 单位为 MB；满 1GB 换成 GB 显示。
String wifiTfSizeText(Object? mb) {
  final value = num.tryParse('${mb ?? ''}');
  if (value == null || value < 0) {
    return '0MB';
  }
  if (value >= 1024) {
    final gb = (value / 1024).toStringAsFixed(1);
    return '${gb.endsWith('.0') ? gb.substring(0, gb.length - 2) : gb}GB';
  }
  return '${value.round()}MB';
}

/// 影子 → TF 卡状态：absent 未插卡 / present 有卡（text 为「已用/总量」）/ unknown 没上报过（text 为 --）。
({WifiTfState state, String text}) wifiTfState(AppL10n l10n, Map<String, dynamic> shadow) {
  final status = '${shadow['tfStatus'] ?? ''}';
  if (status == 'absent') {
    return (state: WifiTfState.absent, text: l10n.wifiTfAbsent);
  }
  if (status != 'present') {
    return (state: WifiTfState.unknown, text: '--');
  }
  final total = num.tryParse('${shadow['tfTotal'] ?? ''}') ?? 0;
  return (
    state: WifiTfState.present,
    text: total > 0 ? '${wifiTfSizeText(shadow['tfUsed'])}/${wifiTfSizeText(total)}' : l10n.wifiTfPresent,
  );
}

/// POST /api/device/play-tf 的错误 → 提示。
String wifiPlayTfErrorText(AppL10n l10n, Object error) {
  final code = error is IotException ? error.numericCode : null;
  return switch (code) {
    4000 => l10n.wifiTfNoCard,
    4041 => l10n.wifiTfNotOnline,
    4045 => l10n.wifiTfUpgrading,
    403 => l10n.wifiTfNoPermission,
    _ => error is IotException && error.message.isNotEmpty ? error.message : l10n.wifiTfOpenFailed,
  };
}

/// 设备对一条指令的结果：success / result，或超时。
typedef WifiCommandOutcome = ({bool timeout, bool success, Object? result});

/// 等设备对某条指令的 command.result（文档 2.4）。须在发请求**之前**创建：推送可能早于 HTTP 响应到达，
/// 先到的按 msgid 暂存。用完调 [dispose]。
class WifiCommandResultWaiter {
  WifiCommandResultWaiter(Stream<Map<String, dynamic>> results, String deviceNo, this.action)
    : _deviceNo = IotApi.plainDeviceNo(deviceNo) {
    _sub = results.listen(_onEvent);
  }

  final String action;
  final String _deviceNo;
  late final StreamSubscription<Map<String, dynamic>> _sub;
  final Map<String, WifiCommandOutcome> _early = {};
  String? _pendingMsgid;
  Completer<WifiCommandOutcome>? _pending;
  Timer? _timer;

  void _onEvent(Map<String, dynamic> event) {
    if ('${event['action'] ?? ''}' != action || IotApi.plainDeviceNo(event['deviceNo']) != _deviceNo) {
      return;
    }
    final outcome = (timeout: false, success: event['success'] == true, result: event['result']);
    final key = '${event['msgid'] ?? ''}';
    if (_pending != null && _pendingMsgid == key) {
      _finish(outcome);
    } else {
      _early[key] = outcome;
    }
  }

  void _finish(WifiCommandOutcome outcome) {
    _timer?.cancel();
    _timer = null;
    final pending = _pending;
    _pending = null;
    if (pending != null && !pending.isCompleted) {
      pending.complete(outcome);
    }
  }

  Future<WifiCommandOutcome> wait(Object? msgid, {Duration timeout = kWifiTfResultTimeout}) {
    final key = '${msgid ?? ''}';
    final early = _early[key];
    if (early != null) {
      return Future.value(early);
    }
    final completer = Completer<WifiCommandOutcome>();
    _pending = completer;
    _pendingMsgid = key;
    _timer = Timer(timeout, () => _finish((timeout: true, success: false, result: null)));
    return completer.future;
  }

  void dispose() {
    unawaited(_sub.cancel());
    _finish((timeout: true, success: false, result: null));
  }
}
