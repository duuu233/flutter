import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'api_config.dart';
import 'api_exception.dart';
import 'api_session.dart';

/// 全局请求入口（App 版），对齐小程序端 `utils/request.js`。
///
/// 职责：
/// - 注入公共 header：`terminal` / `language` / `device` / `userToken`（及 `Authorization`）。
/// - 统一解析 BoltFox 响应：`retCode=200` 成功并返回 `retData`，否则抛 [ApiException]。
/// - 鉴权失效（HTTP 401 或 retCode 401/406）时清除本地登录态并抛出。
///
/// 业务层请通过 [BoltFoxApi] 调用，不要在页面里直接使用本类。
class ApiClient {
  ApiClient._();

  static final ApiClient instance = ApiClient._();

  /// 组装公共请求头。[auth] 为 false 时不携带登录态（如登录/注册/发验证码）。
  Map<String, String> _headers({bool auth = true, Map<String, String>? extra}) {
    final session = ApiSession.instance;
    final headers = <String, String>{
      'terminal': ApiConfig.terminal.toString(),
      'language': session.languageCode.toString(),
    };
    if (session.device.isNotEmpty) {
      headers['device'] = session.device;
    }
    if (auth && session.userToken.isNotEmpty) {
      headers['userToken'] = session.userToken;
      headers['Authorization'] = 'Bearer ${session.userToken}';
    }
    if (extra != null) {
      headers.addAll(extra);
    }
    return headers;
  }

  /// 是否 BoltFox 业务接口（`/Client/` 前缀）。对齐小程序 `request.js isClientApi`。
  bool _isClientApi(String path) => path.startsWith('/Client/');

  /// `/Client/` 接口的公共 query 参数：`terminal` / `language` / `device` / `userToken`。
  ///
  /// 对齐小程序 `request.js getClientQuery` —— 这些公共参数**既放 header 也拼进 query string**。
  /// 后端按 query 里的 `userToken` 鉴权，仅放 header 会导致已登录接口（如绑定设备 addUserProduct）
  /// 鉴权失败（这正是「小程序能绑、App 绑不了」的根因）。非 `/Client/` 或绝对外链不追加。
  /// [auth]=false（登录/注册/发验证码）时不带 `userToken`。
  Map<String, dynamic> _clientQuery(String path, {bool auth = true}) {
    if (!_isClientApi(path)) {
      return const <String, dynamic>{};
    }
    final session = ApiSession.instance;
    final query = <String, dynamic>{
      'terminal': ApiConfig.terminal.toString(),
      'language': session.languageCode.toString(),
    };
    if (session.device.isNotEmpty) {
      query['device'] = session.device;
    }
    if (auth && session.userToken.isNotEmpty) {
      query['userToken'] = session.userToken;
    }
    return query;
  }

  /// 拼接 URL，绝对地址原样使用，并按需附加 query（自动过滤 null / 空串）。
  Uri _uri(String path, [Map<String, dynamic>? query]) {
    final base = path.startsWith('http') ? path : '${ApiConfig.baseUrl}$path';
    final uri = Uri.parse(base);
    if (query == null || query.isEmpty) {
      return uri;
    }
    final merged = <String, String>{...uri.queryParameters};
    query.forEach((key, value) {
      if (value != null && value.toString().isNotEmpty) {
        merged[key] = value.toString();
      }
    });
    if (merged.isEmpty) {
      return uri;
    }
    return uri.replace(queryParameters: merged);
  }

  Future<dynamic> getJson(
    String path, {
    Map<String, dynamic>? query,
    bool auth = true,
  }) async {
    // /Client/ 公共 query 参数（terminal/language/device/userToken）+ 业务 query，对齐小程序。
    final uri = _uri(path, {..._clientQuery(path, auth: auth), ...?query});
    _logRequest('GET', uri, data: query);
    return _sendWithRetry(
      'GET',
      uri,
      () => http
          .get(uri, headers: _headers(auth: auth))
          .timeout(ApiConfig.timeout),
    );
  }

  Future<dynamic> postJson(
    String path, {
    Map<String, dynamic>? body,
    bool auth = true,
  }) async {
    // POST 也要把公共参数拼进 query string（body 仍为 JSON 业务字段）：后端按 query 里的 userToken
    // 鉴权，此前 postJson 未带 query 导致 addUserProduct 等已登录 POST 鉴权失败、绑定不上。
    final uri = _uri(path, _clientQuery(path, auth: auth));
    final payload = body ?? <String, dynamic>{};
    _logRequest('POST', uri, data: payload);
    return _sendWithRetry(
      'POST',
      uri,
      () => http
          .post(
            uri,
            headers: _headers(
              auth: auth,
              extra: {'content-type': 'application/json'},
            ),
            body: jsonEncode(payload),
          )
          .timeout(ApiConfig.timeout),
    );
  }

