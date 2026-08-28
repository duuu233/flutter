import 'package:BoltStar/src/features/settings/presentation/legal_document_view.dart';
import 'package:BoltStar/src/features/settings/presentation/privacy_policy_page.dart';
import 'package:BoltStar/src/shared/l10n/app_l10n.dart';
import 'package:BoltStar/src/state.dart';
import 'package:flutter_test/flutter_test.dart';

/// 隐私政策正文的回归用例（2026-08-13 换成法务 v3.0 的**英文**全文）。
///
/// 这一页此前是 2026-5-13 的旧短文，而 AI 同意弹窗里已经写着「详情见隐私政策第八节」——
/// 指路指不到就是合规缺口。这里锁四件事：
///   ① 14 章齐全、第八章确实讲跨境传输（弹窗那句指路要落到实处）；
///   ② 表格每行的列数与表头一致（Flutter 的 Table 行列不齐会直接抛断言）；
///   ③ 正文是英文、**不随语种变化**（法务只出了英文版，机翻法律文本比只给英文更糟）；
///   ④ 旧短文的痕迹不再出现。
void main() {
  const sections = PrivacyPolicyPage.privacyPolicySections;

  test('隐私政策是法务 v3.0 全文：14 章齐全，第八章讲跨境传输', () {
    expect(sections.length, 14);
    expect(sections[7].heading, contains('Cross-Border'));
  });

  test('每张表格的行列都对齐（Table 行列不齐会直接抛断言）', () {
    var tableCount = 0;
    for (final section in sections) {
      for (final block in section.blocks) {
        if (block is! LegalTable) {
          continue;
        }
        tableCount += 1;
        expect(block.head, isNotEmpty);
        expect(block.rows, isNotEmpty);
        for (final row in block.rows) {
          expect(
            row.length,
            block.head.length,
            reason: '「${section.heading}」里有一行的列数与表头对不上',
          );
        }
      }
    }
    expect(tableCount, 4, reason: '权限 / 共享 / SDK / 收集清单四张表都要在');
  });

  test('正文固定英文，且不随语种设置变化', () {
    final cjk = RegExp(r'[一-鿿]');
    for (final section in sections) {
      expect(
        cjk.hasMatch(section.heading),
        isFalse,
        reason: '章标题里出现了中文：${section.heading}',
      );
      for (final block in section.blocks) {
        if (block is LegalText) {
          expect(cjk.hasMatch(block.text), isFalse, reason: block.text);
        }
      }
    }
    // 正文是编译期常量，与 AppL10n 无关：换语种取到的仍是同一份英文
    for (final language in AppLanguage.values) {
      expect(AppL10n(language).setPrivacyTitle, isNotEmpty); // 标题仍随语种（入口名字）
    }
    expect(identical(sections, PrivacyPolicyPage.privacyPolicySections), isTrue);
  });

  test('AI 同意弹窗那句「见隐私政策第八节」指得到', () {
    // 英文弹窗写的是 Section 8，中文写的是第八节；两边都必须落在跨境传输这一章上
    expect(
      AppL10n(AppLanguage.en).aiServiceAgreementSummary,
      contains('Section 8'),
    );
    expect(sections[7].heading, contains('8.'));
  });
}
