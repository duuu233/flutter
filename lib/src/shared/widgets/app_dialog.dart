import 'package:flutter/material.dart';

import '../l10n/app_l10n.dart';

/// 全项目**唯一**的提示 / 二次确认弹窗样式，1:1 对齐小程序 `.confirm-dialog`
///（`subpackages/device/detail/detail.wxss` 与 `subpackages/album/list/list.wxss`，rpx ÷ 2 = px）：
///
/// - 遮罩 `rgba(0,0,0,.4)`，左右留白 48rpx→24；
/// - 白卡 radius 28rpx→14，内边距 60/48/40rpx→(24, 30, 24, 20)；
/// - 左侧图标盒 96rpx→48，radius 30rpx→15，底色为强调色 8%；与文案间距 28rpx→14；
/// - 标题 38rpx→19/700 `#25282D`，说明 24rpx→12 `#6F7782`，行高 1.45；
/// - 按钮行上边距 42rpx→21、左缩进 118rpx→59、列间距 24rpx→12；
/// - 按钮高 72rpx→36、radius 999、28rpx→14/500；取消 `#EEEEEE`，确认为
///   `#FF9140 → #FF6A20` 竖向渐变（删除类弹窗也是橙色，只有**图标**变红）。
///
/// 项目里所有弹窗都走这里，不再使用系统 [AlertDialog]——否则同一个 App 里会出现
/// 系统样式与小程序样式两套确认框。加载遮罩（`AppLoadingDialog`）与轻提示
///（`AppToast`）不属于本组件的范畴。
enum AppDialogTone {
  /// 常规提示 / 确认：橙色图标盒。
  primary,

  /// 删除、注销等破坏性操作：红色图标盒（小程序 `.danger-icon`）。
  danger,
}

extension on AppDialogTone {
  Color get accent => switch (this) {
    AppDialogTone.primary => const Color(0xFFFF6A20),
    AppDialogTone.danger => const Color(0xFFFF3045),
  };

  IconData get fallbackIcon => switch (this) {
    AppDialogTone.primary => Icons.info_outline_rounded,
    AppDialogTone.danger => Icons.error_outline_rounded,
  };
}

/// 弹出二次确认弹窗：点「确认」返回 true，点「取消」/点遮罩/返回键返回 null。
///
/// [showCancel] 为 false 时只渲染一个通栏「确认」，用于纯告知类提示（登录校验失败、
/// 「已是最新版本」等）——小程序那边是 `wx.showModal({showCancel:false})`。
Future<bool?> showAppConfirmDialog(
  BuildContext context, {
  required String title,
  String? message,
  String? iconAsset,
  IconData? icon,
  AppDialogTone tone = AppDialogTone.primary,
  String? confirmLabel,
  String? cancelLabel,
  bool showCancel = true,
  bool barrierDismissible = true,
  bool useRootNavigator = false,
  Widget? content,
  VoidCallback? onCancelTap,
}) {
  // 双击「确认」会 pop 两次（第二次把弹窗下面的页面也弹掉），用闩锁挡住。
  var resolved = false;
  return showDialog<bool>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.4),
    barrierDismissible: barrierDismissible,
    useRootNavigator: useRootNavigator,
    builder: (dialogContext) {
      void close([bool? result]) {
        if (resolved) {
          return;
        }
        resolved = true;
        Navigator.of(dialogContext).pop(result);
      }

      return AppDialog(
        title: title,
        message: message,
        iconAsset: iconAsset,
        icon: icon,
        tone: tone,
        confirmLabel: confirmLabel,
        cancelLabel: cancelLabel,
        showCancel: showCancel,
        content: content,
        // 传了 onCancelTap 就把左键改成「执行动作但不关弹窗」（如崩溃日志的「复制日志」）。
        onCancel: onCancelTap ?? () => close(),
        onConfirm: () => close(true),
      );
    },
  );
}

/// 纯告知弹窗（单个通栏按钮，默认「我知道了」）。
Future<void> showAppNoticeDialog(
  BuildContext context, {
  required String title,
  String? message,
  String? iconAsset,
  IconData? icon,
  AppDialogTone tone = AppDialogTone.primary,
  String? confirmLabel,
  bool barrierDismissible = true,
  bool useRootNavigator = false,
}) async {
  await showAppConfirmDialog(
    context,
    title: title,
    message: message,
    iconAsset: iconAsset,
    icon: icon,
    tone: tone,
    confirmLabel: confirmLabel ?? AppL10n.of(context).gotIt,
    showCancel: false,
    barrierDismissible: barrierDismissible,
    useRootNavigator: useRootNavigator,
  );
}

