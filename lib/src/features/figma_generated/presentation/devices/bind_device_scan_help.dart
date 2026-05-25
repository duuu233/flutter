import 'package:flutter/material.dart';

import '../widgets/figma_common.dart';

class BindDeviceScanHelp extends StatelessWidget {
  const BindDeviceScanHelp({super.key, this.onRetry});

  final VoidCallback? onRetry;

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
          Positioned.fill(
            child: ColoredBox(color: Colors.black.withValues(alpha: 0.32)),
          ),
          Positioned(
            left: 0,
            top: 346,
            width: 375,
            height: 466,
            child: DecoratedBox(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: Stack(
                children: [
                  const Positioned(
                    left: 0,
                    top: 18,
                    width: 375,
                    child: Text(
                      '扫描不到怎么办？',
                      textAlign: TextAlign.center,
                      style: FigmaTextStyles.pageHeading,
                    ),
                  ),
                  Positioned(
                    right: 20,
                    top: 21,
                    width: 26,
                    height: 26,
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      icon: const Icon(Icons.close_rounded, size: 20),
                      onPressed: () => Navigator.maybePop(context),
                    ),
                  ),
                  const Positioned(
                    left: 129,
                    top: 72,
                    width: 115,
                    height: 115,
                    child: _ScanHelpIcon(),
                  ),
                  const Positioned(
                    left: 39,
                    top: 209,
                    width: 297,
                    child: Text(
                      '请检查：',
                      style: TextStyle(
                        color: Color(0xFF2A2B2B),
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        height: 1.5,
                      ),
                    ),
                  ),
                  const Positioned(
                    left: 39,
                    top: 243,
                    width: 306,
                    child: Text(
                      '1.设备是否有电？\n'
                      '2.当前设备是否被占用？\n'
                      '3.设备蓝牙是否工作正常，手机蓝牙是否打开\n'
                      '4.设备是否与手机距离过远，隔离或有其他遮挡物',
                      style: TextStyle(
                        color: Color(0xCC2A2B2B),
                        fontSize: 14,
                        fontWeight: FontWeight.w400,
                        height: 1.55,
                      ),
                    ),
                  ),
                  Positioned(
                    left: 24,
                    top: 356,
                    width: 327,
                    height: 56,
                    child: FigmaPrimaryButton(
                      label: '重新扫描',
                      onPressed: onRetry,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const FigmaBottomHomeIndicator(),
        ],
      ),
    );
  }
}

class _ScanHelpIcon extends StatelessWidget {
  const _ScanHelpIcon();

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        Container(
          width: 115,
          height: 115,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFFFFEAD9).withValues(alpha: 0.6),
          ),
        ),
        Container(
          width: 77,
          height: 77,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: Color(0xFFFFF4EC),
          ),
        ),
        Container(
          width: 57,
          height: 57,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white,
          ),
          child: const Icon(
            Icons.bluetooth_disabled_rounded,
            color: Color(0xFFFF6A24),
            size: 26,
          ),
        ),
      ],
    );
  }
}
