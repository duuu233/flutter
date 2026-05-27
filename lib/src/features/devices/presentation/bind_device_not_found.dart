import 'package:flutter/material.dart';

import 'package:BoltStar/src/shared/widgets/figma_common.dart';
import 'bind_device_scan_help.dart';

/// 绑定设备-未发现设备页：搜索失败提示与重试，对应 UI 稿「绑定设备-未发现设备」。
class BindDeviceNotFound extends StatelessWidget {
  const BindDeviceNotFound({super.key, this.onRetry, this.onHelp});

  final VoidCallback? onRetry;
  final VoidCallback? onHelp;

  @override
  Widget build(BuildContext context) {
    return FigmaScreen(
      title: '绑定设备',
      scrollable: false,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Spacer(flex: 2),
          const Center(
            child: SizedBox(
              width: 280,
              height: 280,
              child: FigmaDeviceRadar(state: FigmaRadarState.notFound),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            '未发现设备',
            textAlign: TextAlign.center,
            style: FigmaTextStyles.pageHeading,
          ),
          const SizedBox(height: 8),
          const Text(
            '设备连接中断，请检查设备状态后重试',
            textAlign: TextAlign.center,
            style: FigmaTextStyles.bodySmall,
          ),
          const Spacer(flex: 3),
          _ScanHelpLink(
            onTap:
                onHelp ??
                () {
                  Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (_) => const BindDeviceScanHelp(),
                    ),
                  );
                },
          ),
          const SizedBox(height: 16),
        ],
      ),
      bottom: FigmaPrimaryButton(label: '重新扫描', onPressed: onRetry),
    );
  }
}

class _ScanHelpLink extends StatelessWidget {
  const _ScanHelpLink({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: const Text(
        '扫描不到怎么办？',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: Color(0xFF2A2B2B),
          fontSize: 14,
          fontWeight: FontWeight.w400,
          height: 1.4,
        ),
      ),
    );
  }
}
