import 'dart:async' show unawaited;

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:BoltStar/src/shared/widgets/app_dialog.dart';
import 'package:BoltStar/src/shared/widgets/app_widgets.dart';
import 'package:BoltStar/src/shared/widgets/figma_common.dart';
import '../../../device/ble_controller.dart';
import '../../../device/ble/ota_ble.dart';
import '../../../device/frame_device_protocol.dart';
import '../../../routes/app_routes.dart';
import '../../../shared/l10n/app_l10n.dart';
import '../../../shared/permission_gate.dart';
import '../../../shared/widgets/low_battery_tip.dart';
import '../../../state.dart';

/// 设备固件 OTA 升级页 —— 由微信小程序版 `subpackages/device/ota/ota`（ota.js + ota.wxml）移植。
///
/// 流程对齐小程序：进入即拉设备详情（`fetchDeviceFirmwareInfo` → getUserProductDetail）判断
/// 是否有可升级固件；真实升级复用图传已连接的设备，走独立的 FF10 OTA 服务（见 [FrameOtaClient]）。
/// ⚠️ 2026-08-13（两端同步）：**整套「干跑测试(mock 固件)」已删除**——留着它，「升级成功」
/// 就有了两种含义（真机 DFU 成功 / 本地编码校验通过），真机联调时看日志很容易把干跑的成功
/// 当成设备真的升上去了。
///
/// 与「更新 BoltStar」(App 版本更新，`update_boltstar_page`) 是两件事：这里升级的是相框设备固件。
class OtaUpgradePage extends StatefulWidget {
  const OtaUpgradePage({
    super.key,
    required this.state,
    required this.deviceId,
    this.autoStart = false,
  });

  final PhotoFrameState state;
  final String deviceId;

  /// 由详情页 OTA 入口的确认弹窗（立刻更新）进入时为 true：包就绪且已连接则自动开始升级
  /// （对齐小程序 goOtaUpgrade 确认后带 `auto=1` 自动开始）。
  final bool autoStart;

  @override
  State<OtaUpgradePage> createState() => _OtaUpgradePageState();
}

/// 详情页「固件升级」入口流程（对齐小程序 detail.js `goOtaUpgrade`）：
/// ① 未连接→自动扫连；② loading 下二次拉取版本(`getUserProductDetail`)；
/// ③ 已最新/无有效包→提示后返回；④ 有新版→弹「检测到新版本 X，是否升级(稍后/立刻更新)」；
/// ⑤ 确认「立刻更新」→进 OTA 页并 `autoStart` 自动开始。
Future<void> startOtaFlow(
  BuildContext context,
  PhotoFrameState state,
  String deviceId,
) async {
  final device = state.deviceById(deviceId);
  // ① 未连接自动扫连（升级需设备在线）。
  if (!state.isDeviceActuallyConnected(device.id)) {
    // 权限门禁前置于 loading：授权框要单独出现，不与设备操作同屏（见 PermissionGate）。
    if (!await PermissionGate.ensureBleReady(context) || !context.mounted) {
      return;
    }
    AppLoadingDialog.show(context, AppL10n.of(context).otaConnecting);
    // 统一 hide 收口（精确移除 + 无 mounted 门控），替换掉盲 pop（历史闪退根源）：
    // 本流程可叠在详情页其它 loading 之上，show 被静默忽略时盲 pop 会弹掉业务页。
    final ActionFeedback feedback;
    try {
      feedback = await state.connectDevice(device.id);
    } finally {
      AppLoadingDialog.hide(context);
    }
    if (!context.mounted) {
      return;
    }
    if (!feedback.success) {
      AppToast.show(context, feedback.message);
      return;
    }
  }
  // 主动点「固件升级」这一行：本来就连着 / 刚扫连上都要提醒一次电量
  // （对齐小程序 detail.js `enterOtaUpgrade` 走的 ensureConnectedForAction，
  //  2026-08-27 补齐 08-21 那轮遗留的入口）。位置在版本 loading 之前，不与蒙层抢屏。
  await showLowBatteryTipIfNeeded(context, state, device.id);
  if (!context.mounted) {
    return;
  }
  // ② loading 下二次拉取最新版本信息。
  AppLoadingDialog.show(context, AppL10n.of(context).otaCheckingVersion);
  final DeviceItem? updated;
  try {
    updated = await state.fetchDeviceFirmwareInfo(device.id);
  } finally {
    AppLoadingDialog.hide(context);
  }
  if (!context.mounted) {
    return;
  }
  final target = updated ?? device;
  // ③ 已是最新 / 无有效可升级包：提示后返回。
  //
  // 2026-08-12（两端同源）：判据与详情页右侧那行**同一处**（[evaluateFirmwareUpdate]）——
  // 只有读不到设备当前版本时才退回后端的 `isUpdate` 标记。两处各判各的会让用户卡在
  // 「详情说有版本可更新 → 点进来却说已是最新」，永远升不了级。
  final verdict = evaluateFirmwareUpdate(target);
  final canUpgradeNow = verdict == FirmwareUpdateVerdict.update ||
      (verdict == FirmwareUpdateVerdict.unknown && target.hasFirmwareUpdate);
  if (!canUpgradeNow) {
    await showAppNoticeDialog(
      context,
      title: AppL10n.of(context).otaFirmwareUpgrade,
      message: AppL10n.of(context).otaAlreadyLatestContent,
      icon: Icons.system_update_alt_rounded,
      confirmLabel: AppL10n.of(context).otaKnow,
    );
    return;
  }
  // ④ 有新版本：确认弹窗（稍后 / 立刻更新）。
  final confirmed = await showAppConfirmDialog(
    context,
    title: AppL10n.of(context).otaFirmwareUpgrade,
    message: AppL10n.of(context).otaNewVersionConfirm(target.newVersionNo),
    icon: Icons.system_update_alt_rounded,
    cancelLabel: AppL10n.of(context).otaLater,
    confirmLabel: AppL10n.of(context).otaUpdateNow,
  );
  if (confirmed != true || !context.mounted) {
    return;
  }
  // ⑤ 进 OTA 页并自动开始升级。
  await Navigator.of(context).push<void>(
    AppPageRoute(
      builder: (_) => OtaUpgradePage(
        state: state,
        deviceId: device.id,
        autoStart: true,
      ),
    ),
  );
}

