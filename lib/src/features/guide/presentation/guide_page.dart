import 'package:flutter/material.dart';

import '../../../shared/l10n/app_l10n.dart';
import '../../../state.dart';
import 'package:BoltStar/src/shared/widgets/figma_common.dart';

/// 操作指南页面，对照小程序 `subpackages/settings/guide` 还原：
/// 一张玻璃卡内的可展开常见问题列表（带 `why-icon01` 问号图标）。
/// 搜索模块已按产品要求移除（2026-07-17）。
class GuidePage extends StatefulWidget {
  const GuidePage({super.key, required this.state});

  final PhotoFrameState state;

  @override
  State<GuidePage> createState() => _GuidePageState();
}

class _GuidePageState extends State<GuidePage> {
  final Set<String> _expanded = <String>{};

  @override
  void initState() {
    super.initState();
    final initial = widget.state.faqArticles;
    if (initial.isNotEmpty) {
      _expanded.add(initial.first.id);
      // 小程序的本地兜底数据首项和「空间已满」项默认展开。
      if (initial.length > 1) {
        _expanded.add(initial.last.id);
      }
    }
    // 打开时刷新常见问题（失败保留内置文案）。
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await widget.state.refreshFaq();
      if (mounted) {
        setState(() {
          final refreshed = widget.state.faqArticles;
          final ids = refreshed.map((item) => item.id).toSet();
          _expanded.removeWhere((id) => !ids.contains(id));
          // 后端 FAQ 替换本地列表后，小程序默认展开新的第一项。
          if (_expanded.isEmpty && refreshed.isNotEmpty) {
            _expanded.add(refreshed.first.id);
          }
        });
      }
    });
  }

  void _toggle(FaqArticle faq) {
    setState(() {
      if (!_expanded.add(faq.id)) {
        _expanded.remove(faq.id);
      }
    });
    // 展开且当前无答案时，懒加载详情（getProductFaqDetail）。
    if (_expanded.contains(faq.id) && faq.answer.isEmpty) {
      widget.state.loadFaqDetail(faq.id).then((_) {
        if (mounted) {
          setState(() {});
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.state.faqArticles;

    return FigmaScreen(
      title: AppL10n.of(context).guideTitle,
      scrollable: false,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 12),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: 16),
              child: FigmaGlassCard(
                borderRadius: 14,
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 5),
                child: Column(
                  children: [
                    for (final faq in items)
                      _GuideItem(
                        item: faq,
                        expanded: _expanded.contains(faq.id),
                        onTap: () => _toggle(faq),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GuideItem extends StatelessWidget {
  const _GuideItem({
    required this.item,
    required this.expanded,
    required this.onTap,
  });

  final FaqArticle item;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 39),
            child: Row(
              children: [
                Image.asset(
                  'assets/images/why-icon01.png',
                  width: 20,
                  height: 20,
                  fit: BoxFit.contain,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    item.question,
                    style: const TextStyle(
                      color: Color(0xFF4A505A),
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                      height: 1.2,
                    ),
                  ),
                ),
                Icon(
                  expanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  color: const Color(0x992A2B2B),
                  size: 20,
                ),
              ],
            ),
          ),
        ),
        if (expanded)
          Padding(
            padding: const EdgeInsets.only(left: 19, bottom: 9),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 11),
              decoration: BoxDecoration(
                color: const Color(0xFF2A2B2B).withValues(alpha: 0.03),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                item.answer,
                style: TextStyle(
                  color: const Color(0xFF2A2B2B).withValues(alpha: 0.6),
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                  height: 1.66,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
