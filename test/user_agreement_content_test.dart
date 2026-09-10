import 'dart:io';

import 'package:BoltStar/src/features/settings/presentation/legal_document_view.dart';
import 'package:BoltStar/src/features/settings/presentation/user_agreement_page.dart';
import 'package:BoltStar/src/shared/l10n/app_l10n.dart';
import 'package:flutter_test/flutter_test.dart';

/// 用户协议正文的回归用例（2026-09-10 由 2026-5-13 的旧短文换成法务 20260909 那份 docx
/// 的**英文**版）。
///
/// 旧版是三节几百字、走 `AppL10n.pick` 的中英日三份译文；法务给的是 15 章全文，含星币、
/// AI、固件升级、违规处理阶梯表与争议解决。这里锁三件事：
///   ① 15 章齐全，关键章节没在转换中丢；
///   ② 第九章那张违规处理表行列对齐（Flutter 的 Table 行列不齐会直接抛断言）；
///   ③ 正文是英文、**不随语种变化**（法务只出了中英两版，App 端口径是英文）。
void main() {
  const sections = UserAgreementPage.userAgreementSections;

  test('用户协议是法务全文：15 章齐全', () {
    expect(sections.length, 15);
    expect(sections.first.heading, contains('1.'));
    expect(sections.last.heading, contains('15.'));
    final headings = sections.map((section) => section.heading).join('\n');
    for (final topic in <String>[
      'Star Coins',
      'AI Creation',
      'Firmware',
      'Intellectual Property',
      'Dispute Resolution',
    ]) {
      expect(headings, contains(topic), reason: '章标题里应当有「$topic」');
    }
  });

  test('违规处理表的行列对齐（Table 行列不齐会直接抛断言）', () {
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
    expect(tableCount, 1, reason: '第九章的违规处理阶梯表要在');
  });

  test('违规阶梯与《BoltStar AI 服务协议》同口径', () {
    // 法务原文写的是「1st / 2nd / 3rd 各封 24 小时」并声称与 AI 协议一致，而 AI 协议
    // 2026-09-10 已改成「前三次只提示违禁」——产品裁定用户协议按 AI 协议改。这条用例把
    // 两页钉在一起：AI 协议页改了口径而这里没跟，会当场红。
    final tiers = sections
        .expand((section) => section.blocks)
        .whereType<LegalTable>()
        .single;
    expect(tiers.head, <String>['Violation count', 'Measure']);
    expect(tiers.rows, <List<String>>[
      <String>['1st-3rd violations', 'AI features show a violation warning'],
      <String>[
        'After 3 cumulative violations, each additional violation',
        'AI features banned for 24 hours',
      ],
      <String>['Upon 9 cumulative violations', 'AI features permanently banned'],
    ]);

    // AI 服务协议那一页的阶梯是 `l10n.pick` 里的纯文本、`_sectionsFor` 又是私有方法，
    // 拿不到常量；照小程序端的做法直接读源码断言（阶梯改了这里会红）。
    final aiSource = File(
      'lib/src/features/settings/presentation/ai_service_agreement_page.dart',
    ).readAsStringSync();
    for (final line in <String>[
      '1st-3rd | Violation warning shown in AI features',
      'After 3 total, each additional violation | 24-hour AI feature suspension',
      '9 total | Permanent AI feature suspension',
      '第1-3次｜AI功能提示违禁',
      '1〜3回目｜AI機能で違反警告を表示',
    ]) {
      expect(aiSource, contains(line), reason: 'AI 服务协议缺少阶梯行：$line');
    }
    for (final stale in <String>[
      '1st | 24-hour AI feature suspension',
      '第1次｜AI功能封禁24小时',
      '1回目｜AI機能を24時間停止',
    ]) {
      expect(aiSource, isNot(contains(stale)), reason: 'AI 服务协议仍有旧阶梯：$stale');
    }
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
      expect(AppL10n(language).setAgreementTitle, isNotEmpty); // 标题仍随语种
    }
    expect(identical(sections, UserAgreementPage.userAgreementSections), isTrue);
  });

  test('经产品确认的排版修正都在（法务下次给新版时这几条要重新过一遍）', () {
    final all = <String>[
      for (final section in sections) ...<String>[
        section.heading,
        for (final block in section.blocks)
          if (block is LegalText)
            block.text
          else if (block is LegalTable) ...<String>[
            ...block.head,
            for (final row in block.rows) ...row,
          ],
      ],
    ].join('\n');

    // ③ 粗体 run 边界造成的「句号后缺空格」已补齐
    for (final broken in <String>[
      'bold.By',
      'Agreement.If',
      'app.If',
      'prevail.Functions',
      'others.You',
      'Account".After',
    ]) {
      expect(all, isNot(contains(broken)));
    }
    // 同一来源的「标点前多一个空格」也已收齐
    expect(RegExp(r'\s+[.,;]').hasMatch(all), isFalse, reason: '仍有标点前多空格');
  });
}
