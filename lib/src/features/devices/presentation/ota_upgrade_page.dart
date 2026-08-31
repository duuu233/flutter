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

/// 详情页「固件升级」入口流程 —— **逐步对齐小程序 `detail.js` 的 `goOtaUpgrade`
/// + `enterOtaUpgrade`**（2026-08-31 重排）：
/// ① loading「检测版本中」下拉最新版本（`getUserProductDetail`）；
/// ② 已是最新 → 弹「固件升级 / 当前固件已是最新版本 / 知道了」后返回；
/// ③ **包无效**（缺版本号/下载地址/不是 .bin）→ 弹**具体原因**后返回；
/// ④ 有新版 → 弹「检测到新版本：X，是否升级（稍后 / 立刻更新）」；
/// ⑤ 确认「立刻更新」→ 提醒电量 → 未连接则自动扫连 → 进 OTA 页 `autoStart` 自动开始。
///
/// ⚠️ **顺序不能再倒过来**（这是本次与小程序对齐的关键一处）：
/// 原来 App 是「先连设备 → 再查版本」，于是用户点一下「固件升级」，先被拉着等一轮
/// 十几秒的蓝牙扫连，结果很可能只是为了看一句「当前固件已是最新版本」——
/// 版本查询根本不需要连接（走的是后端接口）。小程序一直是「先查、有新版且用户确认了才连」。
///
/// ⚠️ ③ 这一支 App 侧此前**没有**：包无效被并进了「已是最新」，用户看到的是
/// 「当前固件已是最新版本」——明明有新版本却说已最新，等于把后端配错的锅扣在用户身上。
Future<void> startOtaFlow(
  BuildContext context,
  PhotoFrameState state,
  String deviceId,
) async {
  final device = state.deviceById(deviceId);

  // ① loading 下拉取最新版本信息。**不需要蓝牙连接**，所以放在连接之前。
  AppLoadingDialog.show(context, AppL10n.of(context).otaCheckingVersion);
  final DeviceItem? updated;
  try {
    updated = await state.fetchDeviceFirmwareInfo(device.id);
  } finally {
    // 统一 hide 收口（精确移除 + 无 mounted 门控），替换掉盲 pop（历史闪退根源）：
    // 本流程可叠在详情页其它 loading 之上，show 被静默忽略时盲 pop 会弹掉业务页。
    AppLoadingDialog.hide(context);
  }
  if (!context.mounted) {
    return;
  }
  final target = updated ?? device;

  // 判据与详情页右侧那行**同一处**（[evaluateFirmwareUpdate]）——只有读不到设备当前版本时
  // 才退回后端的 `isUpdate` 标记。两处各判各的会让用户卡在「详情说有版本可更新 →
  // 点进来却说已是最新」，永远升不了级。
  final verdict = evaluateFirmwareUpdate(target);
  final l10n = AppL10n.of(context);

  // ③ 包无效：如实说原因，别冒充「已是最新」（口径与 OTA 页 `_load` 的 invalidReason 同源）。
  if (verdict == FirmwareUpdateVerdict.invalid) {
    await showAppNoticeDialog(
      context,
      title: l10n.otaFirmwareUpgrade,
      message: target.newVersionNo.trim().isEmpty ||
              target.downloadPath.trim().isEmpty
          ? l10n.otaInvalidMissingInfo
          : l10n.otaInvalidBinUrl,
      icon: Icons.system_update_alt_rounded,
      confirmLabel: l10n.otaKnow,
    );
    return;
  }

  // ② 已是最新（含「读不到当前版本、后端也没说有更新」）：提示后返回。
  final canUpgradeNow = verdict == FirmwareUpdateVerdict.update ||
      (verdict == FirmwareUpdateVerdict.unknown && target.hasFirmwareUpdate);
  if (!canUpgradeNow) {
    await showAppNoticeDialog(
      context,
      title: l10n.otaFirmwareUpgrade,
      message: l10n.otaAlreadyLatestContent,
      icon: Icons.system_update_alt_rounded,
      confirmLabel: l10n.otaKnow,
    );
    return;
  }

  // ④ 有新版本：确认弹窗（稍后 / 立刻更新）。
  final confirmed = await showAppConfirmDialog(
    context,
    title: l10n.otaFirmwareUpgrade,
    message: l10n.otaNewVersionConfirm(target.newVersionNo),
    icon: Icons.system_update_alt_rounded,
    cancelLabel: l10n.otaLater,
    confirmLabel: l10n.otaUpdateNow,
  );
  if (confirmed != true || !context.mounted) {
    return;
  }

  // ⑤「立刻更新」之后才碰设备（对齐小程序 enterOtaUpgrade）。
  // 先提醒电量，再连接：授权框/提醒要单独出现，不与蒙层同屏（见 PermissionGate）。
  await showLowBatteryTipIfNeeded(context, state, device.id);
  if (!context.mounted) {
    return;
  }
  if (!state.isDeviceActuallyConnected(device.id)) {
    if (!await PermissionGate.ensureBleReady(context) || !context.mounted) {
      return;
    }
    AppLoadingDialog.show(context, l10n.otaConnecting);
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
  if (!context.mounted) {
    return;
  }
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

  // 文案初值留空，展示时在 build 里按当前语言兜底
  //（字段初始化处没有 context，硬编码中文会绕过 i18n）。

  /// 目标版本号。既进 [_buildPackage] 做刷机前预检，也是「发现新版本」那屏的副文案。
  String _latestVersion = '--';

  /// 大标题 / 副文案 —— 与小程序 `ota.js` 的 `statusTitle` / `statusDesc` **一一对应**。
  ///
  /// 刻意做成「每次状态切换显式赋值」而不是从 [_stage] 推导：ota.js 就是这么写的，
  /// 逐条对着那边核最省事；推导版一旦漏一个分支，页面会停在上一屏的文案上，很难发现。
  String _statusTitle = '';
  String _statusDesc = '';

  /// 当前协议阶段（[OtaProgress.phase]），决定进行中那屏的大标题三段切换
  /// （下载中 / 传输中 / 升级中，见 [_stageTitle]）。
  String _phase = '';

  /// 这次失败是**升级过程中**出的（→ 主按钮「重新升级」），还是**版本检查阶段**出的
  /// （→「重新检查」）。对齐 ota.js：两种失败给的补救动作不是一回事。
  bool _failedDuringUpgrade = false;

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

  Future<void> _load() async {
    final id = _deviceId;
    if (id == null) {
      final l10n = AppL10n.of(context);
      setState(() {
        _stage = _OtaStage.failed;
        _failedDuringUpgrade = false; // 检查阶段失败 → 主按钮是「重新检查」
        _statusTitle = l10n.otaDeviceNotFound;
        _statusDesc = l10n.otaMissingDeviceId;
      });
      return;
    }

    setState(() {
      _stage = _OtaStage.checking;
      _statusTitle = AppL10n.of(context).otaCheckingVersion;
      _statusDesc = AppL10n.of(context).otaCheckingFirmware;
      _phase = '';
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
        _failedDuringUpgrade = false;
        _statusTitle = l10n.otaDeviceNotFound;
        _statusDesc = l10n.otaMissingDeviceInfo;
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
      _latestVersion = latestVersion.isEmpty ? '--' : latestVersion;
      _hasPackage = hasPackage;
      _downloadPath = device.downloadPath;
      _sizeBytes = device.firmwareSize;
      _failedDuringUpgrade = false;

      if (packageInvalid) {
        // ota.js：screenStatus 'fail' / '无法升级' / errorMessage（无则「固件包无效…」）
        _stage = _OtaStage.invalid;
        _statusTitle = l10n.otaCannotUpgrade;
        _statusDesc =
            invalidReason.isEmpty ? l10n.otaInvalidPackageDesc : invalidReason;
      } else if (hasPackage) {
        // ota.js：screenStatus 'ready' / '发现新版本' / 副文案就是版本号本身，
        // 未连接时补一句「（将先连接电子纸设备）」——按钮那时是「连接并升级」。
        _stage = autoStarting ? _OtaStage.upgrading : _OtaStage.available;
        if (autoStarting) {
          _phase = '';
          _statusTitle = l10n.otaPreparingUpgrade;
          _statusDesc = l10n.otaPreparingDesc;
          _progressText = '';
        } else {
          _statusTitle = l10n.otaNewVersionFound;
          _statusDesc = _connected
              ? _latestVersion
              : l10n.otaReadyWillConnect(_latestVersion);
          _progressText = '';
        }
      } else {
        // ota.js：screenStatus 'success' / '已是最新版本' / '当前固件已是最新，无需升级'
        _stage = _OtaStage.latest;
        _statusTitle = l10n.otaLatestTitle;
        _statusDesc = l10n.otaLatestDesc;
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
              _stage = _OtaStage.failed;
              _failedDuringUpgrade = true;
              _statusTitle = l10n.otaUpgradeFailed;
              _statusDesc = l10n.otaGenericFailure;
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
    // ⚠️ **不要把 `p.message` 渲染到界面上**（2026-08-31 修「文案不跟语种走」）：
    // 那是协议层写死的中文诊断文案（`ota_ble.dart` 里 11 处，形如
    // 「传输中：1234/56789 字节（12/345 包）」「握手中（MTU 247）」），
    // 英/日/繁用户看到的就是一行中文。字节数/包序这类细节只在排查时有用 ——
    // 留在日志里，界面按阶段取本地化文案。
    debugPrint('[OTA] ${p.phase} ${p.percent}% ${p.message}');
    final l10n = AppL10n.of(context);
    setState(() {
      _phase = p.phase;
      _progress = p.percent.clamp(0, 100) / 100.0;
      _progressText = _progressNote(l10n);
      _statusTitle = _stageTitle(l10n);
    });
  }

  /// 协议阶段 → 进度条下方那一行说明。与 [_stageTitle] 同一套 phase 口径，
  /// 只是标题分三段（下载/传输/升级）、这一行更细一档，好让用户知道卡在哪一步。
  String _progressNote(AppL10n l10n) {
    switch (_phase) {
      case 'preparing':
      case 'prepared':
        return l10n.otaNotePreparing;
      case 'connecting':
        return l10n.otaNoteConnecting;
      case 'starting':
        return l10n.otaNoteHandshaking;
      case 'header':
        return l10n.otaNoteHeader;
      case 'transferring':
        return l10n.otaNoteTransferring;
      case 'retry':
        return l10n.otaNoteRetrying;
      case 'verifying':
        return l10n.otaNoteVerifying;
      case 'done':
        return l10n.otaNoteDone;
      default:
        // 还没收到任何进度回调：不画这一行（大标题和百分比已经说明状态了）。
        return '';
    }
  }

  /// 协议层抛出的失败原因（[OtaException.message]）**是中文诊断文案** ——
  /// 散落在 `ota_ble.dart` 二十来处 throw 里，还带着 MTU / 包序 / 特征 UUID
  /// 这类只有排查时才有用的细节。
  ///
  /// 全量翻译不划算、也不该做（那些话本来就是给我们自己看的），所以按语种分流：
  /// **中文用户原样看到细节**（报障时能直接念给我们），其余语种退回一句
  /// [AppL10n.otaGenericFailure]，细节仍旧进 debugPrint 一份都不少。
  String _failureDetail(AppL10n l10n, String raw) {
    if (raw.isEmpty) {
      return l10n.otaGenericFailure;
    }
    final chinese =
        l10n.language == AppLanguage.zh || l10n.language == AppLanguage.zhHant;
    return chinese ? raw : l10n.otaGenericFailure;
  }

  /// 协议阶段 → 进行中那屏的大标题，与小程序 `ota.js` 的 `STAGE_TITLE` **逐值一致**：
  /// 读包/下载 + 连接握手 → 固件下载中；128 字节头握手 + 窗口化传数据 → 固件传输中；
  /// 发结束包 + 设备整包校验 → 固件升级中。
  ///
  /// ⚠️ 用户就是靠这三段判断「卡在哪一步」：下载中卡住多半是网络，传输中卡住多半是蓝牙，
  /// 合并成一句「升级中」等于把排障线索抹掉。
  String _stageTitle(AppL10n l10n) {
    switch (_phase) {
      case 'preparing':
      case 'prepared':
      case 'connecting':
      case 'starting':
        return l10n.otaStageDownloading;
      case 'header':
      case 'transferring':
      case 'retry':
        return l10n.otaStageTransferring;
      case 'verifying':
      case 'done':
        return l10n.otaStageUpgrading;
      default:
        // 还没收到任何进度回调（刚点下去那一瞬）：沿用当前标题，别闪一下空标题。
        return _statusTitle.isEmpty ? l10n.otaStageDownloading : _statusTitle;
    }
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
        // ota.js：screenStatus 'progress' / '连接电子纸设备中' / '正在连接…请靠近手机…'
        _stage = _OtaStage.upgrading;
        _phase = '';
        _statusTitle = l10n.otaConnectingTitle;
        _statusDesc = l10n.otaConnectingDesc;
        _progress = 0;
        _progressText = '';
      });
      final feedback = await widget.state.connectDevice(widget.deviceId);
      if (!mounted) return;
      if (!feedback.success) {
        setState(() {
          // ota.js：screenStatus 'fail' / '无法升级' / '未能连接电子纸设备…请重试。'
          // 仍留在 available：主按钮据此给「连接并升级」，再点一次会重走扫连。
          _stage = _OtaStage.available;
          _statusTitle = l10n.otaCannotUpgrade;
          _statusDesc = feedback.message.isNotEmpty
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
      // ota.js doRunUpgrade：screenStatus 'progress' / '固件下载中' /
      // '升级中请保持电子纸设备供电、手机屏幕常亮，勿切后台'
      _stage = _OtaStage.upgrading;
      _phase = '';
      _statusTitle = l10n.otaStageDownloading;
      _statusDesc = l10n.otaUpgradingDesc;
      _progress = 0;
      _progressText = '';
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
        _progress = 1;
        _progressText =
            l10n.otaDoneDetail(doneText, result.size, result.totalPackets);
        if (unconfirmed) {
          // ⚠️ 数据发完但没收到设备 0xF3：**按失败画**（ota.js 同口径 —— screenStatus 'fail'、
          // 主按钮「重新升级」、保留升级包）。谎报成功既误导用户「已经升好了」，
          // 又把唯一的重试入口拿掉。
          _stage = _OtaStage.failed;
          _failedDuringUpgrade = true;
          _statusTitle = l10n.otaUpgradeFailed;
          _statusDesc = l10n.otaUnconfirmedDesc;
        } else {
          // 已确认升级成功：隐藏可升级包。
          _stage = _OtaStage.success;
          _hasPackage = false;
          // 设备在 END 校验通过约 2s 后就复位运行新固件，这条 GATT 链路立刻作废。
          // 如实告诉用户「正在重启、稍等几秒再连」——否则他立刻回去点投屏，
          // 会以为是升级把设备刷坏了。
          _statusTitle = l10n.otaSuccessTitle;
          _statusDesc = l10n.otaSuccessDesc;
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
        _failedDuringUpgrade = true;
        _statusTitle = _failTitle(l10n);
        _statusDesc = l10n.otaInterrupted;
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
        _failedDuringUpgrade = true;
        _statusTitle = _failTitle(l10n);
        _statusDesc = aborted
            ? l10n.otaInterrupted
            : error is OtaException
            ? _failureDetail(l10n, error.message)
            : l10n.otaGenericFailure;
      });
    }
  }

  /// 失败屏的大标题（对齐 ota.js：`inDownload ? '固件下载失败' : '升级失败'`）。
  ///
  /// 判据是**最后到达过的协议阶段**：还停在读包/下载（preparing/prepared）或压根没进过
  /// 任何阶段，就是包没拿下来 —— 那是网络问题，不该让用户去查设备。
  String _failTitle(AppL10n l10n) {
    final inDownload =
        _phase.isEmpty || _phase == 'preparing' || _phase == 'prepared';
    return inDownload ? l10n.otaDownloadFailedTitle : l10n.otaUpgradeFailed;
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
  //
  // ⚠️ 2026-08-31 整块重做：**逐条移植小程序 `subpackages/device/ota`**（ota.wxml + ota.wxss）。
  // 小程序 2026-08-13 已把这一页简化成「插画 + 大标题 + 副文案 +（进行中才有的）大百分比 +
  // 进度条 + 两条规则」的居中版式（参照投屏结果页），而 App 侧一直停在三张玻璃卡片
  // （版本卡 / 升级卡 / 说明卡）的旧版式 —— 两边不是同一个页面，这就是「说了好几次没改」那条。
  //
  // 几何一律按小程序 rpx ÷ 2 换算，逐值标注在下面各处。

  /// 五种画面（对齐 ota.js 的 `screenStatus`）。插画只有三张，checking/ready 共用进行中那张。
  _OtaScreen get _screen {
    switch (_stage) {
      case _OtaStage.checking:
        return _OtaScreen.checking;
      case _OtaStage.available:
        return _OtaScreen.ready;
      case _OtaStage.upgrading:
        return _OtaScreen.progress;
      case _OtaStage.latest:
      case _OtaStage.success:
        return _OtaScreen.success;
      case _OtaStage.invalid:
      case _OtaStage.failed:
        return _OtaScreen.fail;
    }
  }

  /// 画面 → 插画。与小程序 `OTA_ART` 同一组图（`upload-icon01/02/03`，本仓也有这三张）。
  String get _artImage {
    switch (_screen) {
      case _OtaScreen.success:
        return 'assets/images/upload-icon03.png';
      case _OtaScreen.fail:
        return 'assets/images/upload-icon02.png';
      case _OtaScreen.checking:
      case _OtaScreen.ready:
      case _OtaScreen.progress:
        return 'assets/images/upload-icon01.png';
    }
  }

  // 「点得动」只取决于「有升级包且不在升级中」——未连接不再是拦截理由，点下去会先自动扫连
  // （见 _runUpgrade）。此前这里含 _connected，按钮画着却点不动，就是用户反馈的「OTA 没反应」。
  bool get _canUpgrade => _stage != _OtaStage.upgrading && _hasPackage;

  /// 是否画底部主按钮（对齐 ota.js 的 `showPrimary`）。
  ///
  /// ⚠️ 「已是最新 / 无法升级」两屏**不画**主按钮：那上面写「已是最新」的按钮点了什么都不会
  /// 发生，是纯粹的噪音；用户在那两屏要的是「返回」，底下那颗一直都在。
  bool get _showPrimary {
    switch (_stage) {
      case _OtaStage.available:
        return true;
      case _OtaStage.failed:
        return true;
      case _OtaStage.checking:
      case _OtaStage.upgrading:
      case _OtaStage.latest:
      case _OtaStage.invalid:
      case _OtaStage.success:
        return false;
    }
  }

  String get _actionText {
    final l10n = AppL10n.of(context);
    switch (_stage) {
      case _OtaStage.available:
        // 未连接时说清楚「点了会先连设备」，别让用户以为按钮坏了
        return _connected
            ? l10n.otaUpgradeNowAction
            : l10n.otaConnectAndUpgrade;
      case _OtaStage.failed:
        // 升级过程中失败 → 「重新升级」；版本检查阶段失败 → 「重新检查」。
        // 两种失败的补救动作不是一回事（对齐 ota.js）。
        return _failedDuringUpgrade ? l10n.otaRetryUpgrade : l10n.otaRecheck;
      case _OtaStage.upgrading:
        return l10n.otaUpgrading;
      case _OtaStage.invalid:
        return l10n.otaCannotUpgrade;
      case _OtaStage.success:
        return l10n.otaDone;
      case _OtaStage.latest:
        return l10n.otaUpToDate;
      case _OtaStage.checking:
        return l10n.otaChecking;
    }
  }

  void _onAction() {
    if (_stage == _OtaStage.failed && !_failedDuringUpgrade) {
      // 版本检查失败：重新检查一遍
      _load();
      return;
    }
    if (_canUpgrade) {
      _runUpgrade();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
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
    final progressing = _screen == _OtaScreen.progress;
    final percent = (_progress * 100).round().clamp(0, 100);

    return FigmaScreen(
      title: l10n.otaFirmwareUpgrade,
      // 2026-08-13（两端同改）：**去掉顶部返回箭头**。升级不可逆、中断有代价，
      // 页面里不留「随手点一下就走」的入口。
      // ⚠️ 去掉的只是箭头：底部在非进行中时给一颗「返回」（见下），
      // 否则升级成功后用户在本页找不到任何出口，就从「防误触」变成「把人困住」。
      // 进行中确实一个返回入口都没有（这正是需求要的），系统手势那条路仍有
      // PopScope 的「退出将中断本次升级」二次确认拦着。
      showBack: false,
      // 小程序 `.ota-body` 的 `padding: 48rpx 56rpx 40rpx` → 左右 28，上下在 body 里给。
      bodyPadding: const EdgeInsets.symmetric(horizontal: 28),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // .ota-art：260×220rpx = 130×110，margin 40rpx auto 48rpx = 上 20 下 24
          //（.ota-body 自己还有 48rpx=24 的上内边距，合起来是 24 + 20）。
          const SizedBox(height: 24 + 20),
          Center(
            child: Image.asset(
              _artImage,
              width: 130,
              height: 110,
              fit: BoxFit.contain,
              // 三张图任一缺失都不该把整页炸掉：留出同样的占位，文案照常读得到。
              errorBuilder: (context, error, stackTrace) =>
                  const SizedBox(width: 130, height: 110),
            ),
          ),
          const SizedBox(height: 24),
          // .ota-title：40rpx=20 / w700 / #2a2d32 / line-height 1
          Text(
            _statusTitle,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF2A2D32),
              fontSize: 20,
              fontWeight: FontWeight.w700,
              height: 1,
            ),
          ),
          // .ota-desc：margin-top 22rpx=11 / 26rpx=13 / #828a95 / line-height 1.5
          if (_statusDesc.isNotEmpty) ...[
            const SizedBox(height: 11),
            Text(
              _statusDesc,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF828A95),
                fontSize: 13,
                height: 1.5,
              ),
            ),
          ],
          if (progressing) ...[
            // .progress-percent：margin-top 56rpx=28 / 72rpx=36 / w700 / #ff6421
            const SizedBox(height: 28),
            Text.rich(
              TextSpan(
                text: '$percent',
                style: const TextStyle(
                  color: Color(0xFFFF6421),
                  fontSize: 36,
                  fontWeight: FontWeight.w700,
                  height: 1,
                ),
                children: const [
                  // .progress-percent__sign：36rpx=18 / w600 / margin-left 4rpx=2
                  TextSpan(
                    text: ' %',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      height: 1,
                    ),
                  ),
                ],
              ),
              textAlign: TextAlign.center,
            ),
            // .progress-wrap：margin-top 28rpx=14；.progress-bar：18rpx=9 高、#e6ebf2 底
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: SizedBox(
                height: 9,
                child: Stack(
                  children: [
                    const ColoredBox(
                      color: Color(0xFFE6EBF2),
                      child: SizedBox.expand(),
                    ),
                    // .progress-fill：linear-gradient(90deg, #ff8a45, #ff6421)
                    FractionallySizedBox(
                      widthFactor: _progress.clamp(0.0, 1.0),
                      child: const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Color(0xFFFF8A45), Color(0xFFFF6421)],
                          ),
                        ),
                        child: SizedBox.expand(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // .progress-note：margin-top 24rpx=12 / 24rpx=12 / #828a95
            if (_progressText.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                _progressText,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFF828A95),
                  fontSize: 12,
                  height: 1.5,
                ),
              ),
            ],
            // .progress-rules（2026-08-13 需求 2）：**只在进行中这一屏**出现 ——
            // 它要说的是「此刻别走开」和「万一失败怎么自救」，成功/失败画面上再挂着
            // 只会跟结论文案抢注意力。
            // ⚠️ 整块**左对齐**：这一屏其余内容都是居中的，两条长句居中后每行断点不齐、
            // 像散文；这是要一条条读进去的告知，序号「1）2）」必须对齐同一条左边界。
            // margin-top 40rpx=20，padding 24rpx 28rpx = 12 / 14。
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.otaRuleWaitPatiently, style: _OtaStyles.rule),
                  // 两条之间留一点气口，比行距大、比段距小（小程序 12rpx=6）：
                  // 读起来是「两条规则」而不是一段话。
                  const SizedBox(height: 6),
                  Text(l10n.otaRuleRecoverHint, style: _OtaStyles.rule),
                ],
              ),
            ),
          ],
          const SizedBox(height: 20),
        ],
      ),
      // .ota-actions：进行中整块不渲染（那一屏本来就不该有任何出口，见 showBack 的说明）；
      // 其余画面是「（可选）主按钮 + 返回」，gap 24rpx=12。
      bottom: progressing
          ? null
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_showPrimary) ...[
                  FigmaPrimaryButton(
                    label: _actionText,
                    onPressed: _onAction,
                  ),
                  const SizedBox(height: 12),
                ],
                // 顶部箭头去掉之后唯一的可见出口（对齐小程序底部那颗「返回」）。
                FigmaSecondaryButton(
                  label: l10n.aiBack,
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
                // 贴底留白补到 30（小程序 `.ota-actions` 的 `60rpx + safe`）：
                // [FigmaScreen] 的 bottom 槽只给了 12，是全站通用值，不为这一页改公共组件。
                const SizedBox(height: 18),
              ],
            ),
    );
  }
}

/// OTA 页的五种画面，对齐小程序 `ota.js` 的 `screenStatus`
/// （checking 检测中 / ready 可升级待开始 / progress 进行中 / success 成功或已最新 / fail 失败或无法升级）。
enum _OtaScreen { checking, ready, progress, success, fail }

class _OtaStyles {
  const _OtaStyles._();

  /// .progress-rule：24rpx=12 / #8b929d / line-height 1.6
  static const TextStyle rule = TextStyle(
    color: Color(0xFF8B929D),
    fontSize: 12,
    height: 1.6,
  );

}
