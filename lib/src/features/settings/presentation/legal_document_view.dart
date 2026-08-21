import 'package:flutter/material.dart';

import 'package:BoltStar/src/shared/widgets/figma_common.dart';
import '../../../shared/l10n/app_l10n.dart';

/// 法律文本页面的正文区块（标题 + 内容）。
///
/// [body] 是整段纯文本（用户协议 / AI 服务协议这类短文用它就够）；隐私政策那种带
/// **小节标题、要点列表和表格**的长文用 [blocks]，两者可以同时给（先画 body 再画 blocks）。
class LegalSection {
  const LegalSection({
    required this.heading,
    this.body = '',
    this.blocks = const <LegalBlock>[],
  });

  final String heading;
  final String body;
  final List<LegalBlock> blocks;
}

/// 长文里的一个正文块。见 [LegalText] / [LegalTable]。
abstract class LegalBlock {
  const LegalBlock();
}

/// 段落（[bullet]=true 时前面带圆点，[subHeading]=true 时是 2.1 这类小节标题）。
class LegalText extends LegalBlock {
  const LegalText(this.text, {this.bullet = false, this.subHeading = false});

  final String text;
  final bool bullet;
  final bool subHeading;
}

/// 表格（权限清单、SDK 清单这类）。
///
/// ⚠️ 列宽不写死、行高更不能写死：权限说明、SDK 名称都会折行。列多到一屏放不下时
/// 整张表**横向可滚**——把字挤成一列一个字才是真的没法读。
class LegalTable extends LegalBlock {
  const LegalTable({required this.head, required this.rows});

  final List<String> head;
  final List<List<String>> rows;
}

/// 隐私政策 / 用户协议等长文本页面的可滚动正文视图。
///
/// 对照小程序 `subpackages/settings/privacy`：整篇正文置于一张玻璃卡内，
/// 居中大标题 + 左右分布的更新/生效日期 + 分节小标题与正文段落。
class LegalDocumentView extends StatelessWidget {
  const LegalDocumentView({
    super.key,
    required this.title,
    required this.updatedAt,
    required this.effectiveAt,
    required this.sections,
    this.intro,
  });

  final String title;
  final String updatedAt;
  final String effectiveAt;
  final List<LegalSection> sections;
  final String? intro;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 30),
      child: FigmaGlassCard(
        borderRadius: 11,
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: Text(title, style: _DocStyles.title)),
            const SizedBox(height: 15),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  AppL10n.of(context).setUpdatedDate(updatedAt),
                  style: _DocStyles.meta,
                ),
                Text(
                  AppL10n.of(context).setEffectiveDate(effectiveAt),
                  style: _DocStyles.meta,
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (intro != null && intro!.trim().isNotEmpty) ...[
              Text(intro!, style: _DocStyles.body),
              const SizedBox(height: 16),
            ],
            for (final section in sections) ...[
              Text(section.heading, style: _DocStyles.heading),
              const SizedBox(height: 8),
              if (section.body.trim().isNotEmpty)
                Text(section.body, style: _DocStyles.body),
              for (final block in section.blocks) _buildBlock(block),
              const SizedBox(height: 16),
            ],
          ],
        ),
      ),
    );
  }
}

Widget _buildBlock(LegalBlock block) {
  if (block is LegalText) {
    if (block.subHeading) {
      return Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 4),
        child: Text(block.text, style: _DocStyles.subHeading),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(
        block.bullet ? '• ${block.text}' : block.text,
        style: _DocStyles.body,
      ),
    );
  }
  if (block is LegalTable) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: _LegalTableView(table: block),
    );
  }
  return const SizedBox.shrink();
}

class _LegalTableView extends StatelessWidget {
  const _LegalTableView({required this.table});

  final LegalTable table;

  /// 每列的最小可读宽度。窄于它就没法读了，这时整张表横向滚动。
  static const double _minColumnWidth = 96;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final minWidth = table.head.length * _minColumnWidth;
        final fits = minWidth <= constraints.maxWidth;
        final content = SizedBox(
          width: fits ? constraints.maxWidth : minWidth,
          child: Table(
            border: TableBorder.all(
              color: const Color(0xFF7E858F).withValues(alpha: 0.22),
              width: 1,
            ),
            defaultVerticalAlignment: TableCellVerticalAlignment.top,
            children: [
              TableRow(
                decoration: BoxDecoration(
                  color: const Color(0xFF7E858F).withValues(alpha: 0.08),
                ),
                children: [
                  for (final cell in table.head)
                    _cell(cell, style: _DocStyles.tableHead),
                ],
              ),
              for (final row in table.rows)
                TableRow(
                  children: [
                    for (final cell in row) _cell(cell, style: _DocStyles.table),
                  ],
                ),
            ],
          ),
        );
        if (fits) {
          return content;
        }
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: content,
        );
      },
    );
  }

  Widget _cell(String text, {required TextStyle style}) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
    child: Text(text, style: style),
  );
}

class _DocStyles {
  const _DocStyles._();

  // .article-title → 40rpx(=20) / weight 700 / 居中
  static const title = TextStyle(
    color: Color(0xFF2A2D32),
    fontSize: 20,
    fontWeight: FontWeight.w700,
    height: 1.2,
  );

  // .date-row → 24rpx(=12) / #7e858f
  static const meta = TextStyle(
    color: Color(0xFF7E858F),
    fontSize: 12,
    fontWeight: FontWeight.w400,
    height: 1.2,
  );

  // .article-section-title → 30rpx(=15) / weight 700
  static const heading = TextStyle(
    color: Color(0xFF2A2D32),
    fontSize: 15,
    fontWeight: FontWeight.w700,
    height: 1.3,
  );

  // .article-sub-title → 28rpx(=14) / weight 600（2.1 这类小节标题）
  static const subHeading = TextStyle(
    color: Color(0xFF2A2D32),
    fontSize: 14,
    fontWeight: FontWeight.w600,
    height: 1.4,
  );

  // 表格：比正文小一号，行距收紧，让多列时还读得下去
  static const table = TextStyle(
    color: Color(0xFF2F343B),
    fontSize: 12,
    fontWeight: FontWeight.w400,
    height: 1.45,
  );

  static const tableHead = TextStyle(
    color: Color(0xFF2A2D32),
    fontSize: 12,
    fontWeight: FontWeight.w600,
    height: 1.45,
  );

  // .article-p / .article-list → 28rpx(=14) / line 1.55 / #2f343b
  static const body = TextStyle(
    color: Color(0xFF2F343B),
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 1.55,
  );
}
