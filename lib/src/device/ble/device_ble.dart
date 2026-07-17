// 相框设备的 BLE 会话层（基于 flutter_blue_plus）。
// 由微信小程序版 `utils/bluetooth.js` + `utils/device-ble.js` 移植到 Dart，行为对齐：
//   · 扫描 / 连接 / 发现 FF00 服务下的 FF01(写)/FF02(通知) / 协商 MTU / 开启通知
//   · 请求-应答（发指令等 0x7F ACK，带超时）
//   · 图传协议(6.8)：0x20 帧头 → 0x21 窗口分包 + 0x23 累计确认 → 0x22 结束校验
//   · 严格遵守 PRD 6.4.1「1 秒红线」：等 ACK 超时(600ms)+ 重发退避(≤150ms) 都远小于 1s
//   · 【新增，小程序做不到】图传前请求短连接间隔(ConnectionPriority.high)，传完恢复省电(lowPower)
//
// iOS 不支持手动设连接间隔/请求 MTU，相关调用会被安全跳过（系统自动协商）。

import 'dart:async';
import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'frame_protocol.dart';
import 'image_codec.dart';

/// 收发监听记录（调试台用它打印每帧 16 进制）。
class BleMonitorRecord {
  BleMonitorRecord({
    required this.dir,
    required this.cmd,
    required this.hex,
    required this.note,
    required this.time,
  });

  final String dir; // TX / RX
  final int cmd;
  final String hex;
  final String note;
  final DateTime time;
}

/// BLE 层错误的机器可读分类：错误**语义**不再编码在展示字符串里。
/// UI（投屏失败页等）按 [FrameBleException.kind] 归类给出原因与建议，
/// message 只负责展示/日志——后续翻译服务层文案不会破坏归类逻辑
/// （此前 casting_progress 用 `raw.contains('繁忙')` 等中文子串匹配，一翻译即全部失灵）。
enum FrameBleErrorKind {
  /// 设备忙（结果码 0x0B / 刷屏或擦写中）——稍后重试即可。
  busy,

  /// 同一条指令已有请求在飞（如与 25s 保活心跳撞 0x04），内部瞬态，短暂重试即可。
  commandPending,

  /// 设备存储已满 / 无空闲槽位。
  storageFull,

  /// 未连接 / 连接已断开 / 该会话不可用。
  disconnected,

  /// 应答超时。
  timeout,

  /// 用户主动中止。
  aborted,

  /// 该型号不支持此操作（如 0x03 屏型不支持图传）。
  unsupported,

  /// 未细分（默认）。
  unknown,
}

class FrameBleException implements Exception {
  FrameBleException(this.message, {this.kind = FrameBleErrorKind.unknown});
  final String message;
  final FrameBleErrorKind kind;
  @override
  String toString() => message;
}

/// 图传预处理结果（性能优化 D1/D2）：整图 CRC32 + 按分包大小预组好的全部 0x21 帧。
/// 由 [FrameBleClient.prepareImageTransfer] 在「预取阶段」产出，[FrameBleClient.uploadImage]
/// 可选传入以跳过发送热路径上的 CRC 计算与逐帧组包。[frames] 在会话未就绪时为 null（只含 crc32）。
class PreparedTransfer {
  PreparedTransfer({
    required this.crc32,
    required this.dataSize,
    required this.chunkSize,
    required this.frames,
  });

  final int crc32;
  final int dataSize;
  final int chunkSize;
  final List<Uint8List>? frames;
}

class _Pending {
  _Pending(this.completer, this.timer);
  final Completer<ParsedAck> completer;
  final Timer timer;
}

/// 单设备 BLE 会话。一个实例管理一台已连接设备的收发与图传。
class FrameBleClient {
  /// 真实投屏参数，与小程序 `utils/device-ble.js` 保持一致。
  static const int transferPacketPaceMs = 3;
  static const int transferWindowPackets = 10;
  static const int transferWindowMaxPackets = 10;
  static const Duration transferAckAdvanceTimeout = Duration(milliseconds: 600);
  static const int transferMaxRetries = 15;

  BluetoothDevice? _device;
  BluetoothCharacteristic? _writeChar;
  StreamSubscription<List<int>>? _notifySub;
  StreamSubscription<BluetoothConnectionState>? _connSub;

  final List<int> _rxBuffer = [];
  final Map<int, _Pending> _pending = {};
  int _mtu = 23;
  bool _writeWithoutResponse = true;
  int _lastImgAck = -1; // 设备已连续接收到的最后包号
  // 图传发送方在等 0x23 累计 ACK 时挂起的唤醒器；ACK 一到 _onNotify 即 complete。
  // 图传协议全程串行（同一时刻只有一张图在传），单个字段即可。
  Completer<void>? _imgAckWaiter;

  /// 收发监听回调（可选）。
  void Function(BleMonitorRecord record)? onMonitor;

  /// Session-lifecycle observers owned by [BleController]. They only expose
  /// transport activity; they do not change scan/connect/reconnect behavior.
  void Function()? onActivity;
  void Function(bool connected)? onLinkStateChanged;
  void Function(bool active)? onTransferSessionChanged;

  int _transferSessionDepth = 0;

  // 物理链路是否存活：连接成功置 true，收到断开事件/主动断开置 false。
  // 若只看 _device/_writeChar 非空，设备侧断开（重启/超距/后台被系统挂起）后 connected
  // 仍会谎报 true——上层会复用这条死会话导致写失败/超时（对齐小程序「连接体检」治理的问题）。
  bool _linkAlive = false;

  int get mtu => _mtu;
  bool get connected => _device != null && _writeChar != null && _linkAlive;
  bool get writeWithoutResponse => _writeWithoutResponse;
  BluetoothDevice? get device => _device;

  /// 由 MTU 推算每个图片数据包能装多少字节（上限 236，见 6.8.2）。
  /// 必须保证「整帧(=chunk+8) ≤ 单次可写(=MTU-3)」，否则数据包会被静默丢弃导致图传卡死。
  int get dataChunk {
    final writable = (_mtu <= 0 ? 185 : _mtu) - 3;
    final maxFrame = writable < 244 ? writable : 244;
    final chunk = maxFrame - 8;
    if (chunk < 1) return 1;
    return chunk > 236 ? 236 : chunk;
  }

  // ── 扫描 ──────────────────────────────────────────────────

