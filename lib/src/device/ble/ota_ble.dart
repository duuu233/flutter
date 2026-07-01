// 设备固件 OTA(DFU) 升级会话层 —— 由微信小程序版 `utils/ota-ble.js` 移植到 Dart，
// 依据《产品需求规格书》6.3.2 / 6.3.3 的自定义 DFU 协议实现（真机三轮联调后的定稿）。
// 与图传(FF00 主服务、0xAA 串行帧、见 device_ble.dart)完全无关：OTA 走独立的 OTA 服务 FF10。
// v1.4 文档定义 FF11 为控制特征、FF12 为数据特征；旧固件若只暴露 FF11，则回退为单特征收发。
//
// 协议要点：
//   1) 校验：每个 APP→设备的包，末尾 1 字节累加校验 = 前面所有字节之和 & 0xFF（不是 CRC16）。
//   2) START(0xF1)：OBJ_TYPE(1) + FW_SIZE(4,小端) + checksum → 设备回 ACK，带 MTU(251) 与 PRN(3)。
//      设备成功应答布局：[0xFC(帧头), 0xF1(回显), RESULT, MTU(1), PRN(1), checksum]。
//   3) DATA (0xF2)：PKT_SEQ(2,小端) + DATA + checksum。每发 PRN 个包等一次设备 DATA ACK，
//      ACK 带「已连续收到的最后包号」。包号没往前走 = 那一包丢了，从 ACK 包号 + 1 重发。
//   4) APP 不发 END：设备自行累计到固件大小后自动算 CRC32、写 BootSetting，回 0xF3 最终结果，
//      约 100ms 后重启跑新固件（此时连接会断开，见 transferData 的「断开即视为已写入重启」）。
//
// 移植要点（对应小程序三处真机修复）：
//   · 设备应答帧头是 0xFC(RSP_OPCODE)，被应答的操作码回显在第 2 字节；据此区分 START/DATA ACK。
//     早期误把 0xFC 当错误码、又把 MTU 当 2 字节小端读，导致合法应答被判无效而 START 超时。
//   · DATA 必须写到「START 成功应答的那条特征」（本机 OTA 全程在 FF11 收发）；写错到 FF12 → 永不回 ACK。
//   · 尾包（不足 PRN 的残包）设备不回 DATA ACK，要收满固件大小后直接回 0xF3；不可当停滞去重发，
//     否则把已收满的设备喂爆 → 设备判错并断开（表现为卡在 ~97% 反复补发后断连）。
//
// iOS 不支持手动请求 MTU / 连接间隔：这里复用图传已协商好的连接（device.mtuNow），不再二次请求。

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:http/http.dart' as http;

import 'frame_protocol.dart';

// ── 协议常量 ──────────────────────────────────────────────
const String _otaServiceUuid = 'FF10';
const String _otaControlUuid = 'FF11';
const String _otaDataUuid = 'FF12';
const String _otaAltControlUuid = 'FF13';

const int _opStart = 0xF1; // APP→设备：开始
const int _opData = 0xF2; // APP→设备：固件数据 / 设备→APP：DATA ACK
const int _opResult = 0xF3; // 设备→APP：最终结果（CRC32 校验 + 写 BootSetting 之后）
const int _opAck = 0xFC; // 设备→APP：START / DATA 应答的帧头(RSP_OPCODE)

// OBJ_TYPE：文档只写「当前作为固件对象使用」，未给确切数值，默认 0x00。
const int _objTypeFirmware = 0x00;
const int _defaultPrn = 3; // 信用窗口：每发这么多包等一次 DATA ACK
const int _defaultDeviceMtu = 251; // 设备声明支持的 MTU；真实可写量以协商结果为准
// 固件大小合法范围(6.3.x)：0x3000 ~ 0x3C000（约 12KB ~ 240KB）。越界只告警不强拦，最终以设备应答为准。
const int _minFwSize = 0x3000;
const int _maxFwSize = 0x3C000;

// OTA 结果码 → 中文（规格书 §6.3.2 OTA 专用码表，与图传 0x7F 通用应答码表不同！）。
const Map<int, String> _otaResultText = {
  0x00: '成功',
  0x01: '校验/芯片信息错误',
  0x02: 'ACK 超时',
  0x03: '主机主动终止',
  0x04: '设备主动终止',
  0x05: '设备状态错误',
  0x06: '不支持的 opcode',
  0x07: '资源不足',
  0x08: '固件大小超限',
  0x09: '参数错误',
};

