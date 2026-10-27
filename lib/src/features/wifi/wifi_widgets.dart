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
