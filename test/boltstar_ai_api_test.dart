import 'package:BoltStar/src/features/ai/ai_i18n.dart';
import 'package:BoltStar/src/network/boltstar_ai_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BoltStarAiApi gateway error parsing', () {
    const requestId = '1-6a687ba9-01f194-2ccddcd63f58';
    const expected =
        'JWTTokenIsMissing：the jwt token is missing（RequestId: $requestId）';

    test('recognizes the fixed JWT error and keeps RequestId', () {
      final message = BoltStarAiApi.gatewayErrorMessage(const {
        'RequestId': requestId,
        'Code': 'JWTTokenIsMissing',
        'Message': 'the jwt token is missing',
      });

      expect(message, expected);
    });

    test('does not expose a response with a different message', () {
      final message = BoltStarAiApi.gatewayErrorMessage(const {
        'RequestId': requestId,
        'Code': 'JWTTokenIsMissing',
        'Message': 'another gateway error',
      });

      expect(message, isNull);
    });

    test('trusted message is separate from developer detail', () {
      const error = AiApiException(
        code: 31001,
        detail: 'developer-only detail',
        userMessage: expected,
      );

      expect(error.detail, 'developer-only detail');
      expect(error.userMessage, expected);
    });

    testWidgets('trusted gateway message is shown in a toast', (tester) async {
      late BuildContext pageContext;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              pageContext = context;
              return const SizedBox();
            },
          ),
        ),
      );

      await AiI18n.of(pageContext).handleError(
        pageContext,
        const AiApiException(code: 31001, userMessage: expected),
      );
      await tester.pump();

      expect(find.text('接口-$expected'), findsOneWidget);
      await tester.pump(const Duration(seconds: 6));
    });
  });
}