String otaResultText(int code) {
  final text = _otaResultText[code];
  if (text != null) return text;
  return '设备返回错误码 0x${(code & 0xFF).toRadixString(16).padLeft(2, '0')}';
}

class OtaException implements Exception {
  OtaException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// 用户主动中断（切后台 / 离开页面）。
class OtaAbortedException extends OtaException {
  OtaAbortedException() : super('OTA_ABORTED');
}

// ── 组帧 ──────────────────────────────────────────────────
int _checksum8(List<int> bytes) {
  int sum = 0;
  for (final b in bytes) {
    sum += b & 0xFF;
  }
  return sum & 0xFF;
}

List<int> _withChecksum(List<int> bytes) => [...bytes, _checksum8(bytes)];

List<int> _buildStartFrame(int size, int objType) => _withChecksum([
      _opStart,
      objType & 0xFF,
      size & 0xFF,
      (size >> 8) & 0xFF,
      (size >> 16) & 0xFF,
      (size >> 24) & 0xFF,
    ]);

List<int> _buildDataFrame(int seq, List<int> chunk) =>
    _withChecksum([_opData, seq & 0xFF, (seq >> 8) & 0xFF, ...chunk]);

/// 由 MTU 推算每个 DATA 包能装的固件字节数：
///   单次可写 = MTU - 3(ATT 头)；DATA 帧固定开销 = 4（操作码1 + 包序号2 + 校验1）。上限 244。
int _chunkFromMtu(int mtu) {
  final writable = (mtu <= 0 ? _defaultDeviceMtu : mtu) - 3;
  final chunk = writable - 4;
  if (chunk < 1) return 1;
  return chunk > 244 ? 244 : chunk;
}

/// START 应答解析结果。
class _StartAck {
  _StartAck({required this.result, required this.mtu, required this.prn, required this.rawHex});
  final int result;
  final int mtu;
  final int prn;
  final String rawHex;
}

/// 进度回调载荷（对齐小程序 emit 的字段）。
class OtaProgress {
  const OtaProgress({
    required this.phase,
    required this.percent,
    required this.message,
    this.sent = 0,
    this.total = 0,
    this.stuckAt,
    this.retries,
  });

  /// preparing / prepared / connecting / starting / transferring / retry / verifying / done。
  final String phase;
  final int percent; // 0~100
  final String message;
  final int sent;
  final int total;
  final int? stuckAt;
  final int? retries;
}

/// 升级结果。
class OtaResult {
  const OtaResult({
    required this.size,
    required this.crc32,
    required this.totalPackets,
    required this.chunkSize,
    this.confirmed = false,
    this.rebooted = false,
    this.dryRun = false,
    this.prn = _defaultPrn,
    this.startFrameHex = '',
    this.firstDataFrameHex = '',
  });

  final int size;
  final int crc32;
  final int totalPackets;
  final int chunkSize;

  /// true=收到设备 0xF3 成功码；false=数据发完但设备已断开/重启，未拿到显式成功应答。
  final bool confirmed;
  final bool rebooted;
  final bool dryRun;
  final int prn;
  final String startFrameHex;
  final String firstDataFrameHex;
}

/// 固件包来源（三选一）：内存 bytes / 远程下载地址 / mock 合成。
class OtaFirmwarePackage {
  const OtaFirmwarePackage({
    this.bytes,
    this.packageUrl,
    this.mock = false,
    this.sizeBytes = 0,
    this.checksum,
    this.version,
  });

  final Uint8List? bytes;
  final String? packageUrl;
  final bool mock;
  final int sizeBytes; // 期望大小；>0 时与实际不符会报错
  final String? checksum; // 期望 CRC32（"0x.." 或十进制），本地核对
  final String? version;
}

/// 已就绪的固件数据（读包 + 本地 CRC32 之后）。
class _PreparedFirmware {
  _PreparedFirmware(this.bytes, this.crc32);
  final Uint8List bytes;
  final int crc32;
}

int? _normalizeChecksum(String? checksum) {
  final text = (checksum ?? '').trim();
  if (RegExp(r'^0x[0-9a-fA-F]+$').hasMatch(text)) {
    return int.parse(text.substring(2), radix: 16) & 0xFFFFFFFF;
  }
  if (RegExp(r'^\d+$').hasMatch(text)) {
    return int.parse(text) & 0xFFFFFFFF;
  }
  return null;
}

/// 设备固件 OTA(DFU) 升级客户端。
///
/// 复用图传已建立的物理连接（传入已连接的 [BluetoothDevice]）：OTA 只是在同一连接上
/// 发现 FF10 服务、在 FF11 特征上收发。固件写完设备重启会断开该连接（属正常）。
class FrameOtaClient {
  FrameOtaClient(this.device);

