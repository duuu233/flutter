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
  /// [renderMode]（2026-10-28）：后台产品配置的渲染模式（esp32 / fpga16），有值才带、原样传（见 PhotoFrameState.resolveRenderMode）。
  static Future<Map<String, dynamic>> play(
    String deviceNo,
    String filePath,
    String type, {
    bool refresh = true,
    bool addToCarousel = false,
    String renderMode = '',
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
          if (renderMode.trim().isNotEmpty) 'renderMode': renderMode.trim(),
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

  /// 固件升级下发（2026-10-31 前端对接变更说明 / 草稿 3.9，同小程序 2026-11-02）：
  /// `{ deviceNo, url（http/https 固件包）, type（main 主控 / fpga）, version（目标版本）}` → `{ msgid }`。
  /// 同一设备同时只允许一个升级任务：重复下发 4000「已有升级任务进行中」，升级中 4045；MQTT 发布失败 5000；离线 4041。
  static Future<Map<String, dynamic>> startOta({
    required String deviceNo,
    required String url,
    required String version,
    String type = 'main',
  }) async {
    return _asMap(
      await _iot.post(
        '/api/device/ota',
        body: {'deviceNo': plainDeviceNo(deviceNo), 'url': url, 'type': type, 'version': version},
      ),
    );
  }

  /// 升级状态（草稿 3.9.1）：`{ msgid, status, type, version, baseVersion, sentAt, elapsedSeconds }`；
  /// 任务只保留 2 小时，过期 / 不存在 4044。
  static Future<Map<String, dynamic>> getOtaStatus(String msgid) async {
    return _asMap(await _iot.get('/api/device/ota/status', query: {'msgid': msgid}));
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

  /// 切到 TF 卡本地播放（2026-10-29 前端对接变更说明）：`{ deviceNo }` → `{ msgid }`。HTTP 成功只表示指令已下发，
  /// 设备是否接受看 WS `command.result`（action=play_tf，按 msgid 匹配）。前置校验：403 无权限、4045 升级中、
  /// 4041 离线（含已是本地模式）、4000 影子 tfStatus=absent 未插卡（tfStatus 未知时服务端不拦）。
  static Future<Map<String, dynamic>> playTf(String deviceNo) async {
    return _asMap(await _iot.post('/api/device/play-tf', body: {'deviceNo': plainDeviceNo(deviceNo)}));
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

  /// 恢复设备内置图片（2026-11-06，同小程序）：`{ deviceNo, renderMode }` → POST /api/device/restore-builtin（JSON）。
  /// 在 WiFi 版「删除设备」（删完云端照片之后、删设备记录之前）、「一键清空」和「我的相册」全删后调；解除绑定不调。
  /// [renderMode] 同投屏，取后台产品配置（PhotoFrameState.resolveRenderMode），有值才带、原样传。
  /// [scene]（2026-11-10，选填，有值才带、原样传）：删光照片后调时传 [restoreSceneDeleteAllPhotos]
  ///（一键清空、我的相册全删）；删除设备不传。入参其余字段与返回不变。
  /// 返回 `{ deviceNo, status }`：status 只有 SENT（已下发）/ SKIPPED（没下发，不用重试）；
  /// 错误码只有 4000 参数错误 / 401 登录失效 / 403 无权限 / 5000 服务异常，怎么收场由调用方决定（见 wifi_remove_flow.dart）。
  static Future<Map<String, dynamic>> restoreBuiltin(
    String deviceNo, {
    String renderMode = '',
    String scene = '',
  }) async {
    return _asMap(
      await _iot.post(
        '/api/device/restore-builtin',
        body: restoreBuiltinBody(deviceNo, renderMode: renderMode, scene: scene),
      ),
    );
  }

  /// restore-builtin 的 scene（2026-11-10）：设备照片已全部删掉。
  static const String restoreSceneDeleteAllPhotos = 'DELETE_ALL_PHOTOS';

  /// restore-builtin 的请求 body（单独拿出来便于测试与打请求日志）。
  static Map<String, Object?> restoreBuiltinBody(String deviceNo, {String renderMode = '', String scene = ''}) {
    return {
      'deviceNo': plainDeviceNo(deviceNo),
      if (renderMode.trim().isNotEmpty) 'renderMode': renderMode.trim(),
      if (scene.trim().isNotEmpty) 'scene': scene.trim(),
    };
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

  /// 消息列表（对接文档 8.1）：`{ total, page, size, unreadCount, list: [{ id, category, type, payload, read, createdAt, title, content }] }`，
  /// 按时间倒序。2026-11-09 新增选填 [lang]（zh-CN / zh-TW / en / ja，不传按简中），返回多 title / content
  /// （服务端按 lang 翻译好、可直接展示）；lang 有值才带，原参数不变。
  static Future<Map<String, dynamic>> getNotifications(
    String deviceNo, {
    int page = 1,
    int size = 20,
    bool unreadOnly = false,
    String lang = '',
  }) async {
    return _asMap(
      await _iot.get(
        '/api/notification/list',
        query: {
          'deviceNo': plainDeviceNo(deviceNo),
          'page': page,
          'size': size,
          if (unreadOnly) 'unreadOnly': 'true',
          if (lang.isNotEmpty) 'lang': lang,
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
