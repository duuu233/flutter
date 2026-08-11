import 'package:shared_preferences/shared_preferences.dart';

/// AI Token 余额（**演示逻辑**）——支付体系（Java 后端）未接，先用本地存储模拟
/// 「余额展示 + 每次对话扣 1 + 不足拦截」。接入真实接口后只改本文件的 [readBalance] /
/// [spend]，页面侧无需改动。
///
/// 2026-08-10 从 `ai_chat_page.dart` 提取成公共模块（对齐小程序 `utils/ai-token.js`）：
/// 会话列表页顶部也要显示同一份余额（需求 1.1），常量再复制一份必然会漂。
///
/// ## [limitEnabled] = false（对齐小程序 2026-08-03 的口径）
/// 余额是本地假的、支付又没上线，扣满 [defaultBalance] 次就再也发不出消息，纯粹卡住体验/测试
/// —— App 侧此前一直开着，等于埋着「聊满 100 次就永久发不出消息」。关掉后：不扣费、不拦截，
/// 余额恒显示 [defaultBalance]（storage 里可能留着历史扣到 0 的旧值，一并忽略，否则会显示
/// 0 Token 像坏了）。接后端时把它改回 true，其余逻辑原样还在。
class AiToken {
  const AiToken._();

  static const String prefsKey = 'aiTokenBalanceDemo';
  static const int defaultBalance = 100;
  static const bool limitEnabled = false;

  static Future<int> readBalance() async {
    if (!limitEnabled) {
      return defaultBalance;
    }
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(prefsKey) ?? defaultBalance;
  }

  /// 扣 1 并落盘，返回扣完的余额。限制关闭时是空操作（返回传入值，调用方不必判分支）。
  static Future<int> spend(int current) async {
    if (!limitEnabled) {
      return current;
    }
    final balance = (current - 1).clamp(0, 1 << 30);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(prefsKey, balance);
    return balance;
  }
}
