import 'package:flutter/material.dart';

import 'package:BoltStar/src/shared/widgets/app_widgets.dart';
import 'package:BoltStar/src/shared/widgets/figma_common.dart';
import '../../../device/ble_controller.dart';
import '../../../device/ble/ota_ble.dart';
import '../../../shared/l10n/app_l10n.dart';
import '../../../state.dart';

/// 设备固件 OTA 升级页 —— 由微信小程序版 `subpackages/device/ota/ota`（ota.js + ota.wxml）移植。
///
/// 流程对齐小程序：进入即拉设备详情（`fetchDeviceFirmwareInfo` → getUserProductDetail）判断
/// 是否有可升级固件；真实升级复用图传已连接的设备，走独立的 FF10 OTA 服务（见 [FrameOtaClient]）。
/// 无硬件 / 无真实固件时可用「干跑测试(mock 固件)」验证读包/组帧/分包链路。
///
/// 与「更新 BoltStar」(App 版本更新，`update_boltstar_page`) 是两件事：这里升级的是相框设备固件。
class OtaUpgradePage extends StatefulWidget {
  const OtaUpgradePage({super.key, required this.state, this.autoStart = false});

  final PhotoFrameState state;

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
Future<void> startOtaFlow(BuildContext context, PhotoFrameState state) async {
  final device = state.selectedDevice;
  // ① 未连接自动扫连（升级需设备在线）。
  if (!BleController.instance.connected) {
    AppLoadingDialog.show(context, AppL10n.of(context).otaConnecting);
    final feedback = await state.connectDevice(device.id);
    if (!context.mounted) {
      return;
    }
    Navigator.of(context, rootNavigator: true).pop();
    if (!feedback.success) {
      AppToast.show(context, feedback.message);
      return;
    }
  }
  // ② loading 下二次拉取最新版本信息。
  AppLoadingDialog.show(context, AppL10n.of(context).otaCheckingVersion);
  final updated = await state.fetchDeviceFirmwareInfo(device.id);
  if (!context.mounted) {
    return;
  }
  Navigator.of(context, rootNavigator: true).pop();
  final target = updated ?? device;
  // ③ 已是最新 / 无有效可升级包：提示后返回。
  if (!target.hasFirmwareUpdate) {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(AppL10n.of(dialogContext).otaFirmwareUpgrade),
        content: Text(AppL10n.of(dialogContext).otaAlreadyLatestContent),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(AppL10n.of(dialogContext).otaKnow),
          ),
        ],
      ),
    );
    return;
  }
  // ④ 有新版本：确认弹窗（稍后 / 立刻更新）。
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(AppL10n.of(dialogContext).otaFirmwareUpgrade),
      content: Text(
        AppL10n.of(dialogContext).otaNewVersionConfirm(target.newVersionNo),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(AppL10n.of(dialogContext).otaLater),
        ),
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(AppL10n.of(dialogContext).otaUpdateNow),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) {
    return;
  }
  // ⑤ 进 OTA 页并自动开始升级。
  await Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) => OtaUpgradePage(state: state, autoStart: true),
    ),
  );
}

/// 页面阶段（对齐 ota.js 的 state）。
enum _OtaStage { checking, latest, available, invalid, upgrading, success, failed }

class _OtaUpgradePageState extends State<OtaUpgradePage> {
  final BleController _ble = BleController.instance;

  _OtaStage _stage = _OtaStage.checking;
  bool _aborted = false;

