import 'package:flutter/material.dart';

import 'package:BoltStar/src/shared/widgets/figma_common.dart';
import '../../../shared/l10n/app_l10n.dart';

/// 法律文本页面的正文区块（标题 + 内容）。
class LegalSection {
  const LegalSection({required this.heading, required this.body});

  final String heading;
  final String body;
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
  });

  final String title;
  final String updatedAt;
  final String effectiveAt;
  final List<LegalSection> sections;

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
            for (final section in sections) ...[
              Text(section.heading, style: _DocStyles.heading),
              const SizedBox(height: 8),
              Text(section.body, style: _DocStyles.body),
              const SizedBox(height: 16),
            ],
          ],
        ),
      ),
    );
  }
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

  // .article-p / .article-list → 28rpx(=14) / line 1.55 / #2f343b
  static const body = TextStyle(
    color: Color(0xFF2F343B),
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 1.55,
  );
}
