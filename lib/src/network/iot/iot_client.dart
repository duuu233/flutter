import 'dart:async';
import 'dart:convert';
import 'dart:io' show IOException;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../shared/l10n/app_l10n.dart';
import '../api_client.dart';
import '../api_session.dart';

/// IoT 服务（WiFi 版设备：投屏、在线、设备信息、配网参数）的 HTTP 传输层，
/// 同步小程序 `utils/iot-request.js` + `utils/iot-errors.js`。
///
/// 刻意不复用 [ApiClient]：两边返回结构、错误码和登录失效判据都不一样——
///   · 返回 `{ code, msg, data }`，code=0 成功；错误文案字段是 `msg`（不是 retMsg）；
///   · 只有鉴权失败、资源不存在、上游不可用用非 200 的 HTTP 状态（401 / 404 / 503），其余业务错误
///     HTTP 200 + body.code，以 body.code 为准；
///   · 401 = 登录失效需重登；**503 = 鉴权依赖的老服务暂时不可用，保留登录态稍后重试，绝不能当 401 处理**；
///   · 403 = 无该设备权限（设备未绑定到当前用户也是 403）。
/// 鉴权 token 与老服务是同一个（Header `userToken`）。
class IotConfig {
  IotConfig._();

  /// 与 BoltFox 老服务是两套服务。切环境：`--dart-define=IOT_BASE_URL=...` / `IOT_WS_URL=...`。
  static const String baseUrl = String.fromEnvironment(
    'IOT_BASE_URL',
    defaultValue: 'https://iot.boltfox.cn',
  );
  static const String wsUrl = String.fromEnvironment(
    'IOT_WS_URL',
    defaultValue: 'wss://iot.boltfox.cn/ws/push',
  );

  static const Duration timeout = Duration(seconds: 10);

  /// 网络层失败（断网 / 超时）的静默重试：只给 GET。投屏等 POST 有副作用，重发可能重复下发。
  static const int getRetryMax = 2;
  static const Duration retryDelay = Duration(milliseconds: 500);
}

/// 调用方该怎么收场：重新登录 / 稍后可重试 / 按提示处理即可。
enum IotErrorAction { relogin, retry, none }

/// IoT 接口异常。[code] 为业务码 / HTTP 状态码，网络失败为 [networkError]。
class IotException implements Exception {
  IotException({
    required this.code,
    required this.message,
    required this.action,
    this.retryAfter = 0,
    this.statusCode = 0,
    this.serverMessage = '',
  });

  static const String networkError = 'NETWORK_ERROR';

  final Object code;

  /// 给用户看的文案（已按码表与当前语言翻译）。
  final String message;
  final IotErrorAction action;

  /// 429 的建议等待秒数（0 = 未给）。
  final int retryAfter;
  final int statusCode;
  final String serverMessage;

  bool get isRelogin => action == IotErrorAction.relogin;
  bool get isRetryable => action == IotErrorAction.retry;

  /// 数值码（网络失败等非数字码为 null）。
  int? get numericCode => code is int ? code as int : int.tryParse('$code');

  @override
  String toString() => 'IotException($code, $message)';
}

/// IoT 统一错误码（接口文档「通用约定 / 错误码」口径）→ (简中, 英, 日) + 收场方式。
const Map<int, (String, String, String, IotErrorAction)> _codeTable = {
  4000: ('参数错误', 'Invalid parameters', 'パラメータが正しくありません', IotErrorAction.none),
  401: ('登录已失效，请重新登录', 'Your session has expired. Please sign in again.', 'ログインの有効期限が切れました。再度ログインしてください', IotErrorAction.relogin),
  403: ('无该设备操作权限', 'No permission for this device', 'このデバイスを操作する権限がありません', IotErrorAction.none),
  404: ('请求的资源不存在', 'The requested resource does not exist', 'リクエストされたリソースが存在しません', IotErrorAction.none),
  // 4040/4041/4044 拆分后的口径：4040 设备不存在、4041 只表示离线、4044 只表示任务不存在/过期
  4040: ('设备不存在', 'Device not found', 'デバイスが存在しません', IotErrorAction.none),
  4041: ('设备已离线，请检查设备网络', 'The device is offline. Please check its network.', 'デバイスがオフラインです。デバイスのネットワークをご確認ください', IotErrorAction.none),
  4044: ('任务不存在或已过期', 'The task does not exist or has expired', 'タスクが存在しないか期限切れです', IotErrorAction.none),
  4045: ('设备升级中，请稍后', 'The device is updating. Please try later.', 'デバイスを更新中です。しばらくしてからお試しください', IotErrorAction.retry),
  4130: ('图片过大，请压缩后重试', 'The image is too large. Please compress it and try again.', '画像が大きすぎます。圧縮してから再度お試しください', IotErrorAction.none),
  429: ('操作太频繁，请稍后重试', 'Too many requests. Please try again later.', '操作が頻繁すぎます。しばらくしてからお試しください', IotErrorAction.retry),
  503: ('服务暂时不可用，请稍后重试', 'Service temporarily unavailable. Please try again later.', 'サービスが一時的に利用できません。しばらくしてからお試しください', IotErrorAction.retry),
  5000: ('服务异常，请稍后重试', 'Service error. Please try again later.', 'サービスエラーです。しばらくしてからお試しください', IotErrorAction.retry),
  5001: ('图片处理失败，请换一张试试', 'Image processing failed. Please try another image.', '画像の処理に失敗しました。別の画像でお試しください', IotErrorAction.none),
  5002: ('文件上传失败，请重试', 'File upload failed. Please try again.', 'ファイルのアップロードに失敗しました。再度お試しください', IotErrorAction.retry),
  5003: ('图片处理超时，请重试', 'Image processing timed out. Please try again.', '画像処理がタイムアウトしました。再度お試しください', IotErrorAction.retry),
};

