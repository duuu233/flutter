import 'dart:convert';

import 'package:crypto/crypto.dart';

/// 敏感字段（密码等）统一 md5(32 位小写十六进制) 后再传输，
/// 与小程序 `utils/md5.js` 的 `md5(password)` 完全一致。
///
/// 后端账号体系里的密码由小程序 `changeUserEmail` 以 md5 存储，
/// 故 App 的 登录/注册/重置/改邮箱 也必须先 md5 再发送，否则与小程序互不相通。
String md5Hex(String input) {
  return md5.convert(utf8.encode(input)).toString();
}