/// 页面阶段（对齐 ota.js 的 state）。
enum _OtaStage { checking, latest, available, invalid, upgrading, success, failed }

class _OtaUpgradePageState extends State<OtaUpgradePage> {
  final BleController _ble = BleController.instance;

  _OtaStage _stage = _OtaStage.checking;
  bool _aborted = false;

  /// 打中止标记的时刻。收尾（[_resetDeviceAfterInterrupt]）据此判断「现在这条链路是不是
  /// 用户在我离开之后自己新建的」——是的话绝不能断（见该方法注释）。
  DateTime? _abortedAt;

  /// 一轮升级的**同步**并发闸（对齐小程序 `ota.js` 的 `_running`）。
  ///
  /// 不能再用 `_stage == upgrading` 当闸：自动开始那条路现在**先把画面落到进行中**
  /// （不闪按钮，见 [_load]），若仍以 stage 判断，[_runUpgrade] 头一行就会把自己挡回去。
  /// 反过来，自动扫连可达十几秒、期间 stage 也还没变，用户点一下就能并发出第二条 DFU 流
  /// （同一 session 交叉写 DATA 必败）。
  bool _running = false;

  /// 详情页「立刻更新」带过来的**自动开始那一跳**：入口 [startOtaFlow] 刚弹过低电量提醒，
  /// 本页第一轮不再弹第二遍（对齐小程序「一次点击只弹一次」）。
  /// 一次性消费：此后本页的手动「连接并升级 / 重新升级」照常各弹各的。
  late bool _lowBatteryTipDoneByEntry = widget.autoStart;

  // 设备名/状态文案初值留空，展示时在 build 里按当前语言兜底
  //（字段初始化处没有 context，硬编码中文会绕过 i18n）。
  String _deviceName = '';
  String _currentVersion = '--';
  String _latestVersion = '--';
  String _packageSizeText = '--';
  String _statusText = '';
  String _errorMessage = '';
  List<String> _releaseNotes = const [];

  bool _hasPackage = false; // 有有效可升级包（后端更新 + .bin 地址）
  String _downloadPath = '';
  int _sizeBytes = 0;

  double _progress = 0; // 0~1
  String _progressText = '';

