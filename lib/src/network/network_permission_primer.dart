import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;

import 'api_config.dart';

/// iOS 首次联网授权的**预热**：启动即发一个无副作用的请求，把系统那个
/// 「允许"BoltStar"使用无线数据？」的弹框提前到首屏。
///
/// ## 为什么需要它
///
/// 中国大陆的 iOS 会在 App **进程内第一次发起网络请求**时弹这个框，在用户点「允许」之前，
/// 所有出站连接都是被挡住的。这个时机不受我们控制 —— 谁先联网，框就在谁头上弹。
///
/// 现场问题（2026-09-01）：**首次安装后直接点微信登录会失败**。因为那时全 App 还没联过网，
/// 第一次出站连接发生在微信授权链路里，请求被挡 → SDK/后端换 code 那一步失败，
/// 用户看到的是一句「微信登录失败」，而真实原因是他还没授权联网。
/// ⚠️ 更麻烦的是**微信的 code 只能消费一次**（见 `BoltFoxApi.weChatMobileLogin` 的说明），
/// 所以这类失败不能靠重试自愈，用户必须重新走一遍授权。
///
/// 把第一次联网提到启动时，用户在首屏就把框点掉，后面所有链路（微信登录、邮箱登录、
/// 版本检查）都在已授权的前提下跑。
///
/// ## 几个刻意的选择
///
/// - **只在 iOS 跑**：安卓没有这层授权，白发一个请求没有意义。
/// - **不 await、不阻塞首帧**：调用方 `unawaited` 即可，它只是「把框弹出来」，
///   不需要等结果，更不该让启动多等一个 RTT。
/// - **失败一律吞掉**：断网、DNS 挂了、服务端 405 —— 对本方法都算成功，
///   因为目的只是「触发系统那次授权判定」，不是「确认服务可用」。
/// - **用 HEAD 而不是 GET**：不取响应体，最省流量；服务端不支持 HEAD 回 405 也无所谓
///   （连接已经建立，框已经弹过了）。
/// - **不走 [ApiClient]**：那一层会拼公共参数、带 userToken、按 retCode 抛
///   [ApiException]、还会静默重试三次。这里只想要一次最朴素的出站连接。
class NetworkPermissionPrimer {
  const NetworkPermissionPrimer._();

  /// 预热请求自己的超时。给得短：它只是去撞一下系统的授权判定，
  /// 用户在框上停留多久与这个超时无关（框弹出来的那一刻目的就达到了）。
  static const Duration _timeout = Duration(seconds: 5);

  /// 触发一次出站连接。**非 iOS 直接返回**，不发任何请求。
  static Future<void> warmUp() async {
    if (!Platform.isIOS) {
      return;
    }
    final uri = Uri.tryParse(ApiConfig.baseUrl);
    if (uri == null) {
      return;
    }
    try {
      final response = await http.head(uri).timeout(_timeout);
      debugPrint('[联网授权] 预热完成 status=${response.statusCode}');
    } catch (error) {
      // 断网 / 用户点了「关闭」/ 服务端不认 HEAD —— 都不影响目的（框已经弹过）。
      debugPrint('[联网授权] 预热请求未成功（不影响功能）：$error');
    }
  }
}
