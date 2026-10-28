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
  /// [refresh]（V1.4，默认 true）：false 只转 bin + 上传 OSS、不下发 play，返回 status=UPLOADED、msgid=null；
  /// 批量投屏前 N-1 张传 false、最后一张 true（V1.4 更新说明 2.4）。
  /// [addToCarousel]（实现报告反馈追加内容第二节，默认 false）：true 把本次图片加入当前轮播选择，与 refresh 独立；
  /// 返回多 carouselUpdated：null 没传 / true 已加入（全部相册时为清缓存）/ false 未加入（未开轮播、已满 100、锁冲突等），
  /// 未加入不影响投屏本身。
  static Future<Map<String, dynamic>> play(
    String deviceNo,
    String filePath,
    String type, {
    bool refresh = true,
    bool addToCarousel = false,
    void Function(double percent)? onProgress,
  }) async {
    return _asMap(
      await _iot.upload(
        '/api/device/play',
        filePath: filePath,
        fields: {
          'deviceNo': plainDeviceNo(deviceNo),
          'type': type,
          if (!refresh) 'refresh': 'false',
          if (addToCarousel) 'addToCarousel': 'true',
        },
        timeout: playTimeout,
        onProgress: onProgress,
      ),
    );
  }

  /// 投屏状态（断线兜底，文档 1.5）：`{ msgid, status, sentAt, elapsedSeconds }`；任务超 1 小时查询返回 4044。
  static Future<Map<String, dynamic>> getPlayStatus(String msgid) async {
    return _asMap(await _iot.get('/api/device/play/status', query: {'msgid': msgid}));
  }

  /// 轮播查询（V1.4 更新说明五）：`{ configured, running, updateType, beginTime, endTime, intervalMinutes, updateDays,
  /// updateTimeList, mode, idle, imgUrls, updatedAt }`。imgUrls：null = 未选择（轮播全部相册），[] = 选的照片已全部失效。
  /// 只校验权限，设备离线也能查。
  static Future<Map<String, dynamic>> getStrategy(String deviceNo) async {
    return _asMap(await _iot.get('/api/device/strategy', query: {'deviceNo': plainDeviceNo(deviceNo)}));
  }

  /// 轮播设置（V1.4）：updateType 2 = 间隔（beginTime / endTime / timingTime 秒），1 = 固定时间（updateDays 1~365 /
  /// updateTimeList HH:mm 数组）；mode 1 顺序 / 2 随机；idle 0 轮播后休眠 / 1 不休眠；
  /// imgUrls 可选：相册 imgBle，最多 100（超过回 4000），按选择顺序；不传 = 全部相册，传空数组会被拒（4000），
  /// 由调用方保证不传空。要求设备在线（离线 4041）。返回 `{ msgid }`。
  static Future<Map<String, dynamic>> setStrategy(Map<String, Object?> payload) async {
    return _asMap(
      await _iot.post(
        '/api/device/strategy',
        body: {...payload, 'deviceNo': plainDeviceNo(payload['deviceNo'])},
      ),
    );
  }

  /// 暂停轮播（对接文档 3.2）。
  static Future<Map<String, dynamic>> stopStrategy(String deviceNo) async {
    return _asMap(await _iot.post('/api/device/strategy/stop', body: {'deviceNo': plainDeviceNo(deviceNo)}));
  }

  /// 删除云端照片 bin（V1.4 更新说明九）：相册记录由 App 先调老服务删，这里只删 OSS 上的 bin 并清设备拉列表的缓存。
  /// payload：`{ deviceNo, imgUrls（imgBle，最多 200）, nextImageUrl? }`；删的是屏上当前图且带了 nextImageUrl 时服务端自动 play 下一张。
  /// 返回 `{ requested, deleted, failed, skipped, current, deviceAction: NONE / PLAY_NEXT / CLEAN_TF, deviceNotified }`。
  static Future<Map<String, dynamic>> deletePhotos(Map<String, Object?> payload) async {
    return _asMap(
      await _iot.post(
        '/api/device/photo/delete',
        body: {...payload, 'deviceNo': plainDeviceNo(payload['deviceNo'])},
      ),
    );
  }

  /// 休眠计划查询（实现报告反馈 2.1）：`{ configured, mode, enabled, beginTime, endTime, sleepTime, wakeTime, updatedAt }`。
  /// configured=false 从未设置；mode 0 关闭 / 1 一次性（beginTime/endTime：yyyy-MM-dd HH:mm）/ 2 周期（sleepTime/wakeTime：HH:mm）。
  /// 只要权限，离线也能查。
  static Future<Map<String, dynamic>> getSleep(String deviceNo) async {
    return _asMap(await _iot.get('/api/device/sleep', query: {'deviceNo': plainDeviceNo(deviceNo)}));
  }

  /// 休眠设置（V1.4 更新说明第四节）：`{ deviceNo, mode: 0 }` / `{ mode: 2, sleepTime, wakeTime }` / `{ mode: 1, beginTime, endTime }`。
  /// 时间一律本地时间，**不要转 UTC**（服务端转）；要求设备在线（离线 4041），参数不合法 4000。
  static Future<Map<String, dynamic>> setSleep(Map<String, Object?> payload) async {
    return _asMap(
      await _iot.post(
        '/api/device/sleep',
        body: {...payload, 'deviceNo': plainDeviceNo(payload['deviceNo'])},
      ),
    );
  }

  /// 消息列表（对接文档 8.1）：`{ total, page, size, unreadCount, list: [{ id, category, type, payload, read, createdAt }] }`，
  /// 按时间倒序。
  static Future<Map<String, dynamic>> getNotifications(
    String deviceNo, {
    int page = 1,
    int size = 20,
    bool unreadOnly = false,
  }) async {
    return _asMap(
      await _iot.get(
        '/api/notification/list',
        query: {
          'deviceNo': plainDeviceNo(deviceNo),
          'page': page,
          'size': size,
          if (unreadOnly) 'unreadOnly': 'true',
        },
      ),
    );
  }

  /// 未读数（8.2）：`{ unreadCount }`。
  static Future<Map<String, dynamic>> getUnreadCount(String deviceNo) async {
    return _asMap(await _iot.get('/api/notification/unread-count', query: {'deviceNo': plainDeviceNo(deviceNo)}));
  }

  /// 标记已读（8.3）：[ids] 为空 = 该设备全部已读；最多 500 个。id 原样回传（Long 可能是字符串）。
  static Future<Map<String, dynamic>> markNotificationsRead(String deviceNo, List<Object> ids) async {
    return _asMap(
      await _iot.post('/api/notification/read', body: {'deviceNo': plainDeviceNo(deviceNo), 'ids': ids}),
    );
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
