/// 统一的接口异常。
///
/// [code] 为后端业务码（retCode，如 200/406）或本地标识（如 `'NETWORK_ERROR'`）。
/// [isAuthError] 为 true 时表示登录态失效（401/406），调用方应引导重新登录。
class ApiException implements Exception {
  ApiException(this.code, this.message, {this.data});

  final Object code;
  final String message;
  final dynamic data;

  bool get isAuthError => code == 401 || code == 406;

  @override
  String toString() => 'ApiException($code, $message)';
}
