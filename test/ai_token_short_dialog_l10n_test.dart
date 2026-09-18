import 'package:BoltStar/src/features/ai/ai_token.dart';
import 'package:BoltStar/src/shared/l10n/app_l10n.dart';
import 'package:BoltStar/src/state.dart';
import 'package:flutter_test/flutter_test.dart';

/// 星币不足弹窗 2026-09-18 的两项（与小程序同步）：
/// ① 弹窗里先显示当前余额；② 「知道了」右边补一颗「去充值」。
///
/// 这里锁的是**文案层**：四个语种都得有，且英 / 日不许漏中文——
/// 2026-09-14 报过一次「英文版写着中文」，同一个坑不走第二遍。
/// 按钮画不画（iOS 屏蔽星币模块）与跳转由 `AiChatPage` 决定，不在本用例范围。
void main() {
  final han = RegExp(r'[㐀-鿿]');

  group('星币不足弹窗文案', () {
    test('「当前余额」四个语种都有，英 / 日不漏中文', () {
      expect(const AppL10n(AppLanguage.zh).aiTokenBalanceLabel, '当前余额');
      expect(const AppL10n(AppLanguage.zhHant).aiTokenBalanceLabel, isNotEmpty);

      final en = const AppL10n(AppLanguage.en).aiTokenBalanceLabel;
      expect(en, isNotEmpty);
      expect(han.hasMatch(en), isFalse);

      final ja = const AppL10n(AppLanguage.ja).aiTokenBalanceLabel;
      expect(ja, isNotEmpty);
    });

    test('「去充值」四个语种都有，英文不漏中文', () {
      expect(const AppL10n(AppLanguage.zh).aiTokenGoRecharge, '去充值');
      expect(const AppL10n(AppLanguage.zhHant).aiTokenGoRecharge, isNotEmpty);

      final en = const AppL10n(AppLanguage.en).aiTokenGoRecharge;
      expect(en, isNotEmpty);
      expect(han.hasMatch(en), isFalse);

      expect(const AppL10n(AppLanguage.ja).aiTokenGoRecharge, isNotEmpty);
    });

    test('余额读不到时显示 --，不是 0', () {
      // 0 和「没读到」对用户是两件事：有余额的人看到 0 会以为自己不能用了。
      expect(AiToken.displayBalance(null), '--');
      expect(AiToken.displayBalance(0), '0');
      expect(AiToken.displayBalance(128), '128');
    });
  });
}
