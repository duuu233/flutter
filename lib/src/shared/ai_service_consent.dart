import 'package:shared_preferences/shared_preferences.dart';

/// Per-user acceptance cache for the BoltStar AI Service Agreement.
///
/// The agreement version is part of the key so a future material revision can
/// require fresh consent by changing [version]. Persistence failure is treated
/// as not accepted so a missing cache always requires fresh consent.
///
/// 2026-08-13 由 v2 升到 v3：AI 上游供应商由「阿里云百炼 / 阿里云计算有限公司」改为
/// 「火山引擎 / 北京火山引擎科技有限公司」。同意书里的**数据接收方**变了，这正是必须
/// 重新取得同意的那一类实质变更——只改文案不升版，老用户会带着「同意发给阿里云」的
/// 旧记录，端上直接把内容发给另一家公司，且再也不会问他第二次。
class AiServiceConsent {
  AiServiceConsent._();

  static const String version = '2026-08-13-v3';
  static const String _keyPrefix = 'boltstar.aiServiceConsent.$version.';

  static String _normalizeUserId(String userId) => userId.trim();

  static String _keyFor(String userId) =>
      '$_keyPrefix${Uri.encodeComponent(_normalizeUserId(userId))}';

  static Future<bool> isAccepted(String userId) async {
    final normalized = _normalizeUserId(userId);
    if (normalized.isEmpty) {
      return false;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_keyFor(normalized)) ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> accept(String userId) async {
    final normalized = _normalizeUserId(userId);
    if (normalized.isEmpty) {
      return false;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      return await prefs.setBool(_keyFor(normalized), true);
    } catch (_) {
      return false;
    }
  }

  static Future<void> clear(String userId) async {
    final normalized = _normalizeUserId(userId);
    if (normalized.isEmpty) {
      return;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_keyFor(normalized));
    } catch (_) {
      // Account cleanup must not be blocked by a preferences failure.
    }
  }
}
