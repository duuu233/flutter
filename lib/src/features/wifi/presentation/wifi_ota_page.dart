import 'dart:async';

import 'package:flutter/material.dart';

import '../../../network/iot/iot_api.dart';
import '../../../network/iot/iot_client.dart';
import '../../../network/iot/iot_ws.dart';
import '../../../shared/l10n/app_l10n.dart';
import '../../../shared/widgets/app_dialog.dart';
import '../../../shared/widgets/app_toast.dart';
import '../../../shared/widgets/app_widgets.dart';
import '../../../shared/widgets/figma_common.dart';
import '../../../shared/widgets/home_figma_common.dart';
import '../../../state.dart';
import '../wifi_l10n.dart';
import '../wifi_ota.dart';
import '../wifi_status.dart';
import '../wifi_widgets.dart';
import '../wifi_fpga.dart';
import 'wifi_provision_page.dart';

/// WiFi 版设备固件升级（2026-11-02，同小程序 `subpackages/device/wifi-ota`；纯逻辑见 [wifi_ota.dart]）。
///
/// 页面形态与配网状态页相同：插画 + 标题 + 说明 + 四步状态圈 + 底部按钮。
///   · 进页先看本地有没有这台设备进行中的升级记录（`ota_inflight:{deviceNo}`）：
///       有且 SENT / DOWNLOADING / FLASHING → 直接接着展示步骤；
///       VERIFYING → 显示「升级完成 · 等待设备重启」，不提示升级；终态 / 4044 → 清记录，按正常检查走。
///   · 正常检查：老服务设备详情的 newVersionNo / downloadPath 对比 IoT 设备信息 firmwareVersion，
///     显示「发现新版本」（立即升级）/「已是最新版本」/「暂时无法判断」/「升级包信息不完整」。
///   · 下发成功立即存 msgid（带 type: 'ota'），3 秒轮询 `GET /api/device/ota/status`，WS `ota.result` 到了立即刷新
///     （WS 只是加速，断线丢事件由轮询兜底；重连后补查一次）。VERIFYING 第 4 步打勾即可离开；
///     FAILED / TIMEOUT 在当前步打叉、给「重新升级」。4000 / 4045（已有进行中的升级）切到「设备正在升级」。
///   · 最终结果由服务端通过消息中心通知（OTA_SUCCESS / OTA_FAILED）。
///   · 进度条（2026-11-12 同小程序）：步骤上方一条，左边当前那一步的文案、右边百分比。服务端 progress（轮询与 WS 都带）
///     只抬「上限」，显示值由本页计时器匀速往上限走（规则见 [wifi_ota.dart]「升级进度条」）；失败停住，VERIFYING 走到 100。
///     收到过的最大进度存进本地记录，重进页面从那里接着走。
///   · 优雅刷新升级（2026-11-13，同小程序 `wifi-ota?mode=fpga`，见 [wifi_fpga.dart]）：[fpga] 为 true 即为安装模式，
///     不比对版本，直接展示设备详情下发的最新版本（newVersionNoFpga）与版本说明（upgradeTipsFpga），进页即记下看过的版本号（红点消失）；下发同一个 `POST /api/device/ota`，type=fpga、version=目标版本；
///     进度条、四步、轮询 / WS、本地进行中记录与固件升级完全一致，只换文字并显示简介。本地记录带 otaType，
///     重进时（无论从哪个入口）按记录里的类型选文字。设备不上报 FPGA 版本（baseVersion 为 null），版本卡只显示安装版本；
///     下发返回 4047（今日升级次数已达上限）按语种提示。
class WifiOtaPage extends StatefulWidget {
  const WifiOtaPage({super.key, required this.state, required this.deviceId, this.fpga = false});

  final PhotoFrameState state;
  final String deviceId;

  /// 优雅刷新升级（从设备信息页「优雅刷新升级」进来时为 true）；false 为普通固件升级。
  final bool fpga;

  @override
  State<WifiOtaPage> createState() => _WifiOtaPageState();
}

enum _Phase { checking, available, latest, unknown, invalid, error, running, verifying, failed, busy }

enum _Art { progress, fail, success }

class _WifiOtaPageState extends State<WifiOtaPage> with WidgetsBindingObserver {
  static const Duration _pollEvery = Duration(seconds: 3);

