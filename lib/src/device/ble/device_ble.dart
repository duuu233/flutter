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
        _linkAlive = false;
        _failAllPending('连接已断开');
      }
    });
    _linkAlive = true;

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
    _linkAlive = false;
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
        } else if (FrameProtocol.isBusyResult(ack.result)) {
          // 设备忙（v1.5 §6.6.1，RESULT=0x0B）：设备在处理其它指令时对新指令回 0x0B。
          // 所有走 ACK 的设备交互（读信息/电量/播放配置、设置播放/校时/删除/刷新、图传起止）都在此汇合，
          // 集中拦截，无论读写一律以「当前设备繁忙，请稍后重试」抛出。
          pending.completer
              .completeError(FrameBleException(FrameProtocol.busyMessage));
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
    final ack = await request(FrameProtocol.cmdSetCurImg,
        payload: FrameProtocol.buildRefreshPayload(index));
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
          crc32: crc, dataSize: data.length, chunkSize: 0, frames: null);
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
        crc32: crc, dataSize: data.length, chunkSize: chunk, frames: frames);
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
    int pace = 10,
    int window = 10,
    PreparedTransfer? prepared,
    bool Function()? shouldAbort,
    void Function(int done, int total, String phase, {int? stuckAt, int? retries})?
        onProgress,
  }) async {
    final dataSize = data.length;
    // D2：只认 dataSize 对得上的预处理结果（防止把别张图的 prepared 传错进来——CRC32/帧都会错，
    // 设备端 0x22 校验必失败）；对得上就复用其整图 CRC32，跳过 0x20 前对整图再扫一遍。
    final PreparedTransfer? pre =
        (prepared != null && prepared.dataSize == dataSize) ? prepared : null;
    final crc = pre != null ? pre.crc32 : FrameImageCodec.crc32(data);

    // 图传前请求短连接间隔（吞吐翻几倍、往返延迟骤降，远离设备 1s 接收超时）。
    // 【App 自有方案】用系统级 ConnectionPriority.high（Android），而非小程序的 0x13/0x05 设备指令。
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
      final win = window < 1 ? 1 : (window > 10 ? 10 : window); // 固件收包缓冲 10 包，夹到 [1,10]
      final totalPackets = (dataSize + chunk - 1) ~/ chunk;

      // D1：预取阶段按会话分包大小预组好的全部 0x21 帧，分包/帧数对得上才用（会话重建后 MTU 可能变化）；
      // 没有或对不上（调试页直调、首张早于连接预取）则发送时逐包现组——buildImgDataFrame 也走查表，仍很快。
      final List<Uint8List>? prebuilt = (pre != null &&
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
          throw FrameBleException('UPLOAD_ABORTED');
        }
        // 卡住重试时收敛：窗口逐步缩到 1 包、每包间隔逐步拉大，专门救「设备只收按序包、忙时丢包」。
        final curWindow = retries == 0 ? win : (win - retries < 1 ? 1 : win - retries);
        final sendPace = retries == 0
            ? curPace
            : (curPace + 30 * retries > 150 ? 150.0 : curPace + 30 * retries);

        // 填窗：保持在途未确认包 < curWindow，每次 0x23 推进后回到这里补满。
        while (nextSeq < totalPackets && nextSeq - _lastImgAck - 1 < curWindow) {
          if (shouldAbort?.call() ?? false) {
            throw FrameBleException('UPLOAD_ABORTED');
          }
          final seq = nextSeq;
          final frame =
              prebuilt != null ? prebuilt[seq] : FrameProtocol.buildImgDataFrame(data, seq, chunk);
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
        final advanced =
            await _waitAckAdvance(before, const Duration(milliseconds: 600));
        if (!advanced) {
          // 超时回调和通知可能同时发生；重发前再复查一次，已推进就直接继续填窗。
          if (_lastImgAck > before) {
            retries = 0;
            onProgress?.call(_confirmed(totalPackets), totalPackets, 'data');
            continue;
          }
          if (++retries > 15) {
            throw FrameBleException(
                '图传中断：设备停在已接收第 $_lastImgAck 包不再前进。可能设备忙或处理不过来。当前 MTU=$_mtu、每包 $chunk 字节');
          }
          onProgress?.call(_confirmed(totalPackets), totalPackets, 'retry',
              stuckAt: _lastImgAck, retries: retries);
          nextSeq = _lastImgAck + 1;
          curPace = curPace + paceStep > pace ? pace.toDouble() : curPace + paceStep;
          cleanRun = 0;
          final backoff = (50 * retries) > 150 ? 150 : 50 * retries; // 极短退避(≤150ms)
          await Future<void>.delayed(Duration(milliseconds: backoff));
          continue;
        }

        // 干净窗口：连续 paceProbeAfter 个就下探更快一档（AIMD，探到 0）。
        if (retries != 0) {
          cleanRun = 0;
        } else if (curPace > paceFloor && ++cleanRun >= paceProbeAfter) {
          curPace = curPace - paceStep < paceFloor ? paceFloor : curPace - paceStep;
          cleanRun = 0;
        }
        retries = 0;
        onProgress?.call(_confirmed(totalPackets), totalPackets, 'data');
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
