import 'package:flutter/material.dart';

import 'package:BoltStar/src/shared/widgets/figma_common.dart';

/// 投屏成功页：提示投屏完成并提供继续投屏 / 返回首页，对应 UI 稿「投屏成功」。
class CastSuccessPage extends StatelessWidget {
  const CastSuccessPage({super.key, this.onContinueCasting, this.onBackHome});

  final VoidCallback? onContinueCasting;
  final VoidCallback? onBackHome;

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
            child: FigmaTopNavigation(title: '投屏成功'),
          ),
          const Positioned(
            left: 130,
            top: 130,
            width: 116,
            height: 116,
            child: FigmaCastResultIcon(success: true),
          ),
          const Positioned(
            left: 24,
            top: 280,
            width: 327,
            child: Text(
              '投屏成功',
              textAlign: TextAlign.center,
              style: FigmaTextStyles.pageHeading,
            ),
          ),
          const Positioned(
            left: 55,
            top: 315,
            width: 265,
            child: Text(
              '照片已成功投屏到设备，可前往相册查看',
              textAlign: TextAlign.center,
              style: FigmaTextStyles.bodySmall,
            ),
          ),
          const Positioned(
            left: 24,
            top: 402,
            width: 327,
            height: 122,
            child: _CastInfoCard(),
          ),
          Positioned(
            left: 24,
            top: 624,
            width: 327,
            height: 56,
            child: FigmaPrimaryButton(
              label: '继续投屏',
              onPressed: onContinueCasting,
            ),
          ),
          Positioned(
            left: 24,
            top: 692,
            width: 327,
            height: 56,
            child: FigmaSecondaryButton(
              label: '返回首页',
              onPressed: onBackHome ?? () => Navigator.maybePop(context),
            ),
          ),
          const FigmaBottomHomeIndicator(),
        ],
      ),
    );
  }
}

class _CastInfoCard extends StatelessWidget {
  const _CastInfoCard();

  @override
  Widget build(BuildContext context) {
    return FigmaGlassCard(
      child: Column(
        children: const [
          FigmaInfoRow(label: '投屏设备', value: '房间相册'),
          FigmaFormDivider(),
          FigmaInfoRow(label: '投屏管理', value: '12张'),
        ],
      ),
    );
  }
}
