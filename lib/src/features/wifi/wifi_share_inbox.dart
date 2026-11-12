import '../../native_device_api.dart';
import '../../shared/debug_log.dart';

/// 设备共享邀请链接的收件箱（2026-11-12）：原生侧（Android ShareLinkActivity / iOS SceneDelegate）记下
/// boltstar://share/accept?… 的 query，这里读走后先存着，等闪屏结束且已登录再由根组件打开接受页。
/// 未登录时一直留着，登录成功后打开（同小程序「登录并接受」）；只在内存，进程被杀就丢（用户再点一次链接即可）。
class WifiShareInbox {
  WifiShareInbox._();

  static Map<String, String>? _pending;

  static bool get hasPending => _pending != null;

  /// 从原生侧读走最新一条（有就覆盖旧的）。
  static Future<void> pull() async {
    final link = await NativeDeviceApi.consumeShareLink();
    if (link != null) {
      _pending = link;
      DebugLog.log('[设备分享] 收到邀请链接 ${link.keys.join(',')}');
    }
  }

  /// 取出并清空。
  static Map<String, String>? take() {
    final value = _pending;
    _pending = null;
    return value;
  }
}
