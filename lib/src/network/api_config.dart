import 'dart:io' show Platform;

/// BoltFox 后端基础配置（App 版）。
///
/// 与小程序端 `utils/config.js` 对齐：相同 baseUrl、相同响应约定（retCode/retMsg/retData）。
/// 差异在于公共参数 `terminal`：小程序固定为 3，App 按平台区分。
class ApiConfig {
  ApiConfig._();

  /// 后端基础地址。
  static const String baseUrl = 'https://api.boltfox.cn';

  /// 普通请求单次超时时间。网络失败会静默重试（见 [ApiClient]），用户端最长约 30s 才看到超时提示。
  static const Duration timeout = Duration(seconds: 10);

  /// 文件上传单次超时时间：上传体积大且服务端还要转码，给更长时间；上传不做自动重试（避免重复上传）。
  static const Duration uploadTimeout = Duration(seconds: 20);

  /// 网络层失败（超时/断网）静默重试次数：首次 + 最多 networkRetryMax 次（共 3 次尝试 ≈ 30s 才提示）。
  static const int networkRetryMax = 2;

  /// 每次重试前的等待间隔，给网络一点恢复时间，同时避免瞬间连打。
  static const Duration networkRetryDelay = Duration(milliseconds: 500);

  /// 终端类型：iOS=1，Android=2（小程序=3、PC=4）。
  ///
  /// 注：取值需与后端约定一致，如后端另有定义请在此调整。
  static int get terminal {
    if (Platform.isIOS) {
      return 1;
    }
    if (Platform.isAndroid) {
      return 2;
    }
    return 1;
  }
}
