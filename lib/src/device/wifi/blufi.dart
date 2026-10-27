import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

/// BluFi（乐鑫 ESP32 蓝牙配网）协议与会话，同步小程序 `utils/blufi.js`（改一端必须同步另一端）。
///
/// 设备与手机的蓝牙通信只在配网阶段使用，消息格式以乐鑫官方 BluFi（EspBlufi demo）为基线：
///   服务 0xFFFF；手机写 0xFF01，设备通知 0xFF02（与蓝牙版 FF00 主服务下的 FF01/FF02 同名不同服务，
///   这里只认 FFFF 服务下的特征）。
///
/// 帧格式：type(1) | frameCtrl(1) | seq(1) | dataLen(1) | data(dataLen) | [checksum(2)]
///   · type 低 2 位：0 控制帧 / 1 数据帧；高 6 位：子类型；
///   · frameCtrl：bit0 加密、bit1 校验、bit2 方向（1=设备→手机）、bit3 要求应答、bit4 分片；
///   · seq：手机发出的每一帧递增（每条连接从 0 开始，设备按序校验，错一个整条会话作废）；
///   · 分片：带 bit4 的帧 data 前 2 字节是「剩余总长度」（小端），设备按首片的长度收齐。
///
/// 本期不做安全协商（DH + AES，产品确认先不加密），也不加校验：与 EspBlufi 未协商时的行为一致，
/// WiFi 密码以明文经蓝牙下发。固件若强制加密，需在这里补 DH 协商。
///
/// 自定义数据（数据帧子类型 0x13）承载协议文档 2.2 的 JSON 消息（如 mqtt_config / mqtt_config_ack）。
///
/// 设备扫描附近 WiFi：手机发控制帧 0x09，设备扫描后回列表。两种回法都认：
///   · 乐鑫标准：数据帧 0x11，每项 len(1) | rssi(1，有符号 dBm) | ssid(len-1)，没有信道；
///   · **本设备实测**：自定义数据 0x13，文本每行一条 `ssid:<名称>,rssi:<dBm>,ch:<信道>`，带信道，
///     且扫得到 5G（设备是双频芯片），据此只留 2.4G（ch 1~14）。
abstract final class Blufi {
  static const String serviceUuid = 'FFFF';
  static const String writeUuid = 'FF01';
  static const String notifyUuid = 'FF02';

  static const int frameCtrl = 0;
  static const int frameData = 1;

  // 控制帧子类型
  static const int ctrlAck = 0x00;
  static const int ctrlSetOpmode = 0x02;
  static const int ctrlConnectWifi = 0x03;
  static const int ctrlGetWifiStatus = 0x05;
  static const int ctrlGetWifiList = 0x09;

  // 数据帧子类型
  static const int dataStaSsid = 0x02;
  static const int dataStaPassword = 0x03;
  static const int dataWifiState = 0x0f;
  static const int dataWifiList = 0x11;
  static const int dataError = 0x12;
  static const int dataCustom = 0x13;
  static const int dataStaEndReason = 0x15;
  static const int dataStaRssi = 0x16;

  // frameCtrl 位
  static const int fcEncrypted = 0x01;
  static const int fcChecksum = 0x02;
  static const int fcDirDevice = 0x04;
  static const int fcRequireAck = 0x08;
  static const int fcFrag = 0x10;

  static const int opmodeSta = 0x01;

  /// 默认 MTU 23 时单帧最多 20 字节；协商到更大 MTU 后按 MTU-3 算，帧内 data 最多 255。
  static const int defaultFrameLimit = 20;
  static const int headerLength = 4;

  /// 收到一批 WiFi 列表后再等这么久没有新的一批，才算扫描结束（设备可能分几条回；产品要求别太快收掉）。
  static const Duration wifiListQuiet = Duration(seconds: 5);

  /// 设备报错（数据帧 0x12）的错误码，按乐鑫 ESP-IDF `esp_blufi_error_state_t`。
  static const Map<int, String> _errorText = {
    0: '序号错误',
    1: '校验错误',
    2: '解密错误',
    3: '加密错误',
    4: '安全初始化错误',
    5: 'DH 内存分配错误',
    6: 'DH 参数错误',
    7: '读取参数错误',
    8: '生成公钥错误',
    9: '数据格式错误',
    10: 'MD5 计算错误',
    11: 'WiFi 扫描失败',
    12: '消息状态错误',
  };

