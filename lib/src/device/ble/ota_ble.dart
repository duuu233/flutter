// 设备固件 OTA(DFU) 升级会话层 —— 由微信小程序版 `utils/ota-ble.js` 移植到 Dart，
// 依据《电子相框产品需求规格书 v1.5》§6.3 的自定义 DFU 协议实现。
// 与图传(FF00 主服务、0xAA 串行帧、见 device_ble.dart)完全无关：OTA 走独立的 OTA 服务 FF10，
// 且 §6.3.3 明确「OTA 通道不使用 6.4 的 0xAA 应用层帧格式」——旧版借用图传的 PKT_SEQ
// 累计确认(ACK_SEQ)已作废，见下。
//
// ★ v1.5 关键变动（按新文档重写，与小程序 2026-07-06 版对齐）：手机端只负责「按文件内容读取并
//   发送」升级包，一切校验数据(128 字节头信息里的 OTAINFO / 头部版本 / 面板类型 / CRC16 / 版本号 /
//   原始 bin CRC32)都由固件方预先打进升级包文件、并由设备端校验；手机不再自行计算 CRC32、也不
//   组装任何头部。升级包文件结构固定为 [128 字节头信息][原始 bin payload]。
//
// 协议流程(§6.3.4 时序图)：
//   1) 校验位：每个 APP→设备的 OTA 请求末尾 1 字节累加 checksum = 前面所有字节之和 & 0xFF（不是 CRC16）。
//   2) START(0xF1)：OBJ_TYPE(1) + FW_SIZE(4,小端) + checksum → 设备初始化写入区，回 ACK[0xFC,0xF1,
//      RESULT,MTU(=251),PRN(=3),checksum]。RESULT!=0 立即停止并按结果码提示。
//   3) 头信息握手：第一个 DATA(0xF2) 承载升级包文件最前面的 128 字节头信息（首包长度 128，设备据此
//      识别为头信息）→ 设备校验 OTAINFO/头部版本/面板/CRC16/版本号 → 回 ACK[0xFC,0xF2,RESULT]。
//      RESULT!=0 停止。
//   4) 数据传输：后续 DATA(0xF2) 承载从升级包第 129 字节起的原始 bin payload 分片；PRN 信用窗口——
//      每发 PRN 个 DATA 包等一次设备 ACK[0xFC,0xF2,RESULT]。新协议的 DATA ACK 只回结果码(不再回
//      「已连续接收包号」)，故不做「按包号重发」；某一批超时/回错 = 传输中断，整轮升级判失败由用户
//      重试(设备侧会等 APP 重新发起)。
//   5) END(0xF3)：payload 发完后 APP 主动发结束包 [0xF3,checksum]，设备校验 total_bytes==bin_size 且
//      CRC32(payload)==bin_crc32 → 回 ACK[0xFC,0xF3,RESULT]。RESULT==0 即升级成功，设备约 100ms 后
//      复位运行新固件。
//
// 待与固件最终对齐的点（真机抓包后核对，与小程序侧 OTA_TODO 一致）：
//   a) START 帧 OBJ_TYPE 的确切取值（此处默认 0x00，握手时兜底再试 0x01）；
//   b) START 帧 FW_SIZE 语义——本实现取「原始 bin payload 大小 = 文件大小 - 128」（与头信息里的
//      bin_size 对齐、也是设备 APP2 写入区大小）；若固件期望为「整包文件大小(含 128 头)」，改
//      _computeFwSize 一处即可。
//
// iOS 不支持手动请求 MTU / 连接间隔：这里复用图传已协商好的连接（device.mtuNow），不再二次请求。

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../../network/api_client.dart';
import 'frame_protocol.dart';

// ── 协议常量 ──────────────────────────────────────────────
const String _otaServiceUuid = 'FF10';
const String _otaControlUuid = 'FF11';
const String _otaDataUuid = 'FF12';
const String _otaAltControlUuid = 'FF13';

const int _opStart = 0xF1; // APP→设备：开始（携带 OBJ_TYPE + FW_SIZE）
const int _opData = 0xF2; // APP→设备：128 字节头信息握手包 / 后续 bin payload 分片
const int _opEnd = 0xF3; // APP→设备：结束包（v1.5 新增，由 APP 主动发送）→ 设备整包校验后回 ACK
const int _opAck = 0xFC; // 设备→APP：START / DATA / END 应答的帧头(RSP_OPCODE)

/// OTA 操作码（对齐小程序 `otaBle.OP` 导出，供页面做帧级日志过滤）。
abstract final class OtaOp {
  static const int start = _opStart;
  static const int data = _opData;
  static const int end = _opEnd;

  /// 兼容旧引用：0xF3 现为 APP→设备 END 操作码，设备的最终结果以 END 的 ACK 形式返回。
  static const int result = _opEnd;
  static const int ack = _opAck;
}

/// 升级包文件最前面的头信息长度（§6.3.4）：第一个 DATA 包固定承载这 128 字节，设备据首包长度识别为头信息。
const int otaHeaderSize = 128;

// START 帧的对象类型。文档只写「当前作为固件对象使用」，未给确切数值，默认 0x00。
const int _objTypeFirmware = 0x00;
const int _defaultPrn = 3; // 信用窗口：每发这么多包等一次 DATA ACK（START ACK 里固件回 3）
const int _defaultDeviceMtu = 251; // 设备声明支持的 MTU；真实可写量以协商结果为准
// bin payload 合法范围：**照规格书原文取 0x3000 ~ 0x3C000**（§6.3.3 START 请求表）。
// 端上曾自作主张把下限"更正"成 0x30000（192KB），而现场固件 bin payload 约 164KB——落在原文
// 范围内却被判成"超出建议范围"，每次升级白打一条误导告警。越界一律只告警不拦，
// 真超限由设备回 0x08。（2026-08-11 双端同改）
const int _minFwSize = 0x3000;
const int _maxFwSize = 0x3C000;

