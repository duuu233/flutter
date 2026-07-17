/// 统一的接口异常。
///
/// [code] 为后端业务码（retCode，如 200/406）或本地标识
/// （`'NETWORK_TIMEOUT'` / `'NETWORK_UNREACHABLE'` / `'PARSE_ERROR'` / `'CLIENT_ERROR'` 等）。
/// [isAuthError] 为 true 时表示登录态失效（401/406），调用方应引导重新登录。
class ApiException implements Exception {
  ApiException(this.code, this.message, {this.data, bool? authError})
    : _authError = authError;

  final Object code;
  final String message;
  final dynamic data;

  /// 显式指定是否鉴权失效；null 时按 code 数值推断（兼容既有抛出点）。
  /// 网关/CDN 返回的 **HTTP** 406（Not Acceptable，与鉴权无关）必须显式传
  /// `authError: false`，否则会被数值推断误判成登录失效、把用户踢回登录页。
  final bool? _authError;

  bool get isAuthError => _authError ?? (code == 401 || code == 406);

  @override
  String toString() => 'ApiException($code, $message)';
}
