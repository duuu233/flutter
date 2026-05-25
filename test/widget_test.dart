import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:BoltStar/src/app.dart';

void main() {
  testWidgets('app boots and can switch to mine tab', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const FrameFlowApp());
    await tester.pump();

    expect(find.byKey(const Key('home-title')), findsOneWidget);

    await tester.tap(find.text('我的'));
    await tester.pump();

    expect(find.byKey(const Key('mine-page-title')), findsOneWidget);
  });
}
