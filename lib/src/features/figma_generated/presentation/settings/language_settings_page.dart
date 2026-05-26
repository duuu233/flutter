import 'package:flutter/material.dart';

import '../../../../state.dart';
import '../widgets/figma_common.dart';

/// 语种设置页面，对应 UI 稿「语种设置」。
///
/// 设计稿提供 4 个语种选项（简体 / 繁体 / English / 日本语），而 [PhotoFrameState]
/// 当前只支持 zh / en / ja 三种，繁体暂时复用简体逻辑。这里先保留 4 个可视选项，
/// 保存时再映射到受支持的语言。后续接入真实多语言资源时替换 [_LanguageOption.apply]。
class LanguageSettingsPage extends StatefulWidget {
  const LanguageSettingsPage({super.key, required this.state});

  final PhotoFrameState state;

  @override
  State<LanguageSettingsPage> createState() => _LanguageSettingsPageState();
}

enum _LanguageOption {
  simplifiedChinese('简体中文', AppLanguage.zh),
  traditionalChinese('繁体中文', AppLanguage.zh),
  english('English', AppLanguage.en),
  japanese('日本语', AppLanguage.ja);

  const _LanguageOption(this.label, this.language);

  final String label;
  final AppLanguage language;
}

class _LanguageSettingsPageState extends State<LanguageSettingsPage> {
  late _LanguageOption _selected = _initialOption();

  _LanguageOption _initialOption() {
    return _LanguageOption.values.firstWhere(
      (option) => option.language == widget.state.language,
      orElse: () => _LanguageOption.simplifiedChinese,
    );
  }

  @override
  Widget build(BuildContext context) {
    return FigmaPhoneFrame(
      child: Stack(
        children: [
          const FigmaPageBackground(),
          const Positioned(
            left: 0,
            top: 0,
            width: 375,
            height: 90,
            child: FigmaTopNavigation(title: '语种设置'),
          ),
          Positioned(
            left: 24,
            top: 109,
            width: 327,
            child: FigmaGlassCard(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                children: [
                  for (var i = 0; i < _LanguageOption.values.length; i++) ...[
                    if (i != 0) const FigmaFormDivider(),
                    _LanguageRow(
                      label: _LanguageOption.values[i].label,
                      selected: _selected == _LanguageOption.values[i],
                      onTap: () {
                        setState(() => _selected = _LanguageOption.values[i]);
                      },
                    ),
                  ],
                ],
              ),
            ),
          ),
          Positioned(
            left: 26,
            top: 543,
            width: 323,
            height: 64,
            child: FigmaPrimaryButton(
              label: '保存设置',
              height: 64,
              onPressed: _save,
            ),
          ),
          const FigmaBottomHomeIndicator(),
        ],
      ),
    );
  }

  void _save() {
    widget.state.switchLanguage(_selected.language);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('语种设置已保存')));
    Navigator.maybePop(context);
  }
}

class _LanguageRow extends StatelessWidget {
  const _LanguageRow({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        height: 56,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              Expanded(child: Text(label, style: FigmaTextStyles.formLabel)),
              if (selected)
                Container(
                  width: 22,
                  height: 22,
                  decoration: const BoxDecoration(
                    color: Color(0xFFEB5F1B),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check_rounded,
                    color: Colors.white,
                    size: 15,
                  ),
                )
              else
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0x332A2B2B)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
