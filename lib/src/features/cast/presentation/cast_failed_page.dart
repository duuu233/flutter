import 'package:flutter/material.dart';

import 'package:BoltStar/src/shared/widgets/figma_common.dart';
import 'cast_result_common.dart';

/// 投屏失败页：提示失败原因并提供重试 / 返回首页，对应 UI 稿「投屏失败」。
class CastFailedPage extends StatelessWidget {
  const CastFailedPage({
    super.key,
    this.onRetry,
    this.onBackHome,
    this.onOpenRecords,
  });

  final VoidCallback? onRetry;
  final VoidCallback? onBackHome;
  final VoidCallback? onOpenRecords;

  @override
  Widget build(BuildContext context) {
    return FigmaScreen(
      title: '投屏失败',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 20),
          const Center(
            child: ProjectionResultArt(
              asset: 'assets/images/upload-icon02.png',
              fallbackIcon: Icons.error_outline_rounded,
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            '投屏失败',
            textAlign: TextAlign.center,
            style: projectionResultTitleStyle,
          ),
          const SizedBox(height: 11),
          const Text(
            '设备连接中断，请检查设备状态后重试',
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
          FigmaPrimaryButton(label: '重新投屏', onPressed: onRetry),
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