  /// 错误码原文（中文，只进日志与联调提示；给用户的文案由页面按语言另给）。
  static String errorText(int code) => _errorText[code] ?? '未知错误';

  /// 信道 → 中心频率（MHz）：2.4G 1~13 为 2407+5×ch、14 为 2484；5G 为 5000+5×ch。
  static int channelFrequency(int channel) {
    if (channel <= 0) return 0;
    if (channel == 14) return 2484;
    return channel < 14 ? 2407 + 5 * channel : 5000 + 5 * channel;
  }

  /// 2.4G 信道 1~14；信道未知（乐鑫标准格式不带）返回 null，由调用方决定。
  static bool? is24GChannel(int? channel) {
    if (channel == null) return null;
    return channel >= 1 && channel <= 14;
  }

  static int typeByte(bool isData, int subtype) =>
      ((subtype & 0x3f) << 2) | (isData ? frameData : frameCtrl);

  /// 把一条消息编成若干帧（必要时分片）。[seqStart]：第一帧的序号；[frameLimit]：单帧最大字节数（MTU-3）。
  /// 第 i 帧的序号是 seqStart + i（按 256 回绕）。
  static List<Uint8List> encodeFrames(
    bool isData,
    int subtype,
    List<int> payload,
    int seqStart, [
    int frameLimit = defaultFrameLimit,
  ]) {
    final maxData = math.min(255, math.max(headerLength + 2, frameLimit - headerLength));
    final type = typeByte(isData, subtype);
    final frames = <Uint8List>[];
    void build(int fc, List<int> data) {
      final seq = (seqStart + frames.length) & 0xff;
      frames.add(Uint8List.fromList([type, fc, seq, data.length, ...data]));
    }

    if (payload.length <= maxData) {
      build(0, payload);
      return frames;
    }
    var offset = 0;
    while (offset < payload.length) {
      final remain = payload.length - offset;
      if (remain <= maxData) {
        build(0, payload.sublist(offset));
        break;
      }
      final chunk = maxData - 2;
      build(fcFrag, [
        remain & 0xff,
        (remain >> 8) & 0xff,
        ...payload.sublist(offset, offset + chunk),
      ]);
      offset += chunk;
    }
    return frames;
  }

  /// 手机发出的帧里带密码的两类：WiFi 密码（数据帧 STA_PASSWORD）和自定义数据（mqtt_config 含 MQTT 密码）。
  /// 这两类帧的原始字节不交给任何日志（返回空串），日志从源头就拿不到密码。
  static String txFrameHex(bool isData, int subtype, List<int> bytes) {
    if (isData && (subtype == dataStaPassword || subtype == dataCustom)) {
      return '';
    }
    return toHex(bytes);
  }

  static String toHex(List<int> bytes) => bytes
      .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
      .join(' ');

  static String utf8Decode(List<int> bytes) => utf8.decode(bytes, allowMalformed: true);

  /// WiFi 连接状态报告：opmode | staState | softapConnNum | TLV(type, len, value)…
  static BlufiWifiState parseWifiState(List<int> bytes) {
    var ssid = '';
    int? endReason;
    int? rssi;
    var i = 3;
    while (i + 1 < bytes.length) {
      final type = bytes[i];
      final len = bytes[i + 1];
      final end = math.min(bytes.length, i + 2 + len);
      final value = bytes.sublist(i + 2, end);
      if (type == dataStaSsid) {
        ssid = utf8Decode(value);
      } else if (type == dataStaEndReason && value.isNotEmpty) {
        endReason = value[0];
      } else if (type == dataStaRssi && value.isNotEmpty) {
        rssi = value[0] > 127 ? value[0] - 256 : value[0];
      }
      i += 2 + len;
    }
    return BlufiWifiState(
      opmode: bytes.isNotEmpty ? bytes[0] : -1,
      staState: bytes.length > 1 ? bytes[1] : -1,
      ssid: ssid,
      endReason: endReason,
      rssi: rssi,
    );
  }

