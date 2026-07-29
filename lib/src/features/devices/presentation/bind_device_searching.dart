import 'package:flutter/material.dart';

import 'package:BoltStar/src/shared/widgets/figma_common.dart';
import '../../../shared/l10n/app_l10n.dart';
import 'bind_device_debug_entry.dart';
import 'bind_device_scan_help.dart';

/// 绑定设备-搜索中页：蓝牙搜索附近相框设备，对应 UI 稿「绑定设备-搜索中」。
class BindDeviceSearching extends StatelessWidget {
  const BindDeviceSearching({super.key, this.onCancel, this.onHelp});

  final VoidCallback? onCancel;
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
          // 与发现结果页使用完全相同的顶部间距和 280×280 占位。首台设备出现后
          // searching → found 只替换下方内容，GIF 的顶部坐标与尺寸都不再跳动。
          const SizedBox(height: 12),
          const Center(
            child: SizedBox(
              width: 280,
              height: 280,
              // 搜索中动画：对齐小程序 bind.wxml 扫描态的 radar gif，使用本地 search-devices.gif。
              child: Image(
                image: AssetImage('assets/images/search-devices.gif'),
                fit: BoxFit.contain,
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            AppL10n.of(context).bindSearchingTitle,
            textAlign: TextAlign.center,
            // 标题加粗对齐小程序 bind.wxss 的 .scan-title(font-weight:700)。
            style: FigmaTextStyles.pageHeading.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            AppL10n.of(context).bindSearchingHint,
            textAlign: TextAlign.center,
            style: FigmaTextStyles.bodySmall,
          ),
          const Spacer(flex: 3),
          // 从下往上拉起帮助弹层（对齐小程序），不再 push 一个全屏页。
          _ScanHelpLink(
            // 用带花括号的 void 闭包，不用 `=> showBindDeviceScanHelp(context)`：
            // 后者返回 Future<void>，要靠 `??` 求两个函数类型的最小公共上界才能
            // 匹配上非空的 VoidCallback。能过，但没必要把编译结果押在类型推断上。
            onTap:
                onHelp ??
                () {
                  showBindDeviceScanHelp(context);
                },
          ),
          const SizedBox(height: 16),
        ],
      ),
      bottom: FigmaPrimaryButton(
        label: AppL10n.of(context).bindCancelScan,
        onPressed: onCancel ?? () => Navigator.maybePop(context),
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
