import 'package:flutter/material.dart';

import '../../../shared/l10n/app_l10n.dart';
import '../../../shared/widgets/simple_html_text.dart';
import '../../../state.dart';
import 'package:BoltStar/src/shared/widgets/figma_common.dart';

/// 操作指南页面，对照小程序 `subpackages/settings/guide` 还原：
/// 一张玻璃卡内的可展开常见问题列表（带 `why-icon01` 问号图标）。
/// 搜索模块已按产品要求移除（2026-07-17）。
///
/// 两条与后端相关的约定（2026-07-19）：
/// - 常见问题**默认全部收起**，不再默认展开首项。
/// - 列表随语种走：进入页面即按当前语种重新拉取；页面停留期间切换语种也会重拉，
///   避免看到上一个语种的残留文案。
class GuidePage extends StatefulWidget {
  const GuidePage({super.key, required this.state});

  final PhotoFrameState state;

  @override
  State<GuidePage> createState() => _GuidePageState();
}

class _GuidePageState extends State<GuidePage> {
  final Set<String> _expanded = <String>{};

  /// 已按哪个语种拉过列表。null = 本页还没拉过。
  AppLanguage? _loadedLanguage;
  bool _loading = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // languageOf 会登记依赖：语种一变，这里会被再调一次，从而按新语种重拉。
    final language = AppLocalizationsScope.languageOf(context);
    if (_loadedLanguage != language) {
      _loadedLanguage = language;
      // 换了语种整套文案都会变，旧的展开态（按 faqId 记）不再有意义。
      _expanded.clear();
      _refresh();
    }
  }

  Future<void> _refresh() async {
    if (_loading) {
      return;
    }
    // didChangeDependencies 之后必然跟一次 build，这里不用 setState。
    _loading = true;

    // 翻页要花好几个 RTT，期间用户可能又切了语种：拉完对一下语种，
    // 不一致就按最新的再拉一遍，避免停在中间那个语种上。
    // 这里读 state.language 而不是 languageOf(context)：跨 await 再去登记
    // InheritedWidget 依赖是不允许的。
    var requested = widget.state.language;
    while (true) {
      await widget.state.refreshFaq();
      if (!mounted) {
        return;
      }
      final current = widget.state.language;
      if (current == requested) {
        // 相同就收工——即使这次是失败返回，也不会在这里空转重试。
        break;
      }
      requested = current;
    }

    setState(() {
      _loading = false;
      // 列表已换，清掉指向旧条目的展开态。
      final ids = widget.state.faqArticles.map((faq) => faq.id).toSet();
      _expanded.removeWhere((id) => !ids.contains(id));
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
    final l10n = AppL10n.of(context);
    final items = widget.state.faqArticles;
    // 缓存还停在别的语种时，宁可显示加载态也不要闪一屏旧语种文案。
    final showLoading = _loading && widget.state.faqNeedsRefresh;

    return FigmaScreen(
      title: l10n.guideTitle,
      scrollable: false,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 12),
          Expanded(
            child: showLoading
                ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                : SingleChildScrollView(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: FigmaGlassCard(
                      borderRadius: 14,
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 5),
                      child: items.isEmpty
                          ? Padding(
                              padding: const EdgeInsets.symmetric(vertical: 28),
                              child: Text(
                                l10n.guideEmpty,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: const Color(0xFF2A2B2B).withValues(alpha: 0.5),
                                  fontSize: 13,
                                ),
                              ),
                            )
                          : Column(
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
    final answerStyle = TextStyle(
      color: const Color(0xFF2A2B2B).withValues(alpha: 0.6),
      fontSize: 12,
      fontWeight: FontWeight.w400,
      height: 1.66,
    );

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
              // 后端 faqContent 是富文本，带 <p>/<br> 等标签（小程序侧用 rich-text
              // 渲染）。纯文本走 Text，省一次解析。
              child: SimpleHtmlText.looksLikeHtml(item.answer)
                  ? SimpleHtmlText(item.answer, baseStyle: answerStyle)
                  : Text(item.answer, style: answerStyle),
            ),
          ),
      ],
    );
  }
}
