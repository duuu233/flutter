import 'package:flutter/material.dart';

import '../widgets/figma_common.dart';
import 'bind_device_scan_help.dart';

class BindDeviceNotFound extends StatelessWidget {
  const BindDeviceNotFound({super.key, this.onRetry, this.onHelp});

  final VoidCallback? onRetry;
  final VoidCallback? onHelp;

  @override
  Widget build(BuildContext context) {
    return FigmaPhoneFrame(
      child: Stack(
        children: [
          const FigmaPageBackground(),
          const Positioned(
            left: -1,
            top: 22,
            width: 378,
            height: 378,
            child: FigmaDeviceRadar(state: FigmaRadarState.notFound),
          ),
          const Positioned(
            left: 0,
            top: 0,
            width: 375,
            height: 90,
            child: FigmaTopNavigation(title: '绑定设备'),
          ),
          const Positioned(
            left: 88,
            top: 333,
            width: 200,
            child: Text(
              '未发现设备',
              textAlign: TextAlign.center,
              style: FigmaTextStyles.pageHeading,
            ),
          ),
          const Positioned(
            left: 72,
            top: 368,
            width: 232,
            child: Text(
              '设备连接中断，请检查设备状态后重试',
              textAlign: TextAlign.center,
              style: FigmaTextStyles.bodySmall,
            ),
          ),
          Positioned(
            left: 112,
            top: 665,
            width: 152,
            child: _ScanHelpLink(
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
          ),
          Positioned(
            left: 24,
            top: 702,
            width: 327,
            height: 56,
            child: FigmaPrimaryButton(label: '重新扫描', onPressed: onRetry),
          ),
          const FigmaBottomHomeIndicator(),
        ],
      ),
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
