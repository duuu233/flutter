// 电子相框 BLE 应用层协议编解码（依据《电子相框产品需求规格书 v1.2》第 6 章）。
// 由微信小程序版 `utils/frame-protocol.js` 移植到 Dart，参数已对齐真机：
//   · 屏幕尺寸：3.7寸 480×720(95张) / 5.89寸 680×960(51张) / 7.3寸 占位
//   · IMG_MASK 为 12 字节(96 位)，低字节在前
//   · 帧 CRC16-Modbus；整图 CRC32-MPEG2
// 纯函数 / 无副作用，便于单测，与具体 BLE 插件解耦（由 device_ble.dart 调用）。
//
// 串行帧格式(6.4.1)：SOF(1=0xAA) | CMD(1) | LEN(2,小端=PAYLOAD字节数) | PAYLOAD(N) | CRC16(2,小端,覆盖 SOF~PAYLOAD)
// 设备应答统一为 CMD=0x7F 的 ACK 帧，PAYLOAD = ACK_CMD(1)+RESULT(1)+数据(6.6.1)。

import 'dart:typed_data';

/// 屏幕类型描述（6.7.3 / 6.10.7）。capacity = 该尺寸最多可存图片张数。
class FrameScreen {
  const FrameScreen({
    required this.type,
    required this.label,
    required this.model,
    required this.width,
    required this.height,
    required this.capacity,
  });

  final int type;
  final String label;
  final String model;
  final int width;
  final int height;
  final int capacity;
}

/// 广播厂商数据解析结果（6.10.7）—— 由小程序 `frame-protocol.parseAdvertising` 移植。
/// [deviceId] 为广播里的 4 字节 Device_ID（`AA:BB:CC:DD` 形式）：跨扫描会话稳定，
/// 是「连接前」就能拿到的硬件序列号，用于把扫描结果和后端已绑定记录容错匹配
///（与连上后 0x01 读到的 6 字节 Device_ID 互为子串，见 serial_match.dart）。
class FrameAdvertising {
  const FrameAdvertising({
    required this.screenType,
    required this.screen,
    required this.model,
    required this.deviceId,
    required this.battery,
    this.deviceIdComplete = false,
    this.deviceIdLayoutFallback = false,
    this.companyMatched = false,
  });

  final int screenType;
  final String screen;
  final String model;

  /// 广播里的 Device_ID：老固件 4 字节、新固件 6 字节（见 [FrameProtocol.parseAdvertising]）。
  final String deviceId;

  /// [deviceId] 是否已是完整 6 字节（新固件）。展示层据此决定能否与设备详情页对齐；
  /// ⚠️ **身份判定不看它**——判重、认领会话、绑定入库一律仍只认连上后 0x01 读到的值，
  /// 广播是明文、可被伪造重放。见 `docs/architecture/BLE_CONNECTION_AND_IDENTITY.md`。
  final bool deviceIdComplete;

  /// 优选布局（长度够就先按 6 字节解）解不通、**回退**另一种布局才解出来的
  /// （2026-08-11 同步小程序）。上层可据此把这条结果看得轻一点，但不必丢弃：
  /// 丢了这台设备在列表里连屏型/电量都没有，也排不进候选。
  final bool deviceIdLayoutFallback;

  /// 厂商数据带 `0xFFFF` Company_ID —— 即「确认是本产品的广播」。
  /// 扫描白名单在设备名缺席时靠它放行；兜底候选也只在它为真的设备里挑。
  final bool companyMatched;

  final int battery;
}

/// 解析出的一帧。
class ParsedFrame {
  const ParsedFrame({
    required this.cmd,
    required this.payload,
    required this.crcOk,
    required this.consumed,
  });

  final int cmd;
  final List<int> payload;
  final bool crcOk;
  final int consumed; // 本帧在缓冲里占用的字节数（用于流式消费）
}

/// 一帧 ACK 的拆解（6.6.1）。
class ParsedAck {
  const ParsedAck({required this.ackCmd, required this.result, required this.data});

  final int ackCmd;
  final int result;
  final List<int> data;

  bool get ok => result == 0x00;
}