  final BluetoothDevice device;

  BluetoothCharacteristic? _controlChar;
  BluetoothCharacteristic? _dataChar;
  BluetoothCharacteristic? _altControlChar;
  BluetoothCharacteristic? _transferChar; // START 成功应答的那条特征，DATA 沿用它
  final List<StreamSubscription<List<int>>> _notifySubs = [];
  StreamSubscription<BluetoothConnectionState>? _connSub;

  int _mtu = _defaultDeviceMtu;
  int _prn = _defaultPrn;
  int _chunkSize = _chunkFromMtu(_defaultDeviceMtu);
  bool _writeWithoutResponse = true;

  int _lastAckSeq = -1;
  int? _finalResult;
  Completer<_StartAck>? _startCompleter;
  bool _disconnected = false;
  String _abortReason = '';
  bool _connected = false;

  /// 收发监听（联调时打印每帧 16 进制，与硬件日志对照）。
  void Function(String dir, String hex)? onMonitor;

  bool get isConnected => _connected && !_disconnected;

  void _report(String dir, List<int> bytes) {
    final fn = onMonitor;
    if (fn == null) return;
    try {
      fn(dir, FrameProtocol.bytesToHex(bytes));
    } catch (_) {}
  }

  // ── 连接 / 发现 ───────────────────────────────────────────

  /// 发现 FF10/FF11、打开通知、读 MTU。复用已建立的物理连接（图传连接）。
  Future<void> _ensureConnection() async {
    if (_connected) return;

    _disconnected = false;
    _connSub = device.connectionState.listen((state) {
      if (state == BluetoothConnectionState.disconnected) {
        _disconnected = true;
        _abortReason = '设备连接已断开';
        final waiter = _startCompleter;
        if (waiter != null && !waiter.isCompleted) {
          waiter.completeError(OtaException(_abortReason));
        }
      }
    });

    // 已连接设备直接发现服务；连接由图传层(BleController)持有。
    final services = await device.discoverServices();
    BluetoothService? svc;
    for (final s in services) {
      if (_short16(s.uuid.str) == _otaServiceUuid) {
        svc = s;
        break;
      }
    }
    if (svc == null) {
      throw OtaException('未发现设备 OTA 服务(FF10)，请确认设备已连接且支持 OTA');
    }

    for (final c in svc.characteristics) {
      final code = _short16(c.uuid.str);
      if (code == _otaControlUuid) _controlChar = c;
      if (code == _otaDataUuid) _dataChar = c;
      if (code == _otaAltControlUuid) _altControlChar = c;
    }
    final control = _controlChar;
    if (control == null) {
      throw OtaException('未找到 OTA 控制特征(FF11)');
    }
    _dataChar ??= control;
    _writeWithoutResponse =
        control.properties.writeWithoutResponse || !control.properties.write;

    // 打开控制/数据/备用控制特征的通知（应答可能落在其中任一条）。
    for (final c in <BluetoothCharacteristic?>{control, _dataChar, _altControlChar}) {
      if (c == null) continue;
      if (!(c.properties.notify || c.properties.indicate)) continue;
      try {
        await c.setNotifyValue(true);
        _notifySubs.add(c.onValueReceived.listen(_onNotify));
      } catch (_) {}
    }

    // 复用图传已协商好的 MTU（Android 每连接只能 requestMtu 一次，此处不再请求）。
    final mtuNow = device.mtuNow;
    _mtu = mtuNow > 0 ? mtuNow : _defaultDeviceMtu;
    _chunkSize = _chunkFromMtu(_mtu < _defaultDeviceMtu ? _mtu : _defaultDeviceMtu);
    _connected = true;
  }

  Future<void> disconnect() async {
    for (final sub in _notifySubs) {
      await sub.cancel();
    }
    _notifySubs.clear();
    await _connSub?.cancel();
    _connSub = null;
    _connected = false;
  }

  // ── 通知接收 / 解帧派发 ───────────────────────────────────

