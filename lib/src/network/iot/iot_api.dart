import 'iot_client.dart';

/// IoT 服务（WiFi 版设备）业务接口，同步小程序 `utils/iot-api.js`。
/// 与 BoltFox 老服务的 [BoltFoxApi] 分开放：两边域名、返回结构和错误码都不同（见 [IotClient]）。
/// 设备相关接口都会实时校验设备权限：设备未绑定到当前用户返回 403。
abstract final class IotApi {
  static IotClient get _iot => IotClient.instance;

  /// 投屏上传超时：文档要求 30 秒以上（服务端同步处理最长约 8 秒，图片上传另算），这里给 60 秒。
  static const Duration playTimeout = Duration(seconds: 60);

  /// 传给后端查询的设备ID不加冒号（产品口径）：设备记录的 deviceId 是 AA:BB:… 格式，这里统一去掉。
  static String plainDeviceNo(Object? deviceNo) =>
      (deviceNo ?? '').toString().replaceAll(RegExp(r'[:\-\s]'), '').toUpperCase();

  static Map<String, dynamic> _asMap(Object? data) =>
      data is Map ? data.map((k, v) => MapEntry(k.toString(), v)) : <String, dynamic>{};

  /// 在线状态：`{ deviceNo, online, lastOnlineAt }`。
  /// [since]（毫秒时间戳，可选）：配网时传本次配网开始时间，只有 lastOnlineAt 晚于它才算 online，避免旧连接误判。
  static Future<Map<String, dynamic>> getDeviceOnline(
    String deviceNo, {
    int? since,
  }) async {
    return _asMap(
      await _iot.get(
        '/api/device/online',
        query: {'deviceNo': plainDeviceNo(deviceNo), 'since': since},
      ),
    );
  }

  /// 设备信息 / 影子：`{ deviceNo, online, lastOnlineAt, firmwareVersion, shadow: {...} }`。
  static Future<Map<String, dynamic>> getDeviceInfo(String deviceNo) async {
    return _asMap(
      await _iot.get('/api/device/info', query: {'deviceNo': plainDeviceNo(deviceNo)}),
    );
  }

  /// WiFi 投屏（前端对接文档 1.1 / 评审回复 v0.32）：multipart 传 deviceNo、type、file；
  /// userNo 已改由服务端从 token 解析，不再传。服务端同步转 bin + 上传 OSS + 下发，最长约 8 秒。
  /// 返回 `{ msgid, binUrl, binSize, status }`：status=SENT（旧版为 DOWNLOADING）表示指令已下发，FAILED 表示 MQTT 下发失败。
  static Future<Map<String, dynamic>> play(
    String deviceNo,
    String filePath,
    String type, {
    void Function(double percent)? onProgress,
  }) async {
    return _asMap(
      await _iot.upload(
        '/api/device/play',
        filePath: filePath,
        fields: {'deviceNo': plainDeviceNo(deviceNo), 'type': type},
        timeout: playTimeout,
        onProgress: onProgress,
      ),
    );
  }

  /// 投屏状态（断线兜底，文档 1.5）：`{ msgid, status, sentAt, elapsedSeconds }`；任务超 1 小时查询返回 4044。
  static Future<Map<String, dynamic>> getPlayStatus(String msgid) async {
    return _asMap(await _iot.get('/api/device/play/status', query: {'msgid': msgid}));
  }

  /// 配网下发给设备的 MQTT 参数：`{ host, port, usr, pwd }`（凭据不写在前端）。
  /// 响应不缓存：请求头要求中间层不缓存，客户端不落盘、不放全局变量，配网第 2 步现取现用、发完即丢；
  /// pwd 不进任何日志。
  static Future<Map<String, dynamic>> getProvisioningMqtt() async {
    return _asMap(
      await _iot.get(
        '/api/device/provisioning/mqtt',
        headers: const {'Cache-Control': 'no-cache, no-store', 'Pragma': 'no-cache'},
      ),
    );
  }
}
