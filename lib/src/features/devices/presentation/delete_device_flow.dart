import 'package:flutter/material.dart';

import '../../../shared/l10n/app_l10n.dart';
import '../../../shared/widgets/app_dialog.dart';
import '../../../shared/widgets/app_toast.dart';
import '../../../shared/widgets/app_widgets.dart';
import '../../../state.dart';
import 'device_clear_flow.dart';

/// 解绑 / 删除进行中标记：并发触发（连点）时第二路直接返回。
/// 文件级单份——原实现是路由 builder 闭包里的局部变量，每次路由实例化各一份，
/// 只能防同一实例内的重入。两条流程共用一把锁：它们互斥（都会把这台设备解绑掉）。
bool _deleteFlowBusy = false;

const String _deleteIcon = 'assets/images/device-detail-icon06.png';

/// 详情页「解除绑定」（对齐小程序 detail.js `showDeleteConfirm` → `confirmDeleteDevice`）：
/// 一次确认 → 解绑。**设备上的照片保留**，只解除账号关系；连接中的会话由
/// [PhotoFrameState.deleteDevice] 内部一并断开，不再要求用户先手动断开。
///
/// 进入时快照设备 id：弹窗等待期间后台 refreshDevices / 首页轮播联动可能改写全局
/// selectedDevice，实时读会把破坏性操作落到另一台设备。
Future<void> startUnbindDeviceFlow(
  BuildContext context,
  PhotoFrameState state,
  String deviceId,
) async {
  if (_deleteFlowBusy || deviceId.isEmpty) {
    return;
  }
  _deleteFlowBusy = true;
  try {
    final l10n = AppL10n.of(context);
    final confirmed = await showAppConfirmDialog(
      context,
      iconAsset: _deleteIcon,
      icon: Icons.link_off_rounded,
      tone: AppDialogTone.danger,
      title: l10n.devUnbindDevice,
      message: l10n.devUnbindDeviceMessage,
      confirmLabel: l10n.devConfirm,
    );
    if (confirmed != true || !context.mounted) {
      return;
    }
    await _runDelete(context, state, deviceId, l10n.devUnbinding);
  } finally {
    _deleteFlowBusy = false;
  }
}

/// 详情页「删除设备」（对齐小程序 detail.js `showPermanentDeleteConfirm`）：
/// **一键清空 + 断开连接 + 解除绑定**，必须在连接态发起。
///
/// 两道二次确认（2026-08-04 文案对齐小程序 detail.wxml 原文）：
///   ① 「删除设备将执行一键清空电子纸设备及小程序/APP内的照片，防止隐私泄露。是否确认删除设备？」
///      → 取消 / 继续；
///   ② 「我已知晓删除电子纸设备相关内容，确认删除」→ 取消 / 确认。
///
/// 第二步确认后先跑一遍清空（复用 [runClearDeviceMemory]，失败即中止不解绑，
/// 否则照片会永远留在一台再也管不到的设备上），再走解绑（内部断开 BLE）。
Future<void> startDeleteDeviceFlow(
  BuildContext context,
  PhotoFrameState state,
  String deviceId,
) async {
  if (_deleteFlowBusy || deviceId.isEmpty) {
    return;
  }
  final l10n = AppL10n.of(context);
  // 入口先判连接：清空要与固件交互，未连接直接提示，不让用户白走两步确认
  //（对齐小程序 showPermanentDeleteConfirm）。用 resolveDeviceConnected：详情接口不下发
  // 完整设备 ID 时，同步判断会把连着的设备误判成未连接（第 7 项同源）。
  if (!await state.resolveDeviceConnected(deviceId)) {
    if (context.mounted) {
      AppToast.warn(context, l10n.devConnectFirst);
    }
    return;
  }
  if (!context.mounted) {
    return;
  }
  _deleteFlowBusy = true;
  try {
    final step1 = await showAppConfirmDialog(
      context,
      iconAsset: _deleteIcon,
      icon: Icons.delete_outline_rounded,
      tone: AppDialogTone.danger,
      title: l10n.devDeleteDevice,
      message: l10n.devDeleteDeviceMessage,
      // 第一步点完还有第二步，按钮叫「继续」。
      confirmLabel: l10n.continueLabel,
    );
    if (step1 != true || !context.mounted) {
      return;
    }
    final step2 = await showAppConfirmDialog(
      context,
      iconAsset: _deleteIcon,
      icon: Icons.delete_outline_rounded,
      tone: AppDialogTone.danger,
      title: l10n.devDeleteDeviceConfirmTitle,
      message: l10n.devDeleteDeviceConfirmMessage,
      confirmLabel: l10n.devConfirm,
    );
    if (step2 != true || !context.mounted) {
      return;
    }
    // 二次确认之后设备可能已经掉线；清空失败就地提示并中止，不继续解绑。
    final cleared = await runClearDeviceMemory(context, state, deviceId);
    if (!cleared || !context.mounted) {
      return;
    }
    await _runDelete(
      context,
      state,
      deviceId,
      l10n.devDeleting,
      successToast: l10n.devDeviceDeleted,
    );
  } finally {
    _deleteFlowBusy = false;
  }
}

/// 解绑落地：蒙层 loading → `state.deleteDevice`（内部会断开占用的 BLE 会话）→
/// 成功则详情页出栈回设备列表。
Future<void> _runDelete(
  BuildContext context,
  PhotoFrameState state,
  String deviceId,
  String loadingText, {
  String? successToast,
}) async {
  AppLoadingDialog.show(context, loadingText);
  final navigator = Navigator.of(context);
  final ActionFeedback feedback;
  try {
    feedback = await state.deleteDevice(deviceId);
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
  // 成功：详情页出栈回到设备列表（列表刷新即为反馈）。解除绑定不弹成功提示（对齐小程序），
  // 「删除设备」这条重流程给一句「设备已删除」。
  if (successToast != null) {
    AppToast.show(context, successToast);
  }
  navigator.pop();
}
