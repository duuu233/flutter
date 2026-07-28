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
