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
    this.value = '',
    this.valueWidget,
    this.showChevron = false,
    this.onTap,
  });

  final String iconAsset;
  final IconData fallbackIcon;
  final String label;

  /// 纯文本右值。给了 [valueWidget] 时忽略。
  final String value;

  /// 富样式右值（如「投屏明细」的彩色 n/总数）。
  final Widget? valueWidget;

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
            valueWidget ??
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

/// 大号百分比数字（小程序 `.progress-percent`：72rpx(=36) 橙色粗体 + 36rpx(=18) 的 `%`）。
///
/// [percent] 是**当前这一张**的传输进度（0~1），与小程序 `progressPercent` 同义。
class ProjectionPercent extends StatelessWidget {
  const ProjectionPercent({super.key, required this.percent});

  final double percent;

  @override
  Widget build(BuildContext context) {
    final value = (percent.clamp(0.0, 1.0) * 100).floor();
    return RichText(
      textAlign: TextAlign.center,
      text: TextSpan(
        text: '$value',
        style: const TextStyle(
          color: Color(0xFFFF6421),
          fontSize: 36,
          fontWeight: FontWeight.w700,
          height: 1,
        ),
        children: const [
          TextSpan(
            text: '%',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

/// 编号提示列表（小程序 `.progress-tips` / `.fail-tips`：玻璃卡片 + 橙色圆形序号 + 灰色文案）。
class ProjectionTips extends StatelessWidget {
  const ProjectionTips({super.key, required this.tips});

  final List<String> tips;

  @override
  Widget build(BuildContext context) {
    return FigmaGlassCard(
      // .progress-tips → padding 30rpx 32rpx(=15×16)
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < tips.length; i++)
            Padding(
              // .progress-tip-item + .progress-tip-item → margin-top 20rpx(=10)
              padding: EdgeInsets.only(top: i == 0 ? 0 : 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    // .progress-tip-index → 32rpx(=16) 方形圆角、橙字、12% 橙底
                    width: 16,
                    height: 16,
                    margin: const EdgeInsets.only(top: 1.5, right: 8),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF6421).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '${i + 1}',
                      style: const TextStyle(
                        color: Color(0xFFFF6421),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        height: 1,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      tips[i],
                      // .progress-tip-text → 24rpx(=12) / #828a95 / line-height 1.5
                      style: const TextStyle(
                        color: Color(0xFF828A95),
                        fontSize: 12,
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// 结果页信息卡：投屏设备 + 投屏明细（小程序 result.wxml 的 `.info-card`）。
///
/// 投屏明细为 `n/总数`，分子按成功(绿 #12b76a)/失败(红 #f0483e)着色，`/分母` 恒灰；
/// 部分成功时两段并排，中间一个灰色逗号。点击整行进投屏记录。
class ProjectionResultInfoCard extends StatelessWidget {
  const ProjectionResultInfoCard({
    super.key,
    required this.deviceName,
    required this.successCount,
    required this.failCount,
    required this.total,
    this.onTapRecords,
  });

  final String deviceName;
  final int successCount;
  final int failCount;
  final int total;
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
            label: '投屏明细',
            valueWidget: _CastDetail(
              successCount: successCount,
              failCount: failCount,
              total: total,
            ),
            showChevron: true,
            onTap: onTapRecords,
          ),
        ],
      ),
    );
  }
}

class _CastDetail extends StatelessWidget {
  const _CastDetail({
    required this.successCount,
    required this.failCount,
    required this.total,
  });

  final int successCount;
  final int failCount;
  final int total;

  @override
  Widget build(BuildContext context) {
    const numStyle = TextStyle(fontSize: 14, fontWeight: FontWeight.w600, height: 1.2);
    const totalStyle = TextStyle(
      color: Color(0xFF808690),
      fontSize: 14,
      height: 1.2,
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (successCount > 0) ...[
          Text(
            '$successCount',
            style: numStyle.copyWith(color: const Color(0xFF12B76A)),
          ),
          Text('/$total', style: totalStyle),
        ],
        if (successCount > 0 && failCount > 0)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              ',',
              style: TextStyle(color: Color(0xFFC2C8D0), fontSize: 14),
            ),
          ),
        if (failCount > 0) ...[
          Text(
            '$failCount',
            style: numStyle.copyWith(color: const Color(0xFFF0483E)),
          ),
          Text('/$total', style: totalStyle),
        ],
      ],
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
              // .progress-bar → 18rpx = 9
              height: 9,
              child: Stack(
                children: [
                  // 轨道底色 .progress-bar background #e6ebf2
                  const Positioned.fill(
                    child: ColoredBox(color: Color(0xFFE6EBF2)),
                  ),
                  // 橙色填充。
                  //
                  // 原来「进度条完全没有橙色」的根因：`FractionallySizedBox` 只给了 widthFactor、
                  // 没给 heightFactor，且它是 Stack 的**非定位子节点**，拿到的是松约束（高度 0~9）。
                  // 它把 `minHeight:0, maxHeight:9` 原样传给里面的 `DecoratedBox`，而 DecoratedBox
                  // 自己没有 child，在松约束下会收缩到 `constraints.smallest` → **高度 0**，
                  // 于是橙条渲染出来是一条高度为 0 的线，肉眼完全看不见。
                  //
                  // 修法：`Positioned.fill` 给紧约束 + `heightFactor: 1` 撑满 9px 轨道高度。
                  // 注意紧约束下 FractionallySizedBox 自身会占满整条轨道、而子节点只有
                  // `宽度×widthFactor`，此时 alignment 就会生效（默认 center 会把橙条居中），
                  // 所以必须显式锚定 `centerLeft`，才能从左往右填充。
                  Positioned.fill(
                    // 宽度做补间动画（对齐小程序 `.progress-fill` 的 transition: width .25s ease）：
                    // percent 变化时橙条平滑推进，而不是一跳一跳。
                    child: TweenAnimationBuilder<double>(
                      // ⚠️ 不要写 `begin:` —— TweenAnimationBuilder 只有在 begin 为 null 时
                      // 才会从「当前显示到的值」续接动画（内部 `newTween.begin ??= 现值`）。
                      // 一旦显式给了 begin（哪怕是 0），每次 percent 变化都会把控制器重置回 begin
                      // 重新跑一遍 250ms。而进度回调约 120ms 一次、动画要 250ms，
                      // 结果就是动画永远跑不完就被打断，橙条不停往回弹再冲上去（锯齿闪烁）。
                      tween: Tween<double>(end: percent.clamp(0.0, 1.0)),
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeOut,
                      builder: (context, value, child) => FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: value,
                        heightFactor: 1,
                        child: child,
                      ),
                      child: const DecoratedBox(
                        decoration: BoxDecoration(
                          // .progress-fill → linear-gradient(90deg, #ff8a45, #ff6421)
                          gradient: LinearGradient(
                            colors: [Color(0xFFFF8A45), Color(0xFFFF6421)],
                          ),
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