  void _onNotify(List<int> value) {
    final bytes = value.map((b) => b & 0xFF).toList();
    if (bytes.isEmpty) return;
    _report('RX', bytes);

    // 设备应答帧头 0xFC，被应答的操作码回显在第 2 字节；兼容「不带 0xFC、直接以操作码打头」的旧固件。
    final echo = bytes[0] == _opAck ? (bytes.length > 1 ? bytes[1] : 0) : bytes[0];

    // START ACK：回显 0xF1；或正等 START 应答且不是 DATA/最终结果。
    final waiter = _startCompleter;
    if (echo == _opStart ||
        (waiter != null && echo != _opData && echo != _opResult)) {
      final ack = _parseStartAck(bytes);
      if (ack == null) {
        debugPrint('[OTA] 忽略无法识别的应答帧：${FrameProtocol.bytesToHex(bytes)}');
        return;
      }
      if (waiter != null && !waiter.isCompleted) {
        _startCompleter = null;
        waiter.complete(ack);
      }
      return;
    }

    // 最终结果 0xF3（设备收齐后自算 CRC32 主动上报）。
    if (echo == _opResult) {
      _finalResult = _parseResult(bytes);
      return;
    }

    // DATA ACK：回显 0xF2，取「已连续接收的最后包号」。
    if (echo == _opData) {
      final seq = _parseDataAckSeq(bytes);
      if (seq > _lastAckSeq) _lastAckSeq = seq;
    }
  }

  // START ACK 权威布局：[0xFC, 0xF1, RESULT, MTU(1,=251), PRN(1), checksum]。
  // 兼容「不带 0xFC 帧头、直接回显 0xF1」的旧固件。MTU/PRN 越界则回落 0，由 applyStartAck 用默认值兜底。
  _StartAck? _parseStartAck(List<int> bytes) {
    final valid = bytes[0] == _opAck || bytes[0] == _opStart;
    if (!valid) return null;
    int i = 0;
    if (bytes[i] == _opAck) i += 1; // 跳过应答帧头 0xFC
    if (i < bytes.length && bytes[i] == _opStart) i += 1; // 跳过回显的 START 0xF1
    final result = bytes.length > i ? bytes[i] & 0xFF : 0xFF;
    int mtu = bytes.length > i + 1 ? bytes[i + 1] & 0xFF : 0;
    int prn = bytes.length > i + 2 ? bytes[i + 2] & 0xFF : 0;
    if (!(mtu >= 23 && mtu <= 517)) mtu = 0;
    if (!(prn >= 1 && prn <= 64)) prn = 0;
    return _StartAck(result: result, mtu: mtu, prn: prn, rawHex: FrameProtocol.bytesToHex(bytes));
  }

  // DATA ACK 权威布局：[0xFC, 0xF2, RESULT, SEQ(2,小端), checksum]，SEQ 在偏移 3；
  // 兼容旧固件 [0xF2, SEQ(2,小端), checksum]（偏移 1）。
  int _parseDataAckSeq(List<int> bytes) {
    final offset = bytes[0] == _opAck ? 3 : 1;
    if (bytes.length < offset + 2) return _lastAckSeq;
    return FrameProtocol.readUint16LE(bytes, offset);
  }

  // 0xF3 最终结果：[0xF3, RESULT, ..] 或带 0xFC 帧头 [0xFC, 0xF3, RESULT, ..]。
  // ⚠️ 时序图疑似在 0xF3 后另有 1 字节子操作码再到 RESULT——真机抓一帧确认后再调整偏移。
  int _parseResult(List<int> bytes) {
    final offset = bytes[0] == _opAck ? 2 : 1;
    return bytes.length > offset ? bytes[offset] & 0xFF : 0xFF;
  }

  // ── 裸写一帧（带「发送缓冲忙就退避重试」）────────────────────
  Future<void> _writeFrame(List<int> bytes, BluetoothCharacteristic chr) async {
    int attempt = 0;
    while (true) {
      try {
        _report('TX', bytes);
        await chr.write(bytes, withoutResponse: _writeWithoutResponse);
        return;
      } catch (e) {
        if (++attempt > 4) rethrow;
        await Future<void>.delayed(const Duration(milliseconds: 80));
      }
    }
  }

