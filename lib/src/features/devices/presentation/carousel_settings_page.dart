import 'package:flutter/material.dart';

import 'package:BoltStar/src/shared/widgets/figma_common.dart';
import '../../../device/frame_device_protocol.dart';
import '../../../state.dart';

/// 轮播设置页：开启/关闭轮播 + 选择轮播方式（顺序 / 随机）。
///
/// 对照微信小程序 `photo-album/subpackages/device/slideshow`：需已连接设备，切换开关/方式走真实
/// BLE `setPlayback`（见 [PhotoFrameState.setDeviceCarousel]）；未连接时提示「请先连接设备」并还原开关，
/// 未开启轮播时「轮播方式」置灰不可选（对齐小程序 `is-disabled`）。
class CarouselSettingsPage extends StatefulWidget {
  const CarouselSettingsPage({super.key, required this.state});

  final PhotoFrameState state;

  @override
  State<CarouselSettingsPage> createState() => _CarouselSettingsPageState();
}

class _CarouselSettingsPageState extends State<CarouselSettingsPage> {
  late bool _enabled;
  late FramePlaybackMode _mode;
  bool _busy = false;

  // .setting-title / .mode-title → 30rpx(=15) / weight 700 / #33373d
  static const _titleStyle = TextStyle(
    color: Color(0xFF33373D),
    fontSize: 15,
    fontWeight: FontWeight.w700,
    height: 1.2,
  );

  @override
  void initState() {
    super.initState();
    final device = widget.state.selectedDevice;
    // 连接才可信：未连接一律按「未开启」展示（对齐小程序 computeCarouselOn / 连接前不允许开启）。
    _enabled = device.connected && device.carouselEnabled;
    _mode = device.playbackMode == FramePlaybackMode.manual
        ? FramePlaybackMode.sequence
        : device.playbackMode;
  }

  Future<void> _apply({
    required bool enabled,
    required FramePlaybackMode mode,
  }) async {
    if (_busy) {
      return;
    }
    setState(() => _busy = true);
    final feedback = await widget.state.setDeviceCarousel(
      widget.state.selectedDevice.id,
      enabled: enabled,
      mode: mode,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _busy = false;
      if (feedback.success) {
        _enabled = enabled;
        _mode = mode;
      }
      // 失败：状态不变，开关按当前 _enabled 自动还原（对齐小程序 applyPlayback 失败还原开关）。
    });
    _showSnack(feedback.message);
  }

  void _showSnack(String message) {
    AppToast.show(context, message);
  }

  @override
  Widget build(BuildContext context) {
    final modeDisabled = !_enabled || _busy;
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
                      onChanged: _busy
                          ? null
                          : (value) => _apply(enabled: value, mode: _mode),
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
                Padding(
                  padding: const EdgeInsets.only(top: 22, bottom: 12),
                  child: Text(
                    '轮播方式',
                    style: _titleStyle.copyWith(
                      color: modeDisabled
                          ? const Color(0xFFB6BBC3)
                          : const Color(0xFF33373D),
                    ),
                  ),
                ),
                _CarouselOption(
                  label: '顺序轮播',
                  selected: _mode == FramePlaybackMode.sequence,
                  disabled: modeDisabled,
                  onTap: () =>
                      _apply(enabled: true, mode: FramePlaybackMode.sequence),
                ),
                const SizedBox(height: 12),
                _CarouselOption(
                  label: '随机轮播',
                  selected: _mode == FramePlaybackMode.random,
                  disabled: modeDisabled,
                  onTap: () =>
                      _apply(enabled: true, mode: FramePlaybackMode.random),
                ),
              ],
            ),
          ),
        ],
      ),
    );
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

/// 轮播方式单选项（小程序 `.mode-option`）：胶囊行 + 自定义圆点；[disabled] 时置灰不可点。
class _CarouselOption extends StatelessWidget {
  const _CarouselOption({
    required this.label,
    required this.selected,
    required this.onTap,
    this.disabled = false,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool disabled;

  @override
  Widget build(BuildContext context) {
    final accent = disabled ? const Color(0xFFC2C6CD) : const Color(0xFFFF6A20);
    return Opacity(
      opacity: disabled ? 0.55 : 1,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: disabled ? null : onTap,
        child: Container(
          height: 47,
          padding: const EdgeInsets.symmetric(horizontal: 17),
          decoration: BoxDecoration(
            color: selected
                ? Colors.white.withValues(alpha: 0.1)
                : const Color(0xFFEEEEEE).withValues(alpha: 0.84),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: selected ? accent : Colors.transparent),
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
                    color: selected ? accent : const Color(0xFF7E858F),
                    width: selected ? 2 : 1,
                  ),
                ),
                child: selected
                    ? Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: accent,
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
      ),
    );
  }
}
