import 'package:flutter/material.dart';

import '../widgets/figma_common.dart';

class CastingProgressPage extends StatelessWidget {
  const CastingProgressPage({
    super.key,
    this.progress = 10 / 12,
    this.progressLabel = '10/12',
  });

  final double progress;
  final String progressLabel;

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
            child: FigmaTopNavigation(title: '投屏中'),
          ),
          const Positioned(
            left: 130,
            top: 158,
            width: 116,
            height: 116,
            child: FigmaCastResultIcon(success: true),
          ),
          const Positioned(
            left: 24,
            top: 326,
            width: 327,
            child: Text(
              '投屏中',
              textAlign: TextAlign.center,
              style: FigmaTextStyles.pageHeading,
            ),
          ),
          const Positioned(
            left: 62,
            top: 361,
            width: 252,
            child: Text(
              '投屏过程中请不要关闭手机',
              textAlign: TextAlign.center,
              style: FigmaTextStyles.bodySmall,
            ),
          ),
          Positioned(
            left: 43,
            top: 436,
            width: 289,
            child: FigmaProgressBar(progress: progress, label: progressLabel),
          ),
          const FigmaBottomHomeIndicator(),
        ],
      ),
    );
  }
}