  @override
  void initState() {
    super.initState();
    // 推迟到首帧后：_load 的同步前段会用 AppL10n.of(context)（InheritedWidget 依赖），
    // initState 里同步调用会抛「dependOnInheritedWidget in initState」。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _load();
      }
    });
  }

  @override
  void dispose() {
    // 页面离开：升级中则打中止标记，让传输尽快干净停下（切后台/离开会挂起蓝牙）。
    if (_stage == _OtaStage.upgrading) {
      _aborted = true;
      _abortedAt = DateTime.now();
    }
    super.dispose();
  }

  String? get _deviceId => widget.deviceId.isEmpty ? null : widget.deviceId;

  bool get _connected =>
      widget.state.isDeviceActuallyConnected(widget.deviceId);

  static String _formatSize(int bytes) {
    if (bytes >= 1024 * 1024) {
      return '${(bytes / 1024 / 1024).toStringAsFixed(1)}MB';
    }
    if (bytes >= 1024) {
      return '${(bytes / 1024).round()}KB';
    }
    return '${bytes}B';
  }

  Future<void> _load() async {
    final id = _deviceId;
    if (id == null) {
      final l10n = AppL10n.of(context);
      setState(() {
        _stage = _OtaStage.failed;
        _statusText = l10n.otaDeviceNotFound;
        _errorMessage = l10n.otaMissingDeviceId;
      });
      return;
    }

    setState(() {
      _stage = _OtaStage.checking;
      _statusText = AppL10n.of(context).otaChecking;
      _errorMessage = '';
      _progress = 0;
      _progressText = '';
    });

    // 拉设备详情合并固件字段（失败回退到本地设备项，仍可走干跑测试）。
    final updated = await widget.state.fetchDeviceFirmwareInfo(id);
    if (!mounted) return;
    final l10n = AppL10n.of(context);
    DeviceItem device;
    try {
      device = updated ?? widget.state.deviceById(id);
    } catch (_) {
      setState(() {
        _stage = _OtaStage.failed;
        _deviceName = l10n.otaDefaultDeviceName;
        _statusText = l10n.otaDeviceNotFound;
        _errorMessage = l10n.otaMissingDeviceInfo;
      });
      return;
    }

    // 当前固件版本：优先取已连接设备 BLE 实读版本，其次后端详情版本。
    final bleFw = _connected ? (_ble.info?.firmwareVersion ?? '') : '';
    final currentVersion = (bleFw.isNotEmpty ? bleFw : device.firmwareVersion).trim();
    final latestVersion = device.newVersionNo.trim();
    // 与详情页右侧那行**同一处判定**（见 [evaluateFirmwareUpdate]）：以设备实测版本为准，
    // 读不到才退回后端 `isUpdate` 标记，保住「不连蓝牙也能查版本」。
    final verdict = evaluateFirmwareUpdate(device, currentVersion: currentVersion);
    final hasPackage = verdict == FirmwareUpdateVerdict.update ||
        (verdict == FirmwareUpdateVerdict.unknown && device.hasFirmwareUpdate);
    final packageInvalid = verdict == FirmwareUpdateVerdict.invalid;

    String invalidReason = '';
    if (packageInvalid) {
      if (latestVersion.isEmpty || device.downloadPath.isEmpty) {
        invalidReason = l10n.otaInvalidMissingInfo;
      } else {
        invalidReason = l10n.otaInvalidBinUrl;
      }
    }

    // 从详情页「立刻更新」进来（autoStart）且包就绪时，**直接以进行中画面落地**：
    // 先渲染一帧「发现新版本 + 可点的主按钮」再切进行中，那一帧就是用户看到的按钮闪动。
    final autoStarting = widget.autoStart && hasPackage;
    setState(() {
      _deviceName = device.name.isEmpty ? l10n.otaDefaultDeviceName : device.name;
      _currentVersion = currentVersion.isEmpty ? '--' : currentVersion;
      _latestVersion = latestVersion.isEmpty ? '--' : latestVersion;
      _hasPackage = hasPackage;
      _downloadPath = device.downloadPath;
      _sizeBytes = device.firmwareSize;
      _packageSizeText = hasPackage
          ? (device.firmwareSize > 0
              ? _formatSize(device.firmwareSize)
              : l10n.otaConfirmAfterDownload)
          : '--';

      if (packageInvalid) {
        _stage = _OtaStage.invalid;
        _statusText = l10n.otaCannotUpgrade;
        _errorMessage = invalidReason;
        _releaseNotes = const [];
      } else if (hasPackage) {
        _stage = autoStarting ? _OtaStage.upgrading : _OtaStage.available;
        _statusText = autoStarting
            ? l10n.otaUpgrading
            : (_connected ? l10n.otaNewVersionFound : l10n.otaDeviceNotConnected);
        _errorMessage = (autoStarting || _connected) ? '' : l10n.otaConnectFirstHint;
        _progressText = autoStarting ? l10n.otaPreparingUpgrade : '';
        _releaseNotes = [l10n.otaNewVersionNote(latestVersion)];
      } else {
        _stage = _OtaStage.latest;
        _statusText = l10n.otaUpToDate;
        _errorMessage = '';
        _releaseNotes = const [];
      }
    });
    // 详情页确认「立刻更新」进入(auto=1)：包就绪即自动开始。
    // 不再要求已连接——入口那次连接可能在进页面的路上掉了，_runUpgrade 自己会先连。
    if (autoStarting && mounted) {
      // 补一层 catch：万一这一跳自己抛了错，画面已经落在「进行中」且没有按钮区，
      // 不接住的话用户会卡在一个动不了的屏上。
      unawaited(
        _runUpgrade().catchError((Object error, StackTrace stack) {
          debugPrint('[OTA] 自动开始升级抛错：$error');
          if (mounted) {
            setState(() {
              _stage = _OtaStage.available;
              _statusText = l10n.otaNewVersionFound;
              _errorMessage = l10n.otaGenericFailure;
            });
          }
        }),
      );
    }
  }

  OtaFirmwarePackage _buildPackage() {
    return OtaFirmwarePackage(
      packageUrl: _downloadPath,
      sizeBytes: _sizeBytes,
      version: _latestVersion,
    );
  }

  void _onProgress(OtaProgress p) {
    if (!mounted) return;
    setState(() {
      _progress = p.percent.clamp(0, 100) / 100.0;
      _progressText = p.message;
    });
  }

  Future<void> _runUpgrade() async {
    if (_running) return;
    _running = true;
    try {
      await _doRunUpgrade();
    } finally {
      _running = false;
    }
  }

  Future<void> _doRunUpgrade() async {
    final l10n = AppL10n.of(context);
    // ⚠️ 2026-08-11（对齐小程序）：未连接**不再是拦截理由，而是「先连上再升」**。
    // 此前这里直接 return，而按钮又画着可点，用户点下去毫无反应，只能自己退回详情页连一次。
    // 现在就地自动扫连（与详情页入口同一套 connectDevice：权限引导 + 扫描 + 连接），
    // 连不上才如实回到可重试状态。
    if (!_connected) {
      if (!await PermissionGate.ensureBleReady(context) || !mounted) return;
      setState(() {
        _stage = _OtaStage.upgrading;
        _statusText = l10n.otaConnecting;
        _errorMessage = '';
        _progress = 0;
        _progressText = l10n.otaConnecting;
      });
      final feedback = await widget.state.connectDevice(widget.deviceId);
      if (!mounted) return;
      if (!feedback.success) {
        setState(() {
          _stage = _OtaStage.available;
          _statusText = l10n.otaDeviceNotConnected;
          _errorMessage = feedback.message.isNotEmpty
              ? feedback.message
              : l10n.otaConnectFailedRetry;
        });
        return;
      }
      // 本页「连接并升级」自己扫连上的：提醒一次电量（2026-08-27 补齐遗留入口）。
      await showLowBatteryTipIfNeeded(context, widget.state, widget.deviceId);
      if (!mounted) return;
    } else if (!_lowBatteryTipDoneByEntry) {
      // 本来就连着：正常也要提醒一次；只有详情页「立刻更新」自动带过来的第一轮跳过
      // ——那一跳的入口刚弹过，这里再弹就成了一次点击弹两遍。
      await showLowBatteryTipIfNeeded(context, widget.state, widget.deviceId);
      if (!mounted) return;
    }
    _lowBatteryTipDoneByEntry = false;

    _aborted = false;
    // 连同上一轮的中止时刻一起清掉：留着的话，本轮的链路（建立时刻必然晚于那个旧时间戳）
    // 会被收尾方误判成「用户新建的连接」而跳过收尾。
    _abortedAt = null;
    setState(() {
      _stage = _OtaStage.upgrading;
      _statusText = l10n.otaUpgrading;
      _errorMessage = '';
      _progress = 0;
      _progressText = l10n.otaPreparingUpgrade;
    });

    // 逐帧联调日志（移植小程序 detail.js「OTA测试」）：设备→APP 的应答全部打印
    // （START ACK / DATA ACK / 0xF3 最终结果），APP→设备海量 DATA 包只打印首包 + 计数避免刷屏；
    // 并捕获最终结果帧(0xF3)，成功后按两种 RESULT 偏移解读打印，供真机抓帧定偏移。
    int txDataCount = 0;
    List<int> finalRxFrame = const [];
    void monitor(String dir, String hex) {
      final bytes = hex
          .split(' ')
          .where((s) => s.isNotEmpty)
          .map((s) => int.tryParse(s, radix: 16) ?? 0)
          .toList();
      if (bytes.isEmpty) return;
      if (dir == 'TX') {
        if (bytes[0] == OtaOp.data) {
          txDataCount += 1;
          if (txDataCount > 1) return;
        }
        debugPrint('[OTA] APP→设备 ${describeOtaFrame(dir, bytes)} | $hex');
        return;
      }
      final echo =
          bytes[0] == OtaOp.ack ? (bytes.length > 1 ? bytes[1] : 0) : bytes[0];
      if (echo == OtaOp.result) finalRxFrame = bytes;
      debugPrint('[OTA] 设备→APP ${describeOtaFrame(dir, bytes)} | $hex');
    }

    try {
      final target = widget.state.deviceById(widget.deviceId);
      final result = await _ble.upgradeFirmware(
        _buildPackage(),
        expectedSerial: target.serialNumber,
        expectedScreenCode: target.screenType.code,
        pace: 3,
        // 传错包/下载截断/刷错面板在发第一帧前就本地拦住：刷错固件不可逆，不能等设备回错误码。
        // 判不出面板时 otaPanelOfDevice 返回 0，预检自动跳过这一项，不误伤。
        expectPanel: otaPanelOfDevice(screenCode: target.screenType.code),
        expectVersion: target.newVersionNo,
        onProgress: _onProgress,
        shouldAbort: () => _aborted,
        // 逐帧 hex 日志仅 debug 输出：release 下 debugPrint 仍会写 logcat，
        // 会把 OTA 帧协议细节暴露给任何可读日志的调试者。
        onMonitor: kDebugMode ? monitor : null,
      );

      if (!mounted) return;

      // 固件已确认(2026-07-01)：收满且 CRC32 无误必回 0xF3、回完约 2s 后才复位重启。confirmed:false 已成
      // 兜底死路——真拿不到 0xF3 时 FrameOtaClient 会抛错走 catch，不再返回「软成功」。万一仍走到这里，
      // 说明确实没收到 0xF3 → 升级未确认，如实提示重试，绝不谎报「升级完成」。
      final unconfirmed = !result.confirmed;
      final doneText =
          unconfirmed ? l10n.otaUnconfirmedRetry : l10n.otaUpgradeComplete;
      // 升级结束触觉反馈：整轮要几十秒，用户多半没盯着屏幕。
      HapticFeedback.mediumImpact();
      setState(() {
        _stage = _OtaStage.success;
        _statusText = doneText;
        _progress = 1;
        _progressText =
            l10n.otaDoneDetail(doneText, result.size, result.totalPackets);
        if (!unconfirmed) {
          // 已确认升级成功：把本地当前版本置为新版本，隐藏可升级包。
          _currentVersion = _latestVersion;
          _hasPackage = false;
          // 设备在 END 校验通过约 2s 后就复位运行新固件，这条 GATT 链路立刻作废。
          // 如实告诉用户「正在重启、稍等几秒再连」——否则他立刻回去点投屏，
          // 会以为是升级把设备刷坏了。
          _errorMessage = '';
          _releaseNotes = [l10n.otaDeviceRebootingHint];
        }
      });
      if (!unconfirmed) {
        // 主动断链：设备正在重启，留着一条死链路只会让详情页/首页拿它发指令一直等到超时
        // （小程序那边是同一条口径）。best-effort，断不掉也不影响本页结论。
        unawaited(_ble.disconnect().catchError((Object error) {
          debugPrint('[OTA] 升级成功后断链失败（可忽略）：$error');
        }));
      }
      if (!unconfirmed && finalRxFrame.isNotEmpty) {
        // 真机联调：按两种 RESULT 偏移解读 0xF3，定下规格书 §5.2 未敲定的偏移。
        debugPrint('[OTA] ${decodeFinalResultFrame(finalRxFrame)}');
      }
      // NOTE: 小程序会 best-effort 调 reportDeviceFirmwareUpgrade 回报后台；
      // 该接口不在 BoltFox `/Client/...` 用户前端接口内，App 侧暂不回报（如后端提供再接）。
    } on OtaAbortedException {
      // 收尾必须在 mounted 检查**之前**：中断最常见的成因就是页面被 pop（dispose 打的
      // _aborted），此刻 mounted 已经是 false，放在后面等于永远不执行。
      await _resetDeviceAfterInterrupt();
      if (!mounted) return;
      setState(() {
        _stage = _OtaStage.failed;
        _statusText = l10n.otaUpgradeFailed;
        _errorMessage = l10n.otaInterrupted;
      });
    } catch (error) {
      final aborted = _aborted;
      if (aborted) {
        await _resetDeviceAfterInterrupt();
      }
      if (!mounted) return;
      // 原始异常进日志；用户只看 OtaException 的协议文案或通用「升级失败」，
      // 不把 PlatformException 之类的技术堆栈文本原样糊到界面上。
      debugPrint('[OTA] 升级失败: $error');
      setState(() {
        _stage = _OtaStage.failed;
        _statusText = l10n.otaUpgradeFailed;
        _errorMessage = aborted
            ? l10n.otaInterrupted
            : error is OtaException
            ? error.message
            : l10n.otaGenericFailure;
      });
    }
  }

  /// 中断（切后台 / 退出升级页 / 用户确认离开）之后的设备侧收尾。
  ///
  /// 同步小程序 `docs/changes/2026-08-12-OTA失败中断不再拖垮设备连接.md` ④：
  /// **中断要走和失败同一套收尾**。此前这里什么都不做，代价有两层：
  /// ① 设备的 DFU 状态机停在半截，同一条 GATT 连接上再 START 必被回 `0x05`——虽然
  ///    [BleController.upgradeFirmware] 的 wedged-retry 能自愈（断链 → 等 3s → 重连 → 重来），
  ///    但那是下一次升级白白多花的一整轮，本来这一刻断一次链就免了；
  /// ② 连接还留着，而设备正忙着收拾自己：详情页/首页拿这条链路读 0x01、读电量会一直等到超时，
  ///    界面上却写着「已连接」——现场那句「升级中断后读不到设备信息」就是它。
  ///
  Future<void> _resetDeviceAfterInterrupt() async {
    // ⚠️ 忙判定（2026-08-13，同步小程序「复位第二刀」那条时序漏洞）：这一刀可能晚到
    // 几秒~十几秒才落下 —— `shouldAbort` 不在 await 中途生效，传输循环要走到下一个窗口
    // 间隙、END 最长等 15s 才发现中断。此刻用户往往**已经回详情页点了连接**：
    // 照断不误就会把他刚建好的链路一起拆掉；若正砍在「连上了但还没登记」之间，
    // 还会留下一条账本外的连接占着设备（单连接设备被占时不广播 → 又回到「重进 App 才好」）。
    final abortedAt = _abortedAt;
    final linkAt = _ble.linkEstablishedAt;
    if (_ble.connecting ||
        (abortedAt != null && linkAt != null && linkAt.isAfter(abortedAt))) {
      debugPrint('[OTA] 跳过中断收尾断链：当前链路是中断之后新建/正在建的，不是本轮 OTA 那条');
      return;
    }
    debugPrint('[OTA] 升级中断：断开链路让设备的 DFU 状态机复位');
    try {
      await _ble.disconnect();
    } catch (error) {
      // best-effort：断不掉也只是回到改动前的状态，不该再往上抛
      debugPrint('[OTA] 中断收尾断链失败（可忽略）：$error');
    }
  }

  // ── 视图 ─────────────────────────────────────────────────
  // 「点得动」只取决于「有升级包且不在升级中」——未连接不再是拦截理由，点下去会先自动扫连
  // （见 _runUpgrade）。此前这里含 _connected，按钮画着却点不动，就是用户反馈的「OTA 没反应」。
  bool get _canUpgrade => _stage != _OtaStage.upgrading && _hasPackage;

  String get _actionText {
    final l10n = AppL10n.of(context);
    switch (_stage) {
      case _OtaStage.upgrading:
        return l10n.otaUpgrading;
      case _OtaStage.available:
        // 未连接时说清楚「点了会先连设备」，别让用户以为按钮坏了
        return _connected
            ? l10n.otaUpgradeNowAction
            : l10n.otaConnectAndUpgrade;
      case _OtaStage.invalid:
        return l10n.otaCannotUpgrade;
      case _OtaStage.failed:
        return l10n.otaRecheck;
      case _OtaStage.success:
        return l10n.otaDone;
      case _OtaStage.latest:
        return l10n.otaUpToDate;
      case _OtaStage.checking:
        return l10n.otaChecking;
    }
  }

  void _onAction() {
    if (_stage == _OtaStage.failed) {
      _load();
      return;
    }
    if (_canUpgrade) {
      _runUpgrade();
    }
  }

  Color get _statusColor {
    switch (_stage) {
      case _OtaStage.available:
        return const Color(0xFFEB5F1B);
      case _OtaStage.invalid:
      case _OtaStage.failed:
        return const Color(0xFFFF3045);
      case _OtaStage.upgrading:
        return const Color(0xFF3D5A80);
      default:
        return const Color(0xFF588157);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    if (_stage == _OtaStage.checking) {
      return FigmaScreen(
        title: l10n.otaTitle,
        // 与主画面同口径：本页不留「随手点一下就走」的顶部入口（见 _buildScreen）
        showBack: false,
        body: Padding(
          padding: const EdgeInsets.only(top: 120),
          // 与其他页一致的转圈 loading（原来只有一行静态文字，没有加载指示）。
          child: PageLoading(label: l10n.otaCheckingFirmware),
        ),
      );
    }

    // 升级中拦截返回：之前无任何拦截，误触返回/侧滑会静默中止固件传输
    // （dispose 打 _aborted），且中断提示只在页内可见，用户毫无感知。
    return PopScope(
      canPop: _stage != _OtaStage.upgrading,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final leave = await _confirmExitWhileUpgrading();
        if (leave && mounted) {
          Navigator.of(context).pop();
        }
      },
      child: _buildScreen(context, l10n),
    );
  }

  /// 升级中确认退出：返回 true 表示用户坚持退出（将中断固件传输）。
  Future<bool> _confirmExitWhileUpgrading() async {
    final l10n = AppL10n.of(context);
    final leave = await showAppConfirmDialog(
      context,
      title: l10n.otaExitConfirmTitle,
      message: l10n.otaExitConfirmContent,
      icon: Icons.exit_to_app_rounded,
      tone: AppDialogTone.danger,
      cancelLabel: l10n.otaExitConfirmStay,
      confirmLabel: l10n.otaExitConfirmLeave,
    );
    return leave ?? false;
  }

  Widget _buildScreen(BuildContext context, AppL10n l10n) {
    return FigmaScreen(
      title: l10n.otaTitle,
      // 2026-08-13（两端同改）：**去掉顶部返回箭头**。升级不可逆、中断有代价，
      // 页面里不留「随手点一下就走」的入口。
      // ⚠️ 去掉的只是箭头：底部按钮区在非进行中时会给一颗「返回」（见下），
      // 否则升级成功后用户在本页找不到任何出口，就从「防误触」变成「把人困住」。
      // 进行中确实一个返回入口都没有（这正是需求要的），系统手势那条路仍有
      // PopScope 的「退出将中断本次升级」二次确认拦着。
      showBack: false,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 12),
          _versionCard(),
          const SizedBox(height: 12),
          _upgradeCard(),
          const SizedBox(height: 12),
          _notesCard(),
          if (_errorMessage.isNotEmpty) ...[
            const SizedBox(height: 12),
            _errorCard(),
          ],
          const SizedBox(height: 16),
          Text(
            l10n.otaKeepPoweredHint,
            style: const TextStyle(
                color: Color(0xFF808690), fontSize: 12, height: 1.5),
          ),
          const SizedBox(height: 16),
          // 内容与底部固定按钮之间的留白：FigmaScreen 给 bottom 的上内边距只有 8，
          // 卡片多/报错卡片出现时滚到底就会顶在按钮上（对齐小程序 2026-08-03 把
          // .ota-body / .result-body 下内边距补到 40rpx=20px：8 + 12 = 20）。
          const SizedBox(height: 12),
        ],
      ),
      bottom: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FigmaPrimaryButton(
            label: _actionText,
            onPressed:
                (_canUpgrade || _stage == _OtaStage.failed) ? _onAction : null,
          ),
          // 顶部箭头去掉之后唯一的可见出口（对齐小程序底部那颗「返回」）：
          // 进行中不画——那一屏本来就不该有返回入口。
          if (_stage != _OtaStage.upgrading) ...[
            const SizedBox(height: 8),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(context).maybePop(),
              child: Container(
                height: 40,
                alignment: Alignment.center,
                child: Text(
                  l10n.aiBack,
                  style: const TextStyle(
                    color: Color(0xFF6F6B66),
                    fontSize: 15,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _versionCard() {
    final l10n = AppL10n.of(context);
    return FigmaGlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFEB5F1B),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Text('OTA',
                style: TextStyle(
                    color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_deviceName,
                    style: const TextStyle(
                        color: Color(0xFF2A2D32), fontSize: 15, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(l10n.otaCurrentVersion(_currentVersion),
                    style: const TextStyle(color: Color(0xFF808690), fontSize: 12)),
              ],
            ),
          ),
          Text(_statusText,
              style: TextStyle(color: _statusColor, fontSize: 13, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _upgradeCard() {
    final l10n = AppL10n.of(context);
    return FigmaGlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.otaFirmwareVersion(_latestVersion),
              style: const TextStyle(
                  color: Color(0xFF2A2D32), fontSize: 14, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(l10n.otaPackageSize(_packageSizeText),
              style: const TextStyle(color: Color(0xFF808690), fontSize: 12)),
          const SizedBox(height: 14),
          FigmaProgressBar(
            progress: _progress,
            label:
                '${_progressText.isNotEmpty ? _progressText : (_stage == _OtaStage.available ? l10n.otaReadyToUpgrade : l10n.otaNoUpgradeNeeded)}  ·  ${(_progress * 100).round()}%',
          ),
          // 两条升级规则**只在进行中这一屏**出现（2026-08-13 两端同改）：其余画面挂着它
          // 只会跟结论文案抢注意力（「已是最新版本」下面写「意外中断可能导致设备无法使用」
          // 是没有意义的）。整块左对齐——居中会让长句断点参差、序号对不齐。
          if (_stage == _OtaStage.upgrading) ...[
            const SizedBox(height: 14),
            Text(
              l10n.otaRuleWaitPatiently,
              textAlign: TextAlign.left,
              style: const TextStyle(
                color: Color(0xFF808690),
                fontSize: 12,
                height: 1.6,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              l10n.otaRuleRecoverHint,
              textAlign: TextAlign.left,
              style: const TextStyle(
                color: Color(0xFF808690),
                fontSize: 12,
                height: 1.6,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _notesCard() {
    final l10n = AppL10n.of(context);
    return FigmaGlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.otaUpgradeContent,
              style: const TextStyle(
                  color: Color(0xFF2A2D32), fontSize: 14, fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          if (_releaseNotes.isEmpty)
            Text(l10n.otaNoReleaseNotes,
                style: const TextStyle(color: Color(0xFF808690), fontSize: 12))
          else
            ..._releaseNotes.map(
              (note) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      margin: const EdgeInsets.only(top: 6, right: 8),
                      width: 5,
                      height: 5,
                      decoration: const BoxDecoration(
                          color: Color(0xFFEB5F1B), shape: BoxShape.circle),
                    ),
                    Expanded(
                      child: Text(note,
                          style: const TextStyle(
                              color: Color(0xFF5A616B), fontSize: 12, height: 1.5)),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _errorCard() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF0F0),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFFD4D4)),
      ),
      child: Text(_errorMessage,
          style: const TextStyle(color: Color(0xFFFF3045), fontSize: 12, height: 1.5)),
    );
  }
}
