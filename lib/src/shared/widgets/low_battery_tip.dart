import 'package:flutter/widgets.dart';

import '../l10n/app_l10n.dart';
import '../../state.dart';
import 'app_dialog.dart';

/// 低电量提醒（2026-08-21 同步小程序 `utils/low-battery.js`）。
///
/// 口径：**用户主动点**任意需要连接电子纸设备的功能按钮（连接、投屏、相册再投/删除、
/// 轮播设置、一键清空、固件升级…）时，电量 ≤10% 弹一次提醒；**自动连接的场景不弹**
/// ——投屏流程内部的续连、页面预热连接那些，用户并没有按下按钮，弹窗只会打断正在跑的流程。
///
/// 两档文案由产品定稿（见 [AppL10n.lowBatteryMessage] / [AppL10n.lowBatteryCriticalMessage]）：
/// - `10 ≥ 电量 > 3`：提示放到光线明亮处、减少操作频次；
/// - `电量 ≤ 3`（含 0）：告知即将关机，去阳光/明亮处光能充电即可恢复。
///
/// ⚠️ 电量未知一律不弹：没有判据就不报警，与详情页「未连接整行 `--`」同一套态度。
const int kLowBatteryMax = 10;
const int kCriticalBatteryMax = 3;

/// 电量落在哪一档。分档是**纯逻辑**，单独抽出来是为了不依赖 BuildContext 就能测
/// （见 `test/low_battery_band_test.dart`，与小程序 `tests/low-battery-tip.test.js` 同一组用例）。
enum LowBatteryBand {
  /// 电量健康或未知：不提醒。
  none,

  /// 10% ~ 4%：提示放到光线明亮处、减少操作频次。
  low,

  /// ≤3%（含 0）：告知即将关机，去阳光/明亮处光能充电。
  critical,
}

LowBatteryBand lowBatteryBandFor(int? battery) {
  if (battery == null || battery < 0 || battery > kLowBatteryMax) {
    return LowBatteryBand.none;
  }
  return battery <= kCriticalBatteryMax
      ? LowBatteryBand.critical
      : LowBatteryBand.low;
}

/// 该电量该弹哪段话；不低电量或电量未知（null）返回 null。
String? lowBatteryMessageFor(BuildContext context, int? battery) {
  final l10n = AppL10n.of(context);
  switch (lowBatteryBandFor(battery)) {
    case LowBatteryBand.none:
      return null;
    case LowBatteryBand.low:
      return l10n.lowBatteryMessage;
    case LowBatteryBand.critical:
      return l10n.lowBatteryCriticalMessage;
  }
}

/// 主动操作前的低电量提醒。返回是否真的弹了窗。
///
/// **不阻断**调用方的动作：弹窗只是告知，用户点「知道了」后原动作照常继续。
/// 之所以 await 而不是甩出去，是为了不和紧随其后的 loading 蒙层抢同一块屏。
Future<bool> showLowBatteryTipIfNeeded(
  BuildContext context,
  PhotoFrameState state,
  String deviceId,
) async {
  if (deviceId.isEmpty) {
    return false;
  }
  final battery = await state.batteryForActionTip(deviceId);
  if (!context.mounted) {
    return false;
  }
  final message = lowBatteryMessageFor(context, battery);
  if (message == null) {
    return false;
  }
  await showAppNoticeDialog(
    context,
    title: AppL10n.of(context).lowBatteryTitle,
    message: message,
  );
  return true;
}
