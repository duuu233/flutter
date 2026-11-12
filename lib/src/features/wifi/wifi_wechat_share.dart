import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:fluwx/fluwx.dart';

import '../account/data/wechat_authorization_client.dart';

/// WiFi 版设备分享发微信（2026-11-12 起发网页卡片）：卡片打开的是设备共享邀请 H5 落地页（[WifiShareLink.h5Url]），
/// 对方在浏览器里拉起 BoltStar App 接受。原先发小程序卡片要打包传小程序原始 ID（WECHAT_MINI_PROGRAM_USERNAME），
/// 没传时「分享设备」置灰——网页卡片只需 App 自己的微信 AppID / Universal Link（与微信登录共用 [WeChatAuthorizationConfig]）。
class WifiWeChatShare {
  WifiWeChatShare._();

  /// 只有 Android / iOS 有微信 SDK。
  static bool get supported =>
      !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

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

  /// 微信是否安装（不支持的平台 / 注册失败按未安装处理）。
  static Future<bool> isWeChatInstalled() async {
    if (!supported) {
      return false;
    }
    try {
      final sdk = await _ready();
      return _registered && await sdk.isWeChatInstalled;
    } catch (_) {
      return false;
    }
  }

  /// 发网页卡片到微信会话；拉起微信成功返回 true（对方是否收到微信不回传）。
  /// 缩略图用设备图（微信要求 thumbData ≤ 32KB，home-device-thumb.png 约 13KB）。
  static Future<bool> shareWebPage({required String url, required String title, required String description}) async {
    if (!supported) {
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
      WeChatShareWebPageModel(
        url,
        title: title,
        description: description,
        thumbData: thumb,
        scene: WeChatScene.session,
      ),
    );
  }
}
