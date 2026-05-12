import 'package:flutter/material.dart';

import '../../../shared/shared.dart';
import '../../../state.dart';

class GuidePage extends StatelessWidget {
  const GuidePage({super.key, required this.state});

  final PhotoFrameState state;

  @override
  Widget build(BuildContext context) {
    final articles = state.buildGuideArticles();
    return SubPageScaffold(
      title: state.tr(zh: '操作指南', en: 'Guides', ja: '操作ガイド'),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: articles.map((article) {
          final summary = switch (state.language) {
            AppLanguage.zh => article.summaryZh,
            AppLanguage.en => article.summaryEn,
            AppLanguage.ja => article.summaryJa,
          };
          final title = switch (state.language) {
            AppLanguage.zh => article.titleZh,
            AppLanguage.en => article.titleEn,
            AppLanguage.ja => article.titleJa,
          };
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: AppPanel(
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: EdgeInsets.zero,
                title: Text(title),
                subtitle: Text(article.category),
                children: summary
                    .map(
                      (line) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Padding(
                              padding: EdgeInsets.only(top: 4),
                              child: Icon(Icons.circle, size: 8),
                            ),
                            const SizedBox(width: 10),
                            Expanded(child: Text(line)),
                          ],
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
