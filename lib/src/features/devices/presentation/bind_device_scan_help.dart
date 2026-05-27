import 'package:flutter/material.dart';

import 'package:BoltStar/src/shared/widgets/home_figma_common.dart';
import 'package:BoltStar/src/shared/widgets/figma_common.dart';

/// 绑定设备-扫码帮助页：指引用户扫码 / 找到设备二维码，对应 UI 稿「扫码帮助」。
class BindDeviceScanHelp extends StatelessWidget {
  const BindDeviceScanHelp({super.key, this.onRetry});

  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return FigmaHomePhoneFrame(
      child: Stack(
        children: [
          const Positioned.fill(child: FigmaHomeBackground()),
          const Positioned(
            left: 52,
            top: 91,
            width: 270,
            height: 270,
            child: FigmaBluetoothRadar(state: FigmaRadarState.notFound),
          ),
          const Positioned(
            left: 0,
            top: 0,
            width: 375,
            height: 90,
            child: FigmaBindDeviceTopBar(),
          ),
          const Positioned(
            left: 0,
            top: 338,
            width: 375,
            child: Text(
              '未发现设备',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF2A2B2B),
                fontSize: 20,
                fontWeight: FontWeight.w600,
                height: 1.2,
              ),
            ),
          ),
          const Positioned(
            left: 0,
            top: 374,
            width: 375,
            child: Text(
              '设备连接中断，请检查设备状态后重试',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0x992A2B2B),
                fontSize: 12,
                fontWeight: FontWeight.w400,
                height: 1.2,
              ),
            ),
          ),
          Positioned.fill(
            child: ColoredBox(color: Colors.black.withValues(alpha: 0.42)),
          ),
          Positioned(
            left: 0,
            top: 346,
            width: 375,
            height: 466,
            child: DecoratedBox(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Stack(
                children: [
                  const Positioned(
                    left: 0,
                    top: 25,
                    width: 375,
                    child: Text(
                      '扫描不到怎么办？',
                      textAlign: TextAlign.center,
                      style: FigmaHomeTextStyles.sheetTitle,
                    ),
                  ),
                  Positioned(
                    right: 28,
                    top: 25,
                    width: 24,
                    height: 24,
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints.tightFor(
                        width: 24,
                        height: 24,
                      ),
                      icon: const Icon(
                        Icons.close_rounded,
                        color: Color(0xFF7E7E7E),
                        size: 26,
                      ),
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
                    top: 213,
                    child: Text(
                      '请检查：',
                      style: TextStyle(
                        color: Color(0xFF2A2B2B),
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        height: 1.5,
                      ),
                    ),
                  ),
                  const Positioned(
                    left: 39,
                    top: 248,
                    width: 306,
                    child: Text(
                      '1.设备是否有电?\n'
                      '2.当前设备是否被占用?\n'
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
                    child: FigmaHomePrimaryButton(
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
            color: const Color(0xFFFFEAD9).withValues(alpha: 0.34),
          ),
        ),
        Container(
          width: 77,
          height: 77,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFFFFE3D1).withValues(alpha: 0.52),
          ),
        ),
        Container(
          width: 57,
          height: 57,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFFFFB287), Color(0xFFFF8B62)],
            ),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: const [
              Icon(
                Icons.center_focus_weak_rounded,
                color: Colors.white,
                size: 28,
              ),
              Icon(Icons.close_rounded, color: Colors.white, size: 16),
            ],
          ),
        ),
      ],
    );
  }
}