  /// 乐鑫标准 WiFi 列表：len | rssi | ssid(len-1) 依次排列。长度不合法的残尾丢弃。没有信道。
  static List<BlufiWifi> parseWifiList(List<int> bytes) {
    final list = <BlufiWifi>[];
    var i = 0;
    while (i < bytes.length) {
      final len = bytes[i];
      if (len == 0 || i + 1 + len > bytes.length) {
        break;
      }
      final rssi = bytes[i + 1] > 127 ? bytes[i + 1] - 256 : bytes[i + 1];
      list.add(BlufiWifi(ssid: utf8Decode(bytes.sublist(i + 2, i + 1 + len)), rssi: rssi));
      i += 1 + len;
    }
    return list;
  }

  static final RegExp _customWifiLine = RegExp(
    r'^\s*ssid:(.*),rssi:(-?\d+),ch:(\d+)\s*$',
    caseSensitive: false,
  );

  /// 本设备用自定义数据（0x13）回的 WiFi 列表：每行 `ssid:<名称>,rssi:<dBm>,ch:<信道>`。
  /// 名称里可能带逗号，所以从行尾往前认 rssi / ch；名称为空的是隐藏网络。认不出的行忽略。
  static List<BlufiWifi> parseCustomWifiList(String text) {
    final list = <BlufiWifi>[];
    for (final line in text.split(RegExp(r'\r?\n'))) {
      final match = _customWifiLine.firstMatch(line);
      if (match == null) continue;
      list.add(
        BlufiWifi(
          ssid: match.group(1)!,
          rssi: int.parse(match.group(2)!),
          channel: int.parse(match.group(3)!),
        ),
      );
    }
    return list;
  }

  /// 自定义数据里的 JSON 消息。协议文档表格写的是 date / ack_msg id，示例写的是 data / ack_msgid，两种都认。
  static BlufiCustom parseCustom(List<int> bytes) {
    final text = utf8Decode(bytes);
    Object? json;
    try {
      json = jsonDecode(text);
    } catch (_) {
      json = null;
    }
    if (json is! Map) {
      return BlufiCustom(text: text);
    }
    final raw = json['data'] ?? json['date'];
    final body = raw is Map
        ? raw.map((k, v) => MapEntry(k.toString(), v))
        : <String, dynamic>{};
    return BlufiCustom(
      text: text,
      action: (json['action'] ?? '').toString(),
      body: body,
      ackMsgid: (body['ack_msgid'] ?? body['ackMsgid'] ?? body['ack_msg_id'] ?? '').toString(),
    );
  }

  /// 自定义消息的 msgid：13 位毫秒 + 3 位随机，共 16 位（设备入网流程 3.1），设备回执原样放进 ack_msgid。
  static String newMsgid() =>
      '${DateTime.now().millisecondsSinceEpoch}${math.Random().nextInt(1000).toString().padLeft(3, '0')}';

  static String _short16(String uuid) {
    final s = uuid.replaceAll('-', '').toUpperCase();
    if (s.length <= 4) return s.padLeft(4, '0');
    if (s.length >= 8) return s.substring(4, 8);
    return s.substring(s.length - 4);
  }

  static final Map<String, BlufiSession> _sessions = <String, BlufiSession>{};

  /// 建立 BluFi 会话：连接 → 找 FFFF 服务与 FF01/FF02 → 打开通知 → 协商 MTU。
  /// 同一台已有可用会话直接复用（搜索页连上 → WiFi 列表页扫描 → 配网下发，同一会话、序号连续）。
  static Future<BlufiSession> connect(String remoteId) async {
    if (remoteId.isEmpty) {
      throw const BlufiException('缺少设备蓝牙标识');
    }
    final existing = _sessions[remoteId];
    if (existing != null && !existing.closed && existing.device.isConnected) {
      return existing;
    }
    _sessions.remove(remoteId);
    final device = BluetoothDevice.fromId(remoteId);
    try {
      if (!device.isConnected) {
        await device.connect(
          license: License.nonprofit,
          timeout: const Duration(seconds: 10),
          mtu: null,
        );
      }
    } catch (error) {
      // 失败先把半开的连接收掉再抛
      try {
        await device.disconnect();
      } catch (_) {}
      rethrow;
    }
    try {
      final session = await BlufiSession._setup(device);
      _sessions[remoteId] = session;
      return session;
    } catch (error) {
      // 半路失败：断开，别让一条半开的连接占着设备（设备被占时不广播，重试会搜不到）
      try {
        await device.disconnect();
      } catch (_) {}
      rethrow;
    }
  }

