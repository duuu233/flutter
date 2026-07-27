import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart' show MediaType;

import '../device/ble/frame_protocol.dart';
import 'api_client.dart';
import 'api_exception.dart';
import 'boltfox_api.dart';

/// seekink 抖动接口封装（对齐小程序 `utils/dithering.js`，2026-07-23 同步）：
/// 把「设备分辨率的图片文件」multipart 上传，收回**二进制六色 4bpp 帧(.bin)**，
/// 直接喂给 device_ble.uploadImage 走 BLE 图传（替代后端 setUserProductUpload 的转码结果）。
///
/// 实现要点/注意：
///   · 响应体即文件流 → 不能走 ApiClient 的 JSON/retCode 解析，用裸 httpClient 读 bodyBytes；
///   · 请求头按对方要求带 AcceptLanguage=en（原话键名无中划线，另补标准 Accept-Language 兜底）；
///   · Authorization = Bearer+空格+token，token 由 /Client/Basic/getXTYUserToken 动态获取：
///     会话级内存缓存一次取用整程复用，投屏预览页进入时预热（prefetchAuthToken）；
///     接口回 401/token 类报错时清缓存自动刷新重试一次，且刷新时给 /getXTYUserToken 带
///     isNewLogin=1 强制后端重新登录取新 token（2026-07-24；否则后端可能把刚过期的同一会话原样
///     返回，重试仍 401），常规首取/预热用 isNewLogin=0；
///   · ⚠️ bin 的像素格式（六色索引映射/扫描顺序）是否与设备一致未真机验证——调用方必须继续用
///     「字节数 = 宽×高÷2」铁闸校验；真机若花屏/串色，对照 v1.5 协议核对 seekink 的调色板顺序。
class DitheringApi {
  DitheringApi._();

  static const String _endpoint =
      'https://cloud.seekink.cn:8443/prod-api/api/v1/label/imageDitheringBinDownload';

  /// 与 ApiConfig.uploadTimeout 约定一致；网络类失败退避重试（接口是纯转换、无服务端记账副作用，重试安全）
  static const Duration _timeout = Duration(seconds: 20);
  static const int _retryAttempts = 3;
  static const Duration _retryDelay = Duration(milliseconds: 800);

  // —— seekink token：会话级内存缓存 ——
  // App 本次启动内所有投屏复用同一个 token，不落 shared_preferences（有效期未知，杀进程重取最稳）；
  // 过期由 requestFrameBin 的 401 刷新兜底，无需预判有效期。
  static String _tokenCache = '';
  static Future<String>? _tokenInFlight;

  /// 兼容后端可能的返回形态：retData 直接是 token 串，或对象包字段（⚠️字段名为假设，待联调确认）；
  /// 若返回已带 Bearer 前缀则剥掉，统一由本模块拼「Bearer+空格+token」。
  static String _normalizeToken(dynamic data) {
    final Object raw = data is String
        ? data
        : (data is Map
              ? (data['token'] ??
                        data['xtyToken'] ??
                        data['userToken'] ??
                        data['accessToken'] ??
                        data['access_token'] ??
                        '')
                    as Object
              : '');
    return raw.toString().replaceFirst(
      RegExp(r'^Bearer\s+', caseSensitive: false),
      '',
    ).trim();
  }

  /// [forceNewLogin]：401 自愈刷新时传 true → 给后端带 isNewLogin=1 强制重新登录取新 token
  /// （否则后端可能把刚过期的同一会话原样返回，重试仍 401）。常规首取/预热传默认 false。
  static Future<String> ensureAuthToken({bool forceNewLogin = false}) {
    if (!forceNewLogin && _tokenCache.isNotEmpty) {
      return Future.value(_tokenCache);
    }
    // 强制刷新时不复用可能属于旧会话的在途请求，另起一发确保 isNewLogin=1 生效
    if (_tokenInFlight != null && !forceNewLogin) {
      return _tokenInFlight!;
    }
    return _tokenInFlight = BoltFoxApi.getXTYUserToken(
      isNewLogin: forceNewLogin ? 1 : 0,
    )
        .then((data) {
          _tokenInFlight = null;
          final token = _normalizeToken(data);
          if (token.isEmpty) {
            throw ApiException('DITHERING_TOKEN', '抖动token获取失败：返回为空');
          }
          _tokenCache = token;
          return token;
        })
        .catchError((Object error) {
          _tokenInFlight = null;
          throw error;
        });
  }

  /// 预热：进投屏预览页时前置调用（与预热设备连接同理），用户构图期间先把 token 取回缓存，
  /// 点「开始投屏」后出帧请求零等待。失败静默——真正投屏时 ensureAuthToken 会再取并正常报错。
  static void prefetchAuthToken() {
    unawaited(ensureAuthToken().then((_) {}, onError: (_) {}));
  }

