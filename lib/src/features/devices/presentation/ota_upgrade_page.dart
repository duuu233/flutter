import 'package:flutter/material.dart';

import 'package:BoltStar/src/shared/widgets/figma_common.dart';
import '../../../device/ble_controller.dart';
import '../../../device/ble/ota_ble.dart';
import '../../../state.dart';

/// 设备固件 OTA 升级页 —— 由微信小程序版 `subpackages/device/ota/ota`（ota.js + ota.wxml）移植。
///
/// 流程对齐小程序：进入即拉设备详情（`fetchDeviceFirmwareInfo` → getUserProductDetail）判断
/// 是否有可升级固件；真实升级复用图传已连接的设备，走独立的 FF10 OTA 服务（见 [FrameOtaClient]）。
/// 无硬件 / 无真实固件时可用「干跑测试(mock 固件)」验证读包/组帧/分包链路。
///
/// 与「更新 BoltStar」(App 版本更新，`update_boltstar_page`) 是两件事：这里升级的是相框设备固件。
class OtaUpgradePage extends StatefulWidget {
  const OtaUpgradePage({super.key, required this.state});

  final PhotoFrameState state;

  @override
  State<OtaUpgradePage> createState() => _OtaUpgradePageState();
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
    DeviceItem device;
    try {
      device = updated ?? widget.state.selectedDevice;
    } catch (_) {
      setState(() {
        _stage = _OtaStage.failed;
        _statusText = '设备不存在';
        _errorMessage = '缺少设备信息，无法检查固件版本。';
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
        invalidReason = '检测到可更新状态，但缺少新版本号或固件下载地址，请稍后重试。';
      } else {
        invalidReason = '固件下载地址不是有效的 .bin 文件，请稍后重试。';
      }
    }

    setState(() {
      _deviceName = device.name.isEmpty ? '智能相框' : device.name;
      _currentVersion = currentVersion.isEmpty ? '--' : currentVersion;
      _latestVersion = latestVersion.isEmpty ? '--' : latestVersion;
      _hasPackage = hasPackage;
      _downloadPath = device.downloadPath;
      _sizeBytes = device.firmwareSize;
      _packageSizeText = hasPackage
          ? (device.firmwareSize > 0 ? _formatSize(device.firmwareSize) : '下载后确认')
          : '--';

      if (hasUpdateFlag && !hasPackage) {
        _stage = _OtaStage.invalid;
        _statusText = '无法升级';
        _errorMessage = invalidReason;
        _releaseNotes = const [];
      } else if (hasPackage) {
        _stage = _OtaStage.available;
        _statusText = _connected ? '发现新版本' : '设备未连接';
        _errorMessage = _connected ? '' : '请先在详情页连接设备，并在升级过程中保持设备在线。';
        _releaseNotes = ['发现新版本：$latestVersion'];
      } else {
        _stage = _OtaStage.latest;
        _statusText = '已是最新';
        _errorMessage = '';
        _releaseNotes = const [];
      }
    });
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
    // 真实升级要求已连接；干跑不需要。
    if (!dryRun && !_connected) {
      setState(() {
        _stage = _OtaStage.available;
        _statusText = '设备未连接';
        _errorMessage = '未获取到设备蓝牙连接，请先在详情页连接设备后再升级。';
      });
      return;
    }

    _aborted = false;
    setState(() {
      _stage = _OtaStage.upgrading;
      _statusText = dryRun ? '干跑中' : '升级中';
      _errorMessage = '';
      _progress = 0;
      _progressText = dryRun ? '准备干跑' : '准备升级';
    });

    try {
      final result = await _ble.upgradeFirmware(
        _buildPackage(dryRun: dryRun),
        dryRun: dryRun,
        pace: 20,
        onProgress: _onProgress,
        shouldAbort: () => _aborted,
      );

      if (!mounted) return;

      if (result.dryRun) {
        final crcHex =
            '0x${result.crc32.toRadixString(16).toUpperCase().padLeft(8, '0')}';
        setState(() {
          _stage = _OtaStage.success;
          _statusText = '干跑通过';
          _progress = 1;
          _progressText =
              '干跑通过：${result.size} 字节 / ${result.totalPackets} 包 / 每包 ${result.chunkSize} 字节';
          _releaseNotes = [
            '固件大小：${result.size} 字节',
            '本地 CRC32：$crcHex',
            '分包：${result.totalPackets} 包 × ${result.chunkSize} 字节，PRN=${result.prn}',
            'START 帧：${result.startFrameHex}',
            '首个 DATA 帧：${_ellipsis(result.firstDataFrameHex, 47)} …',
          ];
        });
        return;
      }

      // 设备收满固件后会立即重启、可能来不及回 0xF3：confirmed:false 表示「数据已全部发送但未拿到显式成功应答」。
      final unconfirmed = !result.confirmed;
      final doneText = unconfirmed ? '数据已发送，设备重启中，请确认固件版本' : '升级完成';
      setState(() {
        _stage = _OtaStage.success;
        _statusText = unconfirmed ? '请确认版本' : '升级完成';
        _progress = 1;
        _progressText =
            '$doneText（${result.size} 字节 / ${result.totalPackets} 包）';
        // 已升级：把本地当前版本置为新版本，隐藏可升级包。
        _currentVersion = _latestVersion;
        _hasPackage = false;
      });
      // NOTE: 小程序会 best-effort 调 reportDeviceFirmwareUpgrade 回报后台；
      // 该接口不在 BoltFox `/Client/...` 用户前端接口内，App 侧暂不回报（如后端提供再接）。
    } on OtaAbortedException {
      if (!mounted) return;
      setState(() {
        _stage = _OtaStage.failed;
        _statusText = dryRun ? '干跑失败' : '升级失败';
        _errorMessage = '升级已中断：升级过程中手机切到后台或页面离开。请保持屏幕常亮后重试。';
      });
    } catch (error) {
      if (!mounted) return;
      final aborted = _aborted;
      setState(() {
        _stage = _OtaStage.failed;
        _statusText = dryRun ? '干跑失败' : '升级失败';
        _errorMessage = aborted
            ? '升级已中断：升级过程中手机切到后台或页面离开。请保持屏幕常亮后重试。'
            : error.toString();
      });
    }
  }

