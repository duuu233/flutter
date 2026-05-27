import 'package:flutter/material.dart';

import 'package:BoltStar/src/shared/widgets/figma_common.dart';

/// 投屏成功页：提示投屏完成并提供继续投屏 / 返回首页，对应 UI 稿「投屏成功」。
class CastSuccessPage extends StatelessWidget {
  const CastSuccessPage({super.key, this.onContinueCasting, this.onBackHome});

  final VoidCallback? onContinueCasting;
  final VoidCallback? onBackHome;

  @override
  Widget build(BuildContext context) {
    return FigmaScreen(
      title: '投屏成功',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: const [
          SizedBox(height: 40),
          Center(child: FigmaCastResultIcon(success: true)),
          SizedBox(height: 24),
          Text(
            '投屏成功',
            textAlign: TextAlign.center,
            style: FigmaTextStyles.pageHeading,
          ),
          SizedBox(height: 8),
          Text(
            '照片已成功投屏到设备，可前往相册查看',
            textAlign: TextAlign.center,
            style: FigmaTextStyles.bodySmall,
          ),
          SizedBox(height: 32),
          _CastInfoCard(),
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
