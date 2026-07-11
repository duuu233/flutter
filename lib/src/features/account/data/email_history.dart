import 'package:shared_preferences/shared_preferences.dart';

/// 用户登录邮箱历史缓存（本地持久化，`shared_preferences`）。
///
/// 登录/注册成功后记住用户输入过的邮箱；下次进入登录页自动填充最近一个，
/// 便于回访用户免于重复输入。最近使用的排在最前，最多保留 [_maxCount] 个。
class EmailHistory {
  EmailHistory._();

  static const String _key = 'login_email_history';
  static const int _maxCount = 8;

  /// 记住一个用户输入过的邮箱（大小写不敏感去重、置顶、限量）。空串忽略。
  static Future<void> add(String email) async {
    final value = email.trim();
    if (value.isEmpty) {
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_key) ?? <String>[];
    list.removeWhere((e) => e.toLowerCase() == value.toLowerCase());
    list.insert(0, value);
    if (list.length > _maxCount) {
      list.removeRange(_maxCount, list.length);
    }
    await prefs.setStringList(_key, list);
  }

  /// 取历史邮箱（最近使用在前）。无则空列表。
  static Future<List<String>> recent() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_key) ?? <String>[];
  }

  /// 最近使用的一个邮箱（无则空串），用于登录页自动填充。
  static Future<String> latest() async {
    final list = await recent();
    return list.isEmpty ? '' : list.first;
  }
}
