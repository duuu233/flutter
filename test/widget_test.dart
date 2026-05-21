import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_application_2/src/app.dart';

void main() {
  testWidgets('app boots and can switch to mine tab', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const FrameFlowApp());
    await tester.pump();

    expect(find.byKey(const Key('home-title')), findsOneWidget);

    await tester.tap(find.byIcon(Icons.person_outline));
    await tester.pump();

    expect(find.byKey(const Key('mine-page-title')), findsOneWidget);
  });
}
