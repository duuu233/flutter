import 'package:flutter/widgets.dart';

import '../../state.dart';

/// 首次启动按**手机系统语言**决定 App 语种（App 端独有；小程序侧另有 `utils/language.js`）。
///
/// 生效顺序：用户在「语种设置」里存过 `LanguagePreference` 就一直以那份为准，没存过才看系统语言。
/// 也就是说这里只影响「装完第一次打开」和「从没进过语种设置」的用户，不会覆盖用户的显式选择。
///
/// ⚠️ 系统语言不在四语种内时兜底 **英文**，不是简中：中文兜底会让一个韩国/德国用户
/// 开屏就撞上一屏看不懂的中文，而英文是这类场景的通行兜底（小程序侧兜底简中是历史取值，
/// 两端在这一点上有意不同，见 `docs/integration/APP_VS_MINIPROGRAM.md`）。
class SystemLanguage {
  const SystemLanguage._();

  /// 系统语言不在支持的四种之内时用英文。
  static const AppLanguage fallback = AppLanguage.en;

  /// 当前系统首选语言 → App 语种。
  ///
  /// 取 `platformDispatcher.locale`（= 系统语言列表里的第一项，即「系统默认语言」），
  /// 不遍历用户的备选语言列表：产品口径是「按系统默认语言，不在四语种内就英文」。
  static AppLanguage resolve() =>
      fromLocale(WidgetsBinding.instance.platformDispatcher.locale);

  /// 单个 [Locale] 的归一化（[resolve] 的纯函数内核，便于测试）。
  static AppLanguage fromLocale(Locale? locale) {
    if (locale == null) {
      return fallback;
    }
    switch (locale.languageCode.toLowerCase()) {
      case 'zh':
        return _isTraditional(locale) ? AppLanguage.zhHant : AppLanguage.zh;
      case 'ja':
        return AppLanguage.ja;
      case 'en':
        return AppLanguage.en;
      default:
        return fallback;
    }
  }

  /// 中文分简繁：`Hant` 脚本，或台/港/澳三地（这些机器常只报地区、不报脚本）算繁体，
  /// 其余（`Hans` / CN / SG / 光一个 `zh`）算简体。
  static bool _isTraditional(Locale locale) {
    if (locale.scriptCode?.toLowerCase() == 'hant') {
      return true;
    }
    const traditionalRegions = {'TW', 'HK', 'MO'};
    return traditionalRegions.contains(locale.countryCode?.toUpperCase());
  }
}
