import 'dart:io' show Platform;

/// BoltFox 后端基础配置（App 版）。
///
/// 与小程序端 `utils/config.js` 对齐：相同 baseUrl、相同响应约定（retCode/retMsg/retData）。
/// 差异在于公共参数 `terminal`：小程序固定为 3，App 按平台区分。
class ApiConfig {
  ApiConfig._();

  /// 后端基础地址。默认生产环境；不传 define 时产物与原硬编码完全一致。
  /// 切测试/预发环境无需改源码：`flutter build apk --dart-define=API_BASE_URL=https://...`
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://api.boltfox.cn',
  );

  /// 普通请求单次超时时间。网络失败会静默重试（见 [ApiClient]），用户端最长约 30s 才看到超时提示。
  static const Duration timeout = Duration(seconds: 10);

  /// 文件上传单次超时时间：上传体积大且服务端还要转码，给更长时间；上传不做自动重试（避免重复上传）。
  static const Duration uploadTimeout = Duration(seconds: 20);

  /// 网络层失败（超时/断网）静默重试次数：首次 + 最多 networkRetryMax 次（共 3 次尝试 ≈ 30s 才提示）。
  static const int networkRetryMax = 2;

  /// 每次重试前的等待间隔，给网络一点恢复时间，同时避免瞬间连打。
  static const Duration networkRetryDelay = Duration(milliseconds: 500);

  /// 终端类型：**Android=1，iOS=2**（小程序=3）。
  ///
  /// ⚠️ 取值以 swagger 为准，别凭直觉排序。`terminal` 在 swagger 里出现 20 处、三种措辞，
  /// 全部一致：`1=安卓客户端,2=苹果客户端,3=小程序` / `1=Android 2=IOS 3=WechatApp` /
  /// `1=Android,2=Ios`。
  ///
  /// 2026-07-19 修：原来写反了（iOS=1/Android=2），后端按 terminal 分发版本信息，
  /// 结果 **iOS 收到安卓的版本号、安卓收到 iOS 的版本号**（`getLastVersion`）。
  /// 这个 header 是全局公共参数，任何按端区分的接口都会一起错，不止版本检查。
  static int get terminal {
    if (Platform.isAndroid) {
      return 1;
    }
    if (Platform.isIOS) {
      return 2;
    }
    // App 只出 Android/iOS 两端，理论不可达；真跑到这里按 Android 处理。
    return 1;
  }
}
