import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../network/iot/iot_api.dart';
import '../../network/iot/iot_client.dart';

/// WiFi 版设备固件升级（OTA）的纯逻辑（2026-11-02，同小程序 `utils/wifi-ota.js`；前端对接文档 20261031 / 草稿 3.9）。
///
/// 流程：老服务设备详情给目标版本 `newVersionNo` 与固件包 `downloadPath`（与蓝牙版同一来源）；
/// IoT `GET /api/device/info` 给设备当前版本 `firmwareVersion`（服务端已归一化为 x.y.z）；
/// 有新版本 → `POST /api/device/ota` 下发 → 拿 msgid → 步骤页按 `GET /api/device/ota/status` 与 WS `ota.result` 走四步。
///
/// 状态：SENT 已下发 / DOWNLOADING 下载中 / FLASHING 刷写中 / VERIFYING 设备回报执行成功、等重启确认 /
/// SUCCESS / FAILED / TIMEOUT 终态。步骤页只消费 SENT~VERIFYING 与 FAILED / TIMEOUT：
///   · VERIFYING 是步骤页的成功终点（第 4 步打勾），但**不是终态**，本地记录要保留；
///   · SUCCESS 不进步骤页，只用于清本地记录；FAILED / TIMEOUT 在当前那一步打叉；
///   · 不认识的值按「未知状态」降级，停在已到达的那一步转圈。
///
/// 本地记录：msgid 在投屏 / 轮播 / OTA 之间共用生成器，所以用独立 key `ota_inflight:{deviceNo}` 存
/// `{ deviceNo, type: 'ota', msgid, version, baseVersion, status, lastStep, savedAt }`，一台设备只留一条；
/// 终态或查询 4044（任务只保留 2 小时）时清掉。「有新版本」之前先看本地有没有进行中的记录。
///
/// 进度条（2026-11-12 同小程序）：ota/status 与 WS ota.result 新增 progress（0~100），规则见下方「升级进度条」一节。

const String kWifiOtaTypeMain = 'main'; // 主控升级；FPGA（type=fpga）为渲染固件安装，见 wifi_fpga.dart

const Map<String, int> _stepOf = {'SENT': 0, 'DOWNLOADING': 1, 'FLASHING': 2, 'VERIFYING': 3};
const List<String> _finalStatuses = ['SUCCESS', 'FAILED', 'TIMEOUT'];
const List<String> _failStatuses = ['FAILED', 'TIMEOUT'];

String normalizeOtaStatus(Object? status) => '${status ?? ''}'.trim().toUpperCase();

bool isOtaFinal(Object? status) => _finalStatuses.contains(normalizeOtaStatus(status));

bool isOtaFailure(Object? status) => _failStatuses.contains(normalizeOtaStatus(status));

bool isOtaTimeout(Object? status) => normalizeOtaStatus(status) == 'TIMEOUT';

/// 步骤序号；不认识的值返回 -1。
int otaStepIndex(Object? status) => _stepOf[normalizeOtaStatus(status)] ?? -1;

enum WifiOtaStepState { pending, loading, done, fail }

enum WifiOtaViewPhase { running, verifying, failed, unknown }

class WifiOtaSteps {
  const WifiOtaSteps(this.phase, this.steps, this.failedStep);

  final WifiOtaViewPhase phase;
  final List<WifiOtaStepState> steps;
  final int failedStep;
}

/// 四步的展示状态。[lastStep]：失败时打叉的那一步（= 失败前最后到达的一步，没到过任何一步按第 1 步）。
WifiOtaSteps otaStepsFor(Object? status, [int lastStep = -1]) {
  final s = normalizeOtaStatus(status);
  final reached = lastStep >= 0 ? (lastStep > 3 ? 3 : lastStep) : 0;
  if (isOtaFailure(s)) {
    return WifiOtaSteps(
      WifiOtaViewPhase.failed,
      [
        for (var i = 0; i < 4; i++)
          i < reached
              ? WifiOtaStepState.done
              : i == reached
              ? WifiOtaStepState.fail
              : WifiOtaStepState.pending,
      ],
      reached,
    );
  }
  final current = _stepOf[s];
  if (current != null) {
    final verifying = s == 'VERIFYING';
    return WifiOtaSteps(
      verifying ? WifiOtaViewPhase.verifying : WifiOtaViewPhase.running,
      [
        for (var i = 0; i < 4; i++)
          verifying || i < current
              ? WifiOtaStepState.done
              : i == current
              ? WifiOtaStepState.loading
              : WifiOtaStepState.pending,
      ],
      -1,
    );
  }
  return WifiOtaSteps(
    WifiOtaViewPhase.unknown,
    [
      for (var i = 0; i < 4; i++)
        i < reached
            ? WifiOtaStepState.done
            : i == reached
            ? WifiOtaStepState.loading
            : WifiOtaStepState.pending,
    ],
    -1,
  );
}

