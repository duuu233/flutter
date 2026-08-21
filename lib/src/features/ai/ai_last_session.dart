/// AI 入口的「上次停在哪一页」记忆（2026-08-13 同步小程序 `utils/ai-last-session.js`）。
///
/// 需求：再次点 AI 入口时接着上次那一页 —— 上次停在某条会话就回**那条会话**，
/// 停在「新对话」空态就仍是空态。判据就是聊天页的 `sessionId`
/// （会话只在**首次发送**时才建，所以「AI 默认页」＝「没有 sessionId」）。
///
/// ⚠️ **只活在内存里，故意不落盘**：AI 会话历史服务端只留 7 天（超期取历史会报错），
/// 跨启动记住一条可能已过期、或已被别的端删掉的会话，用户点进去只会得到一个报错的空聊天页。
/// 内存里这条一定是本次运行刚聊过的，必然还在；重启 App 回落到默认页是可接受的退化。
class AiLastSession {
  AiLastSession._();

  static String _sessionId = '';
  static String _title = '';

  /// 上次停留的会话 ID；空串＝停在默认页（或还没聊过）。
  static String get sessionId => _sessionId;

  /// 上次停留会话的标题（进页面前先顶上，免得标题栏空一下）。
  static String get title => _title;

  /// 记下「用户离开 AI 时停在哪」。空 [sessionId] 表示停在默认页，同样要记
  /// —— 否则用户从会话退回默认页再离开，下次又被带回那条旧会话。
  static void remember({required String sessionId, String title = ''}) {
    _sessionId = sessionId;
    _title = sessionId.isEmpty ? '' : title;
  }

  /// 会话在列表页被删除时清掉指向它的记忆，否则下次点 AI 会打开一条已删会话。
  /// 只清**指向它**的那条：别的会话的记忆与这次删除无关。
  static void forget(String sessionId) {
    if (sessionId.isNotEmpty && _sessionId == sessionId) {
      _sessionId = '';
      _title = '';
    }
  }

  /// 退出登录 / 换账号：记忆属于上一个用户，必须清干净。
  static void clear() {
    _sessionId = '';
    _title = '';
  }
}
