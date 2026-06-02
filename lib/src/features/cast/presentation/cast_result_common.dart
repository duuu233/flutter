import 'package:flutter/material.dart';

import 'package:BoltStar/src/shared/widgets/figma_common.dart';

/// 投屏结果页公共件，对照微信小程序 `photo-album/subpackages/projection/result`
/// （progress / success / fail 在小程序是同一页的三种 status）。
///
/// 顶部插画用 `upload-icon01/02/03.png`，下方信息卡两行（投屏设备 / 投屏管理）。

/// .result-title → 40rpx(=20) / weight 700 / #2a2d32
const projectionResultTitleStyle = TextStyle(
  color: Color(0xFF2A2D32),
  fontSize: 20,
  fontWeight: FontWeight.w700,
  height: 1,
);

/// .result-desc → 26rpx(=13) / #828a95 / line-height 1.5
const projectionResultDescStyle = TextStyle(
  color: Color(0xFF828A95),
  fontSize: 13,
  fontWeight: FontWeight.w400,
  height: 1.5,
);

/// 结果插画（260×220rpx ≈ 130×110）。
class ProjectionResultArt extends StatelessWidget {
  const ProjectionResultArt({super.key, required this.asset, this.fallbackIcon});

  final String asset;
  final IconData? fallbackIcon;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      asset,
      width: 130,
      height: 110,
      fit: BoxFit.contain,
      errorBuilder: (context, error, stackTrace) {
        return Icon(
          fallbackIcon ?? Icons.cast_rounded,
          size: 72,
          color: const Color(0xFFFF6A24),
        );
      },
    );
  }
}

/// 结果信息卡：投屏设备 + 投屏管理（可点进记录）。
class ProjectionInfoCard extends StatelessWidget {
  const ProjectionInfoCard({
    super.key,
    required this.deviceName,
    required this.recordLabel,
    this.onTapRecords,
  });

  final String deviceName;
  final String recordLabel;
  final VoidCallback? onTapRecords;

  @override
  Widget build(BuildContext context) {
    return FigmaGlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          _InfoRow(
            iconAsset: 'assets/images/projection-result-icon01.png',
            fallbackIcon: Icons.cast_connected_rounded,
            label: '投屏设备',
            value: deviceName,
          ),
          Container(
            height: 1,
            color: const Color(0xFF2A2B2B).withValues(alpha: 0.08),
          ),
          _InfoRow(
            iconAsset: 'assets/images/projection-result-icon02.png',
            fallbackIcon: Icons.view_list_rounded,
            label: '投屏管理',
            value: recordLabel,
            showChevron: true,
            onTap: onTapRecords,
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.iconAsset,
    required this.fallbackIcon,
    required this.label,
    required this.value,
    this.showChevron = false,
    this.onTap,
  });

  final String iconAsset;
  final IconData fallbackIcon;
  final String label;
  final String value;
  final bool showChevron;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        height: 60,
        child: Row(
          children: [
            Image.asset(
              iconAsset,
              width: 24,
              height: 24,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) =>
                  Icon(fallbackIcon, size: 22, color: const Color(0xFFFF6A24)),
            ),
            const SizedBox(width: 19),
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
            Text(
              value,
              style: const TextStyle(
                color: Color(0xFF808690),
                fontSize: 14,
                height: 1.2,
              ),
            ),
            if (showChevron) ...[
              const SizedBox(width: 8),
              const Icon(
                Icons.chevron_right_rounded,
                color: Color(0xFFC2C8D0),
                size: 18,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 投屏进度条（小程序 `.progress-wrap`：左侧进度条 + 右侧 当前/总数）。
class ProjectionProgress extends StatelessWidget {
  const ProjectionProgress({
    super.key,
    required this.percent,
    required this.label,
  });

  final double percent;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: SizedBox(
              height: 9,
              child: Stack(
                children: [
                  const Positioned.fill(
                    child: ColoredBox(color: Color(0xFFE6EBF2)),
                  ),
                  FractionallySizedBox(
                    widthFactor: percent.clamp(0.0, 1.0),
                    child: const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Color(0xFFFF8A45), Color(0xFFFF6421)],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          label,
          style: const TextStyle(color: Color(0xFF828A95), fontSize: 13),
        ),
      ],
    );
  }
}
