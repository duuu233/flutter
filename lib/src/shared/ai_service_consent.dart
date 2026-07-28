import 'package:shared_preferences/shared_preferences.dart';

/// Per-user acceptance cache for the BoltStar AI Service Agreement.
///
/// The agreement version is part of the key so a future material revision can
/// require fresh consent by changing [version]. Persistence failure is treated
/// as not accepted so a missing cache always requires fresh consent.
class AiServiceConsent {
  AiServiceConsent._();

  static const String version = '2026-07-28-v2';
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