  /// 释放某台设备的会话（离开配网流程时）。
  static Future<void> release(String remoteId) async {
    await _sessions.remove(remoteId)?.close();
  }
}

class BlufiException implements Exception {
  const BlufiException(this.message, {this.code});

  final String message;

  /// 设备错误码（数据帧 0x12）/ `DISCONNECTED` / null（写指令等本地失败）。
  final Object? code;

  @override
  String toString() => 'BlufiException($code, $message)';
}

class BlufiWifi {
  const BlufiWifi({required this.ssid, required this.rssi, this.channel});

  final String ssid;
  final int rssi;

  /// 信道（本设备自定义格式才有；乐鑫标准格式为 null）。
  final int? channel;
}

class BlufiWifiState {
  const BlufiWifiState({
    required this.opmode,
    required this.staState,
    this.ssid = '',
    this.endReason,
    this.rssi,
  });

  final int opmode;
  final int staState;
  final String ssid;
  final int? endReason;
  final int? rssi;
}

class BlufiCustom {
  const BlufiCustom({
    required this.text,
    this.action = '',
    this.body = const <String, dynamic>{},
    this.ackMsgid = '',
  });

  final String text;
  final String action;
  final Map<String, dynamic> body;
  final String ackMsgid;
}

/// 一条 BluFi 会话。手机发出的帧串行发送（序号必须严格按发出顺序递增）。
class BlufiSession {
  BlufiSession._(this.device, this._write, this._notify);

  final BluetoothDevice device;
  final BluetoothCharacteristic _write;
  final BluetoothCharacteristic _notify;

  int _seq = 0;
  int frameLimit = Blufi.defaultFrameLimit;
  bool closed = false;
  Future<void> _sending = Future<void>.value();
  List<int>? _pending;

  StreamSubscription<List<int>>? _notifySub;
  StreamSubscription<BluetoothConnectionState>? _connSub;

  final StreamController<List<BlufiWifi>> _wifiLists = StreamController<List<BlufiWifi>>.broadcast();
  final StreamController<BlufiCustom> _customs = StreamController<BlufiCustom>.broadcast();
  final StreamController<BlufiException> _errors = StreamController<BlufiException>.broadcast();
  final StreamController<BlufiWifiState> _wifiStates = StreamController<BlufiWifiState>.broadcast();
  final Completer<void> _disconnected = Completer<void>();

  Stream<BlufiWifiState> get wifiStates => _wifiStates.stream;

  static const Duration _writeGap = Duration(milliseconds: 20);

  static Future<BlufiSession> _setup(BluetoothDevice device) async {
    BluetoothCharacteristic? write;
    BluetoothCharacteristic? notify;
    // 安卓上连接成功后服务常常还没就绪，多试几次
    for (var attempt = 0; attempt < 6 && (write == null || notify == null); attempt++) {
      try {
        final services = await device.discoverServices();
        for (final service in services) {
          if (Blufi._short16(service.uuid.str) != Blufi.serviceUuid) continue;
          for (final c in service.characteristics) {
            final code = Blufi._short16(c.uuid.str);
            if (code == Blufi.writeUuid) write = c;
            if (code == Blufi.notifyUuid) notify = c;
          }
        }
      } catch (_) {
        // 下一轮再试
      }
      if (write == null || notify == null) {
        await Future<void>.delayed(const Duration(milliseconds: 300));
      }
    }
    if (write == null || notify == null) {
      throw const BlufiException('未找到设备的配网服务');
    }
    final session = BlufiSession._(device, write, notify);
    session._connSub = device.connectionState.listen((state) {
      if (state == BluetoothConnectionState.disconnected) {
        session._markClosed();
      }
    });
    await notify.setNotifyValue(true);
    session._notifySub = notify.onValueReceived.listen(session._onNotify);
    session.frameLimit = await _negotiateFrameLimit(device);
    return session;
  }

