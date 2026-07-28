import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:BoltStar/src/app.dart';

void main() {
  testWidgets('app boots on the required login page', (tester) async {
    SharedPreferences.setMockInitialValues({});
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

    await tester.pumpWidget(const BoltStarApp());
    await tester.pump(const Duration(seconds: 2));
    // 越过根节点交叉淡入（kRootTransitionDuration = 1100ms）后再断言。
    await tester.pump(const Duration(milliseconds: 1200));

    expect(find.text('首页'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
