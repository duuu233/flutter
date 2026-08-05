import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:fluwx/fluwx.dart';

/// 微信开放平台「移动应用微信登录」SDK 适配层。
///
/// 页面和业务状态只依赖 [WeChatAuthorizationClient]。后续替换微信 SDK 时，只需新增/替换
/// 这个接口的实现，不需要改动登录页和后端会话落库逻辑。
abstract interface class WeChatAuthorizationClient {
  /// 拉起微信授权并返回一次性 authorization code。
  Future<String> authorize();
}

/// 应用默认实现。替换 SDK 时把这里指向新的 [WeChatAuthorizationClient] 即可。
final WeChatAuthorizationClient defaultWeChatAuthorizationClient =
    FluwxWeChatAuthorizationClient.instance;

/// 微信登录排查开关：为 true 时把原始错误细节（SDK 错误类别 / 后端 retCode+retMsg）
/// 一并弹进 toast，见 `auth_page._withDiagnostics`。
///
/// 默认**开**：微信按开放平台登记的签名校验，授权链路只有 release 包能走通，
/// 而 release 包里 `kDebugMode` 恒 false、`debugPrint` 也没有出口，
/// 出问题时屏幕上只剩一句笼统文案，等于没有现场。
/// 发版前关掉：`flutter build apk --dart-define=WECHAT_LOGIN_DIAGNOSTICS=false`。
const bool kWeChatLoginDiagnostics = bool.fromEnvironment(
  'WECHAT_LOGIN_DIAGNOSTICS',
  defaultValue: true,
);

/// 微信授权错误类别：UI 层据此映射当前语言的用户文案（见 auth_page 的 code→l10n 映射）。
/// [message] 保留中文细节仅供日志排查，**不要**直接展示给非中文用户。
enum WeChatAuthErrorCode {
  /// 平台不支持 / AppID·UniversalLink 未配置 / SDK 注册失败等开发期配置错误。
  config,

  /// 手机上未安装微信。
  notInstalled,

  /// 用户主动取消授权。
  canceled,

  /// 用户拒绝授权。
  denied,

  /// 微信版本过旧不支持授权登录。
  versionUnsupported,

  /// 授权等待超时。
  timeout,

  /// 其余失败（SDK 调用失败、state 校验失败、未返回凭证、拉起失败等）。
  generic,
}

/// 微信授权失败错误。[code] 供 UI 层本地化，[message] 为中文详情（日志用）。
class WeChatAuthorizationException implements Exception {
  const WeChatAuthorizationException(
    this.message, [
    this.code = WeChatAuthErrorCode.generic,
  ]);

  final String message;
  final WeChatAuthErrorCode code;

  @override
  String toString() => message;
}

/// 当前 SDK 所需的非敏感配置。
///
/// AppSecret 必须只保存在服务端，严禁通过 dart-define 或源码打进客户端。
class WeChatAuthorizationConfig {
  const WeChatAuthorizationConfig({
    required this.appId,
    required this.universalLink,
  });

  factory WeChatAuthorizationConfig.fromEnvironment() {
    return const WeChatAuthorizationConfig(
      appId: String.fromEnvironment(
        'WECHAT_APP_ID',
        defaultValue: 'wx4cf0c5f38a70d0bc',
      ),
      universalLink: String.fromEnvironment('WECHAT_UNIVERSAL_LINK'),
    );
  }

  final String appId;

  /// 仅 iOS 需要，且必须与微信开放平台及 Associated Domains 配置一致。
  final String universalLink;
}

/// 基于 fluwx 的临时实现；仅负责从微信客户端取得 code，不在客户端换 access_token。
class FluwxWeChatAuthorizationClient implements WeChatAuthorizationClient {
  FluwxWeChatAuthorizationClient({
    WeChatAuthorizationConfig? config,
    Fluwx? sdk,
  }) : _config = config ?? WeChatAuthorizationConfig.fromEnvironment(),
       _sdkOverride = sdk;

  static final FluwxWeChatAuthorizationClient instance =
      FluwxWeChatAuthorizationClient();

  static const Duration _authorizationTimeout = Duration(minutes: 2);

  final WeChatAuthorizationConfig _config;
  final Fluwx? _sdkOverride;

  // 延迟创建，避免非移动端构建和普通 widget 测试在未点击微信登录时触发原生 channel。
  Fluwx? _sdkInstance;
  bool _registered = false;
  Future<String>? _pendingAuthorization;

  Fluwx get _sdk => _sdkOverride ?? (_sdkInstance ??= Fluwx());

  @override
  Future<String> authorize() {
    final pending = _pendingAuthorization;
    if (pending != null) {
      return pending;
    }

    final request = _authorizeOnce();
    _pendingAuthorization = request;
    return request.whenComplete(() {
      if (identical(_pendingAuthorization, request)) {
        _pendingAuthorization = null;
      }
    });
  }

