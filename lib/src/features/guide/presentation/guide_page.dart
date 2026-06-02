import 'package:flutter/material.dart';

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

class _FaqItem {
  const _FaqItem({required this.question, required this.answer});

  final String question;
  final String answer;
}

const List<_FaqItem> _faqItems = [
  _FaqItem(
    question: '如何绑定设备?',
    answer:
        '1.确保相册设备已开机，并打开手机蓝牙。\n'
        '2.进入首页点击绑定设备，或「我的设备」。\n'
        '3.在设备列表中选择要连接的相册设备。\n'
        '4.点击「立即绑定」完成连接。\n'
        '若未搜索到设备，请确认设备在附近并重新搜索。',
  ),
  _FaqItem(
    question: '如何进行照片投屏?',
    answer: '进入首页，选择拍照或相册，确认照片后发送到已连接设备。',
  ),
  _FaqItem(
    question: '如何管理我的相册?',
    answer: '进入我的图库，可查看、删除和重新投屏已上传的照片。',
  ),
  _FaqItem(
    question: '设备照片被清空怎么办?',
    answer: '请在我的图库中重新选择照片投屏，或检查设备存储状态。',
  ),
  _FaqItem(
    question: '相框空间已满怎么办?',
    answer:
        '设备空间已满时，新的照片将无法继续投屏。你可以前往「我的相册」删除部分照片，'
        '或执行一键清空。清理完成后，再重新选择照片进行投屏即可。',
  ),
];

class _GuidePageState extends State<GuidePage> {
  final TextEditingController _searchController = TextEditingController();
  final Set<int> _expanded = {0, 4};
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
                    for (final faqIndex in items)
                      _GuideItem(
                        item: _faqItems[faqIndex],
                        expanded: _expanded.contains(faqIndex),
                        onTap: () {
                          setState(() {
                            if (!_expanded.add(faqIndex)) {
                              _expanded.remove(faqIndex);
                            }
                          });
                        },
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
              decoration: const InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                hintText: '搜索帮助文档',
                hintStyle: TextStyle(
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

  final _FaqItem item;
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
