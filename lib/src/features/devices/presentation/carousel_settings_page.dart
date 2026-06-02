import 'package:flutter/material.dart';

import 'package:BoltStar/src/shared/widgets/figma_common.dart';

/// 轮播设置页：开启/关闭轮播 + 选择轮播方式（顺序 / 随机）。
///
/// 对照微信小程序 `photo-album/subpackages/device/slideshow`。
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

  // .setting-title / .mode-title → 30rpx(=15) / weight 700 / #33373d
  static const _titleStyle = TextStyle(
    color: Color(0xFF33373D),
    fontSize: 15,
    fontWeight: FontWeight.w700,
    height: 1.2,
  );

  @override
  Widget build(BuildContext context) {
    return FigmaScreen(
      title: '轮播设置',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 12),
          FigmaGlassCard(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 开启轮播开关。
                Row(
                  children: [
                    const Expanded(child: Text('开启轮播', style: _titleStyle)),
                    Switch.adaptive(
                      value: _enabled,
                      activeThumbColor: Colors.white,
                      activeTrackColor: const Color(0xFFFF6A20),
                      onChanged: (value) {
                        setState(() => _enabled = value);
                        widget.onEnabledChanged?.call(value);
                      },
                    ),
                  ],
                ),
                // 提示行：圆圈「i」+ 说明。
                const Padding(
                  padding: EdgeInsets.only(top: 9, bottom: 13),
                  child: Row(
                    children: [
                      _InfoBadge(),
                      SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          '轮播以开启时间起算24小时后轮播下一张',
                          style: TextStyle(
                            color: Color(0xFF8A9099),
                            fontSize: 12,
                            height: 1.3,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  height: 1,
                  color: const Color(0xFF2A2B2B).withValues(alpha: 0.08),
                ),
                const Padding(
                  padding: EdgeInsets.only(top: 22, bottom: 12),
                  child: Text('轮播方式', style: _titleStyle),
                ),
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
    setState(() => _mode = value);
    widget.onModeChanged?.call(value);
  }
}

/// 提示前的圆圈「i」图标（小程序 `.tip-icon`）。
class _InfoBadge extends StatelessWidget {
  const _InfoBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 14,
      height: 14,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0xFF7F8995)),
      ),
      child: const Text(
        'i',
        style: TextStyle(
          color: Color(0xFF7F8995),
          fontSize: 9,
          fontWeight: FontWeight.w700,
          height: 1,
        ),
      ),
    );
  }
}

/// 轮播方式单选项（小程序 `.mode-option`）：胶囊行 + 自定义圆点。
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
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 47,
        padding: const EdgeInsets.symmetric(horizontal: 17),
        decoration: BoxDecoration(
          color: selected
              ? Colors.white.withValues(alpha: 0.1)
              : const Color(0xFFEEEEEE).withValues(alpha: 0.84),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? const Color(0xFFFF6A20) : Colors.transparent,
          ),
        ),
        child: Row(
          children: [
            // 自定义单选圆点：未选空心环，选中橙环 + 实心点。
            Container(
              width: 24,
              height: 24,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected
                      ? const Color(0xFFFF6A20)
                      : const Color(0xFF7E858F),
                  width: selected ? 2 : 1,
                ),
              ),
              child: selected
                  ? Container(
                      width: 12,
                      height: 12,
                      decoration: const BoxDecoration(
                        color: Color(0xFFFF6A20),
                        shape: BoxShape.circle,
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 14),
            Text(
              label,
              style: const TextStyle(
                color: Color(0xFF2A2D32),
                fontSize: 14,
                fontWeight: FontWeight.w700,
                height: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