  /// 发送并静默重试：仅网络层失败（超时/断网）才重试，最多 [ApiConfig.networkRetryMax] 次，
  /// 每次间隔 [ApiConfig.networkRetryDelay]；业务/服务器错误（[_parse] 抛出的 [ApiException]）
  /// 不重试（避免重复副作用）。重试耗尽后统一抛出友好提示：网络超时/连接失败，请稍后再试。
  ///
  /// 用户端表现：网络卡住时最长约 30s（3 次尝试 × 10s）才提示，
  /// 对齐小程序 `utils/request.js` 的 requestWithRetry。
  Future<dynamic> _sendWithRetry(
    String method,
    Uri uri,
    Future<http.Response> Function() send,
  ) async {
    var attempt = 0;
    while (true) {
      try {
        final response = await send();
        _logResponse(method, uri, response);
        return _parse(response);
      } on ApiException {
        rethrow; // 业务/服务器错误：不重试
      } on TimeoutException {
        if (attempt < ApiConfig.networkRetryMax) {
          attempt++;
          await Future<void>.delayed(ApiConfig.networkRetryDelay);
          continue;
        }
        throw ApiException('NETWORK_ERROR', '网络超时，请稍后再试');
      } catch (_) {
        if (attempt < ApiConfig.networkRetryMax) {
          attempt++;
          await Future<void>.delayed(ApiConfig.networkRetryDelay);
          continue;
        }
        throw ApiException('NETWORK_ERROR', '网络连接失败，请稍后再试');
      }
    }
  }

  /// 文件上传（form-data）。逐个文件上传，单文件返回其结果，多文件返回结果列表。
  Future<dynamic> upload(
    String path, {
    required List<String> filePaths,
    String field = 'fileParam',
    Map<String, dynamic>? query,
    Map<String, dynamic>? formData,
    bool auth = true,
  }) async {
    if (filePaths.isEmpty) {
      throw ApiException('UPLOAD_FILE_REQUIRED', '请选择上传文件');
    }
    final results = <dynamic>[];
    for (final filePath in filePaths) {
      // 上传同样带 /Client/ 公共 query 参数（terminal/language/device/userToken）+ 业务 query。
      final uri = _uri(path, {..._clientQuery(path, auth: auth), ...?query});
      _logRequest(
        'POST multipart',
        uri,
        data: {...?formData, 'fileName': filePath.split(RegExp(r'[/\\]')).last},
      );
      try {
        final request = http.MultipartRequest('POST', uri);
        request.headers.addAll(_headers(auth: auth));
        formData?.forEach((key, value) {
          if (value != null) {
            request.fields[key] = value.toString();
          }
        });
        request.files.add(await http.MultipartFile.fromPath(field, filePath));
        // 上传用更长的 uploadTimeout（不受普通请求 10s 影响），且不做自动重试（避免重复上传/重复投屏记录）
        final streamed = await request.send().timeout(ApiConfig.uploadTimeout);
        final response = await http.Response.fromStream(streamed);
        _logResponse('POST multipart', uri, response);
        results.add(_parse(response));
      } on ApiException {
        rethrow;
      } on TimeoutException {
        throw ApiException('NETWORK_ERROR', '网络超时，请稍后再试');
      } catch (_) {
        throw ApiException('NETWORK_ERROR', '网络连接失败，请稍后再试');
      }
    }
    return results.length == 1 ? results.first : results;
  }

  /// 解析响应：按 HTTP 状态码与业务 retCode 二次判定，成功返回 retData。
  dynamic _parse(http.Response response) {
    Map<String, dynamic> body;
    try {
      final text = response.bodyBytes.isEmpty
          ? ''
          : utf8.decode(response.bodyBytes);
      final decoded = text.isEmpty ? null : jsonDecode(text);
      body = decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
    } catch (_) {
      body = <String, dynamic>{};
    }

    final retCode = body['retCode'];
    final retMsg = body['retMsg'];

    // 登录过期：HTTP 401 或业务 code 401/406
    if (response.statusCode == 401 || retCode == 401 || retCode == 406) {
      ApiSession.instance.clear();
      throw ApiException(
        retCode is int ? retCode : 401,
        retMsg?.toString() ?? '登录已过期',
      );
    }

    // 非 2xx 视为服务器异常
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(response.statusCode, retMsg?.toString() ?? '服务器异常');
    }

    // BoltFox 约定 retCode=200 表示成功
    if (body.containsKey('retCode')) {
      if (retCode != 200) {
        throw ApiException(
          retCode is int ? retCode : -1,
          retMsg?.toString() ?? '业务处理失败',
          data: body['retData'],
        );
      }
      return body['retData'];
    }

    return body;
  }

  void _logRequest(String method, Uri uri, {Object? data}) {
    if (!kDebugMode) return;
    debugPrint('[HTTP] --> $method $uri');
    if (data != null) {
      debugPrint('[HTTP] request: ${jsonEncode(_redact(data))}');
    }
  }

  void _logResponse(String method, Uri uri, http.Response response) {
    if (!kDebugMode) return;
    final text = response.bodyBytes.isEmpty
        ? ''
        : utf8.decode(response.bodyBytes, allowMalformed: true);
    debugPrint('[HTTP] <-- ${response.statusCode} $method $uri');
    debugPrint('[HTTP] response: ${jsonEncode(_redactJson(text))}');
  }

  Object? _redactJson(String text) {
    try {
      return _redact(jsonDecode(text));
    } catch (_) {
      return text;
    }
  }

  Object? _redact(Object? value, [String? key]) {
    const sensitiveKeys = <String>{
      'authorization',
      'password',
      'confirmpassword',
      'token',
      'usertoken',
    };
    if (key != null && sensitiveKeys.contains(key.toLowerCase())) {
      return '***';
    }
    if (value is Map) {
      return value.map(
        (key, item) => MapEntry(key.toString(), _redact(item, key.toString())),
      );
    }
    if (value is Iterable) {
      return value.map((item) => _redact(item)).toList();
    }
    return value;
  }
}
