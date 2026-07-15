import 'package:BoltStar/src/features/settings/presentation/language_settings_page.dart';
import 'package:BoltStar/src/shared/l10n/app_l10n.dart';
import 'package:BoltStar/src/state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('保存语言后当前页立即重译', (tester) async {
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
}