// ── 升级进度条（2026-11-12，同小程序 utils/wifi-ota.js）──────────
// 服务端 progress（GET /api/device/ota/status 与 WS ota.result 新增，可选）：设备私有进度回执 182 / 184 / 186 / 188
// 换算为 20 / 40 / 60 / 80，每收到一条回执 WS 推一次；进入 VERIFYING 后为 100；固件不上报进度时为 null。
// 页面显示值只增不减、匀速前进（每 [kWifiOtaProgressTick] 走 1%），走到「上限」就停住等下一次上报：
//   · 还没收到任何进度 → 停在 19 等 20；
//   · 收到 20 / 40 / 60 / 80 → 可走到 39 / 59 / 79 / 98（下一档减 1；80 之后与「不上报」同为 98）；
//     即 19 等 20、39 等 40、59 等 60、79 等 80，没收到下一档数值就一直停住（2026-11-13）；
//   · 状态只决定步骤，不放开分档：DOWNLOADING / FLASHING 本身都不会让进度越过 19 / 39 / 59 / 79；
//   · 固件不上报（progress 为 null）：一个数值都没收到就已进入写入（FLASHING）→ 匀速走到 98 停住；
//     下载阶段为 null 不算「不上报」（可能只是 20 还没到），仍停 19；
//   · VERIFYING（SUCCESS 同）→ 100。FAILED / TIMEOUT 停在当时的位置。
// 进度条左边的文案用当前那一步的步骤文案（[otaActiveStep]）。

const Duration kWifiOtaProgressTick = Duration(milliseconds: 200); // 1% / 200ms：一档 20% 约 4 秒
const int _progressFirstCap = 19;
const int _progressStepGap = 19;
const int _progressSilentCap = 98;

/// progress 字段 → 0~100 整数；null / 缺省 / 非数字 → null（不上报）。
int? parseOtaProgress(Object? value) {
  if (value == null) {
    return null;
  }
  final n = value is num ? value : num.tryParse('$value'.trim());
  if (n == null || n.isNaN || n.isInfinite) {
    return null;
  }
  final rounded = n.round();
  return rounded < 0 ? 0 : (rounded > 100 ? 100 : rounded);
}

/// 显示值能走到的上限。[reported]：本次升级收到过的最大进度（null = 一次都没收到）。
int otaProgressCap(Object? status, int? reported) {
  final s = normalizeOtaStatus(status);
  final value = reported ?? 0;
  if (s == 'VERIFYING' || s == 'SUCCESS' || value >= 100) {
    return 100;
  }
  if (value > 0) {
    final cap = value + _progressStepGap;
    return cap > _progressSilentCap ? _progressSilentCap : cap;
  }
  // 一个数值都没收到：已到写入阶段 → 固件不上报，走到 98；否则停 19 等 20
  return s == 'FLASHING' ? _progressSilentCap : _progressFirstCap;
}

/// [otaStepsFor] 结果里「当前那一步」：转圈或打叉的那一步；全勾（VERIFYING）为最后一步。
int otaActiveStep(WifiOtaSteps view) {
  final index = view.steps.indexWhere((step) => step == WifiOtaStepState.loading || step == WifiOtaStepState.fail);
  return index > -1 ? index : view.steps.length - 1;
}

// ── 版本号 ─────────────────────────────────────────────

/// x.y.z（允许前缀 v / V 与两段、四段）→ 数字段；对不上（如旧格式「M H:3 F:0.6.1」）返回 null。
List<int>? parseFirmwareVersion(Object? value) {
  final match = RegExp(r'^[vV]?(\d+(?:\.\d+){1,3})$').firstMatch('${value ?? ''}'.trim());
  return match?.group(1)!.split('.').map(int.parse).toList();
}

int _compareParts(List<int> a, List<int> b) {
  final length = a.length > b.length ? a.length : b.length;
  for (var i = 0; i < length; i++) {
    final x = i < a.length ? a[i] : 0;
    final y = i < b.length ? b[i] : 0;
    if (x != y) {
      return x > y ? 1 : -1;
    }
  }
  return 0;
}

bool _isHttpUrl(String value) => RegExp(r'^https?://\S+$', caseSensitive: false).hasMatch(value.trim());

enum WifiOtaCheckState { available, latest, unknown, invalid }

class WifiOtaCheck {
  const WifiOtaCheck(this.state, this.current, this.latest, this.url);

  final WifiOtaCheckState state;
  final String current;
  final String latest;
  final String url;
}

