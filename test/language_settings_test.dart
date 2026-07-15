import 'package:BoltStar/src/features/settings/presentation/language_settings_page.dart';
import 'package:BoltStar/src/network/api_session.dart';
import 'package:BoltStar/src/shared/l10n/app_l10n.dart';
import 'package:BoltStar/src/state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('英文保存后当前页立即重译', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final state = PhotoFrameState.seeded();

    await tester.pumpWidget(
      AnimatedBuilder(
        animation: state,
        builder: (context, _) => MaterialApp(
          home: LanguageSettingsPage(state: state),
          builder: (context, child) => AppLocalizationsScope(
            language: state.language,
            child: child ?? const SizedBox.shrink(),
          ),
        ),
      ),
    );

    await tester.tap(find.text('English'));
    await tester.pump();
    await tester.tap(find.text('保存设置'));
    await tester.pump();

    expect(find.text('Language'), findsOneWidget);
    expect(find.text('Simplified Chinese'), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);

    await tester.pump(const Duration(seconds: 3));
    state.dispose();
  });

  testWidgets('繁体中文是独立语种并使用请求码 3', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final state = PhotoFrameState.seeded();

    await tester.pumpWidget(
      AnimatedBuilder(
        animation: state,
        builder: (context, _) => MaterialApp(
          home: LanguageSettingsPage(state: state),
          builder: (context, child) => AppLocalizationsScope(
            language: state.language,
            child: child ?? const SizedBox.shrink(),
          ),
        ),
      ),
    );

    await tester.tap(find.text('繁体中文'));
    await tester.tap(find.text('保存设置'));
    await tester.pump();

    expect(state.language, AppLanguage.zhHant);
    expect(ApiSession.instance.languageCode, 3);
    expect(find.text('語種設置'), findsOneWidget);
    expect(find.text('繁體中文'), findsOneWidget);
    expect(find.text('保存設置'), findsOneWidget);

    await tester.pump(const Duration(seconds: 3));
    state.dispose();
  });

  testWidgets('日语保存后当前页立即重译并使用请求码 4', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final state = PhotoFrameState.seeded();

    await tester.pumpWidget(
      AnimatedBuilder(
        animation: state,
        builder: (context, _) => MaterialApp(
          home: LanguageSettingsPage(state: state),
          builder: (context, child) => AppLocalizationsScope(
            language: state.language,
            child: child ?? const SizedBox.shrink(),
          ),
        ),
      ),
    );

    await tester.tap(find.text('日本语'));
    await tester.tap(find.text('保存设置'));
    await tester.pump();

    expect(state.language, AppLanguage.ja);
    expect(ApiSession.instance.languageCode, 4);
    expect(find.text('言語設定'), findsOneWidget);
    expect(find.text('保存'), findsOneWidget);

    await tester.pump(const Duration(seconds: 3));
    state.dispose();
  });

  test(
    'loads both current and legacy Traditional Chinese preference values',
    () async {
      for (final value in ['zhHant', 'zh-Hant', 'zh_hant']) {
        SharedPreferences.setMockInitialValues({'app_language': value});
        expect(await LanguagePreference.load(), AppLanguage.zhHant);
      }
    },
  );
}
