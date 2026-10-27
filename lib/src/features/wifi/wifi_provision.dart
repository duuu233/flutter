import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../device/wifi/blufi.dart';
import '../../network/iot/iot_api.dart';
import '../../network/iot/iot_client.dart';
import '../../shared/l10n/app_l10n.dart';
import '../../state.dart';
import 'wifi_l10n.dart';

/// 搜索页选中的 WiFi 版设备（配网三页之间内存交接，不进路由参数）。
class WifiProvisionTarget {
  const WifiProvisionTarget({
    required this.bleRemoteId,
    required this.deviceNo,
    required this.name,
    required this.spec,
    required this.productId,
    this.productName = '',
  });

  /// BLE 句柄（BluFi 连接用，后端不存）。
  final String bleRemoteId;

  /// 广播名里解析出的 12 位 deviceNo（不带冒号，查询用）。
  final String deviceNo;

  /// 广播名（展示用，绑定时产品名兜底）。
  final String name;

  /// 规格文案（尺寸，展示用）。
  final String spec;

  /// 搜索时 getProductByDevice 查到的产品。
  final String productId;
  final String productName;
}

/// 配网失败：[step] 为失败的步骤下标（0~3），[message] 为给用户看的文案。
class WifiProvisionError implements Exception {
  const WifiProvisionError(this.step, this.message, [this.cause]);

  final int step;
  final String message;
  final Object? cause;

  @override
  String toString() => 'WifiProvisionError($step, $message, $cause)';
}

/// WiFi 版设备配网流程，同步小程序 `utils/wifi-provision.js`（按设备入网流程 2.2）。
///
/// 页面上的四个状态（「配网 4 步与指令时序」）：
///   1 手机网络正常       —— 能解析 IoT 服务域名即可；
///   2 设备网络配置已完成 —— 先调 IoT GET /api/device/provisioning/mqtt 取 MQTT 参数（取不到就停在本步，不动设备）；
///                          BluFi 连上设备（WiFi 列表页扫描时已连上的会话直接复用），三条指令顺序固定：
///                          WiFi 信息（STA 模式 + 名称 + 密码）→ mqtt_config（等 mqtt_config_ack.result=0）→
///                          国家码 wifi_set_country_code（固定 01；成功 / pending=1 / 超时都不阻塞，result 非 0
///                          换新 msgid 重试一次，仍失败继续）；最后发「连接 WiFi」让设备退出配网，随即释放蓝牙
///                          ——步骤 3 起设备已退出配网，不能再补发指令；
///   3 设备正在连接Wi-Fi  —— 设备侧没有状态上报，这一步调老服务绑定；绑定失败停在本步，不开始轮询
///                          （绑定必须先于在线查询：在线接口会调老服务 checkPermission，未绑定返回 403）；
///   4 设备正在连接云端   —— 轮询 GET /api/device/online?deviceNo=&since=（since 为本次配网开始时间），online=true 即成功；
///                          503 / 403 / 网络失败继续轮询，60s 超时；401 停止。
///
/// 页面之间的交接放内存、不进路由：WiFi 密码不该出现在任何路由参数或日志里。
abstract final class WifiProvision {
  static const Duration bleAckTimeout = Duration(seconds: 5);

  /// 国家码：统一传世界通用模式 01（设备入网流程 5.2；小程序同值）。
  static const String countryCode = '01';
  static const Duration onlinePollInterval = Duration(seconds: 2);
  static const Duration onlineTimeout = Duration(seconds: 60);

  static WifiProvisionTarget? _target;
  static ({String ssid, String password})? _credentials;

  static WifiProvisionTarget? get target => _target;

  /// 换目标设备时同时清掉上一次的账号密码。
  static void setTarget(WifiProvisionTarget? value) {
    _target = value;
    _credentials = null;
  }

  static void setCredentials(String ssid, String password) {
    _credentials = (ssid: ssid, password: password);
  }

  static bool get hasJob => _target != null && _credentials != null;

  /// 离开配网流程时清掉交接（密码不在内存里多留）。
  static void clear() {
    _target = null;
    _credentials = null;
  }

  /// MQTT 配置：每次配网现调 IoT 接口取，不缓存（只在 [run] 局部变量里活到 mqtt_config 发出为止）。
  /// 四项缺任何一项都按取不到处理。
  static Future<Map<String, Object?>> _getMqttConfig() async {
    final data = await IotApi.getProvisioningMqtt();
    final host = (data['host'] ?? '').toString().trim();
    final port = num.tryParse('${data['port'] ?? ''}') ?? 0;
    final usr = (data['usr'] ?? '').toString();
    final pwd = (data['pwd'] ?? '').toString();
    if (host.isEmpty || port <= 0 || usr.isEmpty || pwd.isEmpty) {
      throw StateError('MQTT 参数不完整');
    }
    return {'host': host, 'port': port, 'usr': usr, 'pwd': pwd};
  }

  /// 下发国家码 wifi_set_country_code（设备入网流程 3.2 / 5.1），始终不阻塞配网：
  ///   · pending=1 优先于 result：设备暂缓执行，最终生效值以心跳 country_code 为准；
  ///   · 无 pending、result=0：成功；无 pending、result 非 0：换新 msgid 重试一次，仍失败继续配网；
  ///   · 等不到回执（超时 / 写失败）：不重试，继续配网。
  static Future<void> _sendCountryCode(BlufiSession session) async {
    for (var attempt = 1; attempt <= 2; attempt++) {
      Map<String, dynamic> ack;
      try {
        ack = await session.request(
          'wifi_set_country_code',
          {'country': countryCode},
          timeout: bleAckTimeout,
          msgid: Blufi.newMsgid(),
        );
      } catch (_) {
        return;
      }
      if ('${ack['pending']}' == '1' || '${ack['result']}' == '0') {
        return;
      }
    }
  }