  String _deviceName = '智能相框';
  String _currentVersion = '--';
  String _latestVersion = '--';
  String _packageSizeText = '--';
  String _statusText = '检查中';
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
    _load();
  }

  @override
  void dispose() {
    // 页面离开：升级中则打中止标记，让传输尽快干净停下（切后台/离开会挂起蓝牙）。
    if (_stage == _OtaStage.upgrading) {
      _aborted = true;
    }
    super.dispose();
  }

  String? get _deviceId {
    try {
      return widget.state.selectedDevice.id;
    } catch (_) {
      return null;
    }
  }

  bool get _connected => _ble.connected;

  static String _formatSize(int bytes) {
    if (bytes >= 1024 * 1024) {
      return '${(bytes / 1024 / 1024).toStringAsFixed(1)}MB';
    }
    if (bytes >= 1024) {
      return '${(bytes / 1024).round()}KB';
    }
    return '${bytes}B';
  }

  // 版本号一致性：去空格后不区分大小写；任一为空不视为一致（避免「未知版本」被误判已最新）。
  static bool _sameVersion(String a, String b) {
    final na = a.trim().toUpperCase();
    final nb = b.trim().toUpperCase();
    return na.isNotEmpty && nb.isNotEmpty && na == nb;
  }

  Future<void> _load() async {
    final id = _deviceId;
    if (id == null) {
      setState(() {
        _stage = _OtaStage.failed;
        _statusText = '设备不存在';
        _errorMessage = '缺少设备ID，无法检查固件版本。';
      });
      return;
    }

    setState(() {
      _stage = _OtaStage.checking;
      _statusText = '检查中';
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
      device = updated ?? widget.state.selectedDevice;
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
    final bleFw = _ble.info?.firmwareVersion ?? '';
    final currentVersion = (bleFw.isNotEmpty ? bleFw : device.firmwareVersion).trim();
    final latestVersion = device.newVersionNo.trim();
    final alreadyLatest = _sameVersion(currentVersion, latestVersion);
    final hasUpdateFlag = device.isUpdate == 1 && !alreadyLatest;
    final hasPackage = hasUpdateFlag && device.hasFirmwareUpdate;

    String invalidReason = '';
    if (hasUpdateFlag && !device.hasFirmwareUpdate) {
      if (latestVersion.isEmpty || device.downloadPath.isEmpty) {
        invalidReason = l10n.otaInvalidMissingInfo;
      } else {
        invalidReason = l10n.otaInvalidBinUrl;
      }
    }

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

      if (hasUpdateFlag && !hasPackage) {
        _stage = _OtaStage.invalid;
        _statusText = l10n.otaCannotUpgrade;
        _errorMessage = invalidReason;
        _releaseNotes = const [];
      } else if (hasPackage) {
        _stage = _OtaStage.available;
        _statusText = _connected ? l10n.otaNewVersionFound : l10n.otaDeviceNotConnected;
        _errorMessage = _connected ? '' : l10n.otaConnectFirstHint;
        _releaseNotes = [l10n.otaNewVersionNote(latestVersion)];
      } else {
        _stage = _OtaStage.latest;
        _statusText = l10n.otaUpToDate;
        _errorMessage = '';
        _releaseNotes = const [];
      }
    });
    // 详情页确认「立刻更新」进入(auto=1)：包就绪且已连接则自动开始升级。
    if (widget.autoStart &&
        _stage == _OtaStage.available &&
        _connected &&
        mounted) {
      _runUpgrade(dryRun: false);
    }
  }

  OtaFirmwarePackage _buildPackage({required bool dryRun}) {
    if (dryRun || !_hasPackage) {
      // 干跑 / 无真实固件：用 mock 固件校验编码链路。
      return const OtaFirmwarePackage(mock: true, sizeBytes: 65536, version: 'mock');
    }
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

  Future<void> _runUpgrade({required bool dryRun}) async {
    if (_stage == _OtaStage.upgrading) return;
    final l10n = AppL10n.of(context);
    // 真实升级要求已连接；干跑不需要。
    if (!dryRun && !_connected) {
      setState(() {
        _stage = _OtaStage.available;
        _statusText = l10n.otaDeviceNotConnected;
        _errorMessage = l10n.otaNoBleConnection;
      });
      return;
    }

    _aborted = false;
    setState(() {
      _stage = _OtaStage.upgrading;
      _statusText = dryRun ? l10n.otaDryRunning : l10n.otaUpgrading;
      _errorMessage = '';
      _progress = 0;
      _progressText = dryRun ? l10n.otaPreparingDryRun : l10n.otaPreparingUpgrade;
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
      final result = await _ble.upgradeFirmware(
        _buildPackage(dryRun: dryRun),
        dryRun: dryRun,
        pace: 20,
        onProgress: _onProgress,
        shouldAbort: () => _aborted,
        onMonitor: dryRun ? null : monitor,
      );

      if (!mounted) return;

      if (result.dryRun) {
        final crcHex =
            '0x${result.crc32.toRadixString(16).toUpperCase().padLeft(8, '0')}';
        setState(() {
          _stage = _OtaStage.success;
          _statusText = l10n.otaDryRunPassed;
          _progress = 1;
          _progressText = l10n.otaDryRunPassedDetail(
            result.size,
            result.totalPackets,
            result.chunkSize,
          );
          _releaseNotes = [
            l10n.otaFirmwareSizeNote(result.size),
            l10n.otaLocalCrc32Note(crcHex),
            l10n.otaChunkingNote(result.totalPackets, result.chunkSize, result.prn),
            l10n.otaStartFrameNote(result.startFrameHex),
            l10n.otaFirstDataFrameNote(_ellipsis(result.firstDataFrameHex, 47)),
          ];
        });
        return;
      }

      // 固件已确认(2026-07-01)：收满且 CRC32 无误必回 0xF3、回完约 2s 后才复位重启。confirmed:false 已成
      // 兜底死路——真拿不到 0xF3 时 FrameOtaClient 会抛错走 catch，不再返回「软成功」。万一仍走到这里，
      // 说明确实没收到 0xF3 → 升级未确认，如实提示重试，绝不谎报「升级完成」。
      final unconfirmed = !result.confirmed;
      final doneText =
          unconfirmed ? l10n.otaUnconfirmedRetry : l10n.otaUpgradeComplete;
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
        }
      });
      if (!unconfirmed && finalRxFrame.isNotEmpty) {
        // 真机联调：按两种 RESULT 偏移解读 0xF3，定下规格书 §5.2 未敲定的偏移。
        debugPrint('[OTA] ${decodeFinalResultFrame(finalRxFrame)}');
      }
      // NOTE: 小程序会 best-effort 调 reportDeviceFirmwareUpgrade 回报后台；
      // 该接口不在 BoltFox `/Client/...` 用户前端接口内，App 侧暂不回报（如后端提供再接）。
    } on OtaAbortedException {
      if (!mounted) return;
      setState(() {
        _stage = _OtaStage.failed;
        _statusText = dryRun ? l10n.otaDryRunFailed : l10n.otaUpgradeFailed;
        _errorMessage = l10n.otaInterrupted;
      });
    } catch (error) {
      if (!mounted) return;
      final aborted = _aborted;
      setState(() {
        _stage = _OtaStage.failed;
        _statusText = dryRun ? l10n.otaDryRunFailed : l10n.otaUpgradeFailed;
        _errorMessage = aborted ? l10n.otaInterrupted : error.toString();
      });
    }
  }

  static String _ellipsis(String s, int max) => s.length <= max ? s : s.substring(0, max);

  // ── 视图 ─────────────────────────────────────────────────
  bool get _canUpgrade =>
      _stage != _OtaStage.upgrading && _hasPackage && _connected;

  bool get _canDryRun => _stage != _OtaStage.upgrading;

  String get _actionText {
    final l10n = AppL10n.of(context);
    switch (_stage) {
      case _OtaStage.upgrading:
        return l10n.otaUpgrading;
      case _OtaStage.available:
        return _connected ? l10n.otaUpgradeNowAction : l10n.otaDeviceNotConnected;
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
      _runUpgrade(dryRun: false);
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
        body: Padding(
          padding: const EdgeInsets.only(top: 120),
          child: Center(
            child: Text(l10n.otaCheckingFirmware,
                style: const TextStyle(color: Color(0xFF808690))),
          ),
        ),
      );
    }

    // 无真实升级包/未连接时，展示「干跑测试」入口，方便无硬件时验证编码链路。
    final showDryRun = _canDryRun && (!_hasPackage || !_connected);

    return FigmaScreen(
      title: l10n.otaTitle,
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
          if (showDryRun)
            FigmaSecondaryButton(
              label: l10n.otaDryRunTest,
              onPressed: _canDryRun ? () => _runUpgrade(dryRun: true) : null,
            ),
        ],
      ),
      bottom: FigmaPrimaryButton(
        label: _actionText,
        onPressed:
            (_canUpgrade || _stage == _OtaStage.failed) ? _onAction : null,
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