  _Phase _phase = _Phase.checking;
  String _title = '';
  String _hint = '';
  _Art _art = _Art.progress;
  List<WifiOtaStepState>? _steps;
  String _currentVersion = '';
  String _latestVersion = '';
  bool _showVersions = false;

  DeviceItem? _device;
  WifiOtaCheck? _check;
  WifiOnlineStatus _deviceState = WifiOnlineStatus.unknown;
  String _msgid = '';
  int _lastStep = -1;
  Timer? _poll;
  bool _polling = false;
  bool _starting = false;
  bool _hidden = false;
  String _subscribed = '';
  StreamSubscription<Map<String, dynamic>>? _otaSub;
  StreamSubscription<IotWsState>? _stateSub;

  // 进度条（见类注释）
  int? _reported; // 本次升级收到过的最大 progress
  int _shown = 0; // 显示值，只增不减
  int _cap = 0; // 显示值能走到的上限
  String _status = ''; // 最近一次的状态（WS 只带 progress 时沿用）
  String _progressText = '';
  Timer? _progressTimer;

  /// 本次展示的升级类型：main 固件升级 / fpga 优雅刷新升级（重进时按本地记录切换）。
  String _otaType = kWifiOtaTypeMain;
  String _intro = ''; // 优雅刷新版本简介
  bool get _fpga => _otaType == kWifiOtaTypeFpga;

  /// 四步文字：两种模式只有最后一步不同（升级完成 / 安装完成）。
  List<String> _stepTexts(AppL10n l10n) {
    final texts = [...l10n.wifiOtaSteps];
    if (_fpga) {
      texts[texts.length - 1] = l10n.wifiFpgaDone;
    }
    return texts;
  }

