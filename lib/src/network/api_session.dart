import 'package:shared_preferences/shared_preferences.dart';

import '../state.dart';

/// 运行期会话状态：登录 token 与语言码。
///
/// [ApiClient] 在发起请求时从这里读取公共 header
/// （`userToken` / `jwtToken` / `language` / `device`）。
/// 登录成功后调用 [setTokens]；退出登录 / 注销 / 鉴权失效时调用 [clear]。
///
/// token 同步持久化到本地（shared_preferences）：Android 后台进程被系统回收后
/// 冷启动是常态（尤其国产 ROM 切出后一分钟内就可能杀进程），登录态必须跨进程存活，
/// 否则表现为「切出去一会儿回来就要重新登录」。冷启动经 [restore] 读回。
class ApiSession {
  ApiSession._();

  static final ApiSession instance = ApiSession._();

  static const String _tokenPrefsKey = 'boltstar.userToken';
  static const String _jwtTokenPrefsKey = 'boltstar.jwtToken';

  /// 业务 token，继续用于 `userToken` 公共参数与兼容的 Authorization 头。
  String _userToken = '';

  /// 登录接口返回的 JWT，仅用于 `Authentication: Bearer <jwtToken>`。
  String _jwtToken = '';

  /// 持久化写串行队列：setTokens/clear 是同步接口，落盘异步执行；
  /// 链式排队保证「先 set 后 clear」这类快速连续调用不会乱序落盘。
  Future<void> _persistQueue = Future<void>.value();

  /// 语言码：en=1、zh-Hans=2、zh-Hant=3、ja=4。默认简体中文。
  int _languageCode = 2;

  /// 当前应用语言（枚举形态）：供无 BuildContext 的网络层取本地化兜底文案。
  AppLanguage _language = AppLanguage.zh;

  /// 设备型号，用于 `device` header，可选。
  String device = '';

  String get userToken => _userToken;

  String get jwtToken => _jwtToken;

  int get languageCode => _languageCode;

  AppLanguage get language => _language;

  bool get isLoggedIn => _userToken.isNotEmpty && _jwtToken.isNotEmpty;

  void setTokens({required String userToken, required String jwtToken}) {
    _userToken = userToken;
    _jwtToken = jwtToken;
    _enqueuePersist(userToken, jwtToken);
  }

  void clear() {
    _userToken = '';
    _jwtToken = '';
    _enqueuePersist('', '');
  }

  /// 冷启动恢复持久化的登录凭证。两个 token 必须同时存在才是有效会话；
  /// 仅有旧版 userToken 的半会话会被清理并要求用户重新登录。
  /// 读失败按未登录处理——宁可让用户重登一次，不能让启动流程卡死。
  Future<bool> restore() async {
    // 先排空落盘队列：若 restore 前已有 setToken/clear 在途，直接读磁盘会拿到旧值
    // 并覆盖内存新 token。当前 UI 时序（登录页在 restore 完成后才可达）恰好保护了
    // 这一点，但不应依赖 UI 时序。
    await _persistQueue;
    try {
      final prefs = await SharedPreferences.getInstance();
      _userToken = prefs.getString(_tokenPrefsKey) ?? '';
      _jwtToken = prefs.getString(_jwtTokenPrefsKey) ?? '';
      if (!isLoggedIn) {
        _userToken = '';
        _jwtToken = '';
        await prefs.remove(_tokenPrefsKey);
        await prefs.remove(_jwtTokenPrefsKey);
      }
    } catch (_) {
      _userToken = '';
      _jwtToken = '';
    }
    return isLoggedIn;
  }

  void _enqueuePersist(String userToken, String jwtToken) {
    _persistQueue = _persistQueue.then((_) async {
      try {
        final prefs = await SharedPreferences.getInstance();
        if (userToken.isEmpty || jwtToken.isEmpty) {
          await prefs.remove(_tokenPrefsKey);
          await prefs.remove(_jwtTokenPrefsKey);
        } else {
          await prefs.setString(_tokenPrefsKey, userToken);
          await prefs.setString(_jwtTokenPrefsKey, jwtToken);
        }
      } catch (_) {
        // 落盘失败只影响下次冷启动的自动登录，不阻断当前会话。
      }
    });
  }

  /// 跟随应用语言切换更新 `language` header 取值。
  void setLanguage(AppLanguage language) {
    _language = language;
    switch (language) {
      case AppLanguage.en:
        _languageCode = 1;
        break;
      case AppLanguage.zh:
        _languageCode = 2;
        break;
      case AppLanguage.zhHant:
        _languageCode = 3;
        break;
      case AppLanguage.ja:
        _languageCode = 4;
        break;
    }
  }
}
