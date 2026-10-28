import 'package:flutter/material.dart';

import '../../shared/l10n/app_l10n.dart';
import 'wifi_l10n.dart';

/// WiFi 版绿（与 WiFi 图标、「WiFi版」标签同色）/ 蓝牙版蓝（与「蓝牙版」标签同色），同小程序。
const Color kWifiGreen = Color(0xFF0E9F87);
const Color kBleBlue = Color(0xFF2F6FEB);

/// 仿 iPhone 信号格（同小程序 `components/signal-bars`）：4 根竖条底部对齐、高度 1/4 → 满高递增；
/// 未亮为浅灰。[level] 0~4（0 = 未知，全灰）。点亮颜色按设备类型：WiFi（默认）绿，蓝牙版传 [kBleBlue]。
class SignalBars extends StatelessWidget {
  const SignalBars({
    super.key,
    required this.level,
    this.color = kWifiGreen,
    this.small = true,
  });

  final int level;
  final Color color;

  /// small：高 10、竖条宽 2.5（搜索列表 / 卡片）；否则高 13、宽 3（WiFi 列表）。
  final bool small;

  @override
  Widget build(BuildContext context) {
    final height = small ? 10.0 : 13.0;
    final width = small ? 2.5 : 3.0;
    final gap = small ? 1.5 : 2.0;
    return SizedBox(
      height: height,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 1; i <= 4; i++) ...[
            if (i > 1) SizedBox(width: gap),
            Container(
              width: width,
              height: height * i / 4,
              decoration: BoxDecoration(
                color: level >= i ? color : const Color(0xFFD5D9DF),
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 通信类型标签（同小程序 `.comm-badge`）：WiFi 版青绿渐变浅底、蓝牙版蓝色浅底，带小图标。
/// [trailing] 接在文字后面（搜索列表里尺寸查询中的小圆圈 loading）。
class CommBadge extends StatelessWidget {
  const CommBadge({
    super.key,
    required this.wifi,
    required this.text,
    this.textColor,
    this.trailing,
  });

  final bool wifi;
  final String text;

  /// 文字颜色覆盖（「未知设备」用警示色），默认跟随类型色。
  final Color? textColor;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final color = wifi ? kWifiGreen : kBleBlue;
    return Container(
      height: 14,
      padding: const EdgeInsets.only(left: 4, right: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: wifi
              ? const [Color(0x2912B896), Color(0x1F38BDF8)]
              : const [Color(0x242F6FEB), Color(0x1A6366F1)],
        ),
        border: Border.all(
          color: wifi ? const Color(0x520E9F87) : const Color(0x4D2F6FEB),
          width: 0.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(wifi ? Icons.wifi_rounded : Icons.bluetooth_rounded, size: 10, color: color),
          const SizedBox(width: 2),
          Text(
            text,
            maxLines: 1,
            style: TextStyle(
              color: textColor ?? color,
              fontSize: 10,
              fontWeight: FontWeight.w600,
              height: 1,
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }

  /// 只有类型名的标签（设备详情 / 设备选择弹层）。
  static Widget plain(BuildContext context, {required bool wifi}) {
    final l10n = AppL10n.of(context);
    return CommBadge(wifi: wifi, text: wifi ? l10n.wifiBadge : l10n.bleBadge);
  }
}

/// 小圆圈 loading（尺寸查询中 / 状态查询中）。
class WifiMiniSpinner extends StatelessWidget {
  const WifiMiniSpinner({super.key, this.size = 9, this.color = const Color(0xFFFF621F)});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CircularProgressIndicator(
        strokeWidth: 1.5,
        valueColor: AlwaysStoppedAnimation<Color>(color),
        backgroundColor: color.withValues(alpha: 0.2),
      ),
    );
  }
}

// ── 设置页通用件（轮播设置 / 休眠设置，同小程序 `.ws-segment` / `.ws-row` / picker）──

/// 分段选择（同小程序 `.ws-segment`）：选中项橙色描边浅底。
class WifiSegment<T> extends StatelessWidget {
  const WifiSegment({super.key, required this.value, required this.items, required this.onChanged});

  final T value;
  final List<(T, String)> items;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const SizedBox(width: 10),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onChanged(items[i].$1),
              child: Container(
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: items[i].$1 == value ? const Color(0x1AFF6A20) : Colors.white.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: items[i].$1 == value ? const Color(0xFFFF6A20) : Colors.transparent,
                  ),
                ),
                child: Text(
                  items[i].$2,
                  style: TextStyle(
                    color: items[i].$1 == value ? const Color(0xFFFF6A20) : const Color(0xFF5E6470),
                    fontSize: 14,
                    fontWeight: items[i].$1 == value ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// 一行「标签 …… 值 ›」（同小程序 `.ws-row`），点了弹选择器。
class WifiFormRow extends StatelessWidget {
  const WifiFormRow({super.key, required this.label, required this.value, this.onTap, this.trailing});

  final String label;
  final String value;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        height: 48,
        child: Row(
          children: [
            Text(label, style: const TextStyle(color: Color(0xFF33373D), fontSize: 14)),
            const Spacer(),
            trailing ??
                Text(value, style: const TextStyle(color: Color(0xFF2A2D32), fontSize: 14, fontWeight: FontWeight.w600)),
            if (onTap != null) const Icon(Icons.chevron_right_rounded, size: 18, color: Color(0xFF9BA2AD)),
          ],
        ),
      ),
    );
  }
}

String _two(int n) => n.toString().padLeft(2, '0');

/// 选一个 HH:mm（24 小时制）；取消返回 null。
Future<String?> pickWifiTime(BuildContext context, String initial) async {
  final parts = initial.split(':');
  final picked = await showTimePicker(
    context: context,
    initialTime: TimeOfDay(
      hour: int.tryParse(parts.first) ?? 8,
      minute: parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0,
    ),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
      child: child ?? const SizedBox.shrink(),
    ),
  );
  return picked == null ? null : '${_two(picked.hour)}:${_two(picked.minute)}';
}

/// 选一个 yyyy-MM-dd（不早于今天）；取消返回 null。
Future<String?> pickWifiDate(BuildContext context, String initial) async {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  var current = DateTime.tryParse(initial) ?? today;
  if (current.isBefore(today)) {
    current = today;
  }
  final picked = await showDatePicker(
    context: context,
    initialDate: current,
    firstDate: today,
    lastDate: today.add(const Duration(days: 365 * 2)),
  );
  return picked == null ? null : '${picked.year}-${_two(picked.month)}-${_two(picked.day)}';
}

/// 从一列选项里选一个（间隔档位、天数等）；取消返回 null。
Future<int?> pickWifiOption(BuildContext context, List<String> options, int selected) {
  return showModalBottomSheet<int>(
    context: context,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
    builder: (context) => SafeArea(
      child: SizedBox(
        height: 320,
        child: ListView.builder(
          controller: ScrollController(initialScrollOffset: ((selected - 2).clamp(0, options.length) * 48).toDouble()),
          itemExtent: 48,
          itemCount: options.length,
          itemBuilder: (context, index) => InkWell(
            onTap: () => Navigator.of(context).pop(index),
            child: Center(
              child: Text(
                options[index],
                style: TextStyle(
                  color: index == selected ? const Color(0xFFFF6A20) : const Color(0xFF2A2D32),
                  fontSize: 16,
                  fontWeight: index == selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
