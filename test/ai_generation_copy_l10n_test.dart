import 'package:BoltStar/src/features/ai/presentation/ai_chat_page.dart';
import 'package:BoltStar/src/shared/l10n/app_l10n.dart';
import 'package:BoltStar/src/state.dart';
import 'package:flutter_test/flutter_test.dart';

/// AI 助手生图过程里的文案不跟语种变（2026-09-14 报回：英文版写着「初稿已完成」等中文）。
///
/// 根因是服务端流式 `/chat` 推下来两处写死的简中：`progress.message` 与第一条 `pre_text`
/// 的「星宝努力思考中」占位，而 BoltStar 请求里没有语种参数，后端没法按语种给。
void main() {
  final han = RegExp(r'[㐀-鿿]');

  group('进度文案', () {
    test('英文 / 日文不用服务端的简中 message，按 stage 出本地文案', () {
      const en = AppL10n(AppLanguage.en);
      final label = aiProgressLabel(
        en,
        50,
        stage: 'partial_succeeded',
        message: '初稿已完成',
      );
      expect(label, en.aiProgressDraftReady);
      expect(han.hasMatch(label), isFalse);

      const ja = AppL10n(AppLanguage.ja);
      expect(
        aiProgressLabel(ja, 35, stage: 'generating', message: '正在创作图片'),
        ja.aiProgressCreating,
      );
    });

    test('简中照旧用服务端 message（改文案不用发版），繁中自动转繁', () {
      expect(
        aiProgressLabel(
          const AppL10n(AppLanguage.zh),
          35,
          stage: 'generating',
          message: '正在创作图片',
        ),
        '正在创作图片',
      );
      expect(
        aiProgressLabel(
          const AppL10n(AppLanguage.zhHant),
          35,
          stage: 'generating',
          message: '正在创作图片',
        ),
        toTraditionalChineseForTest('正在创作图片'),
      );
    });

    test('没有 stage 时按数值分档，边界与 stage 对齐', () {
      const en = AppL10n(AppLanguage.en);
      expect(aiProgressLabel(en, 3), en.aiProgressConnecting);
      expect(aiProgressLabel(en, 47), en.aiProgressCreating);
      expect(aiProgressLabel(en, 52), en.aiProgressDraftReady);
      expect(aiProgressLabel(en, 82), en.aiProgressRefining);
      expect(aiProgressLabel(en, 88), en.aiProgressDownloading);
      expect(aiProgressLabel(en, 100), en.aiProgressDone);
    });

    test('每个 stage 在英文、日文下都不是中文', () {
      const stages = <String>[
        'starting',
        'request_sent',
        'generating',
        'partial_succeeded',
        'completed',
        'downloading',
        'uploaded',
        'done',
      ];
      const en = AppL10n(AppLanguage.en);
      for (final stage in stages) {
        final label = aiProgressLabel(en, 50, stage: stage, message: '中文');
        expect(han.hasMatch(label), isFalse, reason: '$stage → $label');
      }
      // 日文用汉字是正常的，只校验没有直接漏出服务端的简中 message。
      const ja = AppL10n(AppLanguage.ja);
      for (final stage in stages) {
        expect(
          aiProgressLabel(ja, 50, stage: stage, message: '服务端简中'),
          isNot('服务端简中'),
        );
      }
    });
  });

  group('「星宝努力思考中」占位', () {
    test('服务端写死的简中占位能认出来（两种写法、带省略号也认）', () {
      expect(AppL10n.isThinkingPlaceholder('星宝努力思考中'), isTrue);
      expect(AppL10n.isThinkingPlaceholder('星宝努力思考创作中'), isTrue);
      expect(AppL10n.isThinkingPlaceholder(' 星宝努力思考中… '), isTrue);
      expect(AppL10n.isThinkingPlaceholder('星宝努力思考中...'), isTrue);
    });

    test('每个语种自己的写法也认', () {
      for (final language in AppLanguage.values) {
        expect(
          AppL10n.isThinkingPlaceholder(AppL10n(language).aiThinkingPlaceholder),
          isTrue,
          reason: '$language',
        );
      }
    });

    test('LLM 写的真预描述不能被当成占位吞掉', () {
      expect(AppL10n.isThinkingPlaceholder('正在为您绘制软萌可爱的小猫画面…'), isFalse);
      expect(AppL10n.isThinkingPlaceholder('星宝努力思考中，马上为您画一只猫'), isFalse);
      expect(AppL10n.isThinkingPlaceholder(''), isFalse);
      expect(AppL10n.isThinkingPlaceholder(null), isFalse);
    });

    test('英文下占位换成英文', () {
      expect(
        han.hasMatch(const AppL10n(AppLanguage.en).aiThinkingPlaceholder),
        isFalse,
      );
    });
  });
}

/// 繁中期望值与 `AppL10n.pick` 同一条转换路径，避免在用例里手写繁体。
String toTraditionalChineseForTest(String zh) =>
    const AppL10n(AppLanguage.zhHant).pick(zh, '', '');