/// 把一次 HTTP 响应归一成数据或 [IotException]（纯函数，单测用）。
@visibleForTesting
Object? parseIotResponse(
  int statusCode,
  Object? body, {
  Map<String, String> headers = const {},
  AppL10n? l10n,
}) {
  final payload = body is Map ? body : const <String, dynamic>{};
  final rawCode = payload['code'];
  final bodyCode = rawCode == null || '$rawCode'.isEmpty
      ? null
      : (rawCode is num ? rawCode.toInt() : int.tryParse('$rawCode'));
  final ok = statusCode >= 200 && statusCode < 300 && (bodyCode == null || bodyCode == 0);
  if (ok) {
    return payload['data'];
  }
  // HTTP 401/403/404/503 以 HTTP 状态为准（body 里一般同码）；其余以 body.code 为准
  final code = const [401, 403, 404, 503].contains(statusCode) || bodyCode == null || bodyCode == 0
      ? statusCode
      : bodyCode;
  final serverMessage = (payload['msg'] ?? '').toString();
  throw _exceptionFor(
    code,
    serverMessage,
    statusCode: statusCode,
    retryAfter: code == 429 ? _readRetryAfter(payload, headers) : 0,
    l10n: l10n,
  );
}

IotException _exceptionFor(
  int code,
  String serverMessage, {
  int statusCode = 0,
  int retryAfter = 0,
  AppL10n? l10n,
}) {
  final text = l10n ?? AppL10n(ApiSession.instance.language);
  final known = _codeTable[code];
  if (known != null) {
    return IotException(
      code: code,
      message: text.pick(known.$1, known.$2, known.$3),
      action: known.$4,
      retryAfter: retryAfter,
      statusCode: statusCode,
      serverMessage: serverMessage,
    );
  }
  // 码表外的 HTTP 5xx（网关 502/504 等，响应体往往是 HTML）：按服务异常、可重试处理
  if (code >= 500 && code < 600) {
    final fallback = _codeTable[5000]!;
    return IotException(
      code: code,
      message: text.pick(fallback.$1, fallback.$2, fallback.$3),
      action: IotErrorAction.retry,
      statusCode: statusCode,
      serverMessage: serverMessage,
    );
  }
  final trimmed = serverMessage.trim();
  return IotException(
    code: code,
    message: trimmed.isNotEmpty ? trimmed : text.pick('请求失败', 'Request failed', 'リクエストに失敗しました'),
    action: IotErrorAction.none,
    statusCode: statusCode,
    serverMessage: serverMessage,
  );
}

/// 429 的建议等待秒数：优先 body.data.retryAfter / body.retryAfter，其次 HTTP Header Retry-After。
int _readRetryAfter(Map<dynamic, dynamic> body, Map<String, String> headers) {
  final data = body['data'] is Map ? body['data'] as Map : const {};
  final candidates = <Object?>[data['retryAfter'], body['retryAfter']];
  headers.forEach((key, value) {
    if (key.toLowerCase() == 'retry-after') {
      candidates.add(value);
    }
  });
  for (final value in candidates) {
    final seconds = num.tryParse('${value ?? ''}');
    if (seconds != null && seconds > 0) {
      return seconds.round();
    }
  }
  return 0;
}

IotException _networkFailure(Object error) {
  final l10n = AppL10n(ApiSession.instance.language);
  final timeout = error is TimeoutException;
  return IotException(
    code: IotException.networkError,
    message: timeout
        ? l10n.pick('网络超时，请稍后再试', 'Network timeout. Please try again later.', 'ネットワークがタイムアウトしました。しばらくしてからお試しください')
        : l10n.pick('网络连接失败，请稍后再试', 'Network connection failed. Please try again later.', 'ネットワークに接続できません。しばらくしてからお試しください'),
    action: IotErrorAction.retry,
    serverMessage: error.toString(),
  );
}

