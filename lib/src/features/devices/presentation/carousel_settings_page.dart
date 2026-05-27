import 'package:flutter/material.dart';

import 'package:BoltStar/src/shared/widgets/figma_common.dart';

/// 轮播设置页：设置设备照片的轮播间隔等参数，对应 UI 稿「轮播设置」。
class CarouselSettingsPage extends StatefulWidget {
  const CarouselSettingsPage({
    super.key,
    this.onEnabledChanged,
    this.onModeChanged,
  });

  final ValueChanged<bool>? onEnabledChanged;
  final ValueChanged<String>? onModeChanged;

  @override
  State<CarouselSettingsPage> createState() => _CarouselSettingsPageState();
}

class _CarouselSettingsPageState extends State<CarouselSettingsPage> {
  bool _enabled = true;
  String _mode = 'sequence';

  @override
  Widget build(BuildContext context) {
    return FigmaScreen(
      title: '轮播设置',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 12),
          FigmaGlassCard(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text('开启轮播', style: FigmaTextStyles.formLabel),
                      ),
                      Switch.adaptive(
                        value: _enabled,
                        activeThumbColor: const Color(0xFFEB5F1B),
                        activeTrackColor: const Color(0xFFFFC9AE),
                        onChanged: (value) {
                          setState(() {
                            _enabled = value;
                          });
                          widget.onEnabledChanged?.call(value);
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: const [
                      Icon(
                        Icons.info_outline_rounded,
                        size: 14,
                        color: Color(0x992A2B2B),
                      ),
                      SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '轮播以开启时间起算24小时后轮播下一张',
                          style: FigmaTextStyles.bodySmall,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  const Text('轮播方式', style: FigmaTextStyles.formLabel),
                  const SizedBox(height: 14),
                  _CarouselOption(
                    label: '顺序轮播',
                    selected: _mode == 'sequence',
                    onTap: () => _setMode('sequence'),
                  ),
                  const SizedBox(height: 12),
                  _CarouselOption(
                    label: '随机轮播',
                    selected: _mode == 'random',
                    onTap: () => _setMode('random'),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  void _setMode(String value) {
    setState(() {
      _mode = value;
    });
    widget.onModeChanged?.call(value);
  }
}

class _CarouselOption extends StatelessWidget {
  const _CarouselOption({
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
      borderRadius: BorderRadius.circular(24),
      onTap: onTap,
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFFFBF2EE).withValues(alpha: 0.8)
              : const Color(0xFFBCBCBC).withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: selected ? const Color(0xFFEB5F1B) : const Color(0xA82A2B2B),
          ),
        ),
        child: Row(
          children: [
            Icon(
              selected
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_unchecked_rounded,
              color: selected
                  ? const Color(0xFFEB5F1B)
                  : const Color(0xA82A2B2B),
              size: 24,
            ),
            const SizedBox(width: 16),
            Text(label, style: FigmaTextStyles.formLabel),
          ],
        ),
      ),
    );
  }
}
