import 'package:flutter/material.dart';

import '../../../shared/l10n/app_l10n.dart';
import '../../../state.dart';
import 'package:BoltStar/src/shared/widgets/figma_common.dart';

/// 操作指南页面，对照小程序 `subpackages/settings/guide` 还原：
/// 胶囊搜索框 + 一张玻璃卡内的可展开常见问题列表（带 `why-icon01` 问号图标）。
class GuidePage extends StatefulWidget {
  const GuidePage({super.key, required this.state});

  final PhotoFrameState state;

  @override
  State<GuidePage> createState() => _GuidePageState();
}

class _GuidePageState extends State<GuidePage> {
  final TextEditingController _searchController = TextEditingController();
  final Set<String> _expanded = <String>{};
  String _keyword = '';

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

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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
    final items = <FaqArticle>[
      for (final faq in widget.state.faqArticles)
        if (_keyword.isEmpty ||
            faq.question.contains(_keyword) ||
            faq.answer.contains(_keyword))
          faq,
    ];

    return FigmaScreen(
      title: AppL10n.of(context).guideTitle,
      scrollable: false,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 12),
          _SearchField(
            controller: _searchController,
            onChanged: (value) => setState(() => _keyword = value.trim()),
          ),
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

/// 胶囊搜索框（小程序 `.search-box`）：半透明白底 + 全圆角 + 右侧 `search-icon01`。
class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      padding: const EdgeInsets.fromLTRB(18, 0, 19, 0),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.88)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              cursorColor: const Color(0xFFEB5F1B),
              style: const TextStyle(
                color: Color(0xFF2A2D32),
                fontSize: 14,
                height: 1.2,
              ),
              decoration: InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                hintText: AppL10n.of(context).guideSearchHint,
                hintStyle: const TextStyle(
                  color: Color(0xFF9AA1AB),
                  fontSize: 14,
                  height: 1.2,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Image.asset(
            'assets/images/search-icon01.png',
            width: 16,
            height: 16,
            fit: BoxFit.contain,
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
