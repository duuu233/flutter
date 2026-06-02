import 'package:flutter/material.dart';

import 'package:BoltStar/src/shared/widgets/figma_common.dart';
import 'cast_result_common.dart';

/// 投屏成功页：提示投屏完成并提供继续投屏 / 返回首页，对应 UI 稿「投屏成功」。
class CastSuccessPage extends StatelessWidget {
  const CastSuccessPage({
    super.key,
    this.onContinueCasting,
    this.onBackHome,
    this.onOpenRecords,
  });

  final VoidCallback? onContinueCasting;
  final VoidCallback? onBackHome;
  final VoidCallback? onOpenRecords;

  @override
  Widget build(BuildContext context) {
    return FigmaScreen(
      title: '投屏成功',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 20),
          const Center(
            child: ProjectionResultArt(
              asset: 'assets/images/upload-icon03.png',
              fallbackIcon: Icons.check_circle_outline_rounded,
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            '投屏成功',
            textAlign: TextAlign.center,
            style: projectionResultTitleStyle,
          ),
          const SizedBox(height: 11),
          const Text(
            '照片已成功投屏到设备，可前往相册查看',
            textAlign: TextAlign.center,
            style: projectionResultDescStyle,
          ),
          const SizedBox(height: 30),
          ProjectionInfoCard(
            deviceName: '房间相册',
            recordLabel: '12张',
            onTapRecords: onOpenRecords,
          ),
        ],
      ),
      bottom: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FigmaPrimaryButton(label: '继续投屏', onPressed: onContinueCasting),
          const SizedBox(height: 12),
          FigmaSecondaryButton(
            label: '返回首页',
            onPressed: onBackHome ?? () => Navigator.maybePop(context),
          ),
        ],
      ),
    );
  }
}