/// 是否有新版本：
///   · 目标版本为空 → latest（后台没配升级包）；
///   · 当前版本读不到或不是 x.y.z → unknown（按「无法判断」处理，不报错）；
///   · 两边都是 x.y.z → 目标更高才算有新版本；目标不是 x.y.z 时退回「不相同即有新版本」（与蓝牙版同口径）；
///   · 有新版本但固件包地址不是 http(s) → invalid。
WifiOtaCheck evaluateWifiOta(Object? currentVersion, Object? latestVersion, Object? downloadPath) {
  final current = '${currentVersion ?? ''}'.trim();
  final latest = '${latestVersion ?? ''}'.trim();
  final url = '${downloadPath ?? ''}'.trim();
  if (latest.isEmpty) {
    return WifiOtaCheck(WifiOtaCheckState.latest, current, latest, url);
  }
  final currentParts = parseFirmwareVersion(current);
  if (currentParts == null) {
    return WifiOtaCheck(WifiOtaCheckState.unknown, current, latest, url);
  }
  final latestParts = parseFirmwareVersion(latest);
  final newer = latestParts != null
      ? _compareParts(latestParts, currentParts) > 0
      : latest.toLowerCase() != current.toLowerCase();
  if (!newer) {
    return WifiOtaCheck(WifiOtaCheckState.latest, current, latest, url);
  }
  return WifiOtaCheck(_isHttpUrl(url) ? WifiOtaCheckState.available : WifiOtaCheckState.invalid, current, latest, url);
}

/// IoT 设备信息里的当前固件版本：`firmwareVersion`，没有再看 `shadow.version`。
String wifiFirmwareVersion(Map<String, dynamic>? info) {
  final shadow = info?['shadow'];
  final fromShadow = shadow is Map ? shadow['version'] : null;
  return '${info?['firmwareVersion'] ?? fromShadow ?? ''}'.trim();
}

/// 下发失败是不是「已有进行中的升级」：4045 一律是；4000 在 OTA 接口上表示已有升级任务进行中，
/// 但 4000 也是通用参数错误码——服务端文案明确说的是别的问题（不含「升级 / 进行中」）时按普通失败处理。
bool isWifiOtaBusyError(Object error) {
  if (error is! IotException) {
    return false;
  }
  final code = int.tryParse('${error.code}');
  if (code == 4045) {
    return true;
  }
  if (code != 4000) {
    return false;
  }
  final message = error.serverMessage.trim();
  return message.isEmpty || RegExp('升级|进行中').hasMatch(message);
}

bool _isExpired(Object error) => error is IotException && int.tryParse('${error.code}') == 4044;

// ── 本地进行中记录 ─────────────────────────────────────

class WifiOtaRecord {
  const WifiOtaRecord({
    required this.deviceNo,
    required this.msgid,
    this.version = '',
    this.baseVersion = '',
    this.status = '',
    this.lastStep = -1,
    this.savedAt = 0,
    this.progress,
    this.otaType = kWifiOtaTypeMain,
    this.intro = '',
  });

  final String deviceNo;
  final String msgid;
  final String version;
  final String baseVersion;
  final String status;
  final int lastStep;
  final int savedAt;

  /// 收到过的最大进度（2026-11-12 进度条）；null = 还没收到过。
  final int? progress;

  /// 升级类型（2026-11-13）：main 固件升级 / fpga 渲染固件安装；重进页面按它选文字。
  final String otaType;

  /// 渲染固件简介（fpga 才有），进度页带出。
  final String intro;

  WifiOtaRecord copyWith({String? status, int? lastStep, int? progress}) => WifiOtaRecord(
    deviceNo: deviceNo,
    msgid: msgid,
    version: version,
    baseVersion: baseVersion,
    status: status ?? this.status,
    lastStep: lastStep ?? this.lastStep,
    savedAt: savedAt,
    progress: progress ?? this.progress,
    otaType: otaType,
    intro: intro,
  );

  Map<String, Object> toJson() => {
    'deviceNo': deviceNo,
    'type': 'ota',
    'msgid': msgid,
    'version': version,
    'baseVersion': baseVersion,
    'status': status,
    'lastStep': lastStep,
    'savedAt': savedAt,
    if (progress != null) 'progress': progress!,
    if (otaType != kWifiOtaTypeMain) 'otaType': otaType,
    if (intro.isNotEmpty) 'intro': intro,
  };

  /// 类型不对或缺 msgid 的记录不认（防止拿投屏 msgid 去查 OTA 接口）。
  static WifiOtaRecord? fromJson(Object? raw) {
    if (raw is! Map || raw['type'] != 'ota' || '${raw['msgid'] ?? ''}'.isEmpty) {
      return null;
    }
    return WifiOtaRecord(
      deviceNo: '${raw['deviceNo'] ?? ''}',
      msgid: '${raw['msgid']}',
      version: '${raw['version'] ?? ''}',
      baseVersion: '${raw['baseVersion'] ?? ''}',
      status: '${raw['status'] ?? ''}',
      lastStep: int.tryParse('${raw['lastStep']}') ?? -1,
      savedAt: int.tryParse('${raw['savedAt']}') ?? 0,
      progress: parseOtaProgress(raw['progress']),
      otaType: '${raw['otaType'] ?? ''}'.trim().isNotEmpty ? '${raw['otaType']}'.trim() : kWifiOtaTypeMain,
      intro: '${raw['intro'] ?? ''}',
    );
  }
}

