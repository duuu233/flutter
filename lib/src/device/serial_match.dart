/// 硬件序列号(Device_ID)匹配工具 —— 由小程序 `utils/active-device.js` 的
/// normalizeSerial / serialsMatch 移植。
///
/// 背景：广播厂商数据里的 Device_ID 只有 4 字节，连上后读 0x01 得到的是 6 字节，
/// 后端存的可能是其中任意一种（还可能带 `:`/`-`/空格分隔符、大小写不一）。
/// 精确相等在「广播 4 字节 vs 后端 6 字节」时必然对不上——匹配已绑定设备必须用
/// 归一化 + 互为子串的容错比对，否则会出现「改名/重扫后连不上、正连着被误判未连接」。
library;

/// 归一化：去分隔符（: - 空格）+ 大写，兼容后端与蓝牙两侧可能的格式差异。
String normalizeSerial(Object? value) {
  if (value == null) return '';
  return value.toString().replaceAll(RegExp(r'[:\-\s]'), '').toUpperCase();
}

/// 两个序列号是否指同一台物理设备（2026-07-09 收紧，防跨型号串台）：
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

/// 多来源序列号集合是否指向同一台设备。
///
/// 广播短 ID 可能在两台同批次设备之间重复，因此两侧若存在相同长度的 ID，
/// 只比较最长的共同长度并要求精确相等；不能因为又共享一个短 ID 就放行。
bool serialSetsMatch(Iterable<Object?> a, Iterable<Object?> b) {
  final left = a
      .map(normalizeSerial)
      .where((value) => value.isNotEmpty)
      .toSet();
  final right = b
      .map(normalizeSerial)
      .where((value) => value.isNotEmpty)
      .toSet();
  if (left.isEmpty || right.isEmpty) {
    return false;
  }
  final commonLengths = left
      .map((value) => value.length)
      .where((length) => right.any((value) => value.length == length))
      .toList();
  if (commonLengths.isNotEmpty) {
    final longest = commonLengths.reduce((a, b) => a > b ? a : b);
    final expected = left.where((value) => value.length == longest).toSet();
    return right.any(
      (value) => value.length == longest && expected.contains(value),
    );
  }
  return left.any((x) => right.any((y) => serialsMatch(x, y)));
}

/// 已连接设备的 0x01 完整 ID 是否与用户点击的后端记录一致。
///
/// 后端已有 6 字节完整 ID 时必须精确相等；只有后端本身仅保存广播短 ID 的
/// 兼容记录，才允许短 ID 与完整 ID 做前/后缀锚定。
bool verifiedDeviceSerialMatch(Object? expected, Object? actual) {
  final left = normalizeSerial(expected);
  final right = normalizeSerial(actual);
  if (left.isEmpty || right.isEmpty) {
    return false;
  }
  if (left.length >= 12) {
    return left == right;
  }
  return serialsMatch(left, right);
}

/// 活动会话是否足以认领后端设备记录。后端为完整 ID 时，会话必须也登记到
/// 0x01 完整 ID 且精确相等，不能仅凭双方共享的广播短 ID 复用会话。
bool sessionSerialsMatch(Iterable<Object?> session, Object? expected) {
  final target = normalizeSerial(expected);
  final serials = session
      .map(normalizeSerial)
      .where((value) => value.isNotEmpty)
      .toSet();
  if (target.isEmpty || serials.isEmpty) {
    return false;
  }
  if (target.length >= 12) {
    return serials.any((value) => value.length >= 12 && value == target);
  }
  return serials.any((value) => serialsMatch(value, target));
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