/// 头信息里的「固件类型」(偏移 9)：1 = 3D7 面板(3.7 寸 480×720)，2 = 5D89 面板(5.89 寸 680×960)。
/// 与 SCREEN_TYPE 的 0x01/0x02 一一对应，供本地按设备尺寸预检面板是否刷对。
const Map<int, ({String name, String label, int width, int height})> otaPanels = {
  1: (name: '3D7', label: '3.7寸', width: 480, height: 720),
  2: (name: '5D89', label: '5.89寸', width: 680, height: 960),
};

// OTA 结果码 → 中文（规格书 v1.5 §6.3.2 OTA 专用码表，与图传 0x7F 通用应答码表不同！）。
// 0x0A~0x0E 为 v1.5 新增的头信息握手校验码（§6.3.4「6. 结果码」表）。未知码回落十六进制原文。
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
  0x0A: '协议匹配字段不匹配（非 OTA 包或文件损坏）',
  0x0B: '头部版本不兼容（工具链需升级）',
  0x0C: '固件类型与面板不匹配',
  0x0D: '头部 CRC16 校验失败（传输丢包或文件截断）',
  0x0E: '版本号校验失败（格式/产品/面板不一致）',
};

String otaResultText(int code) {
  final text = _otaResultText[code];
  if (text != null) return text;
  return '设备返回错误码 0x${(code & 0xFF).toRadixString(16).padLeft(2, '0')}';
}

/// 升级包最前面 128 字节头信息的解析结果（§6.3.4 字段表）。
typedef OtaPackageHeader = ({
  bool magicOk,
  int headerVersion,
  int panel,
  int headerLength,
  int binSize,
  int binCrc32,
  int versionLength,
  int headerCrc16,
  String version,
});

int _u16le(List<int> b, int i) => (b[i] & 0xFF) | ((b[i + 1] & 0xFF) << 8);
int _u32le(List<int> b, int i) =>
    (b[i] & 0xFF) |
    ((b[i + 1] & 0xFF) << 8) |
    ((b[i + 2] & 0xFF) << 16) |
    ((b[i + 3] & 0xFF) << 24);

/// 解析升级包最前面的 128 字节头信息。**只读不改**：这 128 字节由固件方预先打好，
/// APP 原样发送、不改写任何字段；这里解析只为「发之前先看一眼包对不对」和日志排查。
OtaPackageHeader inspectOtaHeader(List<int> bytes) {
  final head = bytes.sublist(0, otaHeaderSize);
  final magic = String.fromCharCodes(head.take(7));
  final versionLength = _u16le(head, 20) > 104 ? 104 : _u16le(head, 20);
  final buf = StringBuffer();
  for (int i = 0; i < versionLength; i++) {
    final code = head[24 + i];
    if (code == 0) break;
    buf.writeCharCode(code);
  }
  return (
    magicOk: magic == 'OTAINFO' && head[7] == 0x00,
    headerVersion: head[8],
    panel: head[9],
    headerLength: _u16le(head, 10),
    binSize: _u32le(head, 12),
    binCrc32: _u32le(head, 16),
    versionLength: versionLength,
    headerCrc16: _u16le(head, 22),
    version: buf.toString(),
  );
}

String _panelText(int panel) {
  final spec = otaPanels[panel];
  return spec == null ? '未知面板类型 $panel' : '${spec.name}（${spec.label}）';
}

/// 设备的屏幕类型码/分辨率 → 头信息里的固件类型；判不出返回 0（不参与拦截）。
/// screenType 与面板号同源（0x01 3.7寸=3D7、0x02 5.89寸=5D89）。
int otaPanelOfDevice({int screenCode = 0, int width = 0, int height = 0}) {
  if (otaPanels.containsKey(screenCode)) return screenCode;
  for (final entry in otaPanels.entries) {
    final spec = entry.value;
    if ((width == spec.width && height == spec.height) ||
        (width == spec.height && height == spec.width)) {
      return entry.key;
    }
  }
  return 0;
}

String _hexByte(int b) =>
    (b & 0xFF).toRadixString(16).padLeft(2, '0').toUpperCase();

/// 把一帧 OTA 收发数据解析成可读中文（配合原始 16 进制一起打印，方便与硬件日志逐帧比对）。
/// [dir] 为 'TX'（APP→设备）或 'RX'（设备→APP）。移植自小程序 detail.js `describeOtaFrame`（v1.5 语义）。
String describeOtaFrame(String dir, List<int> bytes) {
  if (bytes.isEmpty) return '空帧';

  if (dir == 'TX') {
    if (bytes[0] == _opStart) return 'START(0xF1) 开始帧';
    if (bytes[0] == _opData) {
      // v1.5 DATA 帧无包序号：[0xF2, ...数据..., checksum]。数据长 128 即头信息握手包。
      final dataLen = bytes.length - 2;
      return dataLen == otaHeaderSize
          ? 'DATA(0xF2) 128 字节头信息握手包'
          : 'DATA(0xF2) payload 分片 $dataLen 字节';
    }
    if (bytes[0] == _opEnd) return 'END(0xF3) 结束帧';
    return '发送 opcode=0x${_hexByte(bytes[0])}';
  }

  // 设备应答帧头为 0xFC(RSP_OPCODE)，第 2 字节回显被应答的操作码；兼容「不带 0xFC、直接以操作码打头」的旧固件。
  final hasHeader = bytes[0] == _opAck;
  final echo = hasHeader ? (bytes.length > 1 ? bytes[1] : 0) : bytes[0];
  int at(int i) => i < bytes.length ? bytes[i] & 0xFF : 0;

  if (echo == _opStart) {
    final i = hasHeader ? 2 : 1;
    return 'START 应答 回显0xF1 RESULT=0x${_hexByte(at(i))}(${otaResultText(at(i))}) '
        'MTU=${at(i + 1)} PRN=${at(i + 2)}';
  }
  if (echo == _opData) {
    final i = hasHeader ? 2 : 1;
    return 'DATA 应答 回显0xF2 RESULT=0x${_hexByte(at(i))}(${otaResultText(at(i))})';
  }
  if (echo == _opEnd) {
    final i = hasHeader ? 2 : 1;
    return 'END 应答(整包校验结果) 回显0xF3 RESULT=0x${_hexByte(at(i))}(${otaResultText(at(i))})';
  }
  return '未识别应答';
}

