// ⚠️ 临时文件：安卓「原生 BLE 连接」与「现有 flutter_blue_plus 连接」的 A/B 对照实验。
//
// 存在理由：用户反馈「同样的弱网设备，别人的 APP 连得上、我们连不上」，并提出是不是
// Flutter 的性能瓶颈、要不要把蓝牙连接改成安卓原生实现。建连本身发生在蓝牙协议栈与控制器
// 固件里，Dart 快慢改变不了 CONNECT_IND 的时机——所以**不能**拿「换原生就更快」当假设直接
// 重写整个传输层。先量，再决定：同一台手机、同一台相框、同一个位置，两条路径各跑若干次，
// 比成功率和分段耗时。
//
// 本文件只被诊断页 `ble_perf_page.dart` 使用，**不参与任何业务连接**。
// 定版选定一种实现后整体删除，清单见
// `docs/history/2026-07/2026-07-30-安卓原生连接AB对比.md`「拆除清单」。

import 'dart:io' show Platform;

import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../ble_controller.dart';
import '../serial_match.dart';
import 'ble_direct_connect_cache.dart';
import 'device_ble.dart';

/// 被测目标。由「选择设备」按钮扫一轮后让用户点选得到，不依赖后端设备列表。
class BleAbTarget {
  const BleAbTarget({
    required this.serial,
    required this.name,
    required this.screenCode,
  });

  /// 完整 6 字节 Device_ID；扫描阶段只能拿到广播 4 字节短 ID，
  /// 所以这里允许是短 ID——最终验身仍由连上后读到的 0x01 完成。
  final String serial;
  final String name;
  final int screenCode;

  String get label => name.isEmpty ? serial : '$name（$serial）';
}

/// 两条路径共用的一次 trial 结果。字段刻意与原生侧返回的 map 同名。
class BleTrialResult {
  const BleTrialResult({
    required this.path,
    required this.ok,
    required this.stage,
    required this.totalMs,
    this.error,
    this.gattStatus,
    this.rssi,
    this.remoteId,
    this.deviceId,
    this.mtu = 0,
    this.advPackets,
    this.advDevices,
    this.timings = const <String, int>{},
    this.log = const <String>[],
  });

  /// 'native' | 'fbp'
  final String path;
  final bool ok;

  /// 成功为 `done`；失败为停住的那一步（scan/connect/discover/mtu/notify/readInfo/…）。
  final String stage;
  final int totalMs;
  final String? error;
  final int? gattStatus;
  final int? rssi;
  final String? remoteId;
  final String? deviceId;
  final int mtu;

  /// 扫描窗口内收到的广播总包数 / 去重设备数。**只有原生侧能给**：
  /// FBP 的 `scan()` 只把「展示签名有变化」的结果回调上来，拿不到原始包计数。
  /// 这个数字本身就是结论的一部分——它等于不过滤扫描时要搬过 platform channel 的量。
  final int? advPackets;
  final int? advDevices;

  final Map<String, int> timings;
  final List<String> log;

  String get pathLabel => path == 'native' ? '原生' : '现有(FBP)';

  factory BleTrialResult.fromNativeMap(Map<Object?, Object?> map) {
    final timings = <String, int>{};
    final raw = map['timings'];
    if (raw is Map) {
      raw.forEach((key, value) {
        if (value is num) timings['$key'] = value.round();
      });
    }
    return BleTrialResult(
      path: 'native',
      ok: map['ok'] == true,
      stage: '${map['stage'] ?? 'unknown'}',
      totalMs: (map['totalMs'] as num?)?.round() ?? 0,
      error: map['error'] as String?,
      gattStatus: (map['gattStatus'] as num?)?.toInt(),
      rssi: (map['rssi'] as num?)?.toInt(),
      remoteId: map['remoteId'] as String?,
      deviceId: map['deviceId'] as String?,
      mtu: (map['mtu'] as num?)?.toInt() ?? 0,
      advPackets: (map['advPackets'] as num?)?.toInt(),
      advDevices: (map['advDevices'] as num?)?.toInt(),
      timings: timings,
      log: (map['log'] as List?)?.map((e) => '$e').toList() ?? const <String>[],
    );
  }

