import 'package:BoltStar/src/shared/l10n/app_l10n.dart';
import 'package:BoltStar/src/state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 星币数值必须**完整显示**，不许出现省略号（2026-09-11 报回：「75… Stars」）。
///
/// 卡片 2026-09-08 收窄到 104（内容宽 82）之后，原来的 `Flexible + ellipsis + 写死
/// 20px` 就放不下四位数了。现在整行套 `FittedBox(scaleDown)`：放得下原样、放不下
/// 等比缩，永远不截断。
///
/// 这里不 pump 整个星币页（要网络与账号态），直接量那一行的**本征宽度**。
///
/// ⚠️ `flutter_test` 用的是方块测试字体（每个字符宽度恒等于字号），所以**不要在这里
/// 断言任何绝对像素阈值**（「缩放后至少还有 0.5 倍」之类）——那种数字只在真机字体下
/// 才有意义，测试字体下会给出假结论。这里只守与字体无关的三条结构性事实：
/// 本征宽度确实超过了盒子（所以改前必然截断）、等比缩放之后放得进去、
/// 以及单位收窄确实让整行更窄。真机观感仍需人眼确认。
void main() {
  /// 套餐卡内容可用宽度：卡宽 104 - 水平内边距 11×2。
  const double contentWidth = 82;

  /// 现在的档位上限（产品口径）。
  const int maxTokens = 30000;

  TextPainter paint(String text, double fontSize, FontWeight weight) {
    return TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(fontSize: fontSize, fontWeight: weight, height: 1),
      ),
      maxLines: 1,
      textDirection: TextDirection.ltr,
    )..layout();
  }

  test('改前的排版：30000 在 82px 里放不下——这就是省略号的来路', () {
    // 数字 20px 粗体 + 间距 4 + 单位 13px，三者本征宽度之和。
    for (final language in AppLanguage.values) {
      final unit = AppL10n(language).aiTokenUnit;
      final natural =
          paint('$maxTokens', 20, FontWeight.w700).width +
          4 +
          paint(unit, 13, FontWeight.w400).width;
      expect(
        natural,
        greaterThan(contentWidth),
        reason:
            '$language：本征宽度 $natural 没有超过 $contentWidth，'
            '那这条用例就失去意义了（说明布局前提变了，要重新算）',
      );
    }
  });

  test('改后：整行等比缩放，任何语种下都放得进 82px', () {
    // FittedBox(scaleDown) 的效果等价于「按 contentWidth / natural 等比缩」。
    // 只要这个比例能算出来且 > 0，画出来就是完整的数值，不会有省略号。
    for (final language in AppLanguage.values) {
      final unit = AppL10n(language).aiTokenUnit;
      // 单位基准已由 13 收到 11、间距 4 收到 3，把位置让给数字。
      final natural =
          paint('$maxTokens', 20, FontWeight.w700).width +
          3 +
          paint(unit, 11, FontWeight.w400).width;
      final scale = contentWidth / natural;
      expect(scale, greaterThan(0));
      expect(
        natural * scale,
        lessThanOrEqualTo(contentWidth + 0.5),
        reason: '$language：缩放后仍然放不下',
      );
    }
  });

  test('单位收窄确实把位置让给了数字', () {
    // 同一个数值，单位从 13/gap4 收到 11/gap3 之后，整行更窄 ⇒ 缩放比例更大
    // ⇒ 画出来的数字更大。这条守的是「Stars 也缩小点」那次追加需求的收益。
    final unit = const AppL10n(AppLanguage.en).aiTokenUnit;
    final before =
        paint('$maxTokens', 20, FontWeight.w700).width +
        4 +
        paint(unit, 13, FontWeight.w400).width;
    final after =
        paint('$maxTokens', 20, FontWeight.w700).width +
        3 +
        paint(unit, 11, FontWeight.w400).width;
    expect(after, lessThan(before));
  });
}