  Future<String> _authorizeOnce() async {
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.android &&
            defaultTargetPlatform != TargetPlatform.iOS)) {
      throw const WeChatAuthorizationException(
        '微信授权登录仅支持 Android 和 iOS。',
        WeChatAuthErrorCode.config,
      );
    }
    if (_config.appId.trim().isEmpty) {
      throw const WeChatAuthorizationException(
        '微信登录尚未配置 AppID，请设置 WECHAT_APP_ID。',
        WeChatAuthErrorCode.config,
      );
    }
    if (defaultTargetPlatform == TargetPlatform.iOS &&
        _config.universalLink.trim().isEmpty) {
      throw const WeChatAuthorizationException(
        'iOS 微信登录尚未配置 Universal Link。',
        WeChatAuthErrorCode.config,
      );
    }

    try {
      await _ensureRegistered();
      if (!await _sdk.isWeChatInstalled) {
        throw const WeChatAuthorizationException(
          '请先安装微信后再使用微信授权登录。',
          WeChatAuthErrorCode.notInstalled,
        );
      }
      return await _requestAuthorizationCode();
    } on WeChatAuthorizationException {
      rethrow;
    } on PlatformException catch (error) {
      final detail = error.message?.trim();
      throw WeChatAuthorizationException(
        detail == null || detail.isEmpty ? '微信 SDK 调用失败，请稍后重试。' : detail,
      );
    } catch (_) {
      throw const WeChatAuthorizationException('微信授权失败，请稍后重试。');
    }
  }

  Future<void> _ensureRegistered() async {
    if (_registered) {
      return;
    }
    final isIOS = defaultTargetPlatform == TargetPlatform.iOS;
    final success = await _sdk.registerApi(
      appId: _config.appId.trim(),
      doOnIOS: isIOS,
      doOnAndroid: !isIOS,
      universalLink: isIOS ? _config.universalLink.trim() : null,
    );
    if (!success) {
      throw const WeChatAuthorizationException(
        '微信 SDK 注册失败，请检查 AppID、应用签名和 Universal Link。',
        WeChatAuthErrorCode.config,
      );
    }
    _registered = true;
  }

  Future<String> _requestAuthorizationCode() async {
    final state = _newState();
    final responseCompleter = Completer<String>();
    final subscriber = _sdk.addSubscriber((response) {
      if (response is! WeChatAuthResponse || responseCompleter.isCompleted) {
        return;
      }

      // 成功响应必须校验 state；错误响应在部分 SDK/平台上可能不回传 state。
      if (response.isSuccessful) {
        if (response.state != state) {
          responseCompleter.completeError(
            const WeChatAuthorizationException('微信授权状态校验失败，请重新登录。'),
          );
          return;
        }
        final code = response.code?.trim() ?? '';
        if (code.isEmpty) {
          responseCompleter.completeError(
            const WeChatAuthorizationException('微信未返回授权凭证，请重新登录。'),
          );
          return;
        }
        responseCompleter.complete(code);
        return;
      }

      if (response.state != null && response.state != state) {
        return;
      }
      responseCompleter.completeError(_exceptionForResponse(response));
    });

    try {
      final launched = await _sdk.authBy(
        which: NormalAuth(scope: 'snsapi_userinfo', state: state),
      );
      if (!launched) {
        throw const WeChatAuthorizationException('无法拉起微信授权，请稍后重试。');
      }
      return await responseCompleter.future.timeout(
        _authorizationTimeout,
        onTimeout: () => throw const WeChatAuthorizationException(
          '微信授权已超时，请重新登录。',
          WeChatAuthErrorCode.timeout,
        ),
      );
    } finally {
      subscriber.cancel();
    }
  }

  WeChatAuthorizationException _exceptionForResponse(
    WeChatAuthResponse response,
  ) {
    return switch (response.errCode) {
      -2 => const WeChatAuthorizationException(
        '已取消微信授权。',
        WeChatAuthErrorCode.canceled,
      ),
      -4 => const WeChatAuthorizationException(
        '微信授权被拒绝。',
        WeChatAuthErrorCode.denied,
      ),
      -5 => const WeChatAuthorizationException(
        '当前微信版本不支持授权登录。',
        WeChatAuthErrorCode.versionUnsupported,
      ),
      -6 => const WeChatAuthorizationException('微信授权功能暂不可用。'),
      _ => WeChatAuthorizationException(
        response.errStr?.trim().isNotEmpty == true
            ? response.errStr!.trim()
            : '微信授权失败，请稍后重试。',
      ),
    };
  }

  String _newState() {
    final random = Random.secure();
    final entropy = List<int>.generate(
      16,
      (_) => random.nextInt(256),
    ).map((value) => value.toRadixString(16).padLeft(2, '0')).join();
    return 'boltstar_${DateTime.now().microsecondsSinceEpoch}_$entropy';
  }
}