/// CMD=0x01 设备信息（6.7.3）。
class FrameDeviceInfo {
  const FrameDeviceInfo({
    required this.deviceId,
    required this.hwVersion,
    required this.imgMask,
    required this.imgCount,
    required this.battery,
    required this.playMode,
    required this.intervalSeconds,
    required this.screenType,
    required this.screen,
    required this.model,
    required this.capacity,
    required this.width,
    required this.height,
    required this.curImgIndex,
    this.firmwareVersion = '',
  });

  final String deviceId;
  final int hwVersion;
  final List<int> imgMask; // 12 字节
  final int imgCount;
  final int battery;
  final String playMode; // order / random / manual
  final int intervalSeconds;
  final int screenType;
  final String screen;
  final String model;
  final int capacity;
  final int width;
  final int height;
  final int curImgIndex;
  final String firmwareVersion;

  FrameDeviceInfo copyWith({String? firmwareVersion}) => FrameDeviceInfo(
        deviceId: deviceId,
        hwVersion: hwVersion,
        imgMask: imgMask,
        imgCount: imgCount,
        battery: battery,
        playMode: playMode,
        intervalSeconds: intervalSeconds,
        screenType: screenType,
        screen: screen,
        model: model,
        capacity: capacity,
        width: width,
        height: height,
        curImgIndex: curImgIndex,
        firmwareVersion: firmwareVersion ?? this.firmwareVersion,
      );
}

/// CMD=0x02 播放配置（6.7.4）。
class FramePlayConfig {
  const FramePlayConfig({required this.playMode, required this.intervalSeconds});
  final String playMode;
  final int intervalSeconds;
}

/// CMD=0x22 结束传输应答（6.8.4）。
class FrameImgEnd {
  const FrameImgEnd({
    required this.imgMask,
    required this.imgCount,
    required this.storageFree,
  });
  final List<int> imgMask;
  final int imgCount;
  final int storageFree;
}

class FrameProtocol {
  FrameProtocol._();

  static const int sof = 0xAA;
  static const int ack = 0x7F;

  // GATT UUID（取 16 位短码匹配，6.3）
  static const String serviceUuid = 'FF00';
  static const String charWriteUuid = 'FF01';
  static const String charNotifyUuid = 'FF02';

  // 命令字（6.5 / 6.7）
  static const int cmdGetInfo = 0x01;
  static const int cmdGetPlay = 0x02;
  static const int cmdGetSwVer = 0x03;
  static const int cmdGetBattery = 0x04;

  /// 获取 BLE 连接间隔（v1.4）。ACK 的 DATA 为 CONN_INTERVAL(2, 小端)，单位 1.25ms。
  static const int cmdGetConnInterval = 0x05;
  static const int cmdSetPlay = 0x10;
  static const int cmdSetTime = 0x11;
  static const int cmdDeleteImg = 0x12;

  /// 设置 BLE 连接间隔（v1.4）。PAYLOAD 为 CONN_INTERVAL(2, 小端)，单位 1.25ms。
  ///
  /// 这条指令是让**设备固件**去向手机发起「连接参数更新请求」。这一点很关键：
  /// BLE 的连接间隔由中心(手机)决定，外设只能「请求」。Android 的
  /// `requestConnectionPriority(HIGH)` 只能拿到 11.25~15ms，而设备自己请求可以要到 7.5ms；
  /// iOS 更是**完全没有**设置连接间隔的 API，只能靠设备端发起（且 Apple 拒绝 <15ms 的请求）。
  static const int cmdSetConnInterval = 0x13;
  static const int cmdImgStart = 0x20;
  static const int cmdImgData = 0x21;
  static const int cmdImgEnd = 0x22;
  static const int cmdImgAck = 0x23;
  static const int cmdSetCurImg = 0x24;
  static const int cmdAck = 0x7F;

  /// 屏幕类型表。7.3寸为占位型号(固件未实现图传)。
  static const Map<int, FrameScreen> screenTypes = {
    0x01: FrameScreen(type: 0x01, label: '3.7寸', model: 'EF6-370', width: 480, height: 720, capacity: 95),
    0x02: FrameScreen(type: 0x02, label: '5.89寸', model: 'EF6-589', width: 680, height: 960, capacity: 51),
    0x03: FrameScreen(type: 0x03, label: '7.3寸', model: 'EF6-730', width: 0, height: 0, capacity: 0),
  };

