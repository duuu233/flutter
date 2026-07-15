import 'package:flutter/material.dart';

import 'package:BoltStar/src/shared/widgets/figma_common.dart';
import '../../../shared/l10n/app_l10n.dart';
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
    final l10n = AppL10n.of(context);
    return FigmaScreen(
      title: l10n.cresFailedTitle,
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
          Text(
            l10n.cresFailedTitle,
            textAlign: TextAlign.center,
            style: projectionResultTitleStyle,
          ),
          const SizedBox(height: 11),
          Text(
            l10n.cresFailedDesc,
            textAlign: TextAlign.center,
            style: projectionResultDescStyle,
          ),
          const SizedBox(height: 30),
          ProjectionInfoCard(
            deviceName: '',
            recordLabel: '',
            onTapRecords: onOpenRecords,
          ),
        ],
      ),
      bottom: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FigmaPrimaryButton(label: l10n.cresRecast, onPressed: onRetry),
          const SizedBox(height: 12),
          FigmaSecondaryButton(
            label: l10n.cresBackHome,
            onPressed: onBackHome ?? () => Navigator.maybePop(context),
          ),
        ],
      ),
    );
  }
}