  /// 扫描附近设备 timeout 时长，返回去重后按信号强度排序的结果。
  /// 不按服务 UUID 过滤（真机广播不一定带 FF00，过滤会漏设备），能否绑定由连接时是否存在 FF00 判定。
  ///
  /// [allowedNames]：广播名白名单（产品列表的 broadcastId，如 `EF6-370`/`EF6-589`）。非空时只保留
  /// platformName 或广播名（大小写不敏感）包含其中之一的设备——只显示目标相框，滤掉周围其它蓝牙设备
  /// （对齐小程序 `utils/bluetooth.js` 的 `isAllowedFrame` 白名单过滤）。为 null/空则不过滤（调试台 allowAll 用）。
  /// [onUpdate]：每搜到一台**新**设备就回调一次「当前已搜到的（已过滤+按信号降序）列表」，供绑定页
  /// 「搜出一个显示一个」增量渲染（对齐小程序 `discoverDevices` 的 onUpdate），不必等满 timeout。
  /// [until]：命中即停。每次列表更新时用「当前已搜到的列表」判断是否已达成目标（如已扫到要连的那台），
  /// 返回真即**立刻停扫并返回**，不再苦等满 timeout——把「连接前扫描」从雷打不动 timeout 压到扫到即走
  /// （通常 <1s），对齐小程序 `bluetooth.discoverDevices` 的 `until`。未命中仍等满 timeout，给设备现身留足
  /// 时间；不传则行为完全不变（绑定/调试整窗扫描照旧）。自身异常按「未命中」处理。
  static Future<List<ScanResult>> scan({
    Duration timeout = const Duration(seconds: 8),
    List<String>? allowedNames,
    void Function(List<ScanResult> devices)? onUpdate,
    bool Function(List<ScanResult> devices)? until,
  }) async {
    // 白名单归一化（去空、大写）；为空表示放开过滤（allowAll）。
    final allow = (allowedNames ?? const <String>[])
        .map((s) => s.trim().toUpperCase())
        .where((s) => s.isNotEmpty)
        .toList();
    bool isAllowed(ScanResult r) {
      if (allow.isEmpty) {
        return true;
      }
      // name 与广播名都查：真机有时只在后续广播包里带上广播名。
      final name = '${r.device.platformName} ${r.advertisementData.advName}'
          .toUpperCase();
      return allow.any((a) => name.contains(a));
    }

    final found = <DeviceIdentifier, ScanResult>{};
    List<ScanResult> sorted() =>
        found.values.toList()..sort((a, b) => b.rssi.compareTo(a.rssi));

    final earlyStop = Completer<void>();

    final sub = FlutterBluePlus.scanResults.listen((list) {
      var changed = false;
      var sawAllowedDevice = false;
      for (final r in list) {
        if (!isAllowed(r)) {
          continue;
        }
        sawAllowedDevice = true;
        // 已收录的设备后续广播包继续刷新（RSSI/电量常在后续包才带全），但只有「新设备」才算变化，
        // 避免纯 RSSI 抖动高频触发 onUpdate 刷屏（对齐小程序按展示签名判变化的意图）。
        final existed = found.containsKey(r.device.remoteId);
        found[r.device.remoteId] = r;
        if (!existed) {
          changed = true;
        }
      }
      if (sawAllowedDevice) {
        final current = sorted();
        if (changed && onUpdate != null) {
          try {
            onUpdate(current);
          } catch (_) {
            // 页面回调自身异常不能中断扫描
          }
        }
        if (!earlyStop.isCompleted && until != null) {
          try {
            if (until(current)) {
              // 与小程序 discoverDevices(until) 一致：目标一出现就让等待方收网，
              // finally 会统一停止系统扫描并清理订阅。
              earlyStop.complete();
            }
          } catch (_) {
            // 匹配器异常不能中断扫描，继续等待自然超时。
          }
        }
      }
    });
    try {
      await FlutterBluePlus.startScan(timeout: timeout);
      // 扫描自然到点(isScanning 置 false) 或 目标命中(earlyStop) 先到者为准。
      await Future.any([
        FlutterBluePlus.isScanning.where((s) => s == false).first,
        earlyStop.future,
      ]);
    } finally {
      await sub.cancel();
      try {
        await FlutterBluePlus.stopScan();
      } catch (_) {}
    }
    return sorted();
  }

  // ── 连接 ──────────────────────────────────────────────────

