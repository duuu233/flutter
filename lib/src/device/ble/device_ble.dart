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

class FrameBleException implements Exception {
  FrameBleException(this.message);
  final String message;
  @override
  String toString() => message;
}

class _Pending {
  _Pending(this.completer, this.timer);
  final Completer<ParsedAck> completer;
  final Timer timer;
}

/// 单设备 BLE 会话。一个实例管理一台已连接设备的收发与图传。
class FrameBleClient {
  BluetoothDevice? _device;
  BluetoothCharacteristic? _writeChar;
  BluetoothCharacteristic? _notifyChar;
  StreamSubscription<List<int>>? _notifySub;
  StreamSubscription<BluetoothConnectionState>? _connSub;

  final List<int> _rxBuffer = [];
  final Map<int, _Pending> _pending = {};
  int _mtu = 23;
  bool _writeWithoutResponse = true;
  int _lastImgAck = -1; // 设备已连续接收到的最后包号

  /// 收发监听回调（可选）。
  void Function(BleMonitorRecord record)? onMonitor;

  int get mtu => _mtu;
  bool get connected => _device != null && _writeChar != null;
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
  static Future<List<ScanResult>> scan({
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final found = <DeviceIdentifier, ScanResult>{};
    final sub = FlutterBluePlus.scanResults.listen((list) {
      for (final r in list) {
        found[r.device.remoteId] = r;
      }
    });
    try {
      await FlutterBluePlus.startScan(timeout: timeout);
      // 等扫描自然结束（startScan 到点会把 isScanning 置 false）
      await FlutterBluePlus.isScanning.where((s) => s == false).first;
    } finally {
      await sub.cancel();
      try {
        await FlutterBluePlus.stopScan();
      } catch (_) {}
    }
    final list = found.values.toList()
      ..sort((a, b) => b.rssi.compareTo(a.rssi));
    return list;
  }

  // ── 连接 ──────────────────────────────────────────────────

  /// 连接设备并发现 FF00 主服务下的写(FF01)/通知(FF02)特征、协商 MTU、开启通知。
  Future<void> connect(BluetoothDevice device) async {
    _device = device;
    _rxBuffer.clear();
    await device.connect(
      license: License.nonprofit,
      timeout: const Duration(seconds: 12),
      mtu: null,
    );

    _connSub = device.connectionState.listen((state) {
      if (state == BluetoothConnectionState.disconnected) {
        _failAllPending('连接已断开');
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

    final services = await device.discoverServices();
    BluetoothService? svc;
    for (final s in services) {
      if (_short16(s.uuid.str) == FrameProtocol.serviceUuid) {
        svc = s;
        break;
      }
    }
    if (svc == null) {
      throw FrameBleException('未找到相框主服务(FF00)，请确认是相框设备');
    }

    BluetoothCharacteristic? wc;
    BluetoothCharacteristic? nc;
    for (final c in svc.characteristics) {
      final code = _short16(c.uuid.str);
      if (code == FrameProtocol.charWriteUuid) wc = c;
      if (code == FrameProtocol.charNotifyUuid) nc = c;
    }
    if (wc == null || nc == null) {
      throw FrameBleException('未找到读写特征(FF01/FF02)');
    }
    _writeChar = wc;
    _notifyChar = nc;
    // FF01 多为「无应答写」；若不支持无应答写则退回有应答。
    _writeWithoutResponse = wc.properties.writeWithoutResponse || !wc.properties.write;

    await nc.setNotifyValue(true);
    _notifySub = nc.onValueReceived.listen(_onNotify);
  }

  Future<void> disconnect() async {
    await _notifySub?.cancel();
    _notifySub = null;
    await _connSub?.cancel();
    _connSub = null;
    _failAllPending('已断开连接');
    try {
      await _device?.disconnect();
    } catch (_) {}
    _writeChar = null;
    _notifyChar = null;
  }

  void _failAllPending(String reason) {
    for (final p in _pending.values) {
      p.timer.cancel();
      if (!p.completer.isCompleted) {
        p.completer.completeError(FrameBleException(reason));
      }
    }
    _pending.clear();
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

  // ── 通知接收 / 解帧派发 ───────────────────────────────────

  void _onNotify(List<int> value) {
    _rxBuffer.addAll(value);
    while (_rxBuffer.isNotEmpty) {
      final parsed = FrameProtocol.tryParseFrame(_rxBuffer);
      if (parsed == null) break;
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
        } else {
          pending.completer.complete(ack);
        }
      }
    }
  }

  void _report(String dir, int cmd, List<int> bytes, {String note = ''}) {
    onMonitor?.call(BleMonitorRecord(
      dir: dir,
      cmd: cmd,
      hex: FrameProtocol.bytesToHex(bytes),
      note: note,
      time: DateTime.now(),
    ));
  }

  // ── 请求-应答 ─────────────────────────────────────────────

  Future<ParsedAck> request(
    int cmd, {
    List<int> payload = const [],
    Duration timeout = const Duration(seconds: 6),
  }) async {
    final chr = _writeChar;
    if (chr == null) throw FrameBleException('未连接或未发现写特征');
    if (_pending.containsKey(cmd)) {
      throw FrameBleException('指令 0x${cmd.toRadixString(16)} 正在等待应答');
    }
    final completer = Completer<ParsedAck>();
    final timer = Timer(timeout, () {
      _pending.remove(cmd);
      if (!completer.isCompleted) {
        completer.completeError(
            FrameBleException('指令 0x${cmd.toRadixString(16)} 应答超时'));
      }
    });
    _pending[cmd] = _Pending(completer, timer);

    final frame = FrameProtocol.buildFrame(cmd, payload);
    _report('TX', cmd, frame);
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

  Future<FrameDeviceInfo> readDeviceInfo() async {
    final infoAck = await request(FrameProtocol.cmdGetInfo);
    var info = FrameProtocol.parseDeviceInfo(infoAck.data);
    try {
      final swAck = await request(FrameProtocol.cmdGetSwVer);
      info = info.copyWith(firmwareVersion: FrameProtocol.parseSwVer(swAck.data));
    } catch (_) {}
    return info;
  }

  Future<int> readBattery() async {
    final ack = await request(FrameProtocol.cmdGetBattery);
    return FrameProtocol.parseBattery(ack.data);
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
    final ack = await request(FrameProtocol.cmdSetPlay,
        payload: FrameProtocol.buildSetPlaybackPayload(mode, intervalSeconds));
    return FrameProtocol.parseMaskResult(ack.data);
  }

  Future<void> setTime(DateTime date) async {
    await request(FrameProtocol.cmdSetTime,
        payload: FrameProtocol.buildSetTimePayload(date));
  }

  Future<List<int>> deleteImage(List<int> indexes) async {
    final ack = await request(FrameProtocol.cmdDeleteImg,
        payload: FrameProtocol.buildDeleteImagePayload(indexes));
    return FrameProtocol.parseMaskResult(ack.data);
  }

  /// 切换/刷新当前显示，返回 CUR_IMG_INDEX。
  Future<int> refreshScreen(int? index) async {
    final ack = await request(FrameProtocol.cmdSetCurImg,
        payload: FrameProtocol.buildRefreshPayload(index));
    return FrameProtocol.parseRefreshResult(ack.data);
  }

  // ── 图传 ──────────────────────────────────────────────────

  /// 上传一张图片（含连接间隔提速）。onProgress(done, total, phase)；phase=retry 时带 stuckAt/retries。
  Future<FrameImgEnd> uploadImage({
    required int screenType,
    required int index,
    required int width,
    required int height,
    required Uint8List data,
    int pace = 45,
    bool Function()? shouldAbort,
    void Function(int done, int total, String phase, {int? stuckAt, int? retries})?
        onProgress,
  }) async {
    final dataSize = data.length;
    final crc = FrameImageCodec.crc32(data);

    // 图传前请求短连接间隔（吞吐翻几倍、往返延迟骤降，远离设备 1s 接收超时）。
    await requestFastConnection();
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
        throw FrameBleException('帧头被拒绝(0x20)：${FrameProtocol.resultText(startAck.result)}');
      }

      final chunk = dataChunk;
      const window = 5;
      final totalPackets = (dataSize + chunk - 1) ~/ chunk;
      final settlePause = pace < 10 ? 10 : pace; // 窗口间小停顿，必须远小于 1s
      int nextSeq = 0;
      int retries = 0;
      _lastImgAck = -1;
      onProgress?.call(0, totalPackets, 'start');

      while (nextSeq < totalPackets) {
        if (shouldAbort?.call() ?? false) {
          throw FrameBleException('UPLOAD_ABORTED');
        }
        // 卡住重试时收敛：窗口逐步缩到 1 包、每包间隔逐步拉大，专门救「设备只收按序包、忙时丢包」。
        final burst = retries == 0 ? window : (window - retries < 1 ? 1 : window - retries);
        final sendPace = retries == 0
            ? pace
            : (pace + 30 * retries > 150 ? 150 : pace + 30 * retries);
        final windowEnd =
            (nextSeq + burst) > totalPackets ? totalPackets : nextSeq + burst;
        for (int seq = nextSeq; seq < windowEnd; seq++) {
          final start = seq * chunk;
          final end = (start + chunk) > dataSize ? dataSize : start + chunk;
          await _writePacket(seq, data.sublist(start, end));
          if (sendPace > 0) {
            await Future<void>.delayed(Duration(milliseconds: sendPace));
          }
        }

        // 等设备 0x23 把「已连续接收包号」推过 nextSeq-1；超时 600ms（< 设备 1s 红线，PRD 6.4.1）。
        final advanced =
            await _waitAckAdvance(nextSeq - 1, const Duration(milliseconds: 600));
        if (!advanced) {
          if (++retries > 15) {
            throw FrameBleException(
                '图传中断：设备停在已接收第 $_lastImgAck 包不再前进。可能设备忙或处理不过来。当前 MTU=$_mtu、每包 $chunk 字节');
          }
          onProgress?.call(nextSeq, totalPackets, 'retry',
              stuckAt: _lastImgAck, retries: retries);
          final backoff = (50 * retries) > 150 ? 150 : 50 * retries; // 极短退避(≤150ms)
          await Future<void>.delayed(Duration(milliseconds: backoff));
          continue;
        }

        nextSeq = _lastImgAck + 1;
        retries = 0;
        onProgress?.call(
            nextSeq > totalPackets ? totalPackets : nextSeq, totalPackets, 'data');
        await Future<void>.delayed(Duration(milliseconds: settlePause));
      }

      // 0x22 结束：设备核对整图 CRC32 并落盘，给足 20s。
      final endAck =
          await request(FrameProtocol.cmdImgEnd, timeout: const Duration(seconds: 20));
      if (!endAck.ok) {
        throw FrameBleException('结束校验失败(0x22)：${FrameProtocol.resultText(endAck.result)}');
      }
      onProgress?.call(totalPackets, totalPackets, 'done');
      return FrameProtocol.parseImgEndResult(endAck.data);
    } finally {
      // 无论成功失败，传完恢复省电长间隔。
      await requestPowerSaveConnection();
    }
  }

  /// 写一个图传数据包，带「缓冲忙就退避重试」。
  Future<void> _writePacket(int seq, List<int> chunk) async {
    final chr = _writeChar;
    if (chr == null) throw FrameBleException('未连接或未发现写特征');
    int attempt = 0;
    while (true) {
      try {
        final frame = FrameProtocol.buildFrame(
            FrameProtocol.cmdImgData, FrameProtocol.buildImgDataPayload(seq, chunk));
        await chr.write(frame, withoutResponse: _writeWithoutResponse);
        return;
      } catch (e) {
        if (++attempt > 4) rethrow;
        await Future<void>.delayed(const Duration(milliseconds: 80));
      }
    }
  }

  /// 轮询等待 _lastImgAck 超过 minExclusive；超时返回 false。15ms 轮询足够（BLE notify 延迟级别）。
  Future<bool> _waitAckAdvance(int minExclusive, Duration timeout) async {
    final deadline = DateTime.now().add(timeout);
    while (_lastImgAck <= minExclusive) {
      if (DateTime.now().isAfter(deadline)) return false;
      await Future<void>.delayed(const Duration(milliseconds: 15));
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
