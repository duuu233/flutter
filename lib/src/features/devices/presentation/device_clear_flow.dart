import 'package:flutter/material.dart';

import '../../../shared/l10n/app_l10n.dart';
import '../../../shared/widgets/app_dialog.dart';
import '../../../shared/widgets/app_toast.dart';
import '../../../shared/widgets/app_widgets.dart';
import '../../../state.dart';

/// 一键清空进行中标记：并发触发（连点）时第二路直接返回。
/// 与 [startDeleteDeviceFlow] 同样是**文件级单份**——放在调用方闭包里的局部变量
/// 每次调用各一份，挡不住重入。
bool _clearFlowBusy = false;

const String _clearIcon = 'assets/images/device-detail-icon05.png';

/// 详情页「一键清空」完整流程（对齐小程序 `detail.js` 的
/// `clearCopies`(第一步警示「同时清空图库」) → `confirmClearCopies`(第二步确认) 两级弹窗）。
///
/// 2026-07-19 由整页路由改成**当前页直接弹窗**：原实现 push 了一个
/// `DeviceClearConfirmPage`，因为 `AppPageRoute` 继承 `MaterialPageRoute`（不透明），
/// 那个「弹窗」不得不在自己页面里重画一份设备详情当假背景 + 手搓一层黑色遮罩，
/// 再把 `AppDialog` 摆在中间。代价是用户看得见一次**页面跳转**（480ms 横滑转场 +
/// 顶栏重建），观感与「二次确认」完全不符，两步之间也没法回到真正的详情页。
/// 现在两步都走 `showAppConfirmDialog`（dialog 路由，自带遮罩、不换页），
/// 与「删除设备」流程 [startDeleteDeviceFlow] 保持同一形态。
///
/// 进入时快照设备 id：两步确认停留期间后台 refreshDevices 可能改写全局 selectedDevice，
/// 实时读会把这个破坏性操作落到另一台设备上。
///
/// 不做权限门禁：入口先判「已连接」，未连接直接提示并返回；`clearDeviceMemory`
/// 本身也不自动扫连（见 state.dart），全程不会触发蓝牙/定位授权。
Future<void> startClearDeviceFlow(
  BuildContext context,
  PhotoFrameState state,
  String deviceId,
) async {
  if (_clearFlowBusy) {
    return;
  }
  if (deviceId.isEmpty) {
    return;
  }
  // 入口先判连接（对齐小程序 detail.js：未连接直接提示，不进两步确认）。
  // clearDeviceMemory 不自动扫连，不在这里拦的话用户点完两步确认才看到
  // 「请先连接设备」——白走一遍确认流程。与轮播设置入口同一形态（app_routes）。
  // 用 resolveDeviceConnected：详情接口不下发完整设备 ID 时，同步判断会把连着的设备误判成未连接。
  if (!await state.resolveDeviceConnected(deviceId)) {
    if (context.mounted) {
      AppToast.show(context, AppL10n.of(context).devConnectFirst);
    }
    return;
  }
  if (!context.mounted) {
    return;
  }
  _clearFlowBusy = true;
  try {
    final l10n = AppL10n.of(context);
    // 第一步：警示「同时清空设备与小程序/APP 图库」。点完还有第二步，按钮是「继续」。
    final warned = await showAppConfirmDialog(
      context,
      iconAsset: _clearIcon,
      icon: Icons.cleaning_services_outlined,
      title: l10n.devClearAll,
      message: l10n.devClearStep1Message,
      cancelLabel: l10n.devThinkAgain,
      confirmLabel: l10n.continueLabel,
    );
    if (warned != true || !context.mounted) {
      return;
    }
    // 第二步：「我已阅读并了解此操作的结果」。
    final confirmed = await showAppConfirmDialog(
      context,
      iconAsset: _clearIcon,
      icon: Icons.cleaning_services_outlined,
      title: l10n.devClearAll,
      message: l10n.devClearStep2Message,
      confirmLabel: l10n.devConfirm,
    );
    if (confirmed != true || !context.mounted) {
      return;
    }
    final cleared = await runClearDeviceMemory(context, state, deviceId);
    // 成功/失败都留在详情页：原实现「成功后 maybePop」是为了退出那个假弹窗页，
    // 现在没有页面要退，只给吐司反馈。
    if (cleared && context.mounted) {
      AppToast.show(context, l10n.devCleared);
    }
  } finally {
    _clearFlowBusy = false;
  }
}

/// 只做「蒙层 loading + 调清空 + 失败提示」这一段，不含二次确认。
///
/// 抽出来是给「删除设备」复用的：那条流程有自己的两道确认，确认完要先清空再解绑，
/// 不能再弹一遍一键清空的确认框。返回是否清空成功——失败时调用方必须中止，
/// 否则设备解绑了、照片却永远留在上面。
Future<bool> runClearDeviceMemory(
  BuildContext context,
  PhotoFrameState state,
  String deviceId,
) async {
  AppLoadingDialog.show(context, AppL10n.of(context).devClearing);
  // hide 放 finally 且不做 mounted 门控（不依赖 context）：清空可长达 180s，
  // 期间页面被卸载也要收掉 root 栈上 canPop:false 的蒙层，否则整个 App 假死。
  final ActionFeedback feedback;
  try {
    feedback = await state.clearDeviceMemory(deviceId);
  } finally {
    AppLoadingDialog.hide(context);
  }
  if (!feedback.success && context.mounted) {
    AppToast.warn(context, feedback.message);
  }
  return feedback.success;
}