  // ── START 握手 ────────────────────────────────────────────
  Future<void> _doStart(int size, {int? objType, Duration? startTimeout}) async {
    // 依次尝试：控制特征 FF11 →（若独立）数据特征 FF12 →（若独立）备用控制 FF13；每条按其写类型。
    final targets = <BluetoothCharacteristic>[];
    void addTarget(BluetoothCharacteristic? c) {
      if (c == null) return;
      if (!(c.properties.write || c.properties.writeWithoutResponse)) return;
      if (targets.any((t) => t.uuid == c.uuid)) return;
      targets.add(c);
    }

    addTarget(_controlChar);
    addTarget(_dataChar);
    addTarget(_altControlChar);
    if (targets.isEmpty) {
      throw OtaException('OTA 特征不支持写入：FF11/FF12/FF13 均未声明 write / writeNoResponse');
    }

    final objTypes = objType != null ? [objType] : const [_objTypeFirmware, 0x01];
    final timeout = startTimeout ??
        (targets.length > 1 || objTypes.length > 1
            ? const Duration(milliseconds: 2500)
            : const Duration(milliseconds: 5000));

    OtaException? lastError;
    for (final target in targets) {
      for (final ot in objTypes) {
        final frame = _buildStartFrame(size, ot);
        // 每次尝试新建一个应答等待者：先写 START 帧，成功后再对「应答 future」套超时，
        // 避免写失败时超时 future 变成悬空的未处理异常（对齐小程序 createStartAckWaiter/cancel）。
        final completer = Completer<_StartAck>();
        _startCompleter = completer;
        try {
          await _writeFrame(frame, target);
          final ack = await completer.future.timeout(
            timeout,
            onTimeout: () => throw OtaException(
              'OTA START 应答超时（control=${_short16(_controlChar!.uuid.str)}, '
              'data=${_dataChar == null ? "-" : _short16(_dataChar!.uuid.str)}, mtu=$_mtu）',
            ),
          );
          _applyStartAck(ack);
          // 设备在哪条特征上应答了 START，后续 DATA 就走同一条（本机 OTA 全程 FF11）。
          _transferChar = target;
          if (_startCompleter == completer) _startCompleter = null;
          return;
        } on OtaException catch (e) {
          lastError = e;
          if (_disconnected) throw OtaException(_abortReason);
        } catch (e) {
          lastError = OtaException(e.toString());
          if (_disconnected) throw OtaException(_abortReason);
        } finally {
          if (_startCompleter == completer) _startCompleter = null;
        }
      }
    }
    throw lastError ?? OtaException('OTA START 写入失败：所有可写特征/写入类型均失败');
  }

  void _applyStartAck(_StartAck ack) {
    if (ack.result != 0x00) {
      throw OtaException('OTA 启动被拒绝：${otaResultText(ack.result)}（ACK=${ack.rawHex}）');
    }
    if (ack.prn > 0) _prn = ack.prn;
    final effectiveMtu = _mtu < (ack.mtu > 0 ? ack.mtu : _defaultDeviceMtu)
        ? _mtu
        : (ack.mtu > 0 ? ack.mtu : _defaultDeviceMtu);
    _chunkSize = _chunkFromMtu(effectiveMtu);
  }

