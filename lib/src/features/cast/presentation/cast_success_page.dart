import 'package:flutter/material.dart';

import 'package:BoltStar/src/shared/widgets/figma_common.dart';
import '../../../shared/l10n/app_l10n.dart';
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
    final l10n = AppL10n.of(context);
    return FigmaScreen(
      title: l10n.cresSuccessTitle,
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
          Text(
            l10n.cresSuccessTitle,
            textAlign: TextAlign.center,
            style: projectionResultTitleStyle,
          ),
          const SizedBox(height: 11),
          Text(
            l10n.cresSuccessDesc,
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
          FigmaPrimaryButton(label: l10n.cresContinueCast, onPressed: onContinueCasting),
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
