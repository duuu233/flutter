import 'package:flutter/material.dart';

import 'package:BoltStar/src/shared/widgets/figma_common.dart';
import '../../../shared/l10n/app_l10n.dart';
import 'bind_device_debug_entry.dart';
import 'bind_device_scan_help.dart';

/// 绑定设备-未发现设备页：搜索失败提示与重试，对应 UI 稿「绑定设备-未发现设备」。
class BindDeviceNotFound extends StatelessWidget {
  const BindDeviceNotFound({super.key, this.onRetry, this.onHelp});

  final VoidCallback? onRetry;
  final VoidCallback? onHelp;

  @override
  Widget build(BuildContext context) {
    return FigmaScreen(
      title: AppL10n.of(context).bindDeviceTitle,
      scrollable: false,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const BindDebugEntryCard(),
          const SizedBox(height: 16),
          const Spacer(flex: 2),
          const Center(
            child: SizedBox(
              width: 280,
              height: 280,
              child: FigmaDeviceRadar(state: FigmaRadarState.notFound),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            AppL10n.of(context).bindNotFoundTitle,
            textAlign: TextAlign.center,
            // 标题加粗对齐小程序 bind.wxss 的 .scan-title(font-weight:700)。
            style: FigmaTextStyles.pageHeading.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            AppL10n.of(context).bindNotFoundHint,
            textAlign: TextAlign.center,
            style: FigmaTextStyles.bodySmall,
          ),
          const Spacer(flex: 3),
          // 从下往上拉起帮助弹层（对齐小程序），不再 push 一个全屏页。
          _ScanHelpLink(
            // 同 bind_device_searching：显式 void 闭包，不依赖 `??` 的类型推断。
            onTap: onHelp ?? () { showBindDeviceScanHelp(context); },
          ),
          const SizedBox(height: 16),
        ],
      ),
      bottom: FigmaPrimaryButton(
        label: AppL10n.of(context).bindRescan,
        onPressed: onRetry,
      ),
    );
  }
}

class _ScanHelpLink extends StatelessWidget {
  const _ScanHelpLink({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // 文字链的点击区靠 padding 撑开：裸 Text 时只有约 20px 高，很难点中。
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(
          AppL10n.of(context).bindScanHelpLink,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Color(0xFF2A2B2B),
            fontSize: 14,
            fontWeight: FontWeight.w400,
            height: 1.4,
          ),
        ),
      ),
    );
  }
}