/// END(0xF3) 应答帧的调试解读：v1.5 §6.3.4 权威布局 [0xFC,0xF3,RESULT,checksum]（解读A）；
/// 保留解读B（0xF3 后夹 1 字节子操作码再到 RESULT）供真机抓帧核对。哪个是 0x00 成功，真实语义就是哪个。
String decodeFinalResultFrame(List<int> bytes) {
  final hasHeader = bytes.isNotEmpty && bytes[0] == _opAck;
  final base = hasHeader ? 2 : 1; // 跳过可选的 0xFC 帧头 + 回显的 0xF3
  String fmt(int i) => i >= bytes.length
      ? '(无此字节)'
      : '0x${_hexByte(bytes[i])}(${otaResultText(bytes[i])})';
  final hex = bytes.map(_hexByte).join(' ');
  return '0xF3 原始帧=$hex ｜ 解读A(F3+RESULT,现用)=${fmt(base)} ｜ 解读B(F3+子码+RESULT)=${fmt(base + 1)}';
}

/// OTA 失败原因分类。用来区分「设备侧状态没复位、复位后还能救」与「包不对/彻底失败」。
enum OtaFailureKind {
  /// 普通失败（超时、断链、包不对……）：不自动重来。
  plain,

  /// START 被回 0x05：上一轮 DFU 半途中断，设备状态机还停在升级态。
  startRejectedBusy,

  /// 头信息握手过不去（无应答，或一直被回 0x05）：START 正常但设备收不下这 128 字节。
  headerStuck,
}

class OtaException implements Exception {
  OtaException(this.message, {this.kind = OtaFailureKind.plain});
  final String message;

  /// 见 [OtaFailureKind]。`startRejectedBusy` / `headerStuck` 这两类的共同点是
  /// **设备一个 payload 字节都还没收下**，所以断链复位后整轮从 START 重来是安全的。
  final OtaFailureKind kind;

  bool get isWedgedSession =>
      kind == OtaFailureKind.startRejectedBusy ||
      kind == OtaFailureKind.headerStuck;

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

/// DATA(0xF2) 帧（v1.5）：[0xF2, ...数据..., checksum]。不再有 2 字节包序号。
/// 数据可能是 128 字节头信息（首包），也可能是 bin payload 分片。
List<int> _buildDataFrame(List<int> chunk) =>
    _withChecksum([_opData, ...chunk]);

/// END(0xF3) 结束帧（v1.5 新增）：[0xF3, checksum]。设备收到后做整包校验并回 ACK。
List<int> _buildEndFrame() => _withChecksum([_opEnd]);

/// START 帧 FW_SIZE：取 bin payload 大小 = 文件总大小 - 128 字节头（见文件头「待对齐点 b」）。
int _computeFwSize(int fileSize) =>
    fileSize > otaHeaderSize ? fileSize - otaHeaderSize : 0;

/// 由 MTU 推算每个 DATA 包能装的固件字节数：
///   单次可写 = MTU - 3(ATT 头)；DATA 帧固定开销 = 2（操作码1 + 校验1，v1.5 不再有 2 字节包序号）。
///   上限 244（MTU=251 时 248-2=246，为安全留一点余量取 244）。
int _chunkFromMtu(int mtu) {
  final writable = (mtu <= 0 ? _defaultDeviceMtu : mtu) - 3;
  final chunk = writable - 2;
  if (chunk < 1) return 1;
  return chunk > 244 ? 244 : chunk;
}

/// START 应答解析结果。
class _StartAck {
  _StartAck({
    required this.result,
    required this.mtu,
    required this.prn,
    required this.rawHex,
  });
  final int result;
  final int mtu;
  final int prn;
  final String rawHex;
}

/// DATA / END 的结果码应答（v1.5 只回 RESULT，不带包号）。
class _AckResult {
  _AckResult({
    required this.opcode,
    required this.result,
    required this.rawHex,
  });
  final int opcode;
  final int result;
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

  /// preparing / prepared / connecting / starting / header / transferring / verifying / done。
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
    this.payloadSize = 0,
    this.confirmed = false,
    this.prn = _defaultPrn,
    this.startFrameHex = '',
    this.headerFrameHex = '',
    this.firstDataFrameHex = '',
    this.endFrameHex = '',
  });

  final int size; // 升级包文件总大小（含 128 字节头）
  final int crc32; // 本地对整包算的 CRC32，仅展示/日志用（校验由设备完成）
  final int totalPackets; // bin payload 分片包数（不含头信息握手包）
  final int chunkSize;
  final int payloadSize; // bin payload 大小 = size - 128

  /// true=设备 END(0xF3) 应答成功码（唯一的成功语义）。v1.5 下失败路径一律抛错，
  /// 成功返回必为 true；保留字段供页面兜底判断。
  final bool confirmed;
  final int prn;
  final String startFrameHex;
  final String headerFrameHex;
  final String firstDataFrameHex;
  final String endFrameHex;
}

/// 固件包来源（二选一）：内存 bytes / 远程下载地址。
/// （2026-08-13 起没有第三种：mock 合成包随干跑一并删除。）
class OtaFirmwarePackage {
  const OtaFirmwarePackage({
    this.bytes,
    this.packageUrl,
    this.sizeBytes = 0,
    this.checksum,
    this.version,
  });

  final Uint8List? bytes;
  final String? packageUrl;
  final int sizeBytes; // 期望大小；>0 时与实际不符会报错
  final String? checksum; // 期望 CRC32（"0x.." 或十进制），本地核对
  final String? version;
}