  /// 一行摘要，直接进结果表与剪贴板。
  String get summary {
    final buffer = StringBuffer()
      ..write(ok ? '✅' : '❌')
      ..write(' $pathLabel ')
      ..write('${totalMs}ms');
    if (rssi != null) buffer.write(' rssi=$rssi');
    if (!ok) {
      buffer.write(' 停在=$stage');
      if (gattStatus != null) buffer.write(' status=$gattStatus');
      if (error != null && error!.isNotEmpty) buffer.write(' ${error!}');
    } else {
      if (mtu > 0) buffer.write(' mtu=$mtu');
      if (deviceId != null) buffer.write(' id=$deviceId');
    }
    if (advPackets != null) buffer.write(' 广播包=$advPackets/${advDevices ?? 0}台');
    if (timings.isNotEmpty) {
      buffer.write(' [');
      buffer.write(timings.entries.map((e) => '${e.key}:${e.value}').join(' '));
      buffer.write(']');
    }
    return buffer.toString();
  }
}

/// 一条路径的累计统计。两个按钮各按一次就多一条样本，按到心里有数为止。
class BleTrialStats {
  BleTrialStats(this.path);

  final String path;
  final List<BleTrialResult> results = <BleTrialResult>[];

  int get total => results.length;
  int get success => results.where((r) => r.ok).length;
  String get successRate =>
      total == 0 ? '-' : '${(success * 100 / total).toStringAsFixed(0)}%';

  List<int> get _okDurations =>
      (results.where((r) => r.ok).map((r) => r.totalMs).toList())..sort();

  int? get medianMs {
    final list = _okDurations;
    if (list.isEmpty) return null;
    return list[list.length ~/ 2];
  }

  int? get minMs => _okDurations.isEmpty ? null : _okDurations.first;
  int? get maxMs => _okDurations.isEmpty ? null : _okDurations.last;

  /// 失败停在哪一步的分布——比平均耗时有用得多：
  /// 全停在 `scan` 是搜不到，全停在 `connect` 才是建连问题。
  Map<String, int> get failureStages {
    final map = <String, int>{};
    for (final r in results.where((r) => !r.ok)) {
      map[r.stage] = (map[r.stage] ?? 0) + 1;
    }
    return map;
  }

  void clear() => results.clear();
}

/// 原生探针的 MethodChannel 门面（对应 `BleNativeProbe.kt`）。
class _NativeProbe {
  static const MethodChannel _channel =
      MethodChannel('com.boltfox.boltstar/ble_probe');

  static bool get isSupported => Platform.isAndroid;

  static Future<Map<Object?, Object?>> runTrial(Map<String, dynamic> args) async {
    final result = await _channel.invokeMethod<Map<Object?, Object?>>(
      'runTrial',
      args,
    );
    return result ?? const <Object?, Object?>{};
  }

  static Future<void> cancel() async {
    try {
      await _channel.invokeMethod<void>('cancel');
    } catch (_) {
      // 取消是 best-effort。
    }
  }
}

/// A/B 对照的执行器。两条路径各一个入口，页面上就是两个按钮。
class BleAbBenchmark {
  BleAbBenchmark._();

  static bool get nativeSupported => _NativeProbe.isSupported;