  // ── 窗口化数据传输 ─────────────────────────────────────────
  // 每发 PRN 个包等一次 DATA ACK；ACK 不前进就从 ACK 包号+1 重发。卡顿时缩窗+减速破死结。
  // 「等待+退避」必须远小于 1s：固件超过 1 秒没收到下一包即判定传输中断（图传红线，OTA 同样适用）。
  Future<OtaResult> _transferData(
    Uint8List bytes,
    int crc32, {
    int pace = 20,
    void Function(OtaProgress)? onProgress,
    bool Function()? shouldAbort,
    Duration finalTimeout = const Duration(seconds: 10),
  }) async {
    final total = bytes.length;
    final chunkSize = _chunkSize;
    final totalPackets = (total + chunkSize - 1) ~/ chunkSize;
    final prn = _prn <= 0 ? _defaultPrn : _prn;
    final transferChar = _transferChar ?? _controlChar!;

    _lastAckSeq = -1;
    _finalResult = null;

    int nextSeq = 0;
    int retries = 0;

    onProgress?.call(OtaProgress(
      phase: 'transferring',
      percent: 15,
      sent: 0,
      total: total,
      message: '开始传输，共 $totalPackets 包，每包 $chunkSize 字节，窗口 PRN=$prn',
    ));

    while (nextSeq < totalPackets && _finalResult == null) {
      if (shouldAbort?.call() ?? false) throw OtaAbortedException();
      if (_disconnected) throw OtaException(_abortReason);

      // 卡住后逐步收敛：每多重试一次窗口缩一包、每包间隔拉大一截。
      final burst = retries == 0 ? prn : (prn - retries < 1 ? 1 : prn - retries);
      final sendPace = retries == 0 ? pace : (pace + 30 * retries > 150 ? 150 : pace + 30 * retries);
      final windowEnd = nextSeq + burst > totalPackets ? totalPackets : nextSeq + burst;

      for (int seq = nextSeq; seq < windowEnd && _finalResult == null; seq++) {
        final start = seq * chunkSize;
        final end = start + chunkSize > total ? total : start + chunkSize;
        await _writeFrame(_buildDataFrame(seq, bytes.sublist(start, end)), transferChar);
        if (sendPace > 0) {
          await Future<void>.delayed(Duration(milliseconds: sendPace));
        }
      }

      if (_finalResult != null) break; // 设备已收齐并给出最终结果

      // 尾窗特判：最后一包（不足 PRN 的残包）设备不回 DATA ACK——要收满固件大小后才直接回 0xF3。
      // 一旦把最后一包发出，就跳出发送循环去等 0xF3 / 设备重启，绝不重发尾包（否则喂爆设备致断开）。
      if (windowEnd >= totalPackets) break;

      final advanced = await _waitAckAdvance(nextSeq - 1, const Duration(milliseconds: 600));
      if (!advanced) {
        if (_disconnected) throw OtaException(_abortReason);
        if (_finalResult != null) break;
        if (++retries > 15) {
          throw OtaException(
            'OTA 中断：设备停在已接收第 $_lastAckSeq 包不再前进（共 $totalPackets 包）。'
            '可能设备忙或处理不过来。当前 MTU=$_mtu、每包 $chunkSize 字节',
          );
        }
        onProgress?.call(OtaProgress(
          phase: 'retry',
          percent: _progressPercent(nextSeq * chunkSize > total ? total : nextSeq * chunkSize, total),
          sent: nextSeq * chunkSize > total ? total : nextSeq * chunkSize,
          total: total,
          stuckAt: _lastAckSeq,
          retries: retries,
          message: '补发数据（设备停在第 $_lastAckSeq 包，第 $retries 次重试）',
        ));
        final backoff = 50 * retries > 150 ? 150 : 50 * retries; // 极短退避
        await Future<void>.delayed(Duration(milliseconds: backoff));
        nextSeq = _lastAckSeq + 1;
        continue;
      }

      nextSeq = _lastAckSeq + 1;
      retries = 0;
      final sent = nextSeq * chunkSize > total ? total : nextSeq * chunkSize;
      onProgress?.call(OtaProgress(
        phase: 'transferring',
        percent: _progressPercent(sent, total),
        sent: sent,
        total: total,
        message: '传输中：$sent/$total 字节',
      ));
    }

    // 数据已全部送达：APP 不发 END，等设备自行算 CRC32 + 写 BootSetting 后回 0xF3。
    onProgress?.call(OtaProgress(
      phase: 'verifying',
      percent: 99,
      sent: total,
      total: total,
      message: '写入完成，等待设备校验',
    ));

    final finalCode = await _waitFinalResult(finalTimeout);
    if (finalCode == null) {
      // 数据 100% 发完后设备断开：DFU 固件收满、写好 BootSetting 后通常立即重启，表现为断连，
      // 可能来不及/丢失 0xF3。视为「已发送完毕、设备重启中」，但不谎报确认成功——请到设备端核对版本。
      if (_disconnected) {
        onProgress?.call(OtaProgress(
          phase: 'done',
          percent: 100,
          sent: total,
          total: total,
          message: '数据已全部发送，设备已断开——通常表示已写入并重启进入新固件。请在设备端确认固件版本是否已更新。',
        ));
        return OtaResult(
          size: total,
          crc32: crc32,
          totalPackets: totalPackets,
          chunkSize: chunkSize,
          prn: prn,
          rebooted: true,
        );
      }
      throw OtaException('OTA 等待设备校验结果超时');
    }

    if (finalCode != 0x00) {
      throw OtaException('设备校验失败：${otaResultText(finalCode)}');
    }

    onProgress?.call(OtaProgress(
      phase: 'done',
      percent: 100,
      sent: total,
      total: total,
      message: '升级完成，设备即将重启',
    ));
    return OtaResult(
      size: total,
      crc32: crc32,
      totalPackets: totalPackets,
      chunkSize: chunkSize,
      prn: prn,
      confirmed: true,
    );
  }

