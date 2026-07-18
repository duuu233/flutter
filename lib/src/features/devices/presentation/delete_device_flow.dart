import 'package:flutter/material.dart';

import '../../../shared/l10n/app_l10n.dart';
import '../../../shared/widgets/app_dialog.dart';
import '../../../shared/widgets/app_toast.dart';
import '../../../shared/widgets/app_widgets.dart';
import '../../../state.dart';

/// 删除设备流程进行中标记：并发触发（连点）时第二路直接返回。
/// 文件级单份——原实现是路由 builder 闭包里的局部变量，每次路由实例化各一份，
/// 只能防同一实例内的重入。
bool _deleteFlowBusy = false;

/// 详情页「删除设备」完整流程（对齐小程序 detail.js `showDeleteConfirm`），
/// 与 [startOtaFlow] 同样抽成独立函数，路由表只做页面分发不再内嵌业务编排：
///   · 连接中：先弹「需先断开」前置确认弹窗 → 断开 → 再弹删除确认弹窗；
///   · 未连接：直接弹删除确认弹窗；
///   · 确认后删除，成功则详情页出栈回设备列表（列表刷新即为反馈，不再弹提示）。
///
/// 进入时快照设备 id：断开/删除全程只认它，不实时读全局 selectedDevice——
/// 弹窗等待期间后台 refreshDevices / 首页轮播联动可能改写选中项，
/// 实时读会把破坏性操作落到另一台设备。
Future<void> startDeleteDeviceFlow(
  BuildContext context,
  PhotoFrameState state,
) async {
  if (_deleteFlowBusy) {
    return;
  }
  final deviceId = state.selectedDeviceId;
  if (deviceId.isEmpty) {
    return;
  }
  _deleteFlowBusy = true;
  try {
    const deleteIcon = 'assets/images/device-detail-icon06.png';
    if (state.deviceById(deviceId).connected) {
      final proceed = await showAppConfirmDialog(
        context,
        iconAsset: deleteIcon,
        icon: Icons.delete_outline_rounded,
        tone: AppDialogTone.danger,
        title: AppL10n.of(context).devDeleteDevice,
        message: AppL10n.of(context).devDeleteNeedDisconnect,
        confirmLabel: AppL10n.of(context).devDisconnectShort,
      );
      if (proceed != true || !context.mounted) {
        return;
      }
      AppLoadingDialog.show(context, AppL10n.of(context).devDisconnecting);
      final ActionFeedback feedback;
      try {
        feedback = await state.disconnectDevice(deviceId);
      } finally {
        // hide 不做 mounted 门控（不依赖 context，见 AppLoadingDialog.hide）。
        AppLoadingDialog.hide(context);
      }
      if (!context.mounted) {
        return;
      }
      if (!feedback.success) {
        AppToast.warn(context, feedback.message);
        return;
      }
    }
    if (!context.mounted) {
      return;
    }
    final confirmed = await showAppConfirmDialog(
      context,
      iconAsset: deleteIcon,
      icon: Icons.delete_outline_rounded,
      tone: AppDialogTone.danger,
      title: AppL10n.of(context).devDeleteDevice,
      message: AppL10n.of(context).devDeleteDeviceMessage,
      confirmLabel: AppL10n.of(context).devConfirm,
    );
    if (confirmed != true || !context.mounted) {
      return;
    }
    AppLoadingDialog.show(context, AppL10n.of(context).devDeleting);
    final navigator = Navigator.of(context);
    final ActionFeedback feedback;
    try {
      feedback = await state.deleteDevice(deviceId);
    } finally {
      AppLoadingDialog.hide(context);
    }
    if (!context.mounted) {
      return;
    }
    if (feedback.success) {
      // 删除成功：详情页出栈回到设备列表（列表刷新即为反馈，不再弹提示，对齐小程序）。
      navigator.pop();
    } else {
      AppToast.warn(context, feedback.message);
    }
  } finally {
    _deleteFlowBusy = false;
  }
}