  // 播放模式 ⇄ 字节（6.7.3）
  static String playModeToString(int value) {
    switch (value) {
      case 0x01:
        return 'random';
      case 0x02:
        return 'manual';
      default:
        return 'order';
    }
  }

  static int playModeToByte(String mode) {
    switch (mode) {
      case 'random':
        return 0x01;
      case 'manual':
        return 0x02;
      default:
        return 0x00;
    }
  }

  // 结果码文案（6.6.1）
  static const Map<int, String> _resultText = {
    0x00: '成功',
    0x01: '参数错误',
    0x02: '长度错误',
    0x03: 'CRC 错误',
    0x04: 'Flash 写入失败',
    0x05: '图片不存在',
    0x06: '存储空间不足',
    0x07: '掩码不一致(该位置已有图/索引越界)',
    0x08: '不支持的命令',
    0x09: '传输中断',
    0x0a: '校验失败(整图CRC32不符)',
    0x0b: '设备忙(Busy)',
  };

  static String resultText(int code) {
    final text = _resultText[code];
    if (text != null) return text;
    return '未知结果码 0x${code.toRadixString(16).padLeft(2, '0')}';
  }

  // 设备忙（v1.5 §6.6.1）：设备正忙于处理其它指令时，对新指令回 RESULT=0x0B。
  // busyMessage 是面向用户的统一提示；device_ble 收到任意指令的 0x0B 应答即以它抛出 FrameBleException，
  // 各处「设备交互的判断」据此提示，避免各写一套文案。
  static const int busyResult = 0x0b;
  static const String busyMessage = '当前电子纸设备繁忙，请稍后重试';

  static bool isBusyResult(int code) => (code & 0xFF) == busyResult;

  // 判断一条错误文案是否为「设备忙」：供 UI 层归类时先短路，避免被更泛的「未连接」文案覆盖。
  static bool isBusyMessage(String? message) =>
      message != null && message.contains(busyMessage);

  // ── 删除图片(0x12)的「良性」结果码（2026-08-10 产品口径）────
  //
  // 同一台设备被两部手机连过：另一部手机删掉的那张，在本机「我的相册」里记录还在
  //（列表按后端投屏成功记录铺），它的 imgIndex 在设备上已经是空槽位。空槽位一起进 0x12 的
  // IMG_INDEX_MASK，固件回 0x07，**整批**删除被打回——同批没问题的照片也跟着删不掉。
  // 这两类结果码代表「要删的图设备上本来就没有」，按已删放行，只删后端记录即可。
  //
  //   0x05 图片不存在 / 0x07 掩码不一致(该位置已有图/索引越界)
  //
  // ⚠️ 只放行这两类：Flash 写入失败(0x04)、传输中断(0x09)、设备忙(0x0B)、断连/应答超时都必须
  //    如实中止——它们代表「设备可能真的没删掉」，放行会变成记录删了、图还挂在相框上，
  //    留下谁也找不到的孤儿槽位。
  //
  // 对齐小程序 `utils/frame-protocol.js` 的 `SKIPPABLE_DELETE_RESULTS`。
  static const List<int> skippableDeleteResults = [0x05, 0x07];

  static bool isSkippableDeleteResult(int code) =>
      skippableDeleteResults.contains(code & 0xFF);

  // 只剩文案时的兜底（错误被外层包装过、或来自没有结果码的老链路）：
  // 匹配 RESULT_TEXT 原文与常见英文写法。优先走结果码，见 FrameBleException.isSkippableDelete。
  static bool isSkippableDeleteMessage(String? message) =>
      message != null &&
      RegExp(
        r'图片不存在|无此图片|照片.*(不存在|异常)|掩码不一致|越界|索引.*(无效|不存在)'
        r'|not[\s_-]*(found|exist)|out[\s_-]*of[\s_-]*(range|bounds|index)',
        caseSensitive: false,
      ).hasMatch(message);