/// 已就绪的固件数据（读包 + 本地 CRC32 之后）。
class _PreparedFirmware {
  _PreparedFirmware(this.bytes, this.crc32);
  final Uint8List bytes;
  final int crc32;
  int get size => bytes.length;
  int get payloadSize => _computeFwSize(bytes.length);
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
/// 发现 FF10 服务、在 FF11 特征上收发。升级成功设备复位重启会断开该连接（属正常）。
class FrameOtaClient {
  FrameOtaClient(this.device);

  final BluetoothDevice device;

  BluetoothCharacteristic? _controlChar;
  BluetoothCharacteristic? _dataChar;
  BluetoothCharacteristic? _altControlChar;
  BluetoothCharacteristic? _transferChar; // START 成功应答的那条特征，DATA/END 沿用它
  final List<StreamSubscription<List<int>>> _notifySubs = [];
  StreamSubscription<BluetoothConnectionState>? _connSub;

  int _mtu = _defaultDeviceMtu;
  int _prn = _defaultPrn;
  int _chunkSize = _chunkFromMtu(_defaultDeviceMtu);
  bool _writeWithoutResponse = true;
  // 本轮是否重发过 128 字节头信息（END 回 0x09 时据此给出解释线索）
  bool _headerResent = false;

  Completer<_StartAck>? _startCompleter;
  // 当前在等的一次 DATA/END 结果码应答；同一时刻只有一个（OTA 全程串行：发一批→等一次 ACK→再发下一批）。
  int _ackWaitOpcode = 0;
  Completer<_AckResult>? _ackCompleter;
  // 尚无人认领的结果码应答缓存（写完到收到 ACK 的竞态兜底）。
  final List<_AckResult> _ackInbox = [];

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
        final startWaiter = _startCompleter;
        if (startWaiter != null && !startWaiter.isCompleted) {
          startWaiter.completeError(OtaException(_abortReason));
        }
        final ackWaiter = _ackCompleter;
        if (ackWaiter != null && !ackWaiter.isCompleted) {
          ackWaiter.completeError(OtaException(_abortReason));
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
    for (final c in <BluetoothCharacteristic?>{
      control,
      _dataChar,
      _altControlChar,
    }) {
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
    _chunkSize = _chunkFromMtu(
      _mtu < _defaultDeviceMtu ? _mtu : _defaultDeviceMtu,
    );
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
    final echo = bytes[0] == _opAck
        ? (bytes.length > 1 ? bytes[1] : 0)
        : bytes[0];

    // START ACK：回显 0xF1；或正等 START 应答且不是 DATA/END，也按 START ACK 解析。
    final startWaiter = _startCompleter;
    if (echo == _opStart ||
        (startWaiter != null && echo != _opData && echo != _opEnd)) {
      final ack = _parseStartAck(bytes);
      if (ack == null) {
        if (kDebugMode) {
          debugPrint('[OTA] 忽略无法识别的应答帧：${FrameProtocol.bytesToHex(bytes)}');
        }
        return;
      }
      if (startWaiter != null && !startWaiter.isCompleted) {
        _startCompleter = null;
        startWaiter.complete(ack);
      }
      return;
    }

    // DATA ACK（回显 0xF2）或 END ACK（回显 0xF3）：都只带 RESULT 结果码，交给对应 opcode 的等待者。
    if (echo == _opData || echo == _opEnd) {
      final offset = bytes[0] == _opAck ? 2 : 1;
      final ack = _AckResult(
        opcode: echo,
        result: bytes.length > offset ? bytes[offset] & 0xFF : 0xFF,
        rawHex: FrameProtocol.bytesToHex(bytes),
      );
      final waiter = _ackCompleter;
      if (waiter != null && !waiter.isCompleted && _ackWaitOpcode == echo) {
        _ackCompleter = null;
        waiter.complete(ack);
        return;
      }
      _ackInbox.add(ack); // 还没人在等（写完到收到 ACK 的竞态），先缓存到收件箱
    }
  }

  // START ACK 权威布局：[0xFC, 0xF1, RESULT, MTU(1,=251), PRN(1), checksum]。
  // 兼容「不带 0xFC 帧头、直接回显 0xF1」的旧固件。MTU/PRN 越界则回落 0，由 _applyStartAck 用默认值兜底。
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
    return _StartAck(
      result: result,
      mtu: mtu,
      prn: prn,
      rawHex: FrameProtocol.bytesToHex(bytes),
    );
  }

