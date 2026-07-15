import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:BoltStar/src/app.dart';

void main() {
  testWidgets('app boots on the required login page', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const BoltStarApp());
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('登 录'), findsOneWidget);
    expect(find.bySemanticsLabel('微信授权登录'), findsOneWidget);
  });
}