/// IoT 请求入口（单例）。业务层请经 [IotApi] 调用。
class IotClient {
  IotClient._();

  static final IotClient instance = IotClient._();

  /// 401 登录失效时的收场（由 [PhotoFrameState] 注入，走与老服务同一套登出引导）。
  /// 503 / 429 等只交给调用方提示，不动登录态。
  static void Function()? onUnauthorized;

  http.Client get _http => ApiClient.instance.httpClient;

  Map<String, String> _headers([Map<String, String>? extra]) {
    final token = ApiSession.instance.userToken;
    return {
      if (token.isNotEmpty) 'userToken': token,
      ...?extra,
    };
  }

  Uri _uri(String path, [Map<String, Object?>? query]) {
    final uri = Uri.parse(path.startsWith('http') ? path : '${IotConfig.baseUrl}$path');
    final params = <String, String>{...uri.queryParameters};
    query?.forEach((key, value) {
      // 空值整项去掉，不拼出 since= 这类空参数
      if (value != null && '$value'.isNotEmpty) {
        params[key] = '$value';
      }
    });
    return params.isEmpty ? uri : uri.replace(queryParameters: params);
  }

  Object? _parse(http.Response response) {
    Object? body;
    try {
      body = response.bodyBytes.isEmpty ? null : jsonDecode(utf8.decode(response.bodyBytes));
    } catch (_) {
      body = null;
    }
    return parseIotResponse(response.statusCode, body, headers: response.headers);
  }

  Never _fail(Object error) {
    if (error is IotException) {
      if (error.isRelogin) {
        onUnauthorized?.call();
      }
      throw error;
    }
    throw _networkFailure(error);
  }

  static bool _isNetworkError(Object error) =>
      error is TimeoutException || error is http.ClientException || error is IOException;

  /// GET：[retry]=false 关掉网络静默重试（需要「失败就立即按失败处理」的场景）。
  Future<Object?> get(
    String path, {
    Map<String, Object?>? query,
    Map<String, String>? headers,
    bool retry = true,
  }) async {
    final uri = _uri(path, query);
    var retriesLeft = retry ? IotConfig.getRetryMax : 0;
    while (true) {
      try {
        final response = await _http
            .get(uri, headers: _headers(headers))
            .timeout(IotConfig.timeout);
        return _parse(response);
      } catch (error) {
        if (_isNetworkError(error) && retriesLeft > 0) {
          retriesLeft--;
          await Future<void>.delayed(IotConfig.retryDelay);
          continue;
        }
        _fail(error);
      }
    }
  }

  /// POST JSON（轮播、休眠、删除照片、消息已读等设备控制）：不做网络重试（有副作用，重发可能重复下发）。
  Future<Object?> post(
    String path, {
    Map<String, Object?> body = const {},
    Map<String, String>? headers,
  }) async {
    final uri = _uri(path);
    try {
      final response = await _http
          .post(
            uri,
            headers: _headers({'Content-Type': 'application/json', ...?headers}),
            body: jsonEncode(body),
          )
          .timeout(IotConfig.timeout);
      return _parse(response);
    } catch (error) {
      _fail(error);
    }
  }

  /// multipart 上传（WiFi 投屏 POST /api/device/play）：不做网络重试（重传会重复投屏）。
  /// [onProgress] 回调已送出的字节占比 0~100（流式写入时按块统计）。
  Future<Object?> upload(
    String path, {
    required String filePath,
    String field = 'file',
    Map<String, String> fields = const {},
    Duration timeout = IotConfig.timeout,
    void Function(double percent)? onProgress,
  }) async {
    final uri = _uri(path);
    try {
      final multipart = http.MultipartRequest('POST', uri)
        ..headers.addAll(_headers())
        ..fields.addAll(fields)
        ..files.add(await http.MultipartFile.fromPath(field, filePath));
      final total = multipart.contentLength;
      // finalize() 之后 headers 才带上 multipart boundary，必须在它之后再拷
      final bytes = multipart.finalize();
      final request = http.StreamedRequest('POST', uri)
        ..headers.addAll(multipart.headers)
        ..contentLength = total;
      var sent = 0;
      bytes.listen(
        (chunk) {
          sent += chunk.length;
          if (onProgress != null && total > 0) {
            try {
              onProgress(sent * 100 / total);
            } catch (_) {
              // 页面进度回调出错不影响上传
            }
          }
          request.sink.add(chunk);
        },
        onDone: () => request.sink.close(),
        onError: (Object error, StackTrace stack) {
          request.sink.addError(error, stack);
          request.sink.close();
        },
        cancelOnError: true,
      );
      final streamed = await _http.send(request).timeout(timeout);
      final response = await http.Response.fromStream(streamed).timeout(timeout);
      return _parse(response);
    } catch (error) {
      _fail(error);
    }
  }
}