  static Future<int> _negotiateFrameLimit(BluetoothDevice device) async {
    var mtu = 0;
    if (Platform.isAndroid) {
      try {
        mtu = await device.requestMtu(247);
      } catch (_) {
        mtu = device.mtuNow;
      }
    } else {
      // iOS 不支持手动设置，读系统协商结果（初值 23 时稍等它上报）
      mtu = device.mtuNow;
      for (var i = 0; i < 10 && mtu <= 23; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        mtu = device.mtuNow;
      }
    }
    return mtu >= 23 ? mtu - 3 : Blufi.defaultFrameLimit;
  }

  void _markClosed() {
    if (closed) return;
    closed = true;
    Blufi._sessions.removeWhere((_, value) => identical(value, this));
    if (!_disconnected.isCompleted) {
      _disconnected.complete();
    }
    unawaited(_notifySub?.cancel());
    unawaited(_connSub?.cancel());
  }

  void _onNotify(List<int> raw) {
    if (raw.length < Blufi.headerLength) return;
    final type = raw[0];
    final fc = raw[1];
    final length = raw[3];
    final end = math.min(raw.length, Blufi.headerLength + length);
    var data = raw.sublist(Blufi.headerLength, end);
    final isData = (type & 0x03) == Blufi.frameData;
    final subtype = type >> 2;
    if ((fc & Blufi.fcEncrypted) != 0) {
      // 本期不协商密钥，设备不该发加密帧；收到就当作无法解析
      _errors.add(const BlufiException('设备要求加密通信，当前版本暂不支持', code: -1));
      return;
    }
    if ((fc & Blufi.fcFrag) != 0) {
      _pending = [...?_pending, ...data.skip(2)];
      return;
    }
    final pending = _pending;
    if (pending != null) {
      data = [...pending, ...data];
      _pending = null;
    }
    if (!isData) {
      return; // 控制帧（ACK 等）配网流程不需要处理
    }
    if (subtype == Blufi.dataWifiList) {
      final list = Blufi.parseWifiList(data);
      debugPrint('[BluFi] 设备扫描到 WiFi ${list.length} 个');
      _wifiLists.add(list);
    } else if (subtype == Blufi.dataWifiState) {
      _wifiStates.add(Blufi.parseWifiState(data));
    } else if (subtype == Blufi.dataCustom) {
      final custom = Blufi.parseCustom(data);
      _customs.add(custom);
      // 本设备的 WiFi 列表走自定义数据（文本行），认得出就按 WiFi 列表发出去
      final wifi = Blufi.parseCustomWifiList(custom.text);
      if (wifi.isNotEmpty) {
        _wifiLists.add(wifi);
      }
    } else if (subtype == Blufi.dataError) {
      final code = data.isNotEmpty ? data[0] : -1;
      debugPrint('[BluFi] 设备报错 $code ${Blufi.errorText(code)}');
      _errors.add(BlufiException('设备返回错误 $code：${Blufi.errorText(code)}', code: code));
    }
  }

  Future<void> _writeFrames(bool isData, int subtype, List<int> payload) {
    // 串行发送：序号必须严格按发出顺序递增，并发写会让设备收到乱序帧
    final run = _sending.then((_) async {
      if (closed) {
        throw const BlufiException('设备蓝牙连接已断开', code: 'DISCONNECTED');
      }
      final frames = Blufi.encodeFrames(isData, subtype, payload, _seq, frameLimit);
      final withoutResponse =
          !_write.properties.write && _write.properties.writeWithoutResponse;
      for (final frame in frames) {
        await _write.write(frame, withoutResponse: withoutResponse);
        _seq = (_seq + 1) & 0xff;
        await Future<void>.delayed(_writeGap);
      }
    });
    _sending = run.catchError((Object _) {});
    return run;
  }

  /// 下发 WiFi：STA 模式 → SSID → 密码（EspBlufi 配网顺序）。
  Future<void> configureSta(String ssid, String password) async {
    await _writeFrames(false, Blufi.ctrlSetOpmode, const [Blufi.opmodeSta]);
    await _writeFrames(true, Blufi.dataStaSsid, utf8.encode(ssid));
    await _writeFrames(true, Blufi.dataStaPassword, utf8.encode(password));
  }

  /// 让设备用已下发的 WiFi 去连接（之后设备退出配网，不再接收蓝牙指令）。
  Future<void> connectWifi() => _writeFrames(false, Blufi.ctrlConnectWifi, const []);

