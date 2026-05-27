import 'package:flutter/material.dart';

/// 法律文本页面的正文区块（标题 + 内容）。
class LegalSection {
  const LegalSection({required this.heading, required this.body});

  final String heading;
  final String body;
}

/// 隐私政策 / 用户协议等长文本页面的可滚动正文视图。
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
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: _DocStyles.title),
          const SizedBox(height: 10),
          Text('更新日期：$updatedAt    生效日期：$effectiveAt', style: _DocStyles.meta),
          const SizedBox(height: 18),
          for (final section in sections) ...[
            Text(section.heading, style: _DocStyles.heading),
            const SizedBox(height: 8),
            Text(section.body, style: _DocStyles.body),
            const SizedBox(height: 18),
          ],
        ],
      ),
    );
  }
}

class _DocStyles {
  const _DocStyles._();

  static const title = TextStyle(
    color: Color(0xFF2A2B2B),
    fontSize: 17,
    fontWeight: FontWeight.w600,
    height: 1.4,
  );

  static const meta = TextStyle(
    color: Color(0x992A2B2B),
    fontSize: 11,
    fontWeight: FontWeight.w400,
    height: 1.4,
  );

  static const heading = TextStyle(
    color: Color(0xFF2A2B2B),
    fontSize: 14,
    fontWeight: FontWeight.w600,
    height: 1.5,
  );

  static const body = TextStyle(
    color: Color(0xCC2A2B2B),
    fontSize: 13,
    fontWeight: FontWeight.w400,
    height: 1.7,
  );
}