  /// 抖动接口的 type 参数：'0'=5.8寸大设备(EF6-589 680×960)、'1'=3.7寸小设备(EF6-370 480×720)。
  /// 按目标分辨率判型（与投屏出图的目标尺寸同源，保证 type 与实际上传的图片尺寸一致）。
  /// 上传图恒为竖向设备分辨率（横向取景的内容已在预览导出时转 270° 进竖向画布），
  /// 宽高对调的匹配只是兜底。小设备尺寸引用协议表，勿写死数字。
  static String typeForDevice(int width, int height) {
    final small = FrameProtocol.screenTypes[0x01]!; // 3.7寸 EF6-370
    final isSmall =
        (width == small.width && height == small.height) ||
        (width == small.height && height == small.width);
    return isSmall ? '1' : '0';
  }

  /// 图片文件 → 设备帧 bin。接口回 JSON/文本（业务报错）时解码抛错（确定性失败不重试）；
  /// 网络类失败（超时/连接）自动退避重试；401/token 类报错清缓存刷新 token 重试一次。
  static Future<Uint8List> requestFrameBin({
    required String filePath,
    required String type,
  }) async {
    final fileBytes = await File(filePath).readAsBytes();
    debugPrint('[抖动bin] 请求：color=BWRYGB imageDitheringModes=2 type=$type 上传=${fileBytes.length}字节');

    var authRetried = false; // 鉴权刷新只做一次：接口侧真拒绝（如账号无权限）时不能打转
    var forceNewLogin = false; // 401 刷新时置真 → 带 isNewLogin=1 强制后端重登
    var attemptsLeft = _retryAttempts;
    while (true) {
      final token = await ensureAuthToken(forceNewLogin: forceNewLogin);
      forceNewLogin = false; // 强制刷新已消费：新 token 已缓存，后续网络重试复用缓存（对齐小程序）
      http.Response res;
      try {
        final request = http.MultipartRequest('POST', Uri.parse(_endpoint));
        request.headers['Authorization'] = 'Bearer $token';
        request.headers['AcceptLanguage'] = 'en'; // 对方给的键名（无中划线），原样带上
        request.headers['Accept-Language'] = 'en'; // 标准头兜底：后端若走通用 i18n 解析读的是它
        request.fields['color'] = 'BWRYGB';
        request.fields['imageDitheringModes'] = '2';
        request.fields['type'] = type;
        request.files.add(
          http.MultipartFile.fromBytes(
            'file',
            fileBytes,
            filename: 'image.jpg',
            contentType: MediaType('image', 'jpeg'),
          ),
        );
        final streamed = await ApiClient.instance.httpClient
            .send(request)
            .timeout(_timeout);
        res = await http.Response.fromStream(streamed).timeout(_timeout);
      } on ApiException {
        rethrow;
      } catch (error) {
        // 没拿到响应（超时/断网），弱网下退避重试
        if (attemptsLeft > 1 &&
            (error is TimeoutException ||
                error is http.ClientException ||
                error is IOException)) {
          attemptsLeft -= 1;
            debugPrint('[抖动bin] 网络失败，将重试（剩余 $attemptsLeft 次）：$error');
          await Future<void>.delayed(_retryDelay);
          continue;
        }
        throw ApiException('DITHERING_NETWORK', '抖动bin转换失败：网络异常（$error）');
      }

      final bytes = res.bodyBytes;
        debugPrint('[抖动bin] 返回：statusCode=${res.statusCode} 字节数=${bytes.length}');
      // 业务报错通常回小体积 JSON（content-type 标 json/text，或首字符 { / [）：解码抛错，不重试
      final contentType = res.headers['content-type'] ?? '';
      final looksText =
          RegExp('json|text', caseSensitive: false).hasMatch(contentType) ||
          (bytes.isNotEmpty &&
              bytes.length < 4096 &&
              (bytes[0] == 0x7b || bytes[0] == 0x5b));
      final text = looksText ? _safeUtf8(bytes) : '';
      // 鉴权失败（HTTP 401，或业务 JSON 报 token/授权类错误）：会话缓存的 token 可能已过期，
      // 清缓存重取一次再发本请求（不消耗网络重试次数）
      final authFailed =
          res.statusCode == 401 ||
          (looksText &&
              RegExp(
                '401|token|unauthorized|授权|过期|expired',
                caseSensitive: false,
              ).hasMatch(text));
      if (authFailed && !authRetried) {
        authRetried = true;
        forceNewLogin = true; // 下一发带 isNewLogin=1 强制重新登录取新 token
        _tokenCache = '';
        debugPrint('[抖动bin] 鉴权失败，带 isNewLogin=1 强制重登刷新 token 重试一次：${text.isNotEmpty ? text : 'HTTP ${res.statusCode}'}');
        continue;
      }
      if (looksText) {
        throw ApiException(
          'DITHERING_ERROR',
          '抖动bin转换失败：${text.isNotEmpty ? text.substring(0, text.length > 60 ? 60 : text.length) : 'HTTP ${res.statusCode}'}',
        );
      }
      if (res.statusCode != 200 || bytes.isEmpty) {
        throw ApiException('DITHERING_ERROR', '抖动bin转换失败：HTTP ${res.statusCode}');
      }
      return bytes;
    }
  }

  static String _safeUtf8(Uint8List bytes) {
    try {
      return utf8.decode(bytes, allowMalformed: true);
    } catch (_) {
      return '';
    }
  }
}