  String get _deviceNo => IotApi.plainDeviceNo(_device?.serialNumber);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // WS 只推状态信号：带了 status 就先按它画，再补查一次；progress（2026-11-12）每条进度回执推一次，同样交给 _applyStatus
    _otaSub = IotWs.instance.on('ota.result').listen((event) {
      if (_msgid.isEmpty || '${event['msgid']}' != _msgid) {
        return;
      }
      final status = '${event['status'] ?? ''}';
      if (status.isNotEmpty || parseOtaProgress(event['progress']) != null) {
        _applyStatus(status.isNotEmpty ? status : _status, event);
      }
      _pollOnce();
    });
    // 重连期间的事件会丢，重连后补查
    _stateSub = IotWs.instance.states.listen((state) {
      if (state.state == 'open' && state.reconnect && _msgid.isNotEmpty) {
        _pollOnce();
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _load();
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 进后台停轮询，回前台接着查（同小程序 onHide / onShow）
    if (state == AppLifecycleState.paused) {
      _hidden = true;
      _stopPolling();
    } else if (state == AppLifecycleState.resumed && _hidden) {
      _hidden = false;
      if (_phase == _Phase.running) {
        _startPolling();
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopPolling();
    _stopProgress();
    unawaited(_otaSub?.cancel());
    unawaited(_stateSub?.cancel());
    if (_subscribed.isNotEmpty) {
      IotWs.instance.unsubscribe(_subscribed);
    }
    super.dispose();
  }

  void _setScreen({
    required _Phase phase,
    required String title,
    required String hint,
    required _Art art,
    List<WifiOtaStepState>? steps,
    bool showVersions = false,
    String currentVersion = '',
    String latestVersion = '',
    String progressText = '',
  }) {
    if (!mounted) {
      return;
    }
    setState(() {
      _phase = phase;
      _title = title;
      _hint = hint;
      _art = art;
      _steps = steps;
      _showVersions = showVersions;
      _currentVersion = currentVersion;
      _latestVersion = latestVersion;
      _progressText = progressText;
    });
  }

  Future<void> _load() async {
    final l10n = AppL10n.of(context);
    _stopPolling();
    _msgid = '';
    _lastStep = -1;
    _resetProgress();
    _otaType = widget.fpga ? kWifiOtaTypeFpga : kWifiOtaTypeMain;
    _intro = '';
    _setScreen(phase: _Phase.checking, title: l10n.wifiOtaChecking, hint: l10n.wifiOtaCheckingHint, art: _Art.progress);
    final device = await widget.state.fetchDeviceFirmwareInfo(widget.deviceId);
    if (!mounted) {
      return;
    }
    if (device == null) {
      _showError(l10n.wifiOtaDeviceLoadFailed);
      return;
    }
    _device = device;
    final deviceNo = _deviceNo;
    if (deviceNo.isEmpty) {
      _showError(l10n.wifiOtaNoDeviceNo);
      return;
    }
    if (_subscribed != deviceNo && !IotWs.instance.subscriptions.contains(deviceNo)) {
      IotWs.instance.subscribe(deviceNo);
      _subscribed = deviceNo;
    }

    // 从「优雅刷新升级」进来即算看过最新版本（含正有安装在进行、直接接着展示的情况），红点消失
    if (widget.fpga) {
      final latest = wifiFpgaLatestOf(device);
      if (latest != null) {
        await WifiFpgaSeenStore.mark(deviceNo, latest.version);
      }
      if (!mounted) {
        return;
      }
    }

    // ① 先看本地进行中的升级（展示「有新版本」之前必须先查）
    final inflight = await WifiOtaStore.refresh(deviceNo);
    if (!mounted) {
      return;
    }
    if (inflight.record != null) {
      _resumeInflight(inflight);
      return;
    }

    // ② 没有进行中的任务：正常比对版本
    Map<String, dynamic>? info;
    try {
      info = await IotApi.getDeviceInfo(deviceNo);
    } catch (_) {
      info = null;
    }
    if (!mounted) {
      return;
    }
    _deviceState = info == null ? WifiOnlineStatus.unknown : wifiDeviceState(info);
    if (widget.fpga) {
      _showFpgaTarget(wifiFpgaLatestOf(device));
      return;
    }
    _check = evaluateWifiOta(wifiFirmwareVersion(info), device.newVersionNo, device.downloadPath);
    _showEvaluation(_check!);
  }

  /// 优雅刷新升级：不比对版本，直接展示设备详情的最新版本与版本说明；设备不上报 FPGA 版本，不显示当前版本。
  void _showFpgaTarget(WifiFpgaVersion? target) {
    final l10n = AppL10n.of(context);
    if (target == null) {
      _check = null;
      _intro = '';
      _setScreen(phase: _Phase.latest, title: l10n.wifiFpgaNone, hint: l10n.wifiFpgaNoneHint, art: _Art.success);
      return;
    }
    final ok = target.hasValidUrl;
    _check = WifiOtaCheck(ok ? WifiOtaCheckState.available : WifiOtaCheckState.invalid, '', target.version, target.url);
    _intro = target.intro;
    _setScreen(
      phase: ok ? _Phase.available : _Phase.invalid,
      title: l10n.wifiFpgaInstallTitle(target.version),
      hint: ok ? l10n.wifiFpgaAvailableHint : l10n.wifiFpgaInvalidUrl,
      art: ok ? _Art.progress : _Art.fail,
      showVersions: true,
      currentVersion: '--',
      latestVersion: target.version,
    );
  }

  void _showError(String message) {
    _setScreen(phase: _Phase.error, title: AppL10n.of(context).wifiOtaCheckFailed, hint: message, art: _Art.fail);
  }

  void _showEvaluation(WifiOtaCheck result) {
    final l10n = AppL10n.of(context);
    final current = result.current.isNotEmpty ? result.current : '--';
    final latest = result.latest.isNotEmpty ? result.latest : '--';
    switch (result.state) {
      case WifiOtaCheckState.available:
        _setScreen(
          phase: _Phase.available,
          title: l10n.wifiOtaNewVersion(result.latest),
          hint: l10n.wifiOtaAvailableHint,
          art: _Art.progress,
          showVersions: true,
          currentVersion: current,
          latestVersion: latest,
        );
      case WifiOtaCheckState.unknown:
        // 当前版本还是旧格式或没上报过：按「无法判断」处理，不报错
        _setScreen(
          phase: _Phase.unknown,
          title: l10n.wifiOtaUnknownTitle,
          hint: l10n.wifiOtaUnknownHint,
          art: _Art.progress,
          showVersions: true,
          currentVersion: current,
          latestVersion: latest,
        );
      case WifiOtaCheckState.invalid:
        _setScreen(
          phase: _Phase.invalid,
          title: l10n.wifiOtaNewVersion(result.latest),
          hint: l10n.wifiOtaInvalidHint,
          art: _Art.fail,
          showVersions: true,
          currentVersion: current,
          latestVersion: latest,
        );
      case WifiOtaCheckState.latest:
        _setScreen(
          phase: _Phase.latest,
          title: l10n.wifiOtaLatest,
          hint: result.current.isNotEmpty ? l10n.wifiOtaCurrentVersionHint(result.current) : l10n.wifiOtaNoUpdateHint,
          art: _Art.success,
          showVersions: true,
          currentVersion: current,
          latestVersion: result.latest.isNotEmpty ? result.latest : current,
        );
    }
  }

  /// 重进页面时接着展示本地记录的任务。
  void _resumeInflight(WifiOtaRefresh inflight) {
    final record = inflight.record!;
    _otaType = record.otaType;
    _intro = record.intro;
    _msgid = record.msgid;
    _lastStep = record.lastStep;
    // 进度条从收到过的最大进度接着走（本地记录与这次查询取大的）
    _resetProgress();
    final saved = record.progress;
    final fresh = parseOtaProgress(inflight.data?['progress']);
    if (saved != null || fresh != null) {
      final a = saved ?? 0;
      final b = fresh ?? 0;
      final value = a > b ? a : b;
      _reported = value;
      _shown = value > 99 ? 99 : value;
    }
    final status = normalizeOtaStatus(
      inflight.status.isNotEmpty ? inflight.status : (record.status.isNotEmpty ? record.status : 'SENT'),
    );
    if (status == 'VERIFYING') {
      _showWaitingReboot();
      return;
    }
    _applyStatus(status, inflight.data);
    if (_phase == _Phase.running) {
      _startPolling();
    }
  }

  /// VERIFYING 之后重进：不进步骤页、不提示升级，等设备重启后服务端确认。
  void _showWaitingReboot() {
    final l10n = AppL10n.of(context);
    _stopPolling();
    _setScreen(
      phase: _Phase.busy,
      title: _fpga ? l10n.wifiFpgaWaitRebootTitle : l10n.wifiOtaWaitRebootTitle,
      hint: _fpga ? l10n.wifiFpgaWaitRebootHint : l10n.wifiOtaWaitRebootHint,
      art: _Art.success,
    );
  }

  /// 已有进行中的升级（4000 / 4045，本地没有 msgid 可查）。
  void _showBusy() {
    final l10n = AppL10n.of(context);
    _stopPolling();
    _setScreen(phase: _Phase.busy, title: l10n.wifiOtaBusyTip, hint: l10n.wifiOtaBusyHint, art: _Art.progress);
  }

  /// 按服务端状态画步骤；[data] 为状态查询结果（可为空）。
  void _applyStatus(String rawStatus, Map<String, dynamic>? data) {
    if (!mounted) {
      return;
    }
    final l10n = AppL10n.of(context);
    final status = normalizeOtaStatus(rawStatus);
    final index = otaStepIndex(status);
    if (index > _lastStep) {
      _lastStep = index;
    }
    if (status.isNotEmpty) {
      _status = status;
    }
    final reported = parseOtaProgress(data?['progress']);
    if (reported != null && reported > (_reported ?? 0)) {
      _reported = reported;
    }
    final deviceNo = _deviceNo;
    if (isOtaFinal(status)) {
      unawaited(WifiOtaStore.clear(deviceNo));
    } else if (index > -1) {
      unawaited(WifiOtaStore.update(deviceNo, status: status, lastStep: _lastStep, progress: _reported));
    }

    // SUCCESS 不在步骤口径内；万一跳过 VERIFYING 直接到了，也按完成收尾，不让第 4 步一直转圈
    final view = otaStepsFor(status == 'SUCCESS' ? 'VERIFYING' : status, _lastStep);
    final progressText = _stepTexts(l10n)[otaActiveStep(view)];
    if (view.phase == WifiOtaViewPhase.failed) {
      _stopPolling();
      _stopProgress(); // 失败停在当时的位置
      _setScreen(
        phase: _Phase.failed,
        title: isOtaTimeout(status) ? (_fpga ? l10n.wifiFpgaTimeout : l10n.wifiOtaTimeout) : (_fpga ? l10n.wifiFpgaFailed : l10n.wifiOtaFailed),
        hint: l10n.wifiOtaFailHint,
        art: _Art.fail,
        steps: view.steps,
        progressText: progressText,
      );
      return;
    }
    // 不认识的状态值不动上限；其余按状态与收到过的最大进度定上限，计时器匀速往上走
    if (index > -1 || status == 'SUCCESS') {
      _cap = otaProgressCap(status, _reported);
    }
    _runProgress();
    if (view.phase == WifiOtaViewPhase.verifying) {
      _stopPolling();
      _setScreen(
        phase: _Phase.verifying,
        title: _fpga ? l10n.wifiFpgaDone : l10n.wifiOtaDone,
        hint: status == 'SUCCESS' ? (_fpga ? l10n.wifiFpgaSuccessHint : l10n.wifiOtaSuccessHint) : l10n.wifiOtaVerifyingHint,
        art: _Art.success,
        steps: view.steps,
        progressText: progressText,
      );
      return;
    }
    final seconds = int.tryParse('${data?['elapsedSeconds'] ?? ''}') ?? 0;
    final elapsed = seconds > 0 ? l10n.wifiOtaElapsed(seconds ~/ 60, seconds % 60) : '';
    _setScreen(
      phase: _Phase.running,
      title: _fpga ? l10n.wifiFpgaRunningTitle : l10n.wifiOtaRunningTitle,
      hint: () {
        final base = _fpga ? l10n.wifiFpgaRunningHint : l10n.wifiOtaRunningHint;
        return elapsed.isNotEmpty ? '$elapsed，$base' : base;
      }(),
      art: _Art.progress,
      steps: view.steps,
      progressText: progressText,
    );
  }

  // ── 进度条（2026-11-12，规则见 wifi_ota.dart「升级进度条」）──
  void _resetProgress() {
    _stopProgress();
    _reported = null;
    _shown = 0;
    _cap = 0;
    _status = '';
  }

  /// 显示值没到上限就每 [kWifiOtaProgressTick] 走 1%，到了就停表，上限抬高后再开。
  void _runProgress() {
    if (_progressTimer != null || !mounted || _shown >= _cap) {
      return;
    }
    _progressTimer = Timer.periodic(kWifiOtaProgressTick, (_) {
      if (!mounted || _shown >= _cap) {
        _stopProgress();
        return;
      }
      setState(() => _shown += 1);
    });
  }

  void _stopProgress() {
    _progressTimer?.cancel();
    _progressTimer = null;
  }

  void _startPolling() {
    _stopPolling();
    if (!mounted || _msgid.isEmpty) {
      return;
    }
    _poll = Timer.periodic(_pollEvery, (_) => _pollOnce());
  }

  void _stopPolling() {
    _poll?.cancel();
    _poll = null;
  }

  Future<void> _pollOnce() async {
    final msgid = _msgid;
    if (msgid.isEmpty || _polling || !mounted) {
      return;
    }
    _polling = true;
    Map<String, dynamic> data;
    try {
      data = await IotApi.getOtaStatus(msgid);
    } catch (error) {
      _polling = false;
      if (error is IotException && int.tryParse('${error.code}') == 4044 && msgid == _msgid && mounted) {
        // 任务过期（服务端只留 2 小时）：清记录，回到正常检查
        await WifiOtaStore.clear(_deviceNo);
        _msgid = '';
        if (mounted) {
          _load();
        }
      }
      return; // 网络 / 503 等：保持当前画面，下一轮再查
    }
    _polling = false;
    if (msgid != _msgid || !mounted) {
      return;
    }
    // 已经停在完成 / 失败上的，迟到的查询结果不再改画面
    if (_phase != _Phase.running) {
      return;
    }
    _applyStatus('${data['status'] ?? ''}', data);
  }

  /// 「立即升级」/「重新升级」。
  Future<void> _startUpgrade() async {
    final result = _check;
    if (_starting || result == null || _device == null) {
      return;
    }
    final l10n = AppL10n.of(context);
    final tip = wifiBlockedTip(l10n, _deviceState);
    if (tip.isNotEmpty) {
      AppToast.warn(context, tip);
      return;
    }
    final confirmed = await showAppConfirmDialog(
      context,
      icon: Icons.system_update_alt_rounded,
      title: _fpga ? l10n.wifiFpgaTitle : l10n.wifiOtaTitle,
      message: _fpga ? l10n.wifiFpgaConfirm(result.latest) : l10n.wifiOtaConfirm(result.latest),
      confirmLabel: _fpga ? l10n.wifiFpgaInstallNow : l10n.wifiOtaUpgradeNow,
    );
    if (confirmed == true && mounted) {
      await _sendUpgrade();
    }
  }

  Future<void> _sendUpgrade() async {
    final result = _check;
    final deviceNo = _deviceNo;
    if (_starting || result == null || deviceNo.isEmpty) {
      return;
    }
    final l10n = AppL10n.of(context);
    _starting = true;
    AppLoadingDialog.show(context, l10n.wifiOtaSending);
    Map<String, dynamic> res;
    try {
      // type：main 固件升级 / fpga 优雅刷新（version 为 FPGA 目标版本），其余与固件升级一致
      res = await IotApi.startOta(deviceNo: deviceNo, url: result.url, type: _otaType, version: result.latest);
    } catch (error) {
      _starting = false;
      AppLoadingDialog.hideIfAny();
      if (!mounted) {
        return;
      }
      if (isWifiFpgaLimitError(error)) {
        // 4047：今日升级次数已达上限，停在当前页，不算失败
        AppToast.warn(context, l10n.wifiFpgaLimit);
        return;
      }
      if (isWifiOtaBusyError(error)) {
        AppToast.warn(context, l10n.wifiOtaBusyTip);
        _showBusy();
        return;
      }
      AppToast.warn(context, error is IotException && error.message.isNotEmpty ? error.message : l10n.wifiOtaSendFailed);
      return;
    }
    _starting = false;
    AppLoadingDialog.hideIfAny();
    if (!mounted) {
      return;
    }
    final msgid = '${res['msgid'] ?? ''}';
    if (msgid.isEmpty) {
      AppToast.warn(context, l10n.wifiOtaSendFailed);
      return;
    }
    // 下发成功立即保存（带类型），一台设备只留一条
    await WifiOtaStore.save(deviceNo, msgid, version: result.latest, baseVersion: result.current, otaType: _otaType, intro: _intro);
    if (!mounted) {
      return;
    }
    _msgid = msgid;
    _lastStep = -1;
    _resetProgress();
    _applyStatus('SENT', null);
    _startPolling();
  }

  /// 失败后的「重新升级」：本页走过版本比对的直接再下发；从本地记录恢复进来的没有比对结果，先重新检查。
  void _retryUpgrade() {
    if (_check?.state == WifiOtaCheckState.available) {
      _startUpgrade();
      return;
    }
    _load();
  }

  void _finish() => Navigator.of(context).maybePop();

  /// 升级进度条（2026-11-12）：左边当前那一步的文案、右边百分比。
  Widget _buildProgress() => _OtaProgressBar(
    key: const ValueKey('wifi-ota-progress'),
    text: _progressText,
    value: _shown,
    failed: _phase == _Phase.failed,
  );

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final titleColor = switch (_phase) {
      _Phase.failed || _Phase.error => const Color(0xFFE5533D),
      _Phase.verifying => const Color(0xFFFF5A1E),
      _ => const Color(0xFF2A2D32),
    };
    final art = switch (_art) {
      _Art.progress => 'assets/images/upload-icon01.png',
      _Art.fail => 'assets/images/upload-icon02.png',
      _Art.success => 'assets/images/upload-icon03.png',
    };
    final texts = _stepTexts(l10n);
    final steps = _steps;
    return FigmaScreen(
      title: _fpga ? l10n.wifiFpgaTitle : l10n.wifiOtaTitle,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 24),
          Image.asset(
            art,
            height: 110,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) => const SizedBox(height: 110),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_phase == _Phase.checking) ...[const WifiMiniSpinner(size: 16), const SizedBox(width: 8)],
              Flexible(
                child: Text(
                  _title,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: titleColor, fontSize: 19, fontWeight: FontWeight.w700, height: 1.4),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            _hint,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFF8B9098), fontSize: 12, height: 1.5),
          ),
          if (_showVersions) ...[
            const SizedBox(height: 20),
            FigmaGlassCard(
              borderRadius: 16,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
              child: Column(
                children: [
                  if (!_fpga) _VersionRow(label: l10n.wifiOtaCurrentVersion, value: _currentVersion),
                  _VersionRow(label: l10n.wifiOtaLatestVersion, value: _latestVersion),
                ],
              ),
            ),
          ],
          // 优雅刷新版本简介（2026-11-13）：安装确认与进度页都带出
          if (_intro.isNotEmpty) ...[
            const SizedBox(height: 12),
            FigmaGlassCard(
              key: const ValueKey('wifi-fpga-intro'),
              borderRadius: 16,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.wifiFpgaIntro, style: const TextStyle(color: Color(0xFF8B9098), fontSize: 12)),
                  const SizedBox(height: 4),
                  Text(_intro, style: const TextStyle(color: Color(0xFF2A2D32), fontSize: 13, height: 1.6)),
                ],
              ),
            ),
          ],
          if (steps != null) ...[
            const SizedBox(height: 20),
            _buildProgress(),
            const SizedBox(height: 12),
            FigmaGlassCard(
              borderRadius: 16,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              child: Column(
                children: [
                  for (var i = 0; i < 4; i++)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Row(
                        children: [
                          WifiStepIcon(index: i, status: steps[i].name),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              texts[i],
                              style: TextStyle(
                                color: steps[i] == WifiOtaStepState.fail
                                    ? const Color(0xFFE5533D)
                                    : steps[i] == WifiOtaStepState.pending
                                    ? const Color(0xFF8B9098)
                                    : const Color(0xFF2A2D32),
                                fontSize: 15,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 24),
        ],
      ),
      bottom: switch (_phase) {
        _Phase.available => FigmaHomePrimaryButton(
          key: const ValueKey('wifi-ota-start'),
          label: _fpga ? l10n.wifiFpgaInstallNow : l10n.wifiOtaUpgradeNow,
          fontWeight: FontWeight.w700,
          onPressed: _startUpgrade,
        ),
        _Phase.verifying || _Phase.busy => FigmaHomePrimaryButton(
          label: l10n.wifiOtaFinish,
          fontWeight: FontWeight.w700,
          onPressed: _finish,
        ),
        _Phase.failed => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FigmaHomePrimaryButton(
              key: const ValueKey('wifi-ota-retry'),
              label: _fpga ? l10n.wifiFpgaRetry : l10n.wifiOtaRetry,
              fontWeight: FontWeight.w700,
              onPressed: _retryUpgrade,
            ),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _finish,
              child: SizedBox(
                height: 44,
                child: Center(
                  child: Text(l10n.wifiCancel, style: const TextStyle(color: Color(0xFFFF621F), fontSize: 16)),
                ),
              ),
            ),
          ],
        ),
        _Phase.unknown || _Phase.error => FigmaHomePrimaryButton(
          label: l10n.wifiOtaRecheck,
          fontWeight: FontWeight.w700,
          onPressed: _load,
        ),
        _ => null,
      },
    );
  }
}

class _OtaProgressBar extends StatelessWidget {
  const _OtaProgressBar({super.key, required this.text, required this.value, required this.failed});

  final String text;
  final int value;
  final bool failed;

  @override
  Widget build(BuildContext context) {
    // 与 WiFi 投屏结果页进度条同一套颜色；失败转红、停在当时的位置
    final color = failed ? const Color(0xFFE5533D) : const Color(0xFFFF621F);
    return FigmaGlassCard(
      borderRadius: 16,
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: failed ? color : const Color(0xFF2A2D32),
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text('$value%', style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: value / 100,
              minHeight: 8,
              backgroundColor: const Color(0x1FFF621F),
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ],
      ),
    );
  }
}

class _VersionRow extends StatelessWidget {
  const _VersionRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: Row(
        children: [
          Text(label, style: const TextStyle(color: Color(0xFF33373D), fontSize: 14, fontWeight: FontWeight.w600)),
          const Spacer(),
          Text(value, style: const TextStyle(color: Color(0xFF777E88), fontSize: 13)),
        ],
      ),
    );
  }
}
