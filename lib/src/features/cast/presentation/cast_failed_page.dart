import 'package:flutter/material.dart';

import 'package:BoltStar/src/shared/widgets/figma_common.dart';

/// 投屏失败页：提示失败原因并提供重试 / 返回首页，对应 UI 稿「投屏失败」。
class CastFailedPage extends StatelessWidget {
  const CastFailedPage({super.key, this.onRetry, this.onBackHome});

  final VoidCallback? onRetry;
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
            child: FigmaTopNavigation(title: '投屏失败'),
          ),
          const Positioned(
            left: 130,
            top: 158,
            width: 116,
            height: 116,
            child: FigmaCastResultIcon(success: false),
          ),
          const Positioned(
            left: 24,
            top: 326,
            width: 327,
            child: Text(
              '投屏失败',
              textAlign: TextAlign.center,
              style: FigmaTextStyles.pageHeading,
            ),
          ),
          const Positioned(
            left: 62,
            top: 361,
            width: 252,
            child: Text(
              '设备连接中断，请检查设备状态后重试',
              textAlign: TextAlign.center,
              style: FigmaTextStyles.bodySmall,
            ),
          ),
          Positioned(
            left: 24,
            top: 624,
            width: 327,
            height: 56,
            child: FigmaPrimaryButton(label: '重新投屏', onPressed: onRetry),
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
