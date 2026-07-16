import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../shared/l10n/app_l10n.dart';
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

  /// 全局共享的 HTTP 客户端：keep-alive 复用 TCP+TLS 连接。
  /// 之前用顶层 http.get/post（每个请求新建一次性 Client），每次都重付
  /// TLS 握手（LTE 上 ~100–300ms）；投屏一批 5 张是「上传+下载 .bin」×5
  /// 共 10 次握手，白白多花 1~3s。设备帧/固件下载也共用此客户端。
  final http.Client _http = http.Client();

  /// 供网络层之外的裸下载（投屏 .bin、OTA 固件）复用同一连接池。
  http.Client get httpClient => _http;

  /// 网络层兜底文案按当前语言取（无 BuildContext，经 ApiSession 拿语言）。
  /// 之前是硬编码中文，英/日用户断网/超时时高频看到中文 toast。
  AppL10n get _l10n => AppL10n(ApiSession.instance.language);

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
      () => _http
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
      () => _http
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
        throw ApiException('NETWORK_ERROR', _l10n.netTimeout);
      } catch (_) {
        if (attempt < ApiConfig.networkRetryMax) {
          attempt++;
          await Future<void>.delayed(ApiConfig.networkRetryDelay);
          continue;
        }
        throw ApiException('NETWORK_ERROR', _l10n.netConnectFailed);
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
      throw ApiException('UPLOAD_FILE_REQUIRED', _l10n.netUploadFileRequired);
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
        final streamed = await _http
            .send(request)
            .timeout(ApiConfig.uploadTimeout);
        final response = await http.Response.fromStream(streamed);
        _logResponse('POST multipart', uri, response);
        results.add(_parse(response));
      } on ApiException {
        rethrow;
      } on TimeoutException {
        throw ApiException('NETWORK_ERROR', _l10n.netTimeout);
      } catch (_) {
        throw ApiException('NETWORK_ERROR', _l10n.netConnectFailed);
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
    // 后端忽略 language 参数、retMsg 以英文为主：已知文案先按当前语言重译
    // （见 AppL10n.localizeServerMessage），否则简中/日文用户会看到英文提示。
    final rawMsg = body['retMsg'];
    final retMsg = rawMsg == null
        ? null
        : _l10n.localizeServerMessage(rawMsg.toString());

    // 登录过期：HTTP 401 或业务 code 401/406
    if (response.statusCode == 401 || retCode == 401 || retCode == 406) {
      ApiSession.instance.clear();
      throw ApiException(
        retCode is int ? retCode : 401,
        retMsg ?? _l10n.netSessionExpired,
      );
    }

    // 非 2xx 视为服务器异常
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(
        response.statusCode,
        retMsg ?? _l10n.netServerError,
      );
    }

    // BoltFox 约定 retCode=200 表示成功
    if (body.containsKey('retCode')) {
      if (retCode != 200) {
        throw ApiException(
          retCode is int ? retCode : -1,
          retMsg ?? _l10n.netRequestFailed,
          data: body['retData'],
        );
      }
      return body['retData'];
    }

    return body;
  }

  void _logRequest(String method, Uri uri, {Object? data}) {
    if (!kDebugMode) return;
    debugPrint('[HTTP] --> $method ${_redactUri(uri)}');
    if (data != null) {
      debugPrint('[HTTP] request: ${jsonEncode(_redact(data))}');
    }
  }

  void _logResponse(String method, Uri uri, http.Response response) {
    if (!kDebugMode) return;
    final text = response.bodyBytes.isEmpty
        ? ''
        : utf8.decode(response.bodyBytes, allowMalformed: true);
    debugPrint('[HTTP] <-- ${response.statusCode} $method ${_redactUri(uri)}');
    debugPrint('[HTTP] response: ${jsonEncode(_redactJson(text))}');
  }

  /// 日志里的 URL 同样要脱敏：/Client/ 公共参数把 userToken 拼进了 query，
  /// 直接打印 $uri 会让 body 脱敏（_redact）形同虚设。
  Uri _redactUri(Uri uri) {
    if (!uri.queryParameters.containsKey('userToken')) return uri;
    return uri.replace(
      queryParameters: {...uri.queryParameters, 'userToken': '***'},
    );
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
