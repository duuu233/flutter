import 'package:flutter/material.dart';

import 'package:BoltStar/src/shared/widgets/home_figma_common.dart';
import '../../../shared/l10n/app_l10n.dart';

/// 绑定设备-「扫描不到怎么办？」帮助弹层。
///
/// 2026-07-19：改为真正的**底部上拉弹框**（`showModalBottomSheet`），对齐小程序交互。
/// 此前是一整个全屏页（`MaterialPageRoute` push）在假装弹层——自绘一层黑色蒙层、
/// 底部贴一张白卡，还把下面的「未找到设备」界面整个重画了一遍。代价是：
/// 从下往上的滑入动画没有（走的是页面转场）、点蒙层不能关闭、返回键行为像「退页」
/// 而不是「收起弹层」，且底层界面的雷达动画被复制成了静止副本。
Future<void> showBindDeviceScanHelp(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    // 与原先自绘蒙层同色，视觉不变。
    barrierColor: Colors.black.withValues(alpha: 0.42),
    // 内容比半屏高（标题 + 115 图标 + 检查清单），不放开会被压到 50% 高度。
    isScrollControlled: true,
    builder: (_) => const BindDeviceScanHelpSheet(),
  );
}

/// 帮助弹层的内容体（白色圆角卡）。单独暴露便于复用与预览。
class BindDeviceScanHelpSheet extends StatelessWidget {
  const BindDeviceScanHelpSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
          // 小屏 / 大系统字号下内容可能超过可用高度，允许滚动而不是溢出报错。
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Stack(
                  alignment: Alignment.center,
                  children: [
                    Text(
                      l10n.bindScanHelpLink,
                      textAlign: TextAlign.center,
                      style: FigmaHomeTextStyles.sheetTitle,
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: IconButton(
                        padding: EdgeInsets.zero,
                        // 关闭按钮同样是「小目标」：撑到 40×40 再放图标。
                        constraints: const BoxConstraints.tightFor(
                          width: 40,
                          height: 40,
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
                  l10n.bindPleaseCheck,
                  style: const TextStyle(
                    color: Color(0xFF2A2B2B),
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  l10n.bindCheckList,
                  style: const TextStyle(
                    color: Color(0xCC2A2B2B),
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                    height: 1.55,
                  ),
                ),
              ],
            ),
          ),
        ),
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
