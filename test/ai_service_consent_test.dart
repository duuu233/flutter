import 'package:BoltStar/src/shared/ai_service_consent.dart';
import 'package:BoltStar/src/shared/l10n/app_l10n.dart';
import 'package:BoltStar/src/state.dart';
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

  // 供应商换人（阿里云 → 火山引擎）是数据接收方的实质变更：不升版的话，老用户会带着
  // 「同意发给阿里云」的旧记录，端上直接把内容发给另一家公司，且再也不会问他第二次。
  test('a material revision invalidates consent granted under the old version', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'boltstar.aiServiceConsent.2026-07-28-v2.user-a': true,
    });

    expect(AiServiceConsent.version, isNot('2026-07-28-v2'));
    expect(await AiServiceConsent.isAccepted('user-a'), isFalse);
  });

  test('the consent summary names the current AI provider in every language', () {
    for (final language in AppLanguage.values) {
      final summary = AppL10n(language).aiServiceAgreementSummary;
      expect(
        summary,
        isNot(anyOf(contains('阿里云'), contains('Alibaba'), contains('Model Studio'))),
        reason: '$language 的同意文案里还留着旧供应商',
      );
      expect(
        summary,
        anyOf(contains('火山引擎'), contains('Volcano Engine')),
        reason: '$language 的同意文案没写明当前供应商',
      );
      // 境外传输是**单独告知**事项（网关在新加坡）：少了这一段，用户同意的就不是实际发生的事
      expect(
        summary,
        anyOf(contains('境外'), contains('国外'), contains('outside mainland China')),
        reason: '$language 的同意文案缺少境外传输告知',
      );
      expect(
        summary,
        // 繁中由简中自动转换（节 → 節），所以两种写法都要认
        anyOf(
          contains('第八节'),
          contains('第八節'),
          contains('第8章'),
          contains('Section 8'),
        ),
        reason: '$language 的同意文案应指向隐私政策里讲跨境传输的那一节',
      );
    }
  });
}
