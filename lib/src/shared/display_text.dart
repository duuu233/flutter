/// 后端文本的展示前归一（移植小程序 `pages/mine/mine.js displayNickname`，2026-07-31）。
///
/// 昵称这类由用户自己输入的字段，历史数据里 emoji 可能被存成**转义串**而不是真实码点：
///
/// ```text
/// "小星\u2728"        ← \uXXXX（BMP 内，如 ✨）
/// "小星\u{1F31F}"     ← \u{XXXXX}（星形平面，如 🌟；emoji 绝大多数在这里）
/// "小星&#127775;"     ← HTML 十进制数字实体
/// "小星&#x1F31F;"     ← HTML 十六进制数字实体
/// ```
///
/// Flutter 的 `Text` 只会把这些原样打出来（用户看到的是一串 `\u{1F31F}`），
/// 所以在**写入展示字段时**解一次码。只处理这四种数字型转义：
/// 具名实体（`&amp;` 等）不解——昵称里出现 `&amp;` 更可能是用户真的打了这几个字符。
String decodeDisplayText(String value) {
  if (value.isEmpty) {
    return value;
  }
  var result = value;
  // \u{1F31F} 形式必须排在 \uXXXX 之前：否则 `\u{1F3` 会先被后者当成 4 位十六进制吃掉。
  result = result.replaceAllMapped(
    RegExp(r'\\u\{([0-9a-fA-F]{1,6})\}'),
    (m) => _fromCodePoint(int.parse(m.group(1)!, radix: 16)) ?? m.group(0)!,
  );
  result = result.replaceAllMapped(
    RegExp(r'\\u([0-9a-fA-F]{4})'),
    (m) => _fromCodePoint(int.parse(m.group(1)!, radix: 16)) ?? m.group(0)!,
  );
  result = result.replaceAllMapped(
    RegExp(r'&#x([0-9a-fA-F]{1,6});'),
    (m) => _fromCodePoint(int.parse(m.group(1)!, radix: 16)) ?? m.group(0)!,
  );
  result = result.replaceAllMapped(
    RegExp(r'&#([0-9]{1,7});'),
    (m) => _fromCodePoint(int.parse(m.group(1)!)) ?? m.group(0)!,
  );
  return result;
}

/// 码点 → 字符串；越界码点返回 null 让调用方原样保留那段文本
/// （`String.fromCharCode` 对 > 0x10FFFF 会抛，昵称解码不该把整页拖崩）。
String? _fromCodePoint(int codePoint) {
  if (codePoint < 0 || codePoint > 0x10FFFF) {
    return null;
  }
  // 代理区（D800–DFFF）单独出现不是合法字符，原样保留。
  if (codePoint >= 0xD800 && codePoint <= 0xDFFF) {
    return null;
  }
  return String.fromCharCode(codePoint);
}
