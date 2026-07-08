/// 硬件序列号(Device_ID)匹配工具 —— 由小程序 `utils/active-device.js` 的
/// normalizeSerial / serialsMatch 移植。
///
/// 背景：广播厂商数据里的 Device_ID 只有 4 字节，连上后读 0x01 得到的是 6 字节，
/// 后端存的可能是其中任意一种（还可能带 `:`/`-`/空格分隔符、大小写不一）。
/// 精确相等在「广播 4 字节 vs 后端 6 字节」时必然对不上——匹配已绑定设备必须用
/// 归一化 + 互为子串的容错比对，否则会出现「改名/重扫后连不上、正连着被误判未连接」。

/// 归一化：去分隔符（: - 空格）+ 大写，兼容后端与蓝牙两侧可能的格式差异。
String normalizeSerial(Object? value) {
  if (value == null) return '';
  return value.toString().replaceAll(RegExp(r'[:\-\s]'), '').toUpperCase();
}

/// 两个序列号是否指同一台物理设备：归一化后精确相等，或互为子串（要求两侧都
/// ≥8 个 hex 字符 = 4 字节，避免短串误并）。
bool serialsMatch(Object? a, Object? b) {
  final left = normalizeSerial(a);
  final right = normalizeSerial(b);
  if (left.isEmpty || right.isEmpty) {
    return false;
  }
  return left == right ||
      (left.length >= 8 &&
          right.length >= 8 &&
          (left.contains(right) || right.contains(left)));
}
