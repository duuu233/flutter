/// 硬件序列号(Device_ID)匹配工具 —— 与小程序 `utils/device-id.js` /
/// `utils/active-device.js` 保持一致。
///
/// 背景：广播厂商数据里的 Device_ID 只有 4 字节，连上后读 0x01 得到的是 6 字节，
/// 广播短 ID 只可用于扫描候选筛选；后端记录、活动会话认领、绑定入库和连接后验身
/// 都必须使用 0x01 返回的完整 6 字节 ID。
library;

const int completeDeviceSerialHexLength = 12;

/// 归一化：去分隔符（: - 空格）+ 大写，兼容后端与蓝牙两侧可能的格式差异。
String normalizeSerial(Object? value) {
  if (value == null) return '';
  return value.toString().replaceAll(RegExp(r'[:\-\s]'), '').toUpperCase();
}

/// 是否为可作为稳定物理身份的完整 6 字节 Device_ID。
///
/// 全 0 / 全 F 是固件未初始化或占位值，不得进入稳定身份链路。
bool isCompleteDeviceSerial(Object? value) {
  final serial = normalizeSerial(value);
  return RegExp(r'^[0-9A-F]{12}$').hasMatch(serial) &&
      serial != '000000000000' &&
      serial != 'FFFFFFFFFFFF';
}

/// 完整设备 ID 的统一展示/入库格式；非法或不完整时返回空串。
String canonicalDeviceSerial(Object? value) {
  final serial = normalizeSerial(value);
  if (!isCompleteDeviceSerial(serial)) {
    return '';
  }
  return <String>[
    for (var i = 0; i < serial.length; i += 2) serial.substring(i, i + 2),
  ].join(':');
}

/// 两个序列号是否可能指同一台物理设备，仅供“扫描候选”使用：
///  1) 归一化后完全相等 → 同一台（最可靠：后端 6 字节 deviceId vs 固件 0x01 读到的 6 字节）；
///  2) 长度相同却不相等 → 一定是两台不同设备（含双方都是完整 6 字节），直接否；
///  3) 长度不同（广播 4 字节 8hex vs 固件/后端 6 字节 12hex）→ 只认「短的是长的前缀或后缀」的锚定匹配，
///     不再用任意位置 contains —— 否则两台设备序列号中段偶然重叠 4 字节就被误判成同一台
///     （EF6-370 串到 EF6-589 的根因之一）。
bool serialsMatch(Object? a, Object? b) {
  final left = normalizeSerial(a);
  final right = normalizeSerial(b);
  if (left.isEmpty || right.isEmpty) {
    return false;
  }
  if (left == right) {
    return true;
  }
  if (left.length == right.length) {
    return false;
  }
  final shorter = left.length < right.length ? left : right;
  final longer = left.length < right.length ? right : left;
  if (shorter.length < 8) {
    return false;
  }
  return longer.startsWith(shorter) || longer.endsWith(shorter);
}

