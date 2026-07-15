import 'package:flutter_test/flutter_test.dart';

import 'package:BoltStar/src/app.dart';

void main() {
  testWidgets('app boots on the required login page', (tester) async {
    await tester.pumpWidget(const BoltStarApp());
    await tester.pump();

    expect(find.text('登 录'), findsOneWidget);
    expect(find.text('微信授权登录'), findsOneWidget);
  });
}
