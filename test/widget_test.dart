import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:BoltStar/src/app.dart';

/// 没存过语种时 App 跟随系统语言（见 `SystemLanguage`），而测试环境的系统语言
/// 默认是 en-US。断言中文文案的用例必须先把系统语言钉成简中，否则测的是英文界面。
void _useChineseSystemLocale(WidgetTester tester) {
  tester.platformDispatcher.localeTestValue = const Locale('zh', 'CN');
  addTearDown(tester.platformDispatcher.clearLocaleTestValue);
}

void main() {
  testWidgets('app boots on the required login page', (tester) async {
    SharedPreferences.setMockInitialValues({});
    _useChineseSystemLocale(tester);
    await tester.pumpWidget(const BoltStarApp());
    await tester.pump(const Duration(seconds: 2));
    // 越过根节点交叉淡入（kRootTransitionDuration = 1100ms）后再断言。
    await tester.pump(const Duration(milliseconds: 1200));

    expect(find.text('登 录'), findsOneWidget);
    expect(find.bySemanticsLabel('微信授权登录'), findsOneWidget);
  });

  testWidgets('app restores a persisted session and renders home safely', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'boltstar.userToken': 'widget-test-token',
      'boltstar.jwtToken': 'widget-test-jwt-token',
    });
    _useChineseSystemLocale(tester);

    await tester.pumpWidget(const BoltStarApp());
    await tester.pump(const Duration(seconds: 2));
    // 越过根节点交叉淡入（kRootTransitionDuration = 1100ms）后再断言。
    await tester.pump(const Duration(milliseconds: 1200));

    expect(find.text('首页'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('系统语言不在四语种内时冷启动按英文渲染', (tester) async {
    SharedPreferences.setMockInitialValues({});
    // 韩语系统：四语种之外 → 兜底英文（不是简中）。
    tester.platformDispatcher.localeTestValue = const Locale('ko', 'KR');
    addTearDown(tester.platformDispatcher.clearLocaleTestValue);

    await tester.pumpWidget(const BoltStarApp());
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(milliseconds: 1200));

    expect(find.text('Log In'), findsOneWidget);
    expect(find.text('登 录'), findsNothing);
  });

  testWidgets('存过语种时以用户选择为准，不跟随系统语言', (tester) async {
    SharedPreferences.setMockInitialValues({'app_language': 'ja'});
    tester.platformDispatcher.localeTestValue = const Locale('zh', 'CN');
    addTearDown(tester.platformDispatcher.clearLocaleTestValue);

    await tester.pumpWidget(const BoltStarApp());
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(milliseconds: 1200));

    expect(find.text('ログイン'), findsOneWidget);
  });
}
