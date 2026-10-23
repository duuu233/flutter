import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart' show MediaType;

import '../device/ble/frame_protocol.dart';
import 'api_client.dart';
import 'api_exception.dart';

/// 抖动出帧接口封装（对齐小程序 `utils/dithering.js`）：
/// 把「设备分辨率的图片文件」multipart 上传，收回**二进制六色 4bpp 帧(.bin)**，
/// 直接喂给 device_ble.uploadImage 走 BLE 图传。
///
/// 2026-10-23 起改调我方后端 `POST /Client/Basic/imageDitheringBinDownload`（form-data，参数与原第三方
/// seekink 接口一致：color / imageDitheringModes / type / file）；原第三方接口及其 token
/// （`/Client/Basic/getXTYUserToken`）不再使用。
///
/// 实现要点/注意：
///   · 公共参数 terminal/language/device/userToken 由 [ApiClient.postMultipartForBytes] 与其它接口
///     同口径注入，userToken 是本 App 用户自己的登录令牌；业务报错/登录过期按 retCode 统一判定；
///   · 响应体即文件流，所以不走 JSON 的 upload，而是 postMultipartForBytes 直接拿 bodyBytes；
///   · 调用方必须继续用「字节数 = 宽×高÷2」铁闸校验返回帧。
class DitheringApi {
  DitheringApi._();

  static const String _path = '/Client/Basic/imageDitheringBinDownload';

  /// 与 ApiConfig.uploadTimeout 约定一致；网络类失败退避重试（接口是纯转换、无记账副作用，重试安全）
  static const Duration _timeout = Duration(seconds: 20);
  static const int _retryAttempts = 3;
  static const Duration _retryDelay = Duration(milliseconds: 800);

  /// 抖动接口的 type 参数（2026-07-22 对接第三方时定义，迁到我方后端后数值不变、后端按此对齐）：
  /// '0'=5.8寸大设备(EF6-589 680×960)、'1'=3.7寸小设备(EF6-370 480×720)；是出帧策略，不是旋转角。
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

  /// 图片文件 → 设备帧 bin。接口回 JSON（业务报错/登录过期）时按 [ApiException] 抛出（不重试）；
  /// 网络类失败（超时/连接）自动退避重试。
  static Future<Uint8List> requestFrameBin({
    required String filePath,
    required String type,
  }) async {
    final fileBytes = await File(filePath).readAsBytes();
    debugPrint('[抖动bin] 请求：color=BWRYGB imageDitheringModes=2 type=$type 上传=${fileBytes.length}字节');

    var attemptsLeft = _retryAttempts;
    while (true) {
      try {
        final bytes = await ApiClient.instance.postMultipartForBytes(
          _path,
          fields: {
            'color': 'BWRYGB',
            'imageDitheringModes': '2',
            'type': type,
          },
          file: http.MultipartFile.fromBytes(
            'file',
            fileBytes,
            filename: 'image.jpg',
            contentType: MediaType('image', 'jpeg'),
          ),
          timeout: _timeout,
        );
        debugPrint('[抖动bin] 返回：字节数=${bytes.length}');
        return bytes;
      } on ApiException catch (error) {
        debugPrint('[抖动bin] 接口报错：$error');
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
    }
  }
}
