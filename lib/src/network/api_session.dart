import '../state.dart';

/// 运行期会话状态：登录 token 与语言码。
///
/// [ApiClient] 在发起请求时从这里读取公共 header（`userToken` / `language` / `device`）。
/// 登录成功后调用 [setToken]；退出登录 / 注销 / 鉴权失效时调用 [clear]。
///
/// 说明：当前为内存态，App 重启后需要重新登录；后续可接入持久化存储
/// （如 shared_preferences）在 [setToken]/[clear] 内同步读写。
class ApiSession {
  ApiSession._();

  static final ApiSession instance = ApiSession._();

  /// 登录态 token，空字符串表示未登录。
  String _userToken = '';

  /// 语言码：en=1、zh-Hans=2、zh-Hant=3、ja=4。默认简体中文。
  int _languageCode = 2;

  /// 当前应用语言（枚举形态）：供无 BuildContext 的网络层取本地化兜底文案。
  AppLanguage _language = AppLanguage.zh;

  /// 设备型号，用于 `device` header，可选。
  String device = '';

  String get userToken => _userToken;

  int get languageCode => _languageCode;

  AppLanguage get language => _language;

  bool get isLoggedIn => _userToken.isNotEmpty;

  void setToken(String token) {
    _userToken = token;
  }

  void clear() {
    _userToken = '';
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
