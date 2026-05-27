import 'package:flutter/material.dart';

import 'package:BoltStar/src/shared/widgets/figma_common.dart';

/// 投屏进行中页：展示投屏传输进度，对应 UI 稿「投屏中」。
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
    return FigmaScreen(
      title: '投屏中',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 68),
          const Center(child: FigmaCastResultIcon(success: true)),
          const SizedBox(height: 24),
          const Text(
            '投屏中',
            textAlign: TextAlign.center,
            style: FigmaTextStyles.pageHeading,
          ),
          const SizedBox(height: 8),
          const Text(
            '投屏过程中请不要关闭手机',
            textAlign: TextAlign.center,
            style: FigmaTextStyles.bodySmall,
          ),
          const SizedBox(height: 40),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 19),
            child: FigmaProgressBar(progress: progress, label: progressLabel),
          ),
        ],
      ),
    );
  }
}