/// 广播 Device_ID 与后端记录里的完整 ID 是否**可能**是同一台 —— **只用于筛扫描候选**。
///
/// 2026-08-11（同步小程序 `broadcastCandidateMatch`）：固件把广播 Device_ID 从 4 字节换成
/// 6 字节后，正式入口连不上。根因是 [serialsMatch] 的规则②「长度相同却不相等 → 两台设备」：
/// 老固件是 8hex vs 12hex（长度不同，走前缀/后缀锚定，匹配得上），新固件变成 12hex vs 12hex，
/// 只要广播那 6 字节与 0x01 的写法不完全一致（字节序反过来、或取的是 MAC 的另一段）
/// 就被一票否决 —— **一个候选都筛不出**，扫满 12 秒后报「未搜索到该电子纸设备」。
///
/// 因此候选筛选放宽成两轮，[strongOnly]=true 时只认第一轮：
///  1) **强匹配**：精确相等 / 短的是长的前缀或后缀（老口径）/ 整串**字节序相反**；
///  2) **弱匹配**：4 字节锚段（首 4 / 末 4 字节，正序或倒序）重合。
///
/// ⚠️ 放宽的只是「哪些设备值得连一次看看」，**身份闸一步没让**：连上后照旧 0x01 精确校验
/// （[verifiedDeviceSerialMatch]），不匹配就断开、排除该候选、下一轮重扫。代价是最坏多连错
/// 一次，收益是无论固件把广播 ID 换成哪种写法都还能连上。
/// [serialsMatch] 本身保持严格——它还被活动会话认领用着，那里没有 0x01 兜底。
bool broadcastCandidateMatch(Object? broadcast, Object? record, {bool strongOnly = false}) {
  final left = normalizeSerial(broadcast);
  final right = normalizeSerial(record);
  if (left.isEmpty || right.isEmpty) {
    return false;
  }
  if (serialsMatch(left, right)) {
    return true;
  }
  if (left.length == right.length && left == _reverseBytes(right)) {
    return true; // 整串字节序相反：同一个 MAC，两端读法不同
  }
  if (strongOnly) {
    return false;
  }
  // 弱匹配：4 字节（8 hex）锚段重合。同批设备共享 OUI，前 4 字节可能偶合到邻居，
  // 所以调用方必须先挑强匹配，没有强匹配才用弱匹配（见 BleController.matchScannedDevice）。
  for (final a in _anchors(left)) {
    for (final b in _anchors(right)) {
      if (a == b) {
        return true;
      }
    }
  }
  return false;
}

/// 序列号首尾各 4 字节的锚段（含字节序相反的写法）。
Set<String> _anchors(String serial) {
  const anchorHex = 8; // 4 字节
  if (serial.length < anchorHex) {
    return const <String>{};
  }
  final head = serial.substring(0, anchorHex);
  final tail = serial.substring(serial.length - anchorHex);
  return <String>{head, tail, _reverseBytes(head), _reverseBytes(tail)};
}

/// 按字节翻转一串 hex（`AABBCC` → `CCBBAA`）；长度为奇数时原样返回。
String _reverseBytes(String serial) {
  if (serial.length.isOdd) {
    return serial;
  }
  final buffer = StringBuffer();
  for (var i = serial.length - 2; i >= 0; i -= 2) {
    buffer.write(serial.substring(i, i + 2));
  }
  return buffer.toString();
}

/// 两组稳定设备身份是否指向同一台设备。
///
/// 两侧只取完整 6 字节 ID 并精确比较；广播短 ID 不具备稳定身份资格。
bool serialSetsMatch(Iterable<Object?> a, Iterable<Object?> b) {
  final left = a.where(isCompleteDeviceSerial).map(normalizeSerial).toSet();
  final right = b.where(isCompleteDeviceSerial).map(normalizeSerial).toSet();
  if (left.isEmpty || right.isEmpty) {
    return false;
  }
  return left.any(right.contains);
}

/// 已连接设备的 0x01 完整 ID 是否与用户点击的后端记录一致。
bool verifiedDeviceSerialMatch(Object? expected, Object? actual) {
  if (!isCompleteDeviceSerial(expected) || !isCompleteDeviceSerial(actual)) {
    return false;
  }
  return normalizeSerial(expected) == normalizeSerial(actual);
}

/// 活动会话是否足以认领后端设备记录。
///
/// 目标和会话都必须具有完整 6 字节 ID 且精确相等；广播短 ID 永不参与认领。
bool sessionSerialsMatch(Iterable<Object?> session, Object? expected) {
  if (!isCompleteDeviceSerial(expected)) {
    return false;
  }
  final target = normalizeSerial(expected);
  final serials = session
      .where(isCompleteDeviceSerial)
      .map(normalizeSerial)
      .toSet();
  return serials.contains(target);
}

/// 屏幕型号是否一致（防跨型号串台，对齐小程序 active-device.sameScreen）：
/// 两侧屏幕类型码都已知且不同 → 判为不同型号设备，返回 false；
/// 任一侧未知(0) → 不阻断，回退纯序列号匹配（信息缺失不拦，保持兼容）。
/// 屏幕类型码 = FrameScreenType.code（0x01=3.7寸 / 0x02=5.89寸 / 0x03=7.3寸）或广播里的 int。
bool sameScreenCode(int a, int b) {
  if (a == 0 || b == 0) {
    return true;
  }
  return a == b;
}
