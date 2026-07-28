import 'package:BoltStar/src/shared/ai_service_consent.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'AI service consent is isolated by user and cleared on logout',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});

      expect(await AiServiceConsent.isAccepted('user-a'), isFalse);
      await AiServiceConsent.accept('user-a');
      expect(await AiServiceConsent.isAccepted('user-a'), isTrue);
      expect(await AiServiceConsent.isAccepted('user-b'), isFalse);

      await AiServiceConsent.accept('user-b');
      expect(await AiServiceConsent.isAccepted('user-b'), isTrue);

      await AiServiceConsent.clear('user-b');
      expect(await AiServiceConsent.isAccepted('user-b'), isFalse);
      expect(await AiServiceConsent.isAccepted('user-a'), isTrue);
    },
  );
}
