import 'package:BoltStar/src/shared/l10n/app_l10n.dart';
import 'package:BoltStar/src/state.dart';
import 'package:flutter_test/flutter_test.dart';

/// AI 助手顶栏标题不跟语种变（2026-09-11 报回）。
///
/// 根因是**后端**新建会话时把标题写死成简中「新对话」，而判定占位时拿的是
/// `l10n.aiNewChat`（跟着 App 语种变）。英文环境下 `'新对话' != 'New Chat'`，
/// 于是这个占位被当成用户自己起的标题，原样画到顶栏和会话列表上。
void main() {
  test('任意语种下的「新对话」占位都要认出来', () {
    // 后端写死的那个（简中）。**英/日环境下也必须认出来**——这条就是 bug 本身。
    expect(AppL10n.isNewChatTitle('新对话'), isTrue);
    expect(AppL10n.isNewChatTitle('New Chat'), isTrue);
    expect(AppL10n.isNewChatTitle('新しいチャット'), isTrue);
    // 繁中由 `_pick` 从简中自动转换，同样要覆盖。
    expect(AppL10n.isNewChatTitle(const AppL10n(AppLanguage.zhHant).aiNewChat), isTrue);

    // 空与 null 按「还没起名」处理。
    expect(AppL10n.isNewChatTitle(''), isTrue);
    expect(AppL10n.isNewChatTitle(null), isTrue);
    expect(AppL10n.isNewChatTitle('   '), isTrue);
  });

  test('用户自己起的标题不能被当成占位吞掉', () {
    // 首条用户消息会成为标题，里面可能**恰好包含**「新对话」三个字——
    // 只有完全相等才算占位，否则用户的标题会被换成当前语种的「新对话」。
    expect(AppL10n.isNewChatTitle('新对话框怎么用'), isFalse);
    expect(AppL10n.isNewChatTitle('帮我生成一张图'), isFalse);
    expect(AppL10n.isNewChatTitle('New Chat App 设计稿'), isFalse);
  });

  test('每个语种的 aiNewChat 都被覆盖——改文案不会漏掉某一种', () {
    // 用遍历语种而不是写死一张表，正是为了这条：任何一个语种的 `aiNewChat`
    // 改了，判定自动跟上，不会重新长出同一个 bug。
    for (final language in AppLanguage.values) {
      expect(
        AppL10n.isNewChatTitle(AppL10n(language).aiNewChat),
        isTrue,
        reason: '$language 的 aiNewChat 没有被 isNewChatTitle 认出来',
      );
    }
  });
}
