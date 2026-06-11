import 'dart:io' show Platform;

/// BoltFox 后端基础配置（App 版）。
///
/// 与小程序端 `utils/config.js` 对齐：相同 baseUrl、相同响应约定（retCode/retMsg/retData）。
/// 差异在于公共参数 `terminal`：小程序固定为 3，App 按平台区分。
class ApiConfig {
  ApiConfig._();

  /// 后端基础地址。
  static const String baseUrl = 'https://api.boltfox.cn';

  /// 请求 / 上传超时时间。
  static const Duration timeout = Duration(seconds: 12);

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
