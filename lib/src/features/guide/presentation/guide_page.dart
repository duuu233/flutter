import 'package:flutter/material.dart';

import '../../../state.dart';
import 'package:BoltStar/src/shared/widgets/figma_common.dart';

/// 操作指南页面，对应 UI 稿「操作指南」：搜索框 + 可展开的常见问题列表。
class GuidePage extends StatefulWidget {
  const GuidePage({super.key, required this.state});

  final PhotoFrameState state;

  @override
  State<GuidePage> createState() => _GuidePageState();
}

class _FaqItem {
  const _FaqItem({required this.question, required this.answer});

  final String question;
  final String answer;
}

const List<_FaqItem> _faqItems = [
  _FaqItem(
    question: '如何绑定设备？',
    answer:
        '1.确保设备电量充足，并开启手机蓝牙。\n'
        '2.进入首页或【我的设备】点击添加设备。\n'
        '3.设备列表中会显示搜索到的相框设备。\n'
        '4.点击【绑定】完成连接。',
  ),
  _FaqItem(
    question: '如何管理我的相册？',
    answer: '在【我的图库】中可查看并删除已上传的照片，删除后将同步移除设备上对应的照片，请谨慎操作。',
  ),
  _FaqItem(
    question: '设备照片被清空怎么办？',
    answer: '设备照片被所有者清空后将无法恢复。您可以重新在图库中选择照片，并再次投屏到设备进行展示。',
  ),
  _FaqItem(
    question: '相框空间已满怎么办？',
    answer:
        '答：相框空间已满时，新的照片将无法继续投放。您可以删除部分照片以释放空间，或前往【设备管理】清空设备内容，'
        '确保有足够空间后再投放。两者择其一进行操作即可。',
  ),
];

class _GuidePageState extends State<GuidePage> {
  final TextEditingController _searchController = TextEditingController();
  final Set<int> _expanded = {0, 3};
  String _keyword = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = <int>[
      for (var i = 0; i < _faqItems.length; i++)
        if (_keyword.isEmpty ||
            _faqItems[i].question.contains(_keyword) ||
            _faqItems[i].answer.contains(_keyword))
          i,
    ];

    return FigmaScreen(
      title: '操作指南',
      scrollable: false,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          _SearchField(
            controller: _searchController,
            onChanged: (value) => setState(() => _keyword = value.trim()),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.only(bottom: 16),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final faqIndex = items[index];
                return _FaqCard(
                  item: _faqItems[faqIndex],
                  expanded: _expanded.contains(faqIndex),
                  onTap: () {
                    setState(() {
                      if (!_expanded.add(faqIndex)) {
                        _expanded.remove(faqIndex);
                      }
                    });
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.86)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              cursorColor: const Color(0xFFEB5F1B),
              style: FigmaTextStyles.formValue,
              decoration: const InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                hintText: '搜索帮助文档',
                hintStyle: FigmaTextStyles.formHint,
              ),
            ),
          ),
          const Icon(
            Icons.search_rounded,
            color: Color(0x992A2B2B),
            size: 20,
          ),
        ],
      ),
    );
  }
}

class _FaqCard extends StatelessWidget {
  const _FaqCard({
    required this.item,
    required this.expanded,
    required this.onTap,
  });

  final _FaqItem item;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FigmaGlassCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: Row(
              children: [
                Container(
                  width: 20,
                  height: 20,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    color: Color(0xFFFF6A24),
                    shape: BoxShape.circle,
                  ),
                  child: const Text(
                    '?',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      height: 1.1,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    item.question,
                    style: const TextStyle(
                      color: Color(0xFF2A2B2B),
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      height: 1.4,
                    ),
                  ),
                ),
                Icon(
                  expanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  color: const Color(0x992A2B2B),
                  size: 22,
                ),
              ],
            ),
          ),
          if (expanded) ...[
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.only(left: 32),
              child: Text(
                item.answer,
                style: const TextStyle(
                  color: Color(0xCC2A2B2B),
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                  height: 1.7,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
