import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:fluwx/fluwx.dart';

import '../account/data/wechat_authorization_client.dart';

/// WiFi 版设备分享（2026-10-29 简化版）：App 把「接受分享」的小程序卡片发到微信会话，对方在小程序里接受
/// （与小程序分享列表 `open-type="share"` 发出的是同一张卡片、同一个接受页路径，见 [WifiShareLink]）。
///
/// 需要两项配置：
///   · `WECHAT_MINI_PROGRAM_USERNAME`：小程序原始 ID（`gh_` 开头），且该小程序与本 App 绑定在同一微信开放平台账号下，
///     否则微信拒绝分享。**未配置时分享按钮置灰**，不硬编码猜测值；
///   · `WECHAT_SHARE_WEBPAGE_URL`：低版本微信打不开小程序卡片时的兜底网页（微信要求必填），默认取 App 已关联的域名。
/// AppID / Universal Link 与微信登录共用 [WeChatAuthorizationConfig]。
class WifiWeChatShare {
  WifiWeChatShare._();

  static const String miniProgramUserName = String.fromEnvironment('WECHAT_MINI_PROGRAM_USERNAME');
  static const String webPageUrl = String.fromEnvironment(
    'WECHAT_SHARE_WEBPAGE_URL',
    defaultValue: 'https://badmin.boltfox.cn/',
  );

  static bool get configured =>
      miniProgramUserName.trim().isNotEmpty &&
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

  static Fluwx? _sdk;
  static bool _registered = false;

  static Future<Fluwx> _ready() async {
    final sdk = _sdk ??= Fluwx();
    if (!_registered) {
      final config = WeChatAuthorizationConfig.fromEnvironment();
      final isIOS = defaultTargetPlatform == TargetPlatform.iOS;
      _registered = await sdk.registerApi(
        appId: config.appId.trim(),
        doOnIOS: isIOS,
        doOnAndroid: !isIOS,
        universalLink: isIOS ? config.universalLink.trim() : null,
      );
    }
    return sdk;
  }

  /// 微信是否安装（未配置 / 注册失败按未安装处理）。
  static Future<bool> isWeChatInstalled() async {
    if (!configured) {
      return false;
    }
    try {
      final sdk = await _ready();
      return _registered && await sdk.isWeChatInstalled;
    } catch (_) {
      return false;
    }
  }

  /// 发小程序卡片到微信会话；拉起微信成功返回 true（对方是否收到微信不回传）。
  static Future<bool> shareMiniProgram({required String path, required String title}) async {
    if (!configured) {
      return false;
    }
    final sdk = await _ready();
    if (!_registered) {
      return false;
    }
    Uint8List? thumb;
    try {
      thumb = (await rootBundle.load('assets/images/home-device-thumb.png')).buffer.asUint8List();
    } catch (_) {
      thumb = null;
    }
    return sdk.share(
      WeChatShareMiniProgramModel(
        webPageUrl: webPageUrl,
        userName: miniProgramUserName.trim(),
        path: path,
        title: title,
        hdImageData: thumb,
        thumbData: thumb,
        scene: WeChatScene.session,
      ),
    );
  }
}
