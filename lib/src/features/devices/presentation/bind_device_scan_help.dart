import 'package:flutter/material.dart';

import 'package:BoltStar/src/shared/widgets/home_figma_common.dart';
import 'package:BoltStar/src/shared/widgets/figma_common.dart';
import '../../../shared/l10n/app_l10n.dart';

/// 绑定设备-扫码帮助页：指引用户扫码 / 找到设备二维码，对应 UI 稿「扫码帮助」。
class BindDeviceScanHelp extends StatelessWidget {
  const BindDeviceScanHelp({super.key, this.onRetry});

  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        FigmaScreen(
          title: AppL10n.of(context).bindDeviceTitle,
          scrollable: false,
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(flex: 2),
              const Center(
                child: SizedBox(
                  width: 240,
                  height: 240,
                  child: FigmaBluetoothRadar(state: FigmaRadarState.notFound),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                AppL10n.of(context).bindNotFoundTitle,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFF2A2B2B),
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                AppL10n.of(context).bindNotFoundHint,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0x992A2B2B),
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                  height: 1.2,
                ),
              ),
              const Spacer(flex: 3),
            ],
          ),
        ),
        Positioned.fill(
          child: ColoredBox(color: Colors.black.withValues(alpha: 0.42)),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: DecoratedBox(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Stack(
                      alignment: Alignment.center,
                      children: [
                        Text(
                          AppL10n.of(context).bindScanHelpLink,
                          textAlign: TextAlign.center,
                          style: FigmaHomeTextStyles.sheetTitle,
                        ),
                        Align(
                          alignment: Alignment.centerRight,
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
                      ],
                    ),
                    const SizedBox(height: 24),
                    const Center(
                      child: SizedBox(
                        width: 115,
                        height: 115,
                        child: _ScanHelpIcon(),
                      ),
                    ),
                    const SizedBox(height: 26),
                    Text(
                      AppL10n.of(context).bindPleaseCheck,
                      style: const TextStyle(
                        color: Color(0xFF2A2B2B),
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      AppL10n.of(context).bindCheckList,
                      style: const TextStyle(
                        color: Color(0xCC2A2B2B),
                        fontSize: 14,
                        fontWeight: FontWeight.w400,
                        height: 1.55,
                      ),
                    ),
                    const SizedBox(height: 24),
                    FigmaHomePrimaryButton(
                      label: AppL10n.of(context).bindRescan,
                      onPressed: onRetry,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
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