  static Future<bool> _phoneOnline() async {
    try {
      final host = Uri.parse(IotConfig.baseUrl).host;
      final result = await InternetAddress.lookup(host).timeout(const Duration(seconds: 5));
      return result.isNotEmpty;
    } on SocketException {
      return false;
    } catch (_) {
      // 超时等：判断不了就放行，由后面的接口裁决
      return true;
    }
  }

  /// 跑一遍配网。[onStep](index, status)：status 为 loading / done。
  /// 成功返回绑定的设备记录 id（回查不到为空串）；失败抛 [WifiProvisionError]。
  static Future<String> run(
    PhotoFrameState state,
    AppL10n l10n, {
    required void Function(int index, String status) onStep,
    required bool Function() isCancelled,
  }) async {
    final target = _target;
    final credentials = _credentials;
    if (target == null || credentials == null) {
      throw WifiProvisionError(0, l10n.wifiJobExpired);
    }
    void checkCancel(int step) {
      if (isCancelled()) {
        throw WifiProvisionError(step, l10n.wifiErrCancelled);
      }
    }

    final since = DateTime.now().millisecondsSinceEpoch;
    BlufiSession? session;
    try {
      // ① 手机网络
      onStep(0, 'loading');
      if (!await _phoneOnline()) {
        throw WifiProvisionError(0, l10n.wifiErrPhoneNetwork);
      }
      onStep(0, 'done');
      checkCancel(1);

      // ② 设备网络配置：先取 MQTT 参数——取不到就不动设备（不下发 WiFi），避免设备只收到半套配置
      onStep(1, 'loading');
      Map<String, Object?>? mqttConfig;
      try {
        mqttConfig = await _getMqttConfig();
      } on IotException catch (error) {
        throw WifiProvisionError(1, error.isRelogin ? l10n.wifiErrRelogin : l10n.wifiErrMqtt, error);
      } catch (error) {
        throw WifiProvisionError(1, l10n.wifiErrMqtt, error);
      }
      checkCancel(1);
      final BlufiSession connected;
      try {
        connected = await Blufi.connect(target.bleRemoteId);
      } catch (error) {
        throw WifiProvisionError(1, l10n.wifiErrConnect, error);
      }
      session = connected;
      checkCancel(1);
      try {
        await connected.configureSta(credentials.ssid, credentials.password);
      } catch (error) {
        throw WifiProvisionError(1, l10n.wifiErrSta, error);
      }
      Map<String, dynamic> mqttAck;
      try {
        mqttAck = await connected.request(
          'mqtt_config',
          mqttConfig!,
          timeout: bleAckTimeout,
          msgid: Blufi.newMsgid(),
        );
      } catch (error) {
        throw WifiProvisionError(1, l10n.wifiErrMqttNoAck, error);
      } finally {
        // 发出去（或发送失败）就不再留：后面的错误路径都碰不到密码
        mqttConfig = null;
      }
      if ('${mqttAck['result']}' != '0') {
        throw WifiProvisionError(1, l10n.wifiErrMqttResult(mqttAck['result']));
      }
      checkCancel(1);
      await _sendCountryCode(connected);
      checkCancel(1);
      // 三条指令都已下发：让设备退出配网、用下发的 WiFi 去连接（乐鑫 BluFi 控制帧 0x03）。
      // 之后设备不再接收蓝牙指令，设备侧也没有状态上报，蓝牙随即释放。
      try {
        await connected.connectWifi();
      } catch (error) {
        throw WifiProvisionError(1, l10n.wifiErrSta, error);
      }
      onStep(1, 'done');
      await connected.close();
      session = null;
      checkCancel(2);

      // ③ 设备连接 WiFi（设备侧无状态上报）：期间完成老服务绑定（绑定必须先于在线查询）
      onStep(2, 'loading');
      final bound = await state.bindWifiDevice(
        deviceNo: target.deviceNo,
        productId: target.productId,
        productName: target.productName,
        broadcastName: target.name,
      );
      if (!bound.success) {
        throw WifiProvisionError(
          2,
          l10n.wifiErrBind(bound.message.isNotEmpty ? bound.message : l10n.wifiErrBindRetry),
        );
      }
      onStep(2, 'done');
      checkCancel(3);

      // ④ 轮询上云：503（权限服务暂不可用）/ 403 / 网络抖动不算失败，继续轮询；401 停止
      onStep(3, 'loading');
      final deadline = DateTime.now().add(onlineTimeout);
      var online = false;
      int? lastCode;
      while (DateTime.now().isBefore(deadline)) {
        checkCancel(3);
        try {
          final res = await IotApi.getDeviceOnline(target.deviceNo, since: since);
          lastCode = null;
          if (res['online'] == true) {
            online = true;
            break;
          }
        } on IotException catch (error) {
          lastCode = error.numericCode;
          if (error.isRelogin) {
            throw WifiProvisionError(3, l10n.wifiErrRelogin, error);
          }
        } catch (_) {
          lastCode = null;
        }
        await Future<void>.delayed(onlinePollInterval);
      }
      if (!online) {
        // 一直 503 是权限服务不可用，不是设备联网失败（设备入网流程 2.2），提示稍后重试
        throw WifiProvisionError(
          3,
          lastCode == 503 ? l10n.wifiErrServiceUnavailable : l10n.wifiErrOnlineTimeout,
        );
      }
      onStep(3, 'done');
      return bound.deviceId;
    } finally {
      final open = session;
      if (open != null) {
        unawaited(open.close());
      }
      if (kDebugMode) {
        debugPrint('[WiFi配网] 结束 ${target.deviceNo}');
      }
    }
  }
}