  // ── 基础工具 ──────────────────────────────────────────────

  static String bytesToHex(List<int> bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join(' ');

  static int readUint16LE(List<int> b, int o) =>
      ((b[o] & 0xFF) | ((b[o + 1] & 0xFF) << 8)) & 0xFFFF;

  static int readUint32LE(List<int> b, int o) =>
      ((b[o] & 0xFF) |
          ((b[o + 1] & 0xFF) << 8) |
          ((b[o + 2] & 0xFF) << 16) |
          ((b[o + 3] & 0xFF) << 24)) &
      0xFFFFFFFF;

  static String _bytesToId(List<int> b, int start, int length) {
    final parts = <String>[];
    for (int i = 0; i < length; i++) {
      final v = start + i < b.length ? b[start + i] : 0;
      parts.add((v & 0xFF).toRadixString(16).padLeft(2, '0').toUpperCase());
    }
    return parts.join(':');
  }

  /// 统计掩码中置位的比特数 = 已存图片张数。
  static int popcount(List<int> bytes, [int start = 0, int? length]) {
    final end = length == null ? bytes.length : start + length;
    int count = 0;
    for (int i = start; i < end && i < bytes.length; i++) {
      int v = bytes[i] & 0xFF;
      while (v != 0) {
        count += v & 1;
        v >>= 1;
      }
    }
    return count;
  }

  /// CRC16-Modbus 查表（性能优化 D1）：图传一张要对上千个 0x21 帧算 CRC16，逐位版在发送热路径上。
  /// 表按同一多项式 0xA001 生成，结果与逐位版完全一致。
  static final Uint16List _crc16ModbusTable = _buildCrc16ModbusTable();
  static Uint16List _buildCrc16ModbusTable() {
    final table = Uint16List(256);
    for (int n = 0; n < 256; n++) {
      int crc = n;
      for (int bit = 0; bit < 8; bit++) {
        crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xA001 : crc >> 1;
      }
      table[n] = crc & 0xFFFF;
    }
    return table;
  }

  /// CRC16-Modbus：初值 0xFFFF，多项式 0xA001(反转)，覆盖 SOF~PAYLOAD(6.4.1)。查表实现（见 D1）。
  static int crc16Modbus(List<int> bytes) {
    int crc = 0xFFFF;
    for (final raw in bytes) {
      crc = (crc >> 8) ^ _crc16ModbusTable[(crc ^ (raw & 0xFF)) & 0xFF];
    }
    return crc & 0xFFFF;
  }

  /// CRC32-MPEG2 查表（性能优化 D2）：一张 5.89 寸帧 326KB 逐位算要 260 万次循环、卡在 0x20 发出之前，
  /// 查表约快 8 倍；表按同一多项式 0x04C11DB7 生成，结果与逐位版完全一致。
  static final Uint32List _crc32Mpeg2Table = _buildCrc32Mpeg2Table();
  static Uint32List _buildCrc32Mpeg2Table() {
    final table = Uint32List(256);
    for (int n = 0; n < 256; n++) {
      int crc = (n << 24) & 0xFFFFFFFF;
      for (int bit = 0; bit < 8; bit++) {
        crc = (crc & 0x80000000) != 0
            ? ((crc << 1) ^ 0x04C11DB7) & 0xFFFFFFFF
            : (crc << 1) & 0xFFFFFFFF;
      }
      table[n] = crc;
    }
    return table;
  }

  /// 整图 CRC32-MPEG2(6.8.1 的 IMG_CRC32)：初值 0xFFFFFFFF，多项式 0x04C11DB7，
  /// 输入/输出都不反转，最终不异或。与帧用的 CRC16-Modbus 不是一回事。查表实现（见 D2）。
  static int crc32Mpeg2(List<int> bytes) {
    int crc = 0xFFFFFFFF;
    for (final raw in bytes) {
      crc = ((crc << 8) ^ _crc32Mpeg2Table[((crc >> 24) ^ (raw & 0xFF)) & 0xFF]) &
          0xFFFFFFFF;
    }
    return crc & 0xFFFFFFFF;
  }

  // ── 组帧 / 解帧 ───────────────────────────────────────────

  /// 组一帧待发送数据。
  static Uint8List buildFrame(int cmd, List<int> payload) {
    final body = <int>[
      sof,
      cmd & 0xFF,
      payload.length & 0xFF,
      (payload.length >> 8) & 0xFF,
    ];
    for (final b in payload) {
      body.add(b & 0xFF);
    }
    final crc = crc16Modbus(body);
    body.add(crc & 0xFF);
    body.add((crc >> 8) & 0xFF);
    return Uint8List.fromList(body);
  }

  /// 从字节流头部尝试解出一帧。数据不足/帧头不对返回 null（用于粘包/分包的流式解析）。
  static ParsedFrame? tryParseFrame(List<int> bytes) {
    if (bytes.length < 6) return null; // 至少 SOF+CMD+LEN(2)+CRC(2)
    if ((bytes[0] & 0xFF) != sof) return null;
    final len = readUint16LE(bytes, 2);
    final total = 4 + len + 2;
    if (bytes.length < total) return null; // 整帧未收齐
    final cmd = bytes[1] & 0xFF;
    final payload = bytes.sublist(4, 4 + len);
    final crcGot = readUint16LE(bytes, 4 + len);
    final crcCalc = crc16Modbus(bytes.sublist(0, 4 + len));
    return ParsedFrame(
      cmd: cmd,
      payload: payload,
      crcOk: crcGot == crcCalc,
      consumed: total,
    );
  }

  static ParsedAck parseAck(List<int> payload) {
    return ParsedAck(
      ackCmd: payload.isNotEmpty ? payload[0] & 0xFF : 0,
      result: payload.length > 1 ? payload[1] & 0xFF : 0xFF,
      data: payload.length > 2 ? payload.sublist(2) : const [],
    );
  }

  // ── 小端写入工具 ──────────────────────────────────────────
  static void _pushUint16LE(List<int> arr, int value) {
    arr.add(value & 0xFF);
    arr.add((value >> 8) & 0xFF);
  }

  static void _pushUint32LE(List<int> arr, int value) {
    arr.add(value & 0xFF);
    arr.add((value >> 8) & 0xFF);
    arr.add((value >> 16) & 0xFF);
    arr.add((value >> 24) & 0xFF);
  }

  // ── 图片掩码 ⇄ 索引（6.7.2 / 6.9.1，12 字节 96 位，低字节在前）──

  static List<int> indexesToMask(List<int> indexes) {
    final mask = List<int>.filled(12, 0);
    for (final raw in indexes) {
      final i = raw;
      if (i >= 0 && i < 96) {
        mask[i >> 3] |= 1 << (i & 7);
      }
    }
    return mask;
  }

  static List<int> maskToIndexes(List<int> maskBytes) {
    final list = <int>[];
    for (int i = 0; i < 96; i++) {
      final byte = (i >> 3) < maskBytes.length ? maskBytes[i >> 3] : 0;
      if ((byte & (1 << (i & 7))) != 0) {
        list.add(i);
      }
    }
    return list;
  }

  static int firstFreeIndex(List<int> maskBytes, int capacity) {
    final max = capacity > 0 ? capacity : 96;
    for (int i = 0; i < max; i++) {
      final byte = (i >> 3) < maskBytes.length ? maskBytes[i >> 3] : 0;
      if ((byte & (1 << (i & 7))) == 0) {
        return i;
      }
    }
    return -1;
  }

  // ── BLE 连接间隔（0x05 / 0x13）─────────────────────────────

  /// 协议里连接间隔的单位：1 unit = 1.25ms。
  static const double connIntervalUnitMs = 1.25;

  /// 连接间隔合法区间（units）：6 = 7.5ms（蓝牙协议最小值）、3200 = 4000ms。
  static const int connIntervalMinUnits = 6;
  static const int connIntervalMaxUnits = 3200;

  static double connectionIntervalUnitsToMs(int units) =>
      units * connIntervalUnitMs;

  static int connectionIntervalMsToUnits(double ms) =>
      (ms / connIntervalUnitMs).round();

  /// CMD=0x13 设置连接间隔的 PAYLOAD：CONN_INTERVAL(2, 小端)，单位 1.25ms。
  static List<int> buildSetConnectionIntervalPayload(int units) {
    final payload = <int>[];
    _pushUint16LE(payload, units);
    return payload;
  }

  /// 解析 CMD=0x05 的 ACK DATA：CONN_INTERVAL(2, 小端)。返回 units（0=没读到）。
  static int parseConnectionIntervalUnits(List<int> data) =>
      data.length >= 2 ? readUint16LE(data, 0) : 0;

  // ── 各命令 PAYLOAD 组装 ───────────────────────────────────

  /// CMD=0x10 设置播放参数：PLAY_MODE(1)+INTERVAL(4,小端)(6.7.7)。
  static List<int> buildSetPlaybackPayload(String mode, int intervalSeconds) {
    final payload = <int>[playModeToByte(mode)];
    _pushUint32LE(payload, intervalSeconds < 0 ? 0 : intervalSeconds);
    return payload;
  }

  /// CMD=0x11 校时：YEAR(2,小端) MONTH DAY HOUR MIN SEC(6.7.8)。
  static List<int> buildSetTimePayload(DateTime date) {
    final payload = <int>[];
    _pushUint16LE(payload, date.year);
    payload.add(date.month); // 1~12
    payload.add(date.day);
    payload.add(date.hour);
    payload.add(date.minute);
    payload.add(date.second);
    return payload;
  }

  /// CMD=0x20 图片帧头(6.8.1)：
  /// SCREEN_TYPE(1) IMG_INDEX(1) WIDTH(2) HEIGHT(2) FORMAT(1) IMG_DATA_SIZE(4) IMG_CRC32(4)，共 15 字节。
  static List<int> buildImgStartPayload({
    required int screenType,
    required int index,
    required int width,
    required int height,
    required int dataSize,
    required int crc32,
    int format = 0x01,
  }) {
    final payload = <int>[screenType & 0xFF, index & 0xFF];
    _pushUint16LE(payload, width);
    _pushUint16LE(payload, height);
    payload.add(format & 0xFF);
    _pushUint32LE(payload, dataSize);
    _pushUint32LE(payload, crc32);
    return payload;
  }

  /// CMD=0x21 数据包(6.8.2)：PKT_SEQ(2,小端)+DATA(本片最多 489 字节，2026-08-14 由 236 放宽)。
  static List<int> buildImgDataPayload(int seq, List<int> chunk) {
    final payload = <int>[];
    _pushUint16LE(payload, seq);
    for (final b in chunk) {
      payload.add(b & 0xFF);
    }
    return payload;
  }

  /// 组一帧完整的 CMD=0x21 图片数据帧（性能优化 D1，含 SOF/LEN/CRC16，返回可直接写特征的 Uint8List）。
  /// 字节与 buildFrame(cmdImgData, buildImgDataPayload(seq, chunk)) 完全一致，但用 Uint8List 整块
  /// setRange + 查表 CRC16，免去逐字节拼接——一张图要组上千帧，这条路径在图传热路径/预组包上。
  /// [data] 整图字节；[seq] 包号(0 起)；[chunkSize] 每包数据字节数(末包自动截短)。
  static Uint8List buildImgDataFrame(Uint8List data, int seq, int chunkSize) {
    final start = seq * chunkSize;
    final end = (start + chunkSize) > data.length ? data.length : start + chunkSize;
    final dataLen = end - start;
    final payloadLen = dataLen + 2; // PKT_SEQ(2) + DATA
    final frame = Uint8List(4 + payloadLen + 2); // SOF+CMD+LEN(2) + PAYLOAD + CRC16(2)
    frame[0] = sof;
    frame[1] = cmdImgData;
    frame[2] = payloadLen & 0xFF;
    frame[3] = (payloadLen >> 8) & 0xFF;
    frame[4] = seq & 0xFF;
    frame[5] = (seq >> 8) & 0xFF;
    frame.setRange(6, 6 + dataLen, data, start);
    // sublistView（零拷贝视图）而非 sublist：这是图传唯一的热路径，一张 5.89 寸图
    // ~1340 帧，每帧为算 CRC 复制 ~250B 就是每张 ~340KB 纯垃圾分配与 GC 抖动。
    final crc = crc16Modbus(Uint8List.sublistView(frame, 0, frame.length - 2));
    frame[frame.length - 2] = crc & 0xFF;
    frame[frame.length - 1] = (crc >> 8) & 0xFF;
    return frame;
  }

  /// CMD=0x12 删除图片：12 字节掩码。
  static List<int> buildDeleteImagePayload(List<int> indexes) => indexesToMask(indexes);

  /// CMD=0x24 切换显示：index；null/越界用 0xFF 表示保持不变。
  static List<int> buildRefreshPayload(int? index) =>
      [(index == null || index < 0) ? 0xFF : index & 0xFF];

  // ── 各命令应答解析 ────────────────────────────────────────

  /// 解析 CMD=0x01 设备信息的 data 段（28 字节，6.7.3）。
  static FrameDeviceInfo parseDeviceInfo(List<int> data) {
    final b = data;
    final screenType = b.length > 26 ? b[26] & 0xFF : 0;
    final screen = screenTypes[screenType];
    return FrameDeviceInfo(
      deviceId: _bytesToId(b, 0, 6),
      hwVersion: b.length > 7 ? readUint16LE(b, 6) : 0,
      imgMask: b.length >= 20 ? b.sublist(8, 20) : List<int>.filled(12, 0),
      imgCount: popcount(b, 8, 12),
      battery: b.length > 20 ? b[20] & 0xFF : 0,
      playMode: playModeToString(b.length > 21 ? b[21] & 0xFF : 0),
      intervalSeconds: b.length > 25 ? readUint32LE(b, 22) : 0,
      screenType: screenType,
      screen: screen?.label ?? '',
      model: screen?.model ?? '',
      capacity: screen?.capacity ?? 0,
      width: screen?.width ?? 0,
      height: screen?.height ?? 0,
      curImgIndex: b.length > 27 ? b[27] & 0xFF : 0,
    );
  }

  /// 广播厂商数据里 Device_ID 的两种长度（6.10.7）。
  ///
  /// 老固件 4 字节（MAC 中的 4 个字节）；**2026-08-04 起新固件改播完整 6 字节 MAC**，
  /// 使扫描阶段就能拿到与 0x01 GET_INFO 一致的完整设备 ID——这条路对 iOS 同样成立
  /// （iOS 系统不给外设 MAC，但厂商广播数据两端都拿得到）。
  static const int adDeviceIdLenV2 = 6;
  static const int adDeviceIdLenV1 = 4;

  /// 解析广播厂商数据（6.10.7）：Screen_Type(1) + Device_ID(**4 或 6**) + Battery(1)，
  /// 可能带 0xFF 0xFF Company_ID 前缀（此时从第 2 字节起为 Screen_Type）。
  /// 屏型不认识或电量非法（>100）视为非相框广播，返回 null。
  ///
  /// ⚠️ 新旧固件必须同时支持（灰度期两种设备并存）：靠「Company_ID 之后的剩余长度」区分，
  /// 老包恒为 6 字节(1+4+1)、新包恒为 8 字节(1+6+1)，长度够就**优选**新布局。
  ///
  /// 2026-08-11（同步小程序）：优选布局**解不通时才回退**另一种。原实现是「长度够 8 就只按
  /// 新版解、绝不回退」，理由是「回退会把 Device_ID 的第 5 个字节当成电量，校验碰巧通过就
  /// 静默给出错误的 ID 和电量」——那条约束针对的是「**两种都解得通**时不许回退」；而这里的
  /// 前提是优选布局**已经作废**（屏型不认识或电量 >100），原本整条广播就要丢掉，设备在列表里
  /// 连屏型/电量都没有、也排不进候选。回退出来的结果带 [FrameAdvertising.deviceIdLayoutFallback]
  /// 标记，供上层辨别。
  /// 与小程序 `frame-protocol.js parseAdvertising` 逐条对齐，改一端必须同步另一端。
  static FrameAdvertising? parseAdvertising(List<int> bytes) {
    final companyMatched =
        bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFF;

    FrameAdvertising? attempt(
      int offset,
      int idLength, {
      bool layoutFallback = false,
    }) {
      // 屏型(1) + ID(idLength) + 电量(1)
      if (bytes.length < offset + idLength + 2) return null;
      final screenType = bytes[offset] & 0xFF;
      // 电量紧跟在 Device_ID 之后，位置随 ID 长度浮动
      final battery = bytes[offset + 1 + idLength] & 0xFF;
      final screen = screenTypes[screenType];
      if (screen == null || battery > 100) return null;
      return FrameAdvertising(
        screenType: screenType,
        screen: screen.label,
        model: screen.model,
        deviceId: _bytesToId(bytes, offset + 1, idLength),
        deviceIdComplete: idLength == adDeviceIdLenV2,
        deviceIdLayoutFallback: layoutFallback,
        companyMatched: companyMatched,
        battery: battery,
      );
    }

    FrameAdvertising? attemptAt(int offset) {
      final rest = bytes.length - offset;
      if (rest >= adDeviceIdLenV2 + 2) {
        // 新固件：屏型1 + ID6 + 电量1
        final preferred = attempt(offset, adDeviceIdLenV2);
        if (preferred != null) return preferred;
        // 优选布局解不通（屏型/电量校验没过）→ 这条本来要整个丢掉，此时才试老布局
        if (rest >= adDeviceIdLenV1 + 2) {
          return attempt(offset, adDeviceIdLenV1, layoutFallback: true);
        }
        return null;
      }
      if (rest >= adDeviceIdLenV1 + 2) {
        return attempt(offset, adDeviceIdLenV1); // 老固件：屏型1 + ID4 + 电量1
      }
      return null;
    }

    // 含 Company_ID：前两字节为 0xFF 0xFF，则从第 2 字节起为 Screen_Type
    if (companyMatched) {
      final withId = attemptAt(2);
      if (withId != null) return withId;
    }
    return attemptAt(0);
  }

  /// CMD=0x03 软件版本：ASCII，遇 \0 截断(6.7.5)。
  static String parseSwVer(List<int> data) {
    final sb = StringBuffer();
    for (final c in data) {
      if (c == 0) break;
      sb.writeCharCode(c & 0xFF);
    }
    return sb.toString().trim();
  }

  /// CMD=0x04 电量：1 字节 0~100(6.7.6)。
  static int parseBattery(List<int> data) => data.isNotEmpty ? data[0] & 0xFF : 0;

  /// CMD=0x02 播放配置：PLAY_MODE(1)+INTERVAL(4,小端)(6.7.4)。
  static FramePlayConfig parsePlayConfig(List<int> data) {
    return FramePlayConfig(
      playMode: playModeToString(data.isNotEmpty ? data[0] & 0xFF : 0),
      intervalSeconds: data.length >= 5 ? readUint32LE(data, 1) : 0,
    );
  }

  /// 「带掩码」类应答(0x10 / 0x12)：返回更新后的 12 字节 IMG_MASK。
  static List<int> parseMaskResult(List<int> data) =>
      data.length >= 12 ? data.sublist(0, 12) : List<int>.filled(12, 0);

  /// CMD=0x24 屏幕刷新应答：CUR_IMG_INDEX(1)(6.7.10)。
  static int parseRefreshResult(List<int> data) => data.isNotEmpty ? data[0] & 0xFF : 0xFF;

  /// CMD=0x23 图传应答(6.6.2)：ACK_SEQ(2,小端) = 已连续收到的最后包号。
  static int parseImgAck(List<int> payload) =>
      payload.length >= 2 ? readUint16LE(payload, 0) : -1;

  /// CMD=0x22 结束应答的 data 段(6.8.4)：IMG_MASK(12)+IMG_COUNT(2)+STORAGE_FREE(4)。
  static FrameImgEnd parseImgEndResult(List<int> data) {
    return FrameImgEnd(
      imgMask: data.length >= 12 ? data.sublist(0, 12) : List<int>.filled(12, 0),
      imgCount: data.length >= 14 ? readUint16LE(data, 12) : 0,
      storageFree: data.length >= 18 ? readUint32LE(data, 14) : 0,
    );
  }
}