/// 弹窗本体。一般用 [showAppConfirmDialog] / [showAppNoticeDialog]；
/// 只有需要把弹窗嵌进页面（如「一键清空」确认页自带遮罩）时才直接用本组件。
class AppDialog extends StatelessWidget {
  const AppDialog({
    super.key,
    required this.title,
    this.message,
    this.iconAsset,
    this.icon,
    this.tone = AppDialogTone.primary,
    this.confirmLabel,
    this.cancelLabel,
    this.showCancel = true,
    this.content,
    this.onCancel,
    required this.onConfirm,
  });

  final String title;
  final String? message;

  /// 优先用切图；缺资源时回退到 [icon]，再回退到 [AppDialogTone] 的默认图标。
  final String? iconAsset;
  final IconData? icon;
  final AppDialogTone tone;
  final String? confirmLabel;
  final String? cancelLabel;
  final bool showCancel;

  /// 说明文案下方的自定义内容（如重命名弹窗的输入框），通栏铺满。
  final Widget? content;
  final VoidCallback? onCancel;
  final VoidCallback? onConfirm;

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final accent = tone.accent;
    final text = message?.trim() ?? '';
    final confirmButton = _AppDialogButton(
      label: confirmLabel ?? l10n.confirm,
      textColor: Colors.white,
      gradient: const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFFFF9140), Color(0xFFFF6A20)],
      ),
      onTap: onConfirm,
    );
    return Dialog(
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 30, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: _buildIcon(accent),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: Color(0xFF25282D),
                          fontSize: 19,
                          fontWeight: FontWeight.w700,
                          height: 1.15,
                        ),
                      ),
                      if (text.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          text,
                          style: const TextStyle(
                            color: Color(0xFF6F7782),
                            fontSize: 12,
                            height: 1.45,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            if (content != null) ...[
              const SizedBox(height: 16),
              content!,
            ],
            const SizedBox(height: 21),
            Padding(
              // 左缩进 59 = 图标盒 48 + 间距 14 − 视觉微调（小程序 118rpx）。
              padding: const EdgeInsets.only(left: 59),
              child: showCancel
                  ? Row(
                      children: [
                        Expanded(
                          child: _AppDialogButton(
                            label: cancelLabel ?? l10n.cancel,
                            textColor: const Color(0xFF32363C),
                            background: const Color(0xFFEEEEEE),
                            onTap: onCancel,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(child: confirmButton),
                      ],
                    )
                  : confirmButton,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIcon(Color accent) {
    final asset = iconAsset;
    final fallback = Icon(icon ?? tone.fallbackIcon, color: accent, size: 24);
    if (asset == null || asset.isEmpty) {
      return fallback;
    }
    return Image.asset(
      asset,
      width: 24,
      height: 24,
      fit: BoxFit.contain,
      errorBuilder: (context, error, stackTrace) => fallback,
    );
  }
}

/// 弹窗内的输入框（重命名设备等），作为 [AppDialog.content] 传入。
class AppDialogTextField extends StatelessWidget {
  const AppDialogTextField({
    super.key,
    required this.controller,
    this.hintText,
    this.maxLength,
    this.keyboardType,
  });

  final TextEditingController controller;
  final String? hintText;
  final int? maxLength;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFF5F6F8),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: TextField(
          controller: controller,
          autofocus: true,
          maxLength: maxLength,
          keyboardType: keyboardType,
          cursorColor: const Color(0xFFEB5F1B),
          style: const TextStyle(
            color: Color(0xFF25282D),
            fontSize: 14,
            height: 1.2,
          ),
          decoration: InputDecoration(
            isCollapsed: true,
            border: InputBorder.none,
            // 计数器占一行高度且贴着卡片底边，视觉很脏，直接隐藏。
            counterText: '',
            hintText: hintText,
            hintStyle: const TextStyle(
              color: Color(0xFF9AA1AC),
              fontSize: 14,
              height: 1.2,
            ),
          ),
        ),
      ),
    );
  }
}

class _AppDialogButton extends StatelessWidget {
  const _AppDialogButton({
    required this.label,
    required this.textColor,
    required this.onTap,
    this.background,
    this.gradient,
  });

  final String label;
  final Color textColor;
  final VoidCallback? onTap;
  final Color? background;
  final Gradient? gradient;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(999);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        gradient: gradient,
        borderRadius: radius,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: radius,
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          child: Container(
            height: 36,
            alignment: Alignment.center,
            child: Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: textColor,
                fontSize: 14,
                fontWeight: FontWeight.w500,
                height: 1,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