  Future<void> requestWifiStatus() => _writeFrames(false, Blufi.ctrlGetWifiStatus, const []);

  /// 让设备扫描附近 WiFi：先把设备切到 STA 模式（设备 WiFi 没起在 STA 时乐鑫的扫描会直接失败），再发 0x09。
  ///   · 设备可能分几批回，每到一批回调 [onBatch](累计列表)，页面边收边显示；
  ///   · 收到一批后 [Blufi.wifiListQuiet]（5 秒）内没有新的一批才算结束，返回累计列表；
  ///   · 还没收到任何一批时：设备报错 / 蓝牙断开 → 抛 [BlufiException]；
  ///     已经收到过列表后的报错只记日志、断开则直接用已收到的结束；
  ///   · 总超时 [timeout]：有收到就用收到的，一条没有返回 null。
  Future<List<BlufiWifi>?> scanWifi(
    Duration timeout, {
    void Function(List<BlufiWifi> all)? onBatch,
  }) async {
    final collected = <BlufiWifi>[];
    final done = Completer<List<BlufiWifi>?>();
    // 写扫描指令失败时没人等 done：先挂一个空监听，免得之后的断开 / 报错变成未处理的异步异常
    unawaited(done.future.then<void>((_) {}, onError: (Object _) {}));
    void settle() {
      if (!done.isCompleted) {
        done.complete(collected.isEmpty ? null : List<BlufiWifi>.from(collected));
      }
    }

    void fail(BlufiException error) {
      if (!done.isCompleted) {
        done.completeError(error);
      }
    }

    Timer? quiet;
    final subs = <StreamSubscription<Object>>[
      _wifiLists.stream.listen((list) {
        collected.addAll(list);
        if (onBatch != null) {
          try {
            onBatch(List<BlufiWifi>.from(collected));
          } catch (_) {}
        }
        quiet?.cancel();
        quiet = Timer(Blufi.wifiListQuiet, settle);
      }),
      _errors.stream.listen((error) {
        if (collected.isEmpty) fail(error);
      }),
    ];
    unawaited(
      _disconnected.future.then((_) {
        if (collected.isNotEmpty) {
          settle();
        } else {
          fail(const BlufiException('设备断开了蓝牙连接', code: 'DISCONNECTED'));
        }
      }),
    );
    final overall = Timer(timeout, settle);
    try {
      await _writeFrames(false, Blufi.ctrlSetOpmode, const [Blufi.opmodeSta]);
      await _writeFrames(false, Blufi.ctrlGetWifiList, const []);
      return await done.future;
    } finally {
      quiet?.cancel();
      overall.cancel();
      for (final sub in subs) {
        unawaited(sub.cancel());
      }
    }
  }

  /// 协议 2.2 的 JSON 指令：发 `{ msgid, action, data }`，等 `${action}_ack`（按 ack_msgid 对上；设备没回
  /// ack_msgid 时按 action 认）。重试必须换新的 msgid（设备入网流程 2.2）。超时抛错。返回应答的 data（含 result）。
  Future<Map<String, dynamic>> request(
    String action,
    Map<String, Object?> data, {
    Duration timeout = const Duration(seconds: 10),
    String? msgid,
  }) async {
    final id = msgid ?? Blufi.newMsgid();
    final reply = Completer<BlufiCustom?>();
    final sub = _customs.stream.listen((message) {
      if (message.action == '${action}_ack' &&
          (message.ackMsgid.isEmpty || message.ackMsgid == id) &&
          !reply.isCompleted) {
        reply.complete(message);
      }
    });
    final timer = Timer(timeout, () {
      if (!reply.isCompleted) reply.complete(null);
    });
    try {
      await _writeFrames(
        true,
        Blufi.dataCustom,
        utf8.encode(jsonEncode({'msgid': id, 'action': action, 'data': data})),
      );
      final message = await reply.future;
      if (message == null) {
        throw BlufiException('设备未应答 $action');
      }
      return message.body;
    } finally {
      timer.cancel();
      unawaited(sub.cancel());
    }
  }

  Future<void> close() async {
    if (closed) return;
    _markClosed();
    try {
      await device.disconnect();
    } catch (_) {}
  }
}