  // ── 等待原语 ──────────────────────────────────────────────
  /// 等某个 opcode(0xF2 DATA / 0xF3 END) 的结果码应答：命中返回 [_AckResult]，
  /// 超时抛 [timeoutMessage]，连接断开抛断开错误。调用前若 ACK 已到并落入收件箱，直接取走。
  Future<_AckResult> _waitAck(
    int opcode,
    Duration timeout,
    String timeoutMessage,
  ) async {
    if (_disconnected) {
      throw OtaException(_abortReason.isEmpty ? 'OTA 连接已断开' : _abortReason);
    }

    final bufferedIndex = _ackInbox.indexWhere((a) => a.opcode == opcode);
    if (bufferedIndex >= 0) {
      return _ackInbox.removeAt(bufferedIndex);
    }

    final completer = Completer<_AckResult>();
    _ackWaitOpcode = opcode;
    _ackCompleter = completer;
    try {
      return await completer.future.timeout(
        timeout,
        onTimeout: () => throw OtaException(timeoutMessage),
      );
    } finally {
      if (_ackCompleter == completer) _ackCompleter = null;
    }
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

  /// 发一帧 DATA/END 并等它的结果码应答。发送前先清空收件箱（本次只认这一帧的应答）。
  Future<_AckResult> _sendFrameAwaitAck(
    List<int> frame,
    int opcode,
    Duration timeout,
    String timeoutMessage,
  ) async {
    _ackInbox.clear();
    await _writeFrame(frame, _transferChar ?? _controlChar!);
    return _waitAck(opcode, timeout, timeoutMessage);
  }

  // ── START 握手 ────────────────────────────────────────────
  Future<void> _doStart(
    int size, {
    int? objType,
    Duration? startTimeout,
    void Function(OtaProgress)? onProgress,
    bool Function()? shouldAbort,
  }) async {
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
      throw OtaException(
        'OTA 特征不支持写入：FF11/FF12/FF13 均未声明 write / writeNoResponse',
      );
    }

    final objTypes = objType != null
        ? [objType]
        : const [_objTypeFirmware, 0x01];
    final timeout =
        startTimeout ??
        (targets.length > 1 || objTypes.length > 1
            ? const Duration(milliseconds: 2500)
            : const Duration(milliseconds: 5000));

    OtaException? lastError;
    final totalAttempts = targets.length * objTypes.length;
    var attempt = 0;
    for (final target in targets) {
      for (final ot in objTypes) {
        // 穷举最坏 ~15s，中途用户可能早就退出升级页了：每换一个组合先看一眼中止标记，
        // 别占着设备把这 15s 走完（被占着时它不广播，此刻任何入口都搜不到它）。
        if (shouldAbort?.call() ?? false) throw OtaAbortedException();
        attempt++;
        // 兜底穷举最坏 ~15s（3 特征 × 2 objType × 2.5s），每换一个组合报一次进度，
        // 否则 UI 停在「握手中」十几秒无变化，用户会误判卡死（纯提示，不改流程）。
        if (totalAttempts > 1) {
          onProgress?.call(
            OtaProgress(
              phase: 'starting',
              percent: 14,
              message: '握手中（尝试 $attempt/$totalAttempts）',
            ),
          );
        }
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
          // 设备在哪条特征上应答了 START，后续 DATA/END 就走同一条（本机 OTA 全程 FF11）。
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
      throw OtaException(
        'OTA 启动被拒绝：${otaResultText(ack.result)}（ACK=${ack.rawHex}）',
        // 0x05「设备状态错误」≈ 上一轮 DFU 没走完，状态机还停在升级态。复用同一条 GATT
        // 连接再怎么重发都是 0x05，必须先把链路断掉让设备复位（见 BleController.upgradeFirmware）。
        kind: ack.result == 0x05
            ? OtaFailureKind.startRejectedBusy
            : OtaFailureKind.plain,
      );
    }
    if (ack.prn > 0) _prn = ack.prn;
    final effectiveMtu = _mtu < (ack.mtu > 0 ? ack.mtu : _defaultDeviceMtu)
        ? _mtu
        : (ack.mtu > 0 ? ack.mtu : _defaultDeviceMtu);
    _chunkSize = _chunkFromMtu(effectiveMtu);
  }

  // ── 分阶段数据传输（v1.5 §6.3.4）─────────────────────────────
  // 手机只负责按文件内容读取并发送：先发 128 字节头信息握手包，再按 PRN 信用窗口发 bin payload，最后
  // 发 END。一切完整性校验(CRC16/CRC32/版本/面板)由设备依据升级包里已打好的头信息完成，手机不重发、
  // 不补包——某一批 ACK 超时或回错即判传输中断，整轮升级失败由用户重试（设备侧会等 APP 重新发起 DFU）。
  Future<OtaResult> _transferData(
    Uint8List bytes,
    int crc32, {
    int pace = 3,
    void Function(OtaProgress)? onProgress,
    bool Function()? shouldAbort,
    Duration finalTimeout = const Duration(seconds: 15),
    Duration headerTimeout = const Duration(seconds: 10),
    Duration headerDelay = const Duration(milliseconds: 300),
    Duration headerRetryDelay = const Duration(milliseconds: 1500),
    int headerAttempts = 3,
  }) async {
    final total = bytes.length;
    if (total < otaHeaderSize) {
      throw OtaException('升级包过小（$total 字节），缺少 128 字节头信息，可能不是有效的 OTA 升级包');
    }

    final header = bytes.sublist(0, otaHeaderSize); // 升级包最前面的 128 字节头信息
    final payload = bytes.sublist(otaHeaderSize); // 从第 129 字节起的原始 bin payload
    final payloadLen = payload.length;
    final chunkSize = _chunkSize;
    final totalPackets = (payloadLen + chunkSize - 1) ~/ chunkSize;
    final prn = _prn <= 0 ? _defaultPrn : _prn;

    _ackCompleter = null;
    _ackInbox.clear();

    // ── 步骤 3：128 字节头信息握手包 ──
    onProgress?.call(
      OtaProgress(
        phase: 'header',
        percent: 15,
        sent: 0,
        total: payloadLen,
        message: '发送 128 字节头信息，等待设备校验头部',
      ),
    );
    // 超时给到 10s：设备收到 START 后要初始化写入区（含 Flash 擦除），再校验头部 CRC16/版本号，
    // 这段忙碌期不回应答是常见的。5s 曾把「设备还在准备」误判成握手失败。
    // ⚠️ 文案不要暗示「面板/型号不匹配」：那种情况设备会明确回 0x0C，能走到超时只可能是它没应答。
    //
    // START ACK 一回来设备就开始擦 Flash，这段时间它可能顾不上收包——FF11 只有无应答写(§6.3.2)，
    // 这时丢包是静默的，谁都不会报错。先等一小会儿(300ms)再发头信息；不敢久等是因为反向也有风险：
    // 固件若同样有「约 1s 没等到下一包就中断」的口径（§6.4 图传即如此），久等反会让它先把这轮判死。
    // 「设备还在忙」那一侧交给下面的退避重发覆盖，两种可能都不押死。
    final headerFrame = _buildDataFrame(header);
    if (kDebugMode) {
      debugPrint(
        '[OTA] 头信息握手包：帧长=${headerFrame.length} 头信息字节数=${header.length} '
        '前12字节=${headerFrame.take(12).map(_hexByte).join(' ')}',
      );
    }
    if (headerDelay > Duration.zero) {
      await Future<void>.delayed(headerDelay);
    }
    _AckResult? headerAck;
    OtaException? headerError;
    for (int attempt = 1; attempt <= headerAttempts; attempt++) {
      // 中断要能在这一层及时收手（2026-08-12，同步小程序）：头信息阶段最坏是
      // 3 次 × 10s 超时 + 两次退避 ≈ 33s，中途用户已经退出升级页了，我们还占着设备
      // 一路重发——而设备被占着时**不广播**，这段时间里任何入口都搜不到它。
      // 数据窗口那一层早就有这个检查了（见下面的 while 循环），头信息这层此前漏了。
      if (shouldAbort?.call() ?? false) throw OtaAbortedException();
      if (attempt > 1) {
        _headerResent = true;
        // 退避重发：设备刚说「状态不对」或干脆没应答，多半还没从上一轮 DFU / 擦写忙态里出来，
        // 立刻重发只会再撞一次。等一等再来，一次比一次久。
        // 设备**按首包长度识别头信息**（§6.3.4），只要它还没收下过，重发的这一包依然按头信息处理。
        await Future<void>.delayed(headerRetryDelay * (attempt - 1));
        onProgress?.call(
          OtaProgress(
            phase: 'header',
            percent: 15,
            sent: 0,
            total: payloadLen,
            message: '头信息未通过，重发第 $attempt 次…',
          ),
        );
      }

      _AckResult ack;
      try {
        ack = await _sendFrameAwaitAck(
          headerFrame,
          _opData,
          headerTimeout,
          '头信息握手超时：${headerTimeout.inSeconds}s 内未收到设备对 128 字节头信息的校验应答',
        );
      } on OtaAbortedException {
        rethrow;
      } on OtaException catch (e) {
        if (!e.message.contains('头信息握手超时')) rethrow; // 断链等致命错误直接上抛
        if (kDebugMode) {
          debugPrint('[OTA] 头信息第 $attempt 次无应答（共 $headerAttempts 次）');
        }
        headerError = e;
        continue;
      }

      if (ack.result == 0x00) {
        headerAck = ack;
        break;
      }
      if (ack.result == 0x05) {
        // 「设备状态错误」说的是**此刻不能受理**，不是「这个包不对」——包不对是 0x0A~0x0E。
        // 属于可重试：等设备从忙态/上一轮 DFU 状态里出来再发一次。
        if (kDebugMode) {
          debugPrint('[OTA] 头信息第 $attempt 次被回 0x05（设备状态错误）：${ack.rawHex}');
        }
        headerError = OtaException(
          '头信息校验未通过：${otaResultText(0x05)}（ACK=${ack.rawHex}）',
        );
        continue;
      }
      // 0x0A~0x0E 明确指向「包不对/头版本/面板/CRC16/版本号」：重发一万次也一样，
      // 直接把设备语义透传给用户。
      throw OtaException(
        '头信息校验未通过：${otaResultText(ack.result)}（ACK=${ack.rawHex}）',
      );
    }
    if (headerAck == null) {
      // 标记 headerStuck：此刻设备一个 payload 字节都没收下，上层可以安全地断链复位后整轮重来。
      throw OtaException(
        '${headerError?.message ?? '头信息握手失败'}（同一连接内已发 $headerAttempts 次头信息）',
        kind: OtaFailureKind.headerStuck,
      );
    }

    // ── 步骤 4：后续 bin payload，PRN 信用窗口 ──
    onProgress?.call(
      OtaProgress(
        phase: 'transferring',
        percent: _progressPercent(0, payloadLen),
        sent: 0,
        total: payloadLen,
        message: '头部校验通过，开始传输：共 $totalPackets 包，每包 $chunkSize 字节，窗口 PRN=$prn',
      ),
    );

    final transferChar = _transferChar ?? _controlChar!;
    int seq = 0;
    while (seq < totalPackets) {
      if (shouldAbort?.call() ?? false) throw OtaAbortedException();
      if (_disconnected) throw OtaException(_abortReason);

      final batchEnd = seq + prn > totalPackets ? totalPackets : seq + prn;
      // 收尾不足一个信用窗口的那一批：设备按 PRN 每收满 prn 包才回一次 ACK，最后凑不满窗口的
      // 1~2 包本来就等不到 DATA ACK（规格书 §8 的应答只画在 `loop[每 PRN 个 DATA 包]` 里）。
      // 673 包 / PRN=3 时最后一窗只有 1 包，现场表现正是「已发送 673/673 包后，设备未在 1.5s 内
      // 应答（疑似丢包）」——数据其实已全部发出。
      final isTailWindow = batchEnd == totalPackets && batchEnd - seq < prn;
      _ackInbox.clear();
      for (int k = seq; k < batchEnd; k++) {
        final start = k * chunkSize;
        final end = start + chunkSize > payloadLen
            ? payloadLen
            : start + chunkSize;
        // DATA 沿用 START 成功的那条特征（见 _doStart）；缺省回落到控制特征 FF11。
        await _writeFrame(
          _buildDataFrame(payload.sublist(start, end)),
          transferChar,
        );
        // 批内最后一包发完直接进入等 ACK，不再多睡一个 pace——
        // 停等窗口本身就是流控，末包后的延时纯属白等。
        if (pace > 0 && k < batchEnd - 1) {
          await Future<void>.delayed(Duration(milliseconds: pace));
        }
      }

      // 每发 PRN 个 DATA 包等一次设备应答，1.5s 收不到即判中断。
      // 收尾窗口例外：它的 ACK 一律按「可选」处理，直接进 END——整包完不完整由 END(0xF3) 的
      // total_bytes == bin_size 与 CRC32 校验裁决（不匹配设备回 0x09），真丢包一样会被抓住，
      // 不会因为放过这次等待而误报升级成功。
      _AckResult? ack;
      try {
        ack = await _waitAck(
          _opData,
          const Duration(milliseconds: 1500),
          'OTA 传输中断：已发送 $batchEnd/$totalPackets 包后，设备未在 1.5s 内应答（疑似丢包），请重试整个升级',
        );
      } on OtaAbortedException {
        rethrow;
      } on OtaException catch (e) {
        if (!isTailWindow || !e.message.contains('未在 1.5s 内应答')) rethrow;
        if (kDebugMode) {
          debugPrint('[OTA] 收尾窗口未收到 DATA ACK（不足一个 PRN 窗口，属预期），继续发送结束包');
        }
        ack = null;
      }
      if (ack != null && ack.result != 0x00) {
        throw OtaException('设备接收数据报错：${otaResultText(ack.result)}');
      }

      seq = batchEnd;
      final sent = seq * chunkSize > payloadLen ? payloadLen : seq * chunkSize;
      onProgress?.call(
        OtaProgress(
          phase: 'transferring',
          percent: _progressPercent(sent, payloadLen),
          sent: sent,
          total: payloadLen,
          message: '传输中：$sent/$payloadLen 字节（$seq/$totalPackets 包）',
        ),
      );
    }

    // ── 步骤 5：END 结束包，设备整包校验 total_bytes==bin_size 且 CRC32(payload)==bin_crc32 ──
    onProgress?.call(
      OtaProgress(
        phase: 'verifying',
        percent: 98,
        sent: payloadLen,
        total: payloadLen,
        message: '数据已发完，发送结束包(0xF3)，等待设备整包校验',
      ),
    );
    // 校验窗口需覆盖「设备最后一批落盘 + CRC32 计算」，给足时长（默认 15s，可由 finalTimeout 覆盖）。
    _AckResult finalAck;
    try {
      finalAck = await _sendFrameAwaitAck(
        _buildEndFrame(),
        _opEnd,
        finalTimeout,
        'OTA 校验超时：结束包已发送，但 ${finalTimeout.inSeconds}s 内未收到设备整包校验结果(0xF3 应答)，请重试',
      );
    } on OtaException catch (e) {
      if (shouldAbort?.call() ?? false) throw OtaAbortedException();
      if (_disconnected || e.message.contains('断开')) {
        throw OtaException('OTA 传输中断：结束包已发送，但设备在返回整包校验结果前断开，升级未完成，请重试。');
      }
      rethrow;
    }

    if (finalAck.result != 0x00) {
      // 0x09 = total_bytes/CRC32 对不上。若本轮重发过头信息，最可能的解释是「设备其实收下了
      // 第一包、只是应答丢了」，重发的 128 字节被算进了 bin 数据——把这条线索一并给出，
      // 免得又去查信号。
      final hint = finalAck.result == 0x09 && _headerResent
          ? '（本轮重发过头信息包：若设备其实已收下第一包，重发的 128 字节会被计入 bin 数据而导致本校验失败，请重试一次）'
          : '';
      throw OtaException('设备整包校验失败：${otaResultText(finalAck.result)}$hint');
    }

    onProgress?.call(
      OtaProgress(
        phase: 'done',
        percent: 100,
        sent: payloadLen,
        total: payloadLen,
        message: '升级完成，设备校验通过，约 100ms 后复位运行新固件',
      ),
    );
    return OtaResult(
      size: total,
      crc32: crc32,
      totalPackets: totalPackets,
      chunkSize: chunkSize,
      payloadSize: payloadLen,
      prn: prn,
      confirmed: true,
    );
  }

  int _progressPercent(int sent, int total) {
    if (total == 0) return 97;
    final p = 15 + (sent / total * 82).floor();
    return p > 97 ? 97 : p;
  }

  // ── 固件包加载 / 准备 ──────────────────────────────────────
  static Future<Uint8List> _downloadFirmware(String url) async {
    // 共用 ApiClient 的连接池；加超时——之前没有超时，弱网半途挂起会让
    // OTA 永远卡在「准备固件包」。
    try {
      final resp = await ApiClient.instance.httpClient
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 30));
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        throw OtaException('固件包下载失败(${resp.statusCode})');
      }
      return resp.bodyBytes;
    } on TimeoutException {
      throw OtaException('固件包下载超时，请检查网络后重试');
    }
  }

  static Future<Uint8List> _loadFirmwareBuffer(OtaFirmwarePackage pkg) async {
    if (pkg.bytes != null) return pkg.bytes!;
    if (pkg.packageUrl != null && pkg.packageUrl!.isNotEmpty) {
      return _downloadFirmware(pkg.packageUrl!);
    }
    throw OtaException('缺少固件包来源（bytes / packageUrl）');
  }

  /// 发包前的本地预检：传错文件/下载截断应该在碰蓝牙之前就拦住，而不是刷到设备上再等它回错误码。
  /// 只拦「一望即知不对」的三类（缺 OTAINFO 标识、头部长度不是 128、声明 bin 大小与文件对不上）
  /// 与「面板明确刷错」；CRC16/CRC32 只记日志不拦——规格书没写这两个校验用的多项式口径，
  /// 本地算法与固件不一致时误拦会把好包挡在门外，这两项本来就该由设备校验（0x0D / 0x09）。
  static OtaPackageHeader _assertPackageLooksRight(
    Uint8List bytes,
    int payloadSize, {
    int expectPanel = 0,
    String expectVersion = '',
  }) {
    final header = inspectOtaHeader(bytes);
    if (kDebugMode) {
      debugPrint(
        '[OTA] 升级包头信息：magicOk=${header.magicOk} 头部版本=${header.headerVersion} '
        '面板=${header.panel} 头部长度=${header.headerLength} '
        '声明bin=${header.binSize} 实际payload=$payloadSize '
        'binCrc32=0x${header.binCrc32.toRadixString(16).toUpperCase()} '
        '本地Crc32Mpeg2=0x${FrameProtocol.crc32Mpeg2(Uint8List.fromList(bytes.sublist(otaHeaderSize))).toRadixString(16).toUpperCase()} '
        '版本号=${header.version}',
      );
    }

    if (!header.magicOk) {
      throw OtaException(
        '升级包无效：文件开头没有 "OTAINFO" 标识（§6.3.4 头信息），这不是一个 OTA 升级包 —— 多半是传错了文件或下载被截断。',
      );
    }
    if (header.headerLength != otaHeaderSize) {
      throw OtaException(
        '升级包无效：头信息声明头部长度 ${header.headerLength} 字节，规格固定为 $otaHeaderSize 字节，文件不是本协议的升级包。',
      );
    }
    if (header.binSize != payloadSize) {
      throw OtaException(
        '升级包不完整：头信息声明 bin 大小 ${header.binSize} 字节，文件实际只有 $payloadSize 字节（不含 128 字节头）。请重新下载或确认是否传错了包。',
      );
    }
    if (expectPanel > 0 && header.panel > 0 && header.panel != expectPanel) {
      throw OtaException(
        '升级包面板不匹配：这是 ${_panelText(header.panel)} 的固件，当前设备是 ${_panelText(expectPanel)}。刷错面板会变砖，已终止。',
      );
    }
    if (expectVersion.isNotEmpty &&
        header.version.isNotEmpty &&
        !header.version.contains(expectVersion)) {
      // 只告警：后端版本号写法（如 V1.0.2）与包内版本串（BR1601A02_..._V102）本就可能不同形，
      // 拦下去会误伤；真不匹配设备会在头信息握手回 0x0E。
      if (kDebugMode) {
        debugPrint(
          '[OTA] 升级包内版本号 "${header.version}" 与后端下发的新版本 "$expectVersion" 不同形，请留意是否传错包',
        );
      }
    }
    return header;
  }

  static Future<_PreparedFirmware> _prepareFirmware(
    OtaFirmwarePackage pkg, {
    void Function(OtaProgress)? onProgress,
    int expectPanel = 0,
    String expectVersion = '',
  }) async {
    onProgress?.call(
      const OtaProgress(phase: 'preparing', percent: 5, message: '准备固件包'),
    );
    final bytes = await _loadFirmwareBuffer(pkg);
    final size = bytes.length;
    if (size == 0) throw OtaException('固件包为空');
    if (pkg.sizeBytes > 0 && size != pkg.sizeBytes) {
      throw OtaException('固件包大小不一致：期望 ${pkg.sizeBytes} 字节，实际 $size 字节');
    }
    // v1.5 升级包结构固定为 [128 字节头信息][bin payload]，文件必须至少含这 128 字节头。
    if (size <= otaHeaderSize) {
      throw OtaException(
        '升级包过小（$size 字节），至少应含 128 字节头信息 + bin payload，可能不是有效的 OTA 升级包',
      );
    }
    final payloadSize = _computeFwSize(size);
    if (payloadSize < _minFwSize || payloadSize > _maxFwSize) {
      if (kDebugMode) {
        debugPrint(
          '[OTA] bin payload $payloadSize 字节超出建议范围 '
          '0x${_minFwSize.toRadixString(16)}~0x${_maxFwSize.toRadixString(16)}（仅告警，最终以设备应答为准）',
        );
      }
    }
    // 发之前先看一眼这个包对不对（传错文件/下载截断/面板刷错），别等刷到设备上才失败。
    _assertPackageLooksRight(
      bytes,
      payloadSize,
      expectPanel: expectPanel,
      expectVersion: expectVersion,
    );

    // v1.5：一切校验数据(含 CRC32)由固件方预先打进升级包头信息、并由设备端校验；手机不再计算/携带
    // CRC32。这里仅为本地展示/日志算一次整包 CRC32；调用方显式给了期望值才做核对。
    final crc32 = FrameProtocol.crc32Mpeg2(bytes);
    final expectedCrc = _normalizeChecksum(pkg.checksum);
    if (expectedCrc != null && expectedCrc != crc32) {
      throw OtaException('固件包本地 CRC32 校验失败');
    }
    onProgress?.call(
      OtaProgress(
        phase: 'prepared',
        percent: 10,
        message: '固件包已就绪',
        total: size,
      ),
    );
    return _PreparedFirmware(bytes, crc32);
  }

  // ── 对外主流程 ────────────────────────────────────────────
  /// 升级设备固件（v1.5：START → 128 字节头信息握手 → PRN 窗口发 payload → END → 设备整包校验）。
  ///
  /// [finalTimeout]：END 发出后等设备整包校验结果(0xF3 应答)的时长。
  ///
  /// ⚠️ 2026-08-13（两端同步）：**干跑（`dryRun` / `dryRunUpgrade` / mock 合成包）整套已删除**。
  /// 留着它，「升级成功」就有了两种含义（真机 DFU 成功 / 本地编码校验通过）——真机联调看日志时
  /// 很容易把干跑的成功当成设备真的升上去了。
  Future<OtaResult> upgradeFirmware(
    OtaFirmwarePackage pkg, {
    void Function(OtaProgress)? onProgress,
    bool Function()? shouldAbort,
    // 3ms 对齐图传链路的发包节奏（transferPacketPaceMs）：PRN=3 的停等窗口本身
    // 就是流控，20ms/包纯粹把 1000+ 包的固件拖慢 ~20s。
    int pace = 3,
    int? objType,
    Duration finalTimeout = const Duration(seconds: 15),
    // 本地预检：设备面板（0=判不出，跳过该项）与后端下发的新版本号（只告警）。
    int expectPanel = 0,
    String expectVersion = '',
  }) async {
    final prepared = await _prepareFirmware(
      pkg,
      onProgress: onProgress,
      expectPanel: expectPanel,
      expectVersion: expectVersion,
    );

    onProgress?.call(
      const OtaProgress(
        phase: 'connecting',
        percent: 12,
        message: '连接 OTA 服务(FF10)',
      ),
    );
    await _ensureConnection();

    onProgress?.call(
      OtaProgress(phase: 'starting', percent: 14, message: '握手中（MTU $_mtu）'),
    );
    // START 携带 FW_SIZE = bin payload 大小（文件大小 - 128 头，见 _computeFwSize）。
    await _doStart(
      prepared.payloadSize,
      objType: objType,
      onProgress: onProgress,
      shouldAbort: shouldAbort,
    );

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
