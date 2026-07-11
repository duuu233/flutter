import 'package:flutter/material.dart';

import '../../../state.dart';
import 'package:BoltStar/src/shared/widgets/figma_common.dart';

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
    return FigmaScreen(
      title: '语种设置',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 17),
          FigmaGlassCard(
            borderRadius: 11,
            child: Column(
              children: [
                for (var i = 0; i < _LanguageOption.values.length; i++) ...[
                  if (i != 0)
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 18),
                      child: Divider(
                        height: 1,
                        thickness: 1,
                        color: Color(0xB8CFD6E0),
                      ),
                    ),
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
        ],
      ),
      bottom: FigmaPrimaryButton(label: '保存设置', onPressed: _save),
    );
  }

  void _save() {
    widget.state.switchLanguage(_selected.language);
    AppToast.show(context, '语种设置已保存');
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
        height: 61,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    color: Color(0xFF2A2D32),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    height: 1.2,
                  ),
                ),
              ),
              if (selected)
                Image.asset(
                  'assets/images/selected-icon.png',
                  width: 26,
                  height: 26,
                  fit: BoxFit.contain,
                )
              else
                Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFFBFC4CC)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