  /// 连接设备并发现 FF00 主服务下的写(FF01)/通知(FF02)特征、协商 MTU、开启通知。
  ///
  /// 两条会话卫生规则（治「连不上也搜不到 + 前台服务空转」与「重连后通知被重复解析」）：
  /// ① 建立中任何一步失败都先回收物理连接再抛错——GATT 挂着时设备停止广播，之后
  ///    扫描永远搜不到这台设备；且失败会话绝不能把 `connected` 谎报成 true。
  /// ② `_linkAlive`/onLinkStateChanged(true) 要等**通知订阅成功后**才置——它一触发
  ///    控制器就启动保活心跳与 Android 前台服务，置早了失败路径下两者会永不停止。
  Future<void> connect(BluetoothDevice device) async {
    // 先清上一段会话的订阅残留：设备侧断开路径只置 _linkAlive=false、不撤订阅
    // （onValueReceived 是全局流，不随断开自动取消），不清的话重连同一设备后
    // 每条通知会被 N+1 个旧监听器重复解析，图传越用越慢。
    await _notifySub?.cancel();
    _notifySub = null;
    await _connSub?.cancel();
    _connSub = null;

    _device = device;
    _rxBuffer.clear();
    try {
      // ① 连接带重试（对齐小程序 device-ble.createConnectionWithRetry）：安卓 GATT 首次连接
      //    易抖动/超时，失败先物理断开清掉半连状态、等 400ms 再试，最多 2 次——单次失败即报错
      //    会让用户手动再点一次，体感明显不如小程序「一次就连上」。
      await _connectWithRetry(device);

      _connSub = device.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected) {
          _linkAlive = false;
          _failAllPending('连接已断开');
          onLinkStateChanged?.call(false);
        }
      });

      // 协商 MTU：Android 顶到 512；iOS 由系统协商，读 mtuNow。
      if (Platform.isAndroid) {
        try {
          _mtu = await device.requestMtu(512);
        } catch (_) {
          _mtu = device.mtuNow;
        }
      } else {
        _mtu = device.mtuNow;
      }

      // ② 服务/特征发现带重试（对齐小程序 discoverMainService/discoverCharacteristics）：
      //    安卓 discoverServices 首次常返回不全，轮询到 FF00 下 FF01(写)/FF02(通知) 齐了再继续，
      //    最多 5 次 / 每次间隔 250ms，用尽仍不全才判失败。
      final chars = await _discoverFrameChars(device);
      final wc = chars[0];
      final nc = chars[1];
      _writeChar = wc;
      // FF01 多为「无应答写」；若不支持无应答写则退回有应答。
      _writeWithoutResponse =
          wc.properties.writeWithoutResponse || !wc.properties.write;

      await nc.setNotifyValue(true);
      _notifySub = nc.onValueReceived.listen(_onNotify);
      // FBP 兜底：远端断开时自动撤销数据订阅（与 connect 入口的手动清理双保险）。
      device.cancelWhenDisconnected(_notifySub!);

      // 全部就绪，链路才算可用（见方法头注释②）。
      _linkAlive = true;
      onLinkStateChanged?.call(true);

      // 连接建立后立即把 BLE 连接间隔设为省电的空闲档(100ms)：图传时才临时切到极速档、传完再回落，
      // 保证保活挂着的连接不长期跑在费电的极速间隔上。best-effort（内部吞错、2s 短超时），失败不阻断连接。
      await applyIdleConnectionInterval();
    } catch (_) {
      // 见方法头注释①：失败必须物理断开，让设备恢复广播、可被再次扫到。
      // disconnect 幂等且自吞底层错误，不会掩盖原始异常。
      await disconnect();
      rethrow;
    }
  }

  /// 建立物理连接（带重试，对齐小程序 device-ble.createConnectionWithRetry）：
  /// 失败先断开清半连状态、等 400ms 再试，最多 [attempts] 次；全部失败抛最后一次错误。
  Future<void> _connectWithRetry(
    BluetoothDevice device, {
    int attempts = 2,
  }) async {
    Object? lastError;
    for (int i = 0; i < attempts; i++) {
      try {
        await device.connect(
          license: License.nonprofit,
          timeout: const Duration(seconds: 12),
          mtu: null,
        );
        return;
      } catch (error) {
        lastError = error;
        // 失败先物理断开：清掉半连状态、让设备恢复广播，否则下次扫描/连接更难成功
        //（对齐小程序 closeBLEConnection + sleep(400) 再重试）。
        try {
          await device.disconnect();
        } catch (_) {}
        if (i < attempts - 1) {
          await Future<void>.delayed(const Duration(milliseconds: 400));
        }
      }
    }
    throw lastError is FrameBleException
        ? lastError
        : FrameBleException('连接设备失败：${lastError ?? '未知错误'}');
  }

  /// 发现 FF00 主服务下的写(FF01)/通知(FF02)特征（带轮询重试，对齐小程序
  /// discoverMainService/discoverCharacteristics）：安卓首次 discoverServices 常返回不全，
  /// 轮询到齐再返回 `[write, notify]`；[attempts] 次 / 每次 250ms 用尽仍不全则抛错。
  Future<List<BluetoothCharacteristic>> _discoverFrameChars(
    BluetoothDevice device, {
    int attempts = 5,
  }) async {
    Object? lastError;
    for (int i = 0; i < attempts; i++) {
      try {
        final services = await device.discoverServices();
        BluetoothService? svc;
        for (final s in services) {
          if (_short16(s.uuid.str) == FrameProtocol.serviceUuid) {
            svc = s;
            break;
          }
        }
        if (svc != null) {
          BluetoothCharacteristic? wc;
          BluetoothCharacteristic? nc;
          for (final c in svc.characteristics) {
            final code = _short16(c.uuid.str);
            if (code == FrameProtocol.charWriteUuid) wc = c;
            if (code == FrameProtocol.charNotifyUuid) nc = c;
          }
          if (wc != null && nc != null) {
            return [wc, nc];
          }
        }
      } catch (error) {
        lastError = error;
      }
      if (i < attempts - 1) {
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
    }
    throw FrameBleException(
      lastError == null
          ? '未找到相框主服务(FF00)或读写特征(FF01/FF02)，请确认是相框设备'
          : '发现相框服务失败：$lastError',
    );
  }

  Future<void> disconnect() async {
    _linkAlive = false;
    _finishAllTransferSessions();
    await _notifySub?.cancel();
    _notifySub = null;
    await _connSub?.cancel();
    _connSub = null;
    _failAllPending('已断开连接');
    try {
      await _device?.disconnect();
    } catch (_) {}
    _writeChar = null;
  }

  void _failAllPending(String reason) {
    for (final p in _pending.values) {
      p.timer.cancel();
      if (!p.completer.isCompleted) {
        p.completer.completeError(
          FrameBleException(reason, kind: FrameBleErrorKind.disconnected),
        );
      }
    }
    _pending.clear();
    // 图传数据阶段挂着的 ACK 等待者也要立刻唤醒：否则断链后要等满 600ms ACK 超时、
    // 再经 4×80ms 写重试才把错误浮出来（报错慢 ~1s）。completeError 会沿
    // _waitAckAdvance → uploadImage 直接抛出，finally 的 endTransferSession
    // 对已断链是安全的 best-effort。
    final waiter = _imgAckWaiter;
    if (waiter != null && !waiter.isCompleted) {
      waiter.completeError(
        FrameBleException(reason, kind: FrameBleErrorKind.disconnected),
      );
    }
  }

  // ── 连接间隔（关键：图传前请求短间隔提速、传完恢复省电）──────

  /// 请求高优先级 / 短连接间隔（Android：CONNECTION_PRIORITY_HIGH ≈ 11.25–15ms）。iOS 跳过。
  Future<void> requestFastConnection() async {
    if (!Platform.isAndroid) return;
    try {
      await _device?.requestConnectionPriority(
        connectionPriorityRequest: ConnectionPriority.high,
      );
    } catch (_) {}
  }

  /// 恢复低功耗 / 长连接间隔（Android：CONNECTION_PRIORITY_LOW_POWER）。iOS 跳过。
  Future<void> requestPowerSaveConnection() async {
    if (!Platform.isAndroid) return;
    try {
      await _device?.requestConnectionPriority(
        connectionPriorityRequest: ConnectionPriority.lowPower,
      );
    } catch (_) {}
  }

  // ── BLE 连接间隔（CMD 0x05 / 0x13）────────────────────────
  //
  // 为什么必须有这两条指令（这是 App 图传比小程序慢的主因）：
  // BLE 的连接间隔由**中心(手机)**决定，外设只能发起「连接参数更新请求」让中心批准。
  //   · Android 的 `requestConnectionPriority(HIGH)` 只能把间隔压到 **11.25~15ms**；
  //   · iOS 干脆**没有**任何设置连接间隔的 API。
  // 而 0x13 是让**设备固件**去发起参数更新请求，能要到 **7.5ms**（协议最小值）。
  // 间隔直接决定吞吐（每个连接事件才能发一批包），7.5ms vs 15ms 就是约 2 倍的差距。
  // 小程序一直在下发 0x13，App 之前完全没实现 → 一直跑在手机默认/HIGH 的慢间隔上。

  /// 图传目标连接间隔：Android 7.5ms（协议最小值，安卓中心侧通常批准）；
  /// iOS 15ms —— Apple 规范拒绝 <15ms 的参数更新请求，请求 7.5ms 会被直接忽略、
  /// 链路反而停在系统自选的 30/45ms 上（小程序真机实测：请求 15ms 后吞吐 11.1→17.6KB/s）。
  static double get transferConnIntervalMs => Platform.isAndroid ? 7.5 : 15.0;

  /// 空闲期(非图传)的省电连接间隔：连接建立后、以及每次图传结束后都下发 0x13 把间隔回落到此值。
  /// 只有真正传图时才由 [optimizeConnectionIntervalForTransfer] 切到极速档(安卓 7.5 / iOS 15ms)——
  /// 连接是保活的，长期挂在费电的极速间隔上没必要（对齐小程序 device-ble.IDLE_CONN_INTERVAL_MS）。
  static const double idleConnIntervalMs = 100;

  /// 读取当前 BLE 连接间隔（CMD=0x05）。返回毫秒；读不到返回 0。
  ///
  /// 超时收紧到 2s（默认 6s）：0x05/0x13 是 v1.4 才有的指令，老固件可能**根本不回**。
  /// 用默认超时的话，每批投屏都要在这里白等 6s——比不做这个优化还慢。
  Future<double> getConnectionIntervalMs() async {
    final ack = await request(
      FrameProtocol.cmdGetConnInterval,
      timeout: const Duration(seconds: 2),
    );
    if (!ack.ok) {
      throw FrameBleException(FrameProtocol.resultText(ack.result));
    }
    final units = FrameProtocol.parseConnectionIntervalUnits(ack.data);
    return FrameProtocol.connectionIntervalUnitsToMs(units);
  }

  /// 设置 BLE 连接间隔（CMD=0x13）。[ms] 会按 1.25ms 单位四舍五入并做范围校验。
  Future<double> setConnectionIntervalMs(double ms) async {
    final units = FrameProtocol.connectionIntervalMsToUnits(ms);
    if (units < FrameProtocol.connIntervalMinUnits ||
        units > FrameProtocol.connIntervalMaxUnits) {
      throw FrameBleException(
        '连接间隔需在 ${FrameProtocol.connIntervalMinUnits}~${FrameProtocol.connIntervalMaxUnits} units 之间',
      );
    }
    final ack = await request(
      FrameProtocol.cmdSetConnInterval,
      payload: FrameProtocol.buildSetConnectionIntervalPayload(units),
      // 同 0x05：老固件可能不认这条指令，超时收紧到 2s，别让整批白等 6s。
      timeout: const Duration(seconds: 2),
    );
    if (!ack.ok) {
      throw FrameBleException(FrameProtocol.resultText(ack.result));
    }
    return FrameProtocol.connectionIntervalUnitsToMs(units);
  }

  /// 图传前的连接参数优化：**无条件**下发 0x13 把连接间隔切到 [transferConnIntervalMs]，
  /// 再回读 0x05 验证是否真的生效。失败不抛（旧固件可能不支持 0x05/0x13），图传照常继续。
  ///
  /// 为什么无条件下发（对齐小程序 2026-07-13 的修正）：0x05 读回的可能是固件保存的**配置值**，
  /// 而不是链路的实时参数——新连接的链路参数由手机侧决定。若因「读到的值已等于目标」就跳过 0x13，
  /// 整场图传会跑在手机默认间隔上，表现正是「传一段停一下、明显偏慢」。代价仅一条指令。
  Future<void> optimizeConnectionIntervalForTransfer() async {
    // Android 侧的系统级请求与设备侧的 0x13 不冲突，两个一起上效果最好。
    await requestFastConnection();
    try {
      final target = transferConnIntervalMs;
      await setConnectionIntervalMs(target);
      // 参数更新要走几个连接事件才落定，立刻回读常拿到旧值。
      await Future<void>.delayed(const Duration(milliseconds: 300));
      final actual = await getConnectionIntervalMs();
      if (kDebugMode) {
        debugPrint(
          '[BLE] 连接间隔：请求 ${target}ms，回读 ${actual}ms'
          '${(actual - target).abs() < 0.01 ? '（已生效）' : '（未生效，链路仍跑在实际值上）'}',
        );
      }
    } catch (error) {
      // 旧固件不支持 0x05/0x13、或设备拒绝：不阻断图传，只是跑在较慢的间隔上。
      if (kDebugMode) {
        debugPrint('[BLE] 连接间隔优化失败（不影响图传）：$error');
      }
    }
  }

  /// 把 BLE 连接间隔回落到空闲省电档（[idleConnIntervalMs]=100ms）：连接建立后、以及每次图传结束后调用，
  /// 让链路只在真正传图时跑极速档(7.5/15ms)，其余时间用省电的长间隔。best-effort、绝不抛：
  ///   ① 已断开直接跳过——不为了设间隔反而干扰断线清理；
  ///   ② 旧固件不支持 0x13 / 设备拒绝时吞掉（[setConnectionIntervalMs] 内部 0x13 已用 2s 短超时）。
  /// 注意：图传最后一张的异步刷屏(0x24)期间设备会对新指令回忙(0x0B)，调用方应等刷屏跑完再调本函数，
  /// 否则这次回落会撞上 0x0B 白白失败（见 projection_service 收尾对 lastRefresh 的链式处理）。
  Future<void> applyIdleConnectionInterval() async {
    if (!_linkAlive) return;
    try {
      await setConnectionIntervalMs(idleConnIntervalMs);
    } catch (error) {
      if (kDebugMode) {
        debugPrint('[BLE] 设空闲连接间隔失败（不影响使用）：$error');
      }
    }
  }

  /// 图传会话开始：整批投屏**只调一次**，不要每张图都调。
  ///
  /// 之前 `uploadImage` 每张都 requestFastConnection、传完又在 finally 里
  /// requestPowerSaveConnection —— 批量投屏时每两张之间链路都会掉回 LOW_POWER
  /// （安卓约 100~125ms 间隔），下一张开头还要在这个慢间隔上重新协商回高优先级，
  /// 白白拖慢每一张的前半段。现在把「设快 / 恢复省电」提到整批的首尾各一次。
  Future<void> beginTransferSession() async {
    _transferSessionDepth++;
    if (_transferSessionDepth == 1) {
      onTransferSessionChanged?.call(true);
    }
    try {
      await optimizeConnectionIntervalForTransfer();
    } catch (_) {
      _finishTransferSession();
      rethrow;
    }
  }

  /// 图传会话结束：恢复省电长间隔。
  /// 两条一起做：① Android 系统侧优先级回落 LOW_POWER；② 下发 0x13 把连接间隔回落到空闲档(100ms)。
  /// 注意：批量投屏(manageConnection=false)时最后一张会异步刷屏(0x24)，调用方须等刷屏跑完再调本方法，
  /// 否则 0x13 会撞上设备忙(0x0B)白白失败（见 projection_service 收尾对 lastRefresh 的链式处理）。
  Future<void> endTransferSession() async {
    try {
      await requestPowerSaveConnection();
      await applyIdleConnectionInterval();
    } finally {
      _finishTransferSession();
    }
  }

  void _finishTransferSession() {
    if (_transferSessionDepth == 0) {
      return;
    }
    _transferSessionDepth--;
    if (_transferSessionDepth == 0) {
      onTransferSessionChanged?.call(false);
    }
  }

  void _finishAllTransferSessions() {
    if (_transferSessionDepth == 0) {
      return;
    }
    _transferSessionDepth = 0;
    onTransferSessionChanged?.call(false);
  }

  // ── 通知接收 / 解帧派发 ───────────────────────────────────

  /// 接收缓冲上限：超过视为粘连/脏数据（坏 LEN 或失步），触发丢头重同步（对齐小程序 RX_BUFFER_MAX=2048）。
  static const int _rxBufferMax = 2048;

  /// 从 [from] 起在接收缓冲里找下一个 SOF(0xAA) 的下标；找不到返回 -1。
  int _indexOfSof(int from) {
    for (var i = from; i < _rxBuffer.length; i++) {
      if ((_rxBuffer[i] & 0xFF) == FrameProtocol.sof) return i;
    }
    return -1;
  }

  void _onNotify(List<int> value) {
    _rxBuffer.addAll(value);
    while (_rxBuffer.isNotEmpty) {
      final parsed = FrameProtocol.tryParseFrame(_rxBuffer);
      if (parsed == null) {
        // 解不出完整帧：区分「头就不是 SOF(失步/脏字节)」与「是 SOF 但整帧未收齐(等更多字节)」。
        // 失步时丢弃到下一个 SOF 重同步——否则一个坏头会永久卡死后续所有帧解析，该设备的每条指令
        // 都会应答超时（对齐小程序 device-ble.js 的丢头重同步 + RX_BUFFER_MAX 上限）。
        if ((_rxBuffer.first & 0xFF) != FrameProtocol.sof) {
          final next = _indexOfSof(1);
          if (next < 0) {
            _rxBuffer.clear(); // 没有 SOF：整段都是脏数据，清空
          } else {
            _rxBuffer.removeRange(0, next); // 丢到下一个 SOF
          }
          continue;
        }
        // 头是 SOF 但整帧未收齐：正常等更多字节。但缓冲异常膨胀（坏 LEN 声称超大帧、字节永不到齐）时，
        // 丢掉这个假 SOF 再找下一个 SOF 重同步，避免无上限堆积卡死。
        if (_rxBuffer.length > _rxBufferMax) {
          final next = _indexOfSof(1);
          if (next < 0) {
            _rxBuffer.clear();
          } else {
            _rxBuffer.removeRange(0, next);
          }
          continue;
        }
        break; // 头是 SOF、缓冲正常：等更多字节
      }
      final raw = _rxBuffer.sublist(0, parsed.consumed);
      _rxBuffer.removeRange(0, parsed.consumed);

      // 图传数据/批量 ACK 数量巨大，不逐条上报日志（与小程序一致）。
      if (parsed.cmd != FrameProtocol.cmdImgData &&
          parsed.cmd != FrameProtocol.cmdImgAck) {
        _report('RX', parsed.cmd, raw, note: parsed.crcOk ? '' : 'CRC校验失败');
      }

      if (parsed.cmd == FrameProtocol.cmdImgAck) {
        if (parsed.crcOk) {
          final seq = FrameProtocol.parseImgAck(parsed.payload);
          if (seq > _lastImgAck) _lastImgAck = seq;
          // 事件驱动唤醒等 ACK 的发送方（见 _waitAckAdvance）：
          // ACK 到达即刻推进，不再吃 15ms 轮询的平均 7.5ms 延迟。
          final waiter = _imgAckWaiter;
          if (waiter != null && !waiter.isCompleted) waiter.complete();
        }
        continue;
      }

      if (parsed.cmd != FrameProtocol.ack) continue;
      final ack = FrameProtocol.parseAck(parsed.payload);
      final pending = _pending.remove(ack.ackCmd);
      if (pending == null) continue;
      pending.timer.cancel();
      if (!pending.completer.isCompleted) {
        if (!parsed.crcOk) {
          pending.completer.completeError(FrameBleException('应答 CRC 校验失败'));
        } else if (FrameProtocol.isBusyResult(ack.result)) {
          // 设备忙（v1.5 §6.6.1，RESULT=0x0B）：设备在处理其它指令时对新指令回 0x0B。
          // 所有走 ACK 的设备交互（读信息/电量/播放配置、设置播放/校时/删除/刷新、图传起止）都在此汇合，
          // 集中拦截，无论读写一律以「当前设备繁忙，请稍后重试」抛出。
          pending.completer.completeError(
            FrameBleException(
              FrameProtocol.busyMessage,
              kind: FrameBleErrorKind.busy,
            ),
          );
        } else {
          pending.completer.complete(ack);
        }
      }
    }
  }

  void _report(String dir, int cmd, List<int> bytes, {String note = ''}) {
    onMonitor?.call(
      BleMonitorRecord(
        dir: dir,
        cmd: cmd,
        hex: FrameProtocol.bytesToHex(bytes),
        note: note,
        time: DateTime.now(),
      ),
    );
  }

  // ── 请求-应答 ─────────────────────────────────────────────

  /// [countsAsActivity]=false 供保活心跳使用：心跳只为在链路上制造流量，
  /// 不代表用户操作，不应刷新空闲租约——否则租约永远不会到期，
  /// 「前台空闲 10 分钟可断开」的策略会被心跳自己架空。
  Future<ParsedAck> request(
    int cmd, {
    List<int> payload = const [],
    Duration timeout = const Duration(seconds: 6),
    bool countsAsActivity = true,
  }) async {
    final chr = _writeChar;
    if (chr == null) {
      throw FrameBleException(
        '未连接或未发现写特征',
        kind: FrameBleErrorKind.disconnected,
      );
    }
    if (_pending.containsKey(cmd)) {
      throw FrameBleException(
        '指令 0x${cmd.toRadixString(16)} 正在等待应答',
        kind: FrameBleErrorKind.commandPending,
      );
    }
    final completer = Completer<ParsedAck>();
    final timer = Timer(timeout, () {
      _pending.remove(cmd);
      if (!completer.isCompleted) {
        completer.completeError(
          FrameBleException(
            '指令 0x${cmd.toRadixString(16)} 应答超时',
            kind: FrameBleErrorKind.timeout,
          ),
        );
      }
    });
    _pending[cmd] = _Pending(completer, timer);

    final frame = FrameProtocol.buildFrame(cmd, payload);
    _report('TX', cmd, frame);
    if (countsAsActivity) {
      onActivity?.call();
    }
    try {
      await chr.write(frame, withoutResponse: _writeWithoutResponse);
    } catch (e) {
      _pending.remove(cmd);
      timer.cancel();
      rethrow;
    }
    return completer.future;
  }

  // ── 业务指令 ──────────────────────────────────────────────

  /// 只读投屏关键路径需要的设备核心信息（CMD=0x01），不附带固件版本请求（性能优化 B2）：
  /// 0x03 固件版本对图传无用，却要多一个 BLE 往返挡在首张之前，故投屏走这条精简读取。
  Future<FrameDeviceInfo> readTransferInfo() async {
    final infoAck = await request(FrameProtocol.cmdGetInfo);
    return FrameProtocol.parseDeviceInfo(infoAck.data);
  }

  Future<FrameDeviceInfo> readDeviceInfo() async {
    var info = await readTransferInfo();
    try {
      final swAck = await request(FrameProtocol.cmdGetSwVer);
      info = info.copyWith(
        firmwareVersion: FrameProtocol.parseSwVer(swAck.data),
      );
    } catch (_) {}
    return info;
  }

  Future<int> readBattery() async {
    try {
      final ack = await request(FrameProtocol.cmdGetBattery);
      return FrameProtocol.parseBattery(ack.data);
    } on FrameBleException catch (e) {
      // 与 25s 保活心跳（同为 0x04）撞车时不要把「指令正在等待应答」这类内部措辞
      // 抛给用户：心跳超时上限 2s，稍候一次重试即可覆盖。
      if (e.kind != FrameBleErrorKind.commandPending) rethrow;
      await Future<void>.delayed(const Duration(milliseconds: 2200));
      final ack = await request(FrameProtocol.cmdGetBattery);
      return FrameProtocol.parseBattery(ack.data);
    }
  }

  /// 空闲保活心跳：发一条最轻的读电量(0x04)在链路上制造流量。
  ///
  /// 相框是电池供电设备，固件对空闲链路有自己的断链超时（实测 1~2 分钟无流量
  /// 就被设备侧断开），App 侧「前台保持 10 分钟」的租约策略必须靠周期心跳兜住，
  /// 否则策略形同虚设。心跳不算用户活动（countsAsActivity=false，不刷新租约）；
  /// 全程吞错——设备正忙回 0x0B、老固件超时都无妨，写出去的帧本身就是保活流量；
  /// 有指令在飞时直接跳过，绝不与业务请求抢 0x04 槽位。
  Future<void> keepAlivePing() async {
    if (!_linkAlive || _pending.isNotEmpty) {
      return;
    }
    try {
      await request(
        FrameProtocol.cmdGetBattery,
        timeout: const Duration(seconds: 2),
        countsAsActivity: false,
      );
    } catch (_) {}
  }

  Future<FramePlayConfig> getPlayConfig() async {
    final ack = await request(FrameProtocol.cmdGetPlay);
    return FrameProtocol.parsePlayConfig(ack.data);
  }

  Future<String> getSwVersion() async {
    final ack = await request(FrameProtocol.cmdGetSwVer);
    return FrameProtocol.parseSwVer(ack.data);
  }

  /// 返回更新后的 12 字节 IMG_MASK。
  Future<List<int>> setPlayback(String mode, int intervalSeconds) async {
    final ack = await request(
      FrameProtocol.cmdSetPlay,
      payload: FrameProtocol.buildSetPlaybackPayload(mode, intervalSeconds),
    );
    return FrameProtocol.parseMaskResult(ack.data);
  }

  Future<void> setTime(DateTime date) async {
    await request(
      FrameProtocol.cmdSetTime,
      payload: FrameProtocol.buildSetTimePayload(date),
    );
  }

  /// 删除图片（0x12）：传图片索引数组，内部转 12 字节掩码；设备返回删除后的 IMG_MASK。
  ///
  /// 删除由设备逐张擦除 flash，张数越多越慢（一键清空可能一次删几十张，设备全部删完才回一次应答）。
  /// 按张数放宽应答等待，避免设备还在删就被判「应答超时」误报「设备暂时无法连接」：
  /// 每张 2s 预算（60 张≈120s）、下限 6s、上限封顶 180s；调用方可传 [timeout] 显式覆盖。
  Future<List<int>> deleteImage(List<int> indexes, {Duration? timeout}) async {
    var waitMs = indexes.length * 2000;
    if (waitMs < 6000) waitMs = 6000;
    if (waitMs > 180000) waitMs = 180000;
    final ack = await request(
      FrameProtocol.cmdDeleteImg,
      payload: FrameProtocol.buildDeleteImagePayload(indexes),
      timeout: timeout ?? Duration(milliseconds: waitMs),
    );
    return FrameProtocol.parseMaskResult(ack.data);
  }

  /// 切换/刷新当前显示，返回 CUR_IMG_INDEX。
  Future<int> refreshScreen(int? index) async {
    final ack = await request(
      FrameProtocol.cmdSetCurImg,
      payload: FrameProtocol.buildRefreshPayload(index),
    );
    return FrameProtocol.parseRefreshResult(ack.data);
  }

  // ── 图传 ──────────────────────────────────────────────────

  /// 图传预处理（性能优化 D1/D2）：整图 CRC32 + 按当前会话分包大小预组好全部 0x21 帧。
  /// 纯计算、不碰蓝牙，设计为在「预取阶段」调用——与上一张图的 BLE 传输/本张的网络下载重叠，
  /// 把这两块耗时从「发 0x20 → 逐包发送」的串行热路径上挪走。每 256 帧让出一次事件循环，
  /// 避免长同步计算饿死正在并行进行的上一张图传的 0x23 ACK 处理。
  /// 未连接（分包大小未知）时只算 CRC32、frames 返回 null；[uploadImage] 收到对不上的 prepared
  /// 会自动回退为逐包现组，不影响正确性。
  Future<PreparedTransfer> prepareImageTransfer(Uint8List data) async {
    final crc = FrameImageCodec.crc32(data);
    if (!connected) {
      return PreparedTransfer(
        crc32: crc,
        dataSize: data.length,
        chunkSize: 0,
        frames: null,
      );
    }
    final chunk = dataChunk;
    final total = data.isEmpty ? 0 : (data.length + chunk - 1) ~/ chunk;
    final frames = <Uint8List>[];
    for (int seq = 0; seq < total; seq++) {
      frames.add(FrameProtocol.buildImgDataFrame(data, seq, chunk));
      if ((seq & 0xFF) == 0xFF) {
        await Future<void>.delayed(Duration.zero); // 让出事件循环
      }
    }
    return PreparedTransfer(
      crc32: crc,
      dataSize: data.length,
      chunkSize: chunk,
      frames: frames,
    );
  }

  /// 上传一张图片（含连接间隔提速）。onProgress(done, total, phase)；phase=retry 时带 stuckAt/retries。
  ///
  /// 数据段以「累计 ACK 驱动的滑动窗口」发送（性能优化 A1/A2/B1）：始终保持 ≤[window] 个未确认包在途，
  /// 设备每回一个 0x23 推进一格就立刻补包填满窗口，填掉 ACK 往返空档，不再「发满一批→停等→再发下一批」。
  /// [pace] 是发送节奏的上界（AIMD 自适应，B2）：连续多个干净窗口就下探更快（探到 0），一卡顿就回调并
  /// 上调一档兜底；[prepared] 为预取阶段的预处理结果（D1/D2），dataSize/分包对得上才用，否则自动回退现组。
  Future<FrameImgEnd> uploadImage({
    required int screenType,
    required int index,
    required int width,
    required int height,
    required Uint8List data,
    // 发送节奏上界（ms）。3ms 对齐小程序 PACKET_PACE_MS：固件已扩大收包缓冲(10 包)，
    // 配合 7.5ms 连接间隔按最快速率喂数据。原来默认 10ms —— AIMD 每 6 个干净窗口才降 0.5ms，
    // 从 10 探到 0 要 120 个窗口，整张图的前 1/6 都跑在明显偏慢的节奏上。
    int pace = transferPacketPaceMs,
    int window = transferWindowPackets,
    // 是否由本方法自己管理连接参数（设快 / 传完恢复省电）。
    // 批量投屏请传 false，改由调用方在**整批**首尾各调一次
    // [beginTransferSession] / [endTransferSession] —— 否则每张之间链路会掉回
    // LOW_POWER 再重新协商，白白拖慢每张的前半段。调试台直调本方法时用默认 true。
    bool manageConnection = true,
    PreparedTransfer? prepared,
    bool Function()? shouldAbort,
    void Function(
      int done,
      int total,
      String phase, {
      int? stuckAt,
      int? retries,
    })?
    onProgress,
  }) async {
    // 图传状态（_lastImgAck/_imgAckWaiter）是实例级单字段，协议全程串行；这里加门闩
    // 把「串行」变成硬约束——两路并发图传会互相打脏 ACK 状态，两张都以传输中断收场
    //（正常 UI 流程不会并发，但硬件调试台与业务页可同时触发）。
    if (_imgUploadBusy) {
      throw FrameBleException(
        '已有图传进行中，请等待当前传输结束',
        kind: FrameBleErrorKind.busy,
      );
    }
    _imgUploadBusy = true;

    final dataSize = data.length;
    // D2：只认 dataSize 对得上的预处理结果（防止把别张图的 prepared 传错进来——CRC32/帧都会错，
    // 设备端 0x22 校验必失败）；对得上就复用其整图 CRC32，跳过 0x20 前对整图再扫一遍。
    final PreparedTransfer? pre =
        (prepared != null && prepared.dataSize == dataSize) ? prepared : null;
    final crc = pre != null ? pre.crc32 : FrameImageCodec.crc32(data);

    // 图传前把连接间隔切到最快（吞吐翻倍、往返延迟骤降，远离设备 1s 接收超时）。
    // 批量投屏时 manageConnection=false —— 由调用方在整批首尾各调一次，见 beginTransferSession。
    if (manageConnection) {
      try {
        await beginTransferSession();
      } catch (_) {
        _imgUploadBusy = false;
        rethrow;
      }
    }
    try {
      final startAck = await request(
        FrameProtocol.cmdImgStart,
        payload: FrameProtocol.buildImgStartPayload(
          screenType: screenType,
          index: index,
          width: width,
          height: height,
          dataSize: dataSize,
          crc32: crc,
        ),
        timeout: const Duration(seconds: 10),
      );
      if (!startAck.ok) {
        throw FrameBleException(
          '帧头被拒绝(0x20)：${FrameProtocol.resultText(startAck.result)}',
          kind: FrameProtocol.isBusyResult(startAck.result)
              ? FrameBleErrorKind.busy
              : (startAck.result == 0x06
                    ? FrameBleErrorKind.storageFull
                    : FrameBleErrorKind.unknown),
        );
      }

      final chunk = dataChunk;
      final win = window < 1
          ? 1
          : (window > transferWindowMaxPackets
                ? transferWindowMaxPackets
                : window); // 固件收包缓冲 10 包，夹到 [1,10]
      final totalPackets = (dataSize + chunk - 1) ~/ chunk;

      // D1：预取阶段按会话分包大小预组好的全部 0x21 帧，分包/帧数对得上才用（会话重建后 MTU 可能变化）；
      // 没有或对不上（调试页直调、首张早于连接预取）则发送时逐包现组——buildImgDataFrame 也走查表，仍很快。
      final List<Uint8List>? prebuilt =
          (pre != null &&
              pre.chunkSize == chunk &&
              pre.frames != null &&
              pre.frames!.length == totalPackets)
          ? pre.frames
          : null;

      int nextSeq = 0;
      int retries = 0;
      const paceFloor = 0.0;
      const paceStep = 0.5;
      const paceProbeAfter = 6;
      double curPace = pace.toDouble();
      int cleanRun = 0;
      _lastImgAck = -1;
      onProgress?.call(0, totalPackets, 'start');

      while (_lastImgAck < totalPackets - 1) {
        if (shouldAbort?.call() ?? false) {
          throw FrameBleException('UPLOAD_ABORTED', kind: FrameBleErrorKind.aborted);
        }
        // 卡住重试时收敛：窗口逐步缩到 1 包、每包间隔逐步拉大，专门救「设备只收按序包、忙时丢包」。
        final curWindow = retries == 0
            ? win
            : (win - retries < 1 ? 1 : win - retries);
        final sendPace = retries == 0
            ? curPace
            : (curPace + 30 * retries > 150 ? 150.0 : curPace + 30 * retries);

        // 填窗：保持在途未确认包 < curWindow，每次 0x23 推进后回到这里补满。
        while (nextSeq < totalPackets &&
            nextSeq - _lastImgAck - 1 < curWindow) {
          if (shouldAbort?.call() ?? false) {
            throw FrameBleException('UPLOAD_ABORTED', kind: FrameBleErrorKind.aborted);
          }
          final seq = nextSeq;
          final frame = prebuilt != null
              ? prebuilt[seq]
              : FrameProtocol.buildImgDataFrame(data, seq, chunk);
          await _writePacket(frame);
          nextSeq++;
          final moreThisRound =
              nextSeq < totalPackets && nextSeq - _lastImgAck - 1 < curWindow;
          if (sendPace > 0 && moreThisRound) {
            await _sleepMs(sendPace);
          }
        }

        // 尾包 ACK 可能已在最后一次 write 的回调返回前到达，先复查，避免完成后再空等 600ms（B5）。
        if (_lastImgAck >= totalPackets - 1) break;

        final before = _lastImgAck;
        // 等设备 0x23 把「已连续接收包号」推过 before；超时 600ms（< 设备 1s 红线，PRD 6.4.1）。
        final advanced = await _waitAckAdvance(
          before,
          transferAckAdvanceTimeout,
        );
        if (!advanced) {
          // 超时回调和通知可能同时发生；重发前再复查一次，已推进就直接继续填窗。
          if (_lastImgAck > before) {
            retries = 0;
            onProgress?.call(_confirmed(totalPackets), totalPackets, 'data');
            continue;
          }
          if (++retries > transferMaxRetries) {
            throw FrameBleException(
              '图传中断：设备停在已接收第 $_lastImgAck 包不再前进。可能设备忙或处理不过来。当前 MTU=$_mtu、每包 $chunk 字节',
            );
          }
          onProgress?.call(
            _confirmed(totalPackets),
            totalPackets,
            'retry',
            stuckAt: _lastImgAck,
            retries: retries,
          );
          nextSeq = _lastImgAck + 1;
          curPace = curPace + paceStep > pace
              ? pace.toDouble()
              : curPace + paceStep;
          cleanRun = 0;
          final backoff = (50 * retries) > 150
              ? 150
              : 50 * retries; // 极短退避(≤150ms)
          await Future<void>.delayed(Duration(milliseconds: backoff));
          continue;
        }

        // 干净窗口：连续 paceProbeAfter 个就下探更快一档（AIMD，探到 0）。
        if (retries != 0) {
          cleanRun = 0;
        } else if (curPace > paceFloor && ++cleanRun >= paceProbeAfter) {
          curPace = curPace - paceStep < paceFloor
              ? paceFloor
              : curPace - paceStep;
          cleanRun = 0;
        }
        retries = 0;
        onProgress?.call(_confirmed(totalPackets), totalPackets, 'data');
      }

      // 0x22 结束：设备核对整图 CRC32 并落盘，给足 20s。
      final endAck = await request(
        FrameProtocol.cmdImgEnd,
        timeout: const Duration(seconds: 20),
      );
      if (!endAck.ok) {
        throw FrameBleException(
          '结束校验失败(0x22)：${FrameProtocol.resultText(endAck.result)}',
        );
      }
      onProgress?.call(totalPackets, totalPackets, 'done');
      return FrameProtocol.parseImgEndResult(endAck.data);
    } finally {
      _imgUploadBusy = false;
      // 无论成功失败，传完恢复省电长间隔（批量投屏由调用方在整批结束后统一恢复）。
      if (manageConnection) {
        await endTransferSession();
      }
    }
  }

  /// 图传互斥门闩（见 [uploadImage] 开头）。
  bool _imgUploadBusy = false;

  // 已确认包数（用于进度回调）：_lastImgAck+1，夹到 totalPackets。
  int _confirmed(int totalPackets) {
    final c = _lastImgAck + 1;
    return c > totalPackets ? totalPackets : c;
  }

  /// 写一个图传数据包（[frame] 为已组好的完整 0x21 帧），带「缓冲忙就退避重试」。
  Future<void> _writePacket(Uint8List frame) async {
    final chr = _writeChar;
    if (chr == null) throw FrameBleException('未连接或未发现写特征');
    int attempt = 0;
    while (true) {
      try {
        await chr.write(frame, withoutResponse: _writeWithoutResponse);
        return;
      } catch (e) {
        if (++attempt > 4) rethrow;
        await Future<void>.delayed(const Duration(milliseconds: 80));
      }
    }
  }

  // 支持小数毫秒的节流（AIMD 的 pace 以 0.5ms 为步进）。Duration 只接受整数，用微秒承载。
  Future<void> _sleepMs(double ms) {
    if (ms <= 0) return Future<void>.value();
    return Future<void>.delayed(Duration(microseconds: (ms * 1000).round()));
  }

  /// 等待 _lastImgAck 超过 minExclusive；超时返回 false。
  ///
  /// 事件驱动：挂一个 Completer，_onNotify 收到 0x23 ACK 时立即唤醒。
  /// 之前用 15ms 轮询，窗口打满时每次停等平均多耗 ~7.5ms——480×720 一帧
  /// 733 包按每窗一停估算，每张图要白等 0.5~1s。
  Future<bool> _waitAckAdvance(int minExclusive, Duration timeout) async {
    final deadline = DateTime.now().add(timeout);
    while (_lastImgAck <= minExclusive) {
      final remaining = deadline.difference(DateTime.now());
      if (remaining <= Duration.zero) return false;
      // 检查与挂载之间没有 await，单 isolate 下不会丢唤醒。
      final waiter = _imgAckWaiter = Completer<void>();
      try {
        await waiter.future.timeout(remaining);
      } on TimeoutException {
        return _lastImgAck > minExclusive;
      } finally {
        if (identical(_imgAckWaiter, waiter)) _imgAckWaiter = null;
      }
    }
    return true;
  }

  // 取 128 位/16 位 UUID 的 16 位短码做匹配（如 0000FF00-... → FF00）。
  static String _short16(String uuid) {
    final s = uuid.replaceAll('-', '').toUpperCase();
    if (s.length <= 4) return s.padLeft(4, '0');
    if (s.length >= 8) return s.substring(4, 8);
    return s.substring(s.length - 4);
  }
}