  /// 扫一轮，把在场的相框列出来供用户点选目标。
  static Future<List<ScanResult>> discoverTargets({
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final ctrl = BleController.instance;
    if (!await ctrl.ensurePermission()) {
      throw StateError('蓝牙不可用或未授权');
    }
    if (ctrl.connected) {
      await ctrl.disconnect();
    }
    return ctrl.scan(timeout: timeout);
  }

  /// ① 现有路径：完全走生产代码（`BleController.scan` + `BleController.connect`），
  /// 包含弱信号闸、建连超时阶梯与安卓 autoConnect 兜底。测的就是用户真实体感。
  ///
  /// 刻意**不**走 `connectBoundDevice`：那条入口还包含系统已连接表与直连缓存两条快路径，
  /// 命中时几乎瞬时完成，与原生探针的完整扫描不在同一起跑线上，混在一起统计毫无意义。
  static Future<BleTrialResult> runFbpTrial({
    required BleAbTarget target,
    bool clearDirectCache = true,
    Duration scanTimeout = const Duration(seconds: 12),
  }) async {
    final ctrl = BleController.instance;
    final timings = <String, int>{};
    final log = <String>[];
    final sw = Stopwatch()..start();
    var last = 0;

    void mark(String stage) {
      timings[stage] = sw.elapsedMilliseconds - last;
      last = sw.elapsedMilliseconds;
    }

    void note(String message) => log.add('+${sw.elapsedMilliseconds}ms $message');

    BleTrialResult done({
      required bool ok,
      required String stage,
      String? error,
      int? rssi,
      String? remoteId,
      String? deviceId,
      int mtu = 0,
    }) {
      return BleTrialResult(
        path: 'fbp',
        ok: ok,
        stage: stage,
        totalMs: sw.elapsedMilliseconds,
        error: error,
        rssi: rssi,
        remoteId: remoteId,
        deviceId: deviceId,
        mtu: mtu,
        timings: timings,
        log: log,
      );
    }

    try {
      note('trial start');
      if (ctrl.connected) {
        await ctrl.disconnect();
        note('断开既有会话');
      }
      if (clearDirectCache) {
        // 让两条路径同起跑线：清掉直连缓存，逼这一轮走完整扫描。
        // 缓存会在下次正常连接成功后自动重建，不留长期影响。
        await BleDirectConnectCache.instance.remove(target.serial);
        note('已清直连缓存');
      }
      if (!await ctrl.ensurePermission()) {
        return done(ok: false, stage: 'permission', error: '蓝牙不可用或未授权');
      }
      mark('prepare');

      // 复刻生产路径的弱信号闸：命中候选后，RSSI 低于闸值时最多再等 1.5s 抢更强的一帧。
      final waited = Stopwatch();
      final found = await ctrl.scan(
        timeout: scanTimeout,
        until: (list) {
          final hit = BleController.matchScannedDevice(
            list,
            serial: target.serial,
            name: target.name,
            screenCode: target.screenCode,
          );
          if (hit == null) return false;
          if (!waited.isRunning) waited.start();
          return BleController.shouldConnectAtRssi(hit.rssi, waited.elapsed);
        },
      );
      mark('scan');

      final hit = BleController.matchScannedDevice(
        found,
        serial: target.serial,
        name: target.name,
        screenCode: target.screenCode,
      );
      if (hit == null) {
        note('扫描窗口内未命中目标（在场 ${found.length} 台）');
        return done(ok: false, stage: 'scan', error: '未扫到目标设备');
      }
      note('matched ${hit.device.remoteId.str} rssi=${hit.rssi}');

      // 与生产路径一致：停扫沉淀后再建连（扫描与 GATT 抢同一路射频）。
      await FrameBleClient.settleAfterScan();
      mark('settle');

      final error = await ctrl.connect(hit);
      mark('connectAndReadInfo');
      if (error != null) {
        note('connect 失败：$error');
        return done(
          ok: false,
          stage: 'connect',
          error: error,
          rssi: hit.rssi,
          remoteId: hit.device.remoteId.str,
        );
      }

      final deviceId = ctrl.info?.deviceId ?? '';
      final mtu = ctrl.client.mtu;
      note('connected mtu=$mtu deviceId=$deviceId');
      // 与原生侧同一把尺子：目标序列号来自广播（4 字节短 ID），0x01 返回的是 6 字节完整 ID，
      // 只能按「短值是长值的前缀或后缀」匹配，不能精确相等。
      if (target.serial.isNotEmpty && !serialsMatch(deviceId, target.serial)) {
        return done(
          ok: false,
          stage: 'identity-mismatch',
          error: '0x01 返回 $deviceId，与目标不符',
          rssi: hit.rssi,
          remoteId: hit.device.remoteId.str,
          deviceId: deviceId,
          mtu: mtu,
        );
      }
      return done(
        ok: true,
        stage: 'done',
        rssi: hit.rssi,
        remoteId: hit.device.remoteId.str,
        deviceId: deviceId,
        mtu: mtu,
      );
    } catch (error) {
      note('异常：$error');
      return done(ok: false, stage: 'exception', error: '$error');
    } finally {
      // 对照实验必须每轮回到「未连接」，否则下一轮的起点不同、数据不可比。
      if (ctrl.connected) {
        await ctrl.disconnect();
      }
    }
  }

  /// ② 原生路径：Kotlin 侧 `BleNativeProbe` 跑同构的一次冷连接。
  ///
  /// 跑之前必须把 FBP 会话断干净——两套 GATT 客户端同时在场会互相干扰，测出来的不作数。
  static Future<BleTrialResult> runNativeTrial({
    required BleAbTarget target,
    bool useScanFilter = false,
    bool aggressiveMatch = true,
    bool autoConnect = false,
    int settleMs = 0,
    Duration scanTimeout = const Duration(seconds: 12),
    Duration connectTimeout = const Duration(seconds: 8),
  }) async {
    if (!_NativeProbe.isSupported) {
      return const BleTrialResult(
        path: 'native',
        ok: false,
        stage: 'unsupported',
        totalMs: 0,
        error: '原生探针仅安卓可用',
      );
    }
    final ctrl = BleController.instance;
    if (ctrl.connected) {
      await ctrl.disconnect();
    }
    if (!await ctrl.ensurePermission()) {
      return const BleTrialResult(
        path: 'native',
        ok: false,
        stage: 'permission',
        totalMs: 0,
        error: '蓝牙不可用或未授权',
      );
    }
    try {
      final map = await _NativeProbe.runTrial(<String, dynamic>{
        'serial': target.serial,
        'screenCode': target.screenCode,
        // 广播里读不出厂商数据时的候选白名单，与扫描侧同款型号名。
        'namePrefixes': const <String>['EF6-370', 'EF6-589', 'EF6-730'],
        'scanTimeoutMs': scanTimeout.inMilliseconds,
        'connectTimeoutMs': connectTimeout.inMilliseconds,
        'settleMs': settleMs,
        'autoConnect': autoConnect,
        'useScanFilter': useScanFilter,
        'aggressiveMatch': aggressiveMatch,
      });
      return BleTrialResult.fromNativeMap(map);
    } on PlatformException catch (error) {
      return BleTrialResult(
        path: 'native',
        ok: false,
        stage: 'platform',
        totalMs: 0,
        error: '${error.code}: ${error.message}',
      );
    } catch (error) {
      return BleTrialResult(
        path: 'native',
        ok: false,
        stage: 'exception',
        totalMs: 0,
        error: '$error',
      );
    }
  }

  static Future<void> cancelNative() => _NativeProbe.cancel();

  /// 导出成可直接贴进文档的对照报告。
  static String report({
    required BleAbTarget? target,
    required BleTrialStats fbp,
    required BleTrialStats native,
  }) {
    final buffer = StringBuffer()
      ..writeln('# 安卓原生 vs 现有(FBP) 连接对照')
      ..writeln('目标：${target?.label ?? '未选择'}')
      ..writeln();

    void section(String title, BleTrialStats stats) {
      buffer
        ..writeln('## $title')
        ..writeln(
          '样本 ${stats.total} 次，成功 ${stats.success} 次（${stats.successRate}）；'
          '成功耗时 中位 ${stats.medianMs ?? '-'}ms / 最快 ${stats.minMs ?? '-'}ms / 最慢 ${stats.maxMs ?? '-'}ms',
        );
      final failures = stats.failureStages;
      if (failures.isNotEmpty) {
        buffer.writeln(
          '失败分布：${failures.entries.map((e) => '${e.key}×${e.value}').join('，')}',
        );
      }
      for (var i = 0; i < stats.results.length; i++) {
        buffer.writeln('${i + 1}. ${stats.results[i].summary}');
      }
      buffer.writeln();
    }

    section('现有路径 (flutter_blue_plus)', fbp);
    section('原生路径 (Kotlin BluetoothGatt)', native);
    return buffer.toString();
  }
}