  static String _ellipsis(String s, int max) => s.length <= max ? s : s.substring(0, max);

  // ── 视图 ─────────────────────────────────────────────────
  bool get _canUpgrade =>
      _stage != _OtaStage.upgrading && _hasPackage && _connected;

  bool get _canDryRun => _stage != _OtaStage.upgrading;

  String get _actionText {
    switch (_stage) {
      case _OtaStage.upgrading:
        return '升级中';
      case _OtaStage.available:
        return _connected ? '立即升级' : '设备未连接';
      case _OtaStage.invalid:
        return '无法升级';
      case _OtaStage.failed:
        return '重新检查';
      case _OtaStage.success:
        return '已完成';
      case _OtaStage.latest:
        return '已是最新';
      case _OtaStage.checking:
        return '检查中';
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
    if (_stage == _OtaStage.checking) {
      return const FigmaScreen(
        title: 'OTA升级',
        body: Padding(
          padding: EdgeInsets.only(top: 120),
          child: Center(
            child: Text('正在检查固件版本...',
                style: TextStyle(color: Color(0xFF808690))),
          ),
        ),
      );
    }

    // 无真实升级包/未连接时，展示「干跑测试」入口，方便无硬件时验证编码链路。
    final showDryRun = _canDryRun && (!_hasPackage || !_connected);

    return FigmaScreen(
      title: 'OTA升级',
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
          const Text(
            '升级过程中请保持设备供电、手机屏幕常亮，并避免切换到后台。',
            style: TextStyle(color: Color(0xFF808690), fontSize: 12, height: 1.5),
          ),
          const SizedBox(height: 16),
          if (showDryRun)
            FigmaSecondaryButton(
              label: '干跑测试（mock 固件）',
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
                Text('当前版本 $_currentVersion',
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
    return FigmaGlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('固件版本 $_latestVersion',
              style: const TextStyle(
                  color: Color(0xFF2A2D32), fontSize: 14, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text('升级包 $_packageSizeText',
              style: const TextStyle(color: Color(0xFF808690), fontSize: 12)),
          const SizedBox(height: 14),
          FigmaProgressBar(
            progress: _progress,
            label:
                '${_progressText.isNotEmpty ? _progressText : (_stage == _OtaStage.available ? '可开始升级' : '无需升级')}  ·  ${(_progress * 100).round()}%',
          ),
        ],
      ),
    );
  }

  Widget _notesCard() {
    return FigmaGlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('升级内容',
              style: TextStyle(
                  color: Color(0xFF2A2D32), fontSize: 14, fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          if (_releaseNotes.isEmpty)
            const Text('暂无升级说明',
                style: TextStyle(color: Color(0xFF808690), fontSize: 12))
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