/// 查一次本地进行中任务的结果。[record] 为 null 表示本地没有进行中的任务（或刚被清掉）。
class WifiOtaRefresh {
  const WifiOtaRefresh({this.record, this.status = '', this.data, this.expired = false, this.error});

  final WifiOtaRecord? record;
  final String status;
  final Map<String, dynamic>? data;
  final bool expired;
  final Object? error;
}

abstract final class WifiOtaStore {
  static String storageKey(String deviceNo) => 'ota_inflight:${IotApi.plainDeviceNo(deviceNo)}';

  static Future<WifiOtaRecord?> read(String deviceNo) async {
    final no = IotApi.plainDeviceNo(deviceNo);
    if (no.isEmpty) {
      return null;
    }
    try {
      final sp = await SharedPreferences.getInstance();
      final text = sp.getString(storageKey(no));
      return text == null ? null : WifiOtaRecord.fromJson(jsonDecode(text));
    } catch (_) {
      return null;
    }
  }

  static Future<WifiOtaRecord?> save(
    String deviceNo,
    String msgid, {
    String version = '',
    String baseVersion = '',
    String status = 'SENT',
    int lastStep = 0,
    String otaType = kWifiOtaTypeMain,
    String intro = '',
  }) async {
    final no = IotApi.plainDeviceNo(deviceNo);
    if (no.isEmpty || msgid.isEmpty) {
      return null;
    }
    final record = WifiOtaRecord(
      deviceNo: no,
      msgid: msgid,
      version: version,
      baseVersion: baseVersion,
      status: status,
      lastStep: lastStep,
      savedAt: DateTime.now().millisecondsSinceEpoch,
      otaType: otaType,
      intro: intro,
    );
    await _write(no, record);
    return record;
  }

  /// 记下最近一次查到的状态（重进页面先按它画，再等接口结果）；[progress] 为收到过的最大进度，null 不改。
  static Future<WifiOtaRecord?> update(
    String deviceNo, {
    required String status,
    required int lastStep,
    int? progress,
  }) async {
    final record = await read(deviceNo);
    if (record == null) {
      return null;
    }
    final next = record.copyWith(status: status, lastStep: lastStep, progress: progress);
    await _write(record.deviceNo, next);
    return next;
  }

  static Future<void> clear(String deviceNo) async {
    final no = IotApi.plainDeviceNo(deviceNo);
    if (no.isEmpty) {
      return;
    }
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.remove(storageKey(no));
    } catch (_) {
      // 清不掉下次查询 4044 时还会再清
    }
  }

  static Future<void> _write(String deviceNo, WifiOtaRecord record) async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(storageKey(deviceNo), jsonEncode(record.toJson()));
    } catch (error) {
      debugPrint('[WiFi升级] 保存 msgid 失败 $error');
    }
  }

  /// 向服务端核对本地进行中的任务：终态 / 4044 清掉记录；查询失败（网络 / 503 等）保留记录，下次再查。
  /// [getStatus] 默认调 [IotApi.getOtaStatus]，测试可替换。
  static Future<WifiOtaRefresh> refresh(
    String deviceNo, {
    Future<Map<String, dynamic>> Function(String msgid)? getStatus,
  }) async {
    final record = await read(deviceNo);
    if (record == null) {
      return const WifiOtaRefresh();
    }
    Map<String, dynamic> data;
    try {
      data = await (getStatus ?? IotApi.getOtaStatus)(record.msgid);
    } catch (error) {
      if (_isExpired(error)) {
        await clear(deviceNo);
        return const WifiOtaRefresh(expired: true);
      }
      return WifiOtaRefresh(record: record, status: record.status, error: error);
    }
    final status = normalizeOtaStatus(data['status']);
    if (isOtaFinal(status)) {
      await clear(deviceNo);
      return WifiOtaRefresh(status: status, data: data);
    }
    final index = otaStepIndex(status);
    final lastStep = index > record.lastStep ? index : record.lastStep;
    // 进度条：记下收到过的最大进度，重进页面从这里接着走
    final fresh = parseOtaProgress(data['progress']);
    final saved = record.progress ?? 0;
    final progress = fresh == null ? null : (fresh > saved ? fresh : saved);
    final next = await update(deviceNo, status: status, lastStep: lastStep, progress: progress) ?? record;
    return WifiOtaRefresh(record: next, status: status, data: data);
  }
}