  /// 轮询等待「已连续接收包号」越过 minExclusive，或收到最终结果/断开；超时返回 false。
  Future<bool> _waitAckAdvance(int minExclusive, Duration timeout) async {
    final deadline = DateTime.now().add(timeout);
    while (_lastAckSeq <= minExclusive) {
      if (_finalResult != null || _disconnected) return true;
      if (DateTime.now().isAfter(deadline)) return false;
      await Future<void>.delayed(const Duration(milliseconds: 15));
    }
    return true;
  }

  /// 轮询等待设备 0xF3 最终结果（算 CRC32 + 写 BootSetting 可能要几秒）；断开/超时返回 null。
  Future<int?> _waitFinalResult(Duration timeout) async {
    final deadline = DateTime.now().add(timeout);
    while (_finalResult == null) {
      if (_disconnected) return null;
      if (DateTime.now().isAfter(deadline)) return null;
      await Future<void>.delayed(const Duration(milliseconds: 30));
    }
    return _finalResult;
  }

  int _progressPercent(int sent, int total) {
    if (total == 0) return 98;
    final p = 15 + (sent / total * 83).floor();
    return p > 98 ? 98 : p;
  }

  // ── 固件包加载 / 准备 ──────────────────────────────────────
  static Future<Uint8List> _downloadFirmware(String url) async {
    final resp = await http.get(Uri.parse(url));
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw OtaException('固件包下载失败(${resp.statusCode})');
    }
    return resp.bodyBytes;
  }

  static Uint8List _mockFirmwareBuffer(int size, String? version) {
    final total = size < _minFwSize ? 65536 : size;
    final seed = (version == null || version.isEmpty) ? 'mock' : version;
    final bytes = Uint8List(total);
    for (int i = 0; i < total; i++) {
      bytes[i] = (i * 31 + seed.codeUnitAt(i % seed.length)) & 0xFF;
    }
    return bytes;
  }

  static Future<Uint8List> _loadFirmwareBuffer(OtaFirmwarePackage pkg) async {
    if (pkg.bytes != null) return pkg.bytes!;
    if (pkg.packageUrl != null && pkg.packageUrl!.isNotEmpty) {
      return _downloadFirmware(pkg.packageUrl!);
    }
    if (pkg.mock) return _mockFirmwareBuffer(pkg.sizeBytes, pkg.version);
    throw OtaException('缺少固件包来源（bytes / packageUrl / mock）');
  }

  static Future<_PreparedFirmware> _prepareFirmware(
    OtaFirmwarePackage pkg, {
    void Function(OtaProgress)? onProgress,
  }) async {
    onProgress?.call(const OtaProgress(phase: 'preparing', percent: 5, message: '准备固件包'));
    final bytes = await _loadFirmwareBuffer(pkg);
    final size = bytes.length;
    if (size == 0) throw OtaException('固件包为空');
    if (pkg.sizeBytes > 0 && size != pkg.sizeBytes) {
      throw OtaException('固件包大小不一致：期望 ${pkg.sizeBytes} 字节，实际 $size 字节');
    }
    if (size < _minFwSize || size > _maxFwSize) {
      debugPrint('[OTA] 固件大小 $size 字节超出建议范围 '
          '0x${_minFwSize.toRadixString(16)}~0x${_maxFwSize.toRadixString(16)}');
    }
    // CRC32 仅用于本地完整性核对/展示；START 不携带 CRC32，校验由设备自行完成（协议要求）。
    final crc32 = FrameProtocol.crc32Mpeg2(bytes);
    final expectedCrc = _normalizeChecksum(pkg.checksum);
    if (expectedCrc != null && expectedCrc != crc32) {
      throw OtaException('固件包本地 CRC32 校验失败');
    }
    onProgress?.call(OtaProgress(
      phase: 'prepared',
      percent: 10,
      message: '固件包已就绪',
      total: size,
    ));
    return _PreparedFirmware(bytes, crc32);
  }

