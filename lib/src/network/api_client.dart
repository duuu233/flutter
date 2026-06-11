import 'dart:convert';

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
    try {
      final response = await http
          .get(_uri(path, query), headers: _headers(auth: auth))
          .timeout(ApiConfig.timeout);
      return _parse(response);
    } on ApiException {
      rethrow;
    } catch (_) {
      throw ApiException('NETWORK_ERROR', '网络连接失败');
    }
  }

  Future<dynamic> postJson(
    String path, {
    Map<String, dynamic>? body,
    bool auth = true,
  }) async {
    try {
      final response = await http
          .post(
            _uri(path),
            headers: _headers(
              auth: auth,
              extra: {'content-type': 'application/json'},
            ),
            body: jsonEncode(body ?? <String, dynamic>{}),
          )
          .timeout(ApiConfig.timeout);
      return _parse(response);
    } on ApiException {
      rethrow;
    } catch (_) {
      throw ApiException('NETWORK_ERROR', '网络连接失败');
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
      try {
        final request = http.MultipartRequest('POST', _uri(path, query));
        request.headers.addAll(_headers(auth: auth));
        formData?.forEach((key, value) {
          if (value != null) {
            request.fields[key] = value.toString();
          }
        });
        request.files.add(await http.MultipartFile.fromPath(field, filePath));
        final streamed = await request.send().timeout(ApiConfig.timeout);
        final response = await http.Response.fromStream(streamed);
        results.add(_parse(response));
      } on ApiException {
        rethrow;
      } catch (_) {
        throw ApiException('NETWORK_ERROR', '网络连接失败');
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
      throw ApiException(
        response.statusCode,
        retMsg?.toString() ?? '服务器异常',
      );
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
}
