import 'package:BoltStar/src/network/api_session.dart';
import 'package:BoltStar/src/shared/l10n/system_language.dart';
import 'package:BoltStar/src/state.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('简中：Hans / CN / SG / 裸 zh 都归简体', () {
    for (final locale in <Locale>[
      const Locale('zh'),
      const Locale('zh', 'CN'),
      const Locale('zh', 'SG'),
      const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
      const Locale.fromSubtags(
        languageCode: 'zh',
        scriptCode: 'Hans',
        countryCode: 'CN',
      ),
    ]) {
      expect(
        SystemLanguage.fromLocale(locale),
        AppLanguage.zh,
        reason: '$locale',
      );
    }
  });

  test('繁中：Hant 脚本与台/港/澳地区都归繁体', () {
    for (final locale in <Locale>[
      const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
      const Locale.fromSubtags(
        languageCode: 'zh',
        scriptCode: 'Hant',
        countryCode: 'TW',
      ),
      const Locale('zh', 'TW'),
      const Locale('zh', 'HK'),
      const Locale('zh', 'MO'),
    ]) {
      expect(
        SystemLanguage.fromLocale(locale),
        AppLanguage.zhHant,
        reason: '$locale',
      );
    }
  });

  test('英文与日文按语言码归位（带地区也认）', () {
    expect(SystemLanguage.fromLocale(const Locale('en')), AppLanguage.en);
    expect(SystemLanguage.fromLocale(const Locale('en', 'US')), AppLanguage.en);
    expect(SystemLanguage.fromLocale(const Locale('en', 'GB')), AppLanguage.en);
    expect(SystemLanguage.fromLocale(const Locale('ja')), AppLanguage.ja);
    expect(SystemLanguage.fromLocale(const Locale('ja', 'JP')), AppLanguage.ja);
  });

  test('四语种之外一律英文兜底（含读不到系统语言）', () {
    for (final locale in <Locale>[
      const Locale('ko'),
      const Locale('de', 'DE'),
      const Locale('fr'),
      const Locale('es', 'MX'),
      const Locale('th'),
      const Locale('ru'),
    ]) {
      expect(
        SystemLanguage.fromLocale(locale),
        AppLanguage.en,
        reason: '$locale',
      );
    }
    expect(SystemLanguage.fromLocale(null), AppLanguage.en);
    expect(SystemLanguage.fallback, AppLanguage.en);
  });

  testWidgets('resolve 取系统默认语言，且初始语种同步进请求头', (tester) async {
    tester.platformDispatcher.localeTestValue = const Locale('ja', 'JP');
    addTearDown(tester.platformDispatcher.clearLocaleTestValue);

    expect(SystemLanguage.resolve(), AppLanguage.ja);

    final state = PhotoFrameState.seeded(language: SystemLanguage.resolve());
    expect(state.language, AppLanguage.ja);
    expect(ApiSession.instance.languageCode, 4);
    state.dispose();
  });

  testWidgets('系统是韩语时按英文起步', (tester) async {
    tester.platformDispatcher.localeTestValue = const Locale('ko', 'KR');
    addTearDown(tester.platformDispatcher.clearLocaleTestValue);

    final state = PhotoFrameState.seeded(language: SystemLanguage.resolve());
    expect(state.language, AppLanguage.en);
    expect(ApiSession.instance.languageCode, 1);
    state.dispose();
  });
}