  // ── 干跑（无 BLE）：校验「读包 + 组帧 + 校验 + 分包」，真机才跑真实传输。──
  static Future<OtaResult> _dryRun(
    _PreparedFirmware prepared, {
    void Function(OtaProgress)? onProgress,
    bool Function()? shouldAbort,
  }) async {
    final bytes = prepared.bytes;
    final total = bytes.length;
    final chunkSize = _chunkFromMtu(_defaultDeviceMtu); // 244：按满 MTU 估算
    final totalPackets = (total + chunkSize - 1) ~/ chunkSize;
    const prn = _defaultPrn;

    final startFrame = _buildStartFrame(total, _objTypeFirmware);
    final firstChunkEnd = chunkSize < total ? chunkSize : total;
    final firstDataFrame = _buildDataFrame(0, bytes.sublist(0, firstChunkEnd));

    for (int seq = 0; seq < totalPackets; seq++) {
      if (shouldAbort?.call() ?? false) throw OtaAbortedException();
      final start = seq * chunkSize;
      final end = start + chunkSize > total ? total : start + chunkSize;
      final frame = _buildDataFrame(seq, bytes.sublist(start, end));
      if (_checksum8(frame.sublist(0, frame.length - 1)) != frame[frame.length - 1]) {
        throw OtaException('第 $seq 包校验位自检失败');
      }
      final sent = end;
      if (seq % prn == 0 || seq == totalPackets - 1) {
        onProgress?.call(OtaProgress(
          phase: 'transferring',
          percent: total == 0 ? 98 : (15 + (sent / total * 83).floor()).clamp(15, 98).toInt(),
          sent: sent,
          total: total,
          message: '干跑：$sent/$total 字节（${seq + 1}/$totalPackets 包）',
        ));
        await Future<void>.delayed(const Duration(milliseconds: 8));
      }
    }

    onProgress?.call(OtaProgress(
      phase: 'done',
      percent: 100,
      sent: total,
      total: total,
      message: '干跑完成（未经过真实蓝牙）',
    ));

    return OtaResult(
      size: total,
      crc32: prepared.crc32,
      totalPackets: totalPackets,
      chunkSize: chunkSize,
      prn: prn,
      dryRun: true,
      startFrameHex: FrameProtocol.bytesToHex(startFrame),
      firstDataFrameHex: FrameProtocol.bytesToHex(firstDataFrame),
    );
  }

  // ── 对外主流程 ────────────────────────────────────────────
  /// 干跑：纯本地校验「读包 + 组帧 + 校验 + 分包」，不连蓝牙、无需设备实例。
  /// 开发者工具 / 无硬件 / 无真实固件时用来验证编码链路。
  static Future<OtaResult> dryRunUpgrade(
    OtaFirmwarePackage pkg, {
    void Function(OtaProgress)? onProgress,
    bool Function()? shouldAbort,
  }) async {
    final prepared = await _prepareFirmware(pkg, onProgress: onProgress);
    return _dryRun(prepared, onProgress: onProgress, shouldAbort: shouldAbort);
  }

  /// 升级设备固件。
  ///
  /// [dryRun]=true 时纯本地校验编码与分包，不连蓝牙（无硬件/无固件时用）。
  Future<OtaResult> upgradeFirmware(
    OtaFirmwarePackage pkg, {
    void Function(OtaProgress)? onProgress,
    bool Function()? shouldAbort,
    bool dryRun = false,
    int pace = 20,
    int? objType,
    Duration finalTimeout = const Duration(seconds: 10),
  }) async {
    final prepared = await _prepareFirmware(pkg, onProgress: onProgress);

    if (dryRun) {
      return _dryRun(prepared, onProgress: onProgress, shouldAbort: shouldAbort);
    }

    onProgress?.call(const OtaProgress(phase: 'connecting', percent: 12, message: '连接 OTA 服务(FF10)'));
    await _ensureConnection();

    onProgress?.call(OtaProgress(phase: 'starting', percent: 14, message: '握手中（MTU $_mtu）'));
    await _doStart(prepared.bytes.length, objType: objType);

    return _transferData(
      prepared.bytes,
      prepared.crc32,
      pace: pace,
      onProgress: onProgress,
      shouldAbort: shouldAbort,
      finalTimeout: finalTimeout,
    );
  }

  // 取 128 位/16 位 UUID 的 16 位短码（如 0000FF10-... → FF10）。
  static String _short16(String uuid) {
    final s = uuid.replaceAll('-', '').toUpperCase();
    if (s.length <= 4) return s.padLeft(4, '0');
    if (s.length >= 8) return s.substring(4, 8);
    return s.substring(s.length - 4);
  }
}
