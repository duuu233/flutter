import 'dart:async';

import 'package:flutter/material.dart';

import '../../../network/iot/iot_api.dart';
import '../../../network/iot/iot_ws.dart';
import '../../../shared/l10n/app_l10n.dart';
import '../../../shared/widgets/figma_common.dart';
import '../../../state.dart';
import '../wifi_cast_entry.dart';
import '../wifi_l10n.dart';
import '../wifi_status.dart';
import '../wifi_widgets.dart';

/// WiFi 版设备详情，同步小程序 `subpackages/device/wifi-detail`（对接进度 STEP 4 设备查询 + STEP 3 投屏入口）。
///
/// 蓝牙版详情（[DeviceDetailsPage]）全是蓝牙能力（连接、读 0x01、轮播、清空、OTA），WiFi 版一个都用不上，单独成页：
///   · 设备记录：设备列表里的这一条（名称、设备 ID、尺寸、设备图）；
///   · 状态：IoT GET /api/device/info（在线、最后上线、固件版本、影子：电量 / WiFi 信号与名称 / TF / 国家码 / 最后心跳）；
///     订阅 WS device.status，上下线时自动重查（只推信号不推详情）；
///   · 操作：「投屏」（拍照 / 相册 → 预览构图 → WiFi 投屏结果页）、「刷新状态」。
/// 轮播、刷新屏幕、TF、休眠、OTA 等设备控制属于后续 STEP，未接；App 也没有删除 / 重新配网操作。
class WifiDeviceDetailPage extends StatefulWidget {
  const WifiDeviceDetailPage({super.key, required this.state, required this.deviceId});

  final PhotoFrameState state;
  final String deviceId;

  @override
  State<WifiDeviceDetailPage> createState() => _WifiDeviceDetailPageState();
}

class _WifiDeviceDetailPageState extends State<WifiDeviceDetailPage> {
  StreamSubscription<Map<String, dynamic>>? _statusSub;
  String _subscribed = '';

  DeviceItem get _device => widget.state.deviceById(widget.deviceId);

  String get _deviceNo => IotApi.plainDeviceNo(_device.serialNumber);

  @override
  void initState() {
    super.initState();
    // 上下线推送：只推信号，收到就重查一次（需先订阅）
    _statusSub = IotWs.instance.on('device.status').listen((event) {
      if (IotApi.plainDeviceNo(event['deviceNo']) == _deviceNo) {
        WifiStatusStore.instance.refresh(_device);
      }
    });
    final deviceNo = _deviceNo;
    if (deviceNo.isNotEmpty && !IotWs.instance.subscriptions.contains(deviceNo)) {
      IotWs.instance.subscribe(deviceNo);
      _subscribed = deviceNo;
    }
    // 推到首帧之后：refresh 会同步 notify，构建期间通知会让下层页面的监听者在 build 中 setState
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        WifiStatusStore.instance.refresh(_device);
      }
    });
  }

  @override
  void dispose() {
    unawaited(_statusSub?.cancel());
    if (_subscribed.isNotEmpty) {
      IotWs.instance.unsubscribe(_subscribed);
    }
    super.dispose();
  }

  void _refreshTap() {
    final store = WifiStatusStore.instance;
    if (store.of(widget.deviceId).status == WifiOnlineStatus.loading) {
      return;
    }
    store.refresh(_device, showLoading: true);
  }

  String _tfText(AppL10n l10n, Map<String, dynamic> shadow) {
    final status = '${shadow['tfStatus'] ?? ''}';
    if (status == 'absent') return l10n.wifiTfAbsent;
    if (status != 'present') return '';
    final total = num.tryParse('${shadow['tfTotal'] ?? ''}') ?? 0;
    final used = num.tryParse('${shadow['tfUsed'] ?? ''}') ?? 0;
    return total > 0 ? l10n.wifiTfUsage(used, total) : l10n.wifiTfPresent;
  }

  String _countryText(AppL10n l10n, Object? code) {
    final value = '${code ?? ''}'.trim();
    if (value.isEmpty) return '';
    return value == '1' || value == '01' ? l10n.wifiCountryWorld : value;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([widget.state, WifiStatusStore.instance]),
      builder: (context, _) {
        final device = _device;
        final status = WifiStatusStore.instance.of(device.id);
        final online = status.online;
        final shadow = status.shadow;
        final info = status.info;
        final rssi = num.tryParse('${shadow['wifiRssi'] ?? ''}');
        final known = status.status == WifiOnlineStatus.online || status.status == WifiOnlineStatus.offline;
        final rows = <({String label, String value, Widget? leading})>[
          (
            label: l10n.wifiRowBattery,
            value: online && status.battery != null ? '${status.battery}%' : '',
            leading: null,
          ),
          (
            label: l10n.wifiRowSignal,
            value: online && rssi != null && rssi < 0 ? '${rssi.round()}dBm' : '',
            leading: online && status.signalBars > 0 ? SignalBars(level: status.signalBars) : null,
          ),
          (label: l10n.wifiRowName, value: '${shadow['wifiName'] ?? ''}', leading: null),
          (
            label: l10n.wifiRowVersion,
            value: '${info['firmwareVersion'] ?? shadow['espVersion'] ?? shadow['version'] ?? ''}',
            leading: null,
          ),
          (label: l10n.wifiRowTf, value: _tfText(l10n, shadow), leading: null),
          (label: l10n.wifiRowCountry, value: _countryText(l10n, shadow['countryCode']), leading: null),
          (label: l10n.wifiRowLastOnline, value: '${info['lastOnlineAt'] ?? ''}', leading: null),
          (label: l10n.wifiRowLastHeart, value: '${shadow['lastHeartAt'] ?? ''}', leading: null),
        ];
        final stateColor = switch (status.status) {
          WifiOnlineStatus.online => kWifiGreen,
          WifiOnlineStatus.offline => const Color(0xFF9BA2AD),
          _ => const Color(0xFF8B9098),
        };
        return FigmaScreen(
          title: l10n.wifiDetailTitle,
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 16),
              FigmaGlassCard(
                borderRadius: 18,
                padding: const EdgeInsets.all(18),
                child: Row(
                  children: [
                    Image.asset(
                      device.thumbAsset,
                      width: 64,
                      height: 64,
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) =>
                          const Icon(Icons.photo_library_outlined, color: Color(0xFFEB5F1B), size: 34),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  device.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Color(0xFF2A2D32),
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              CommBadge.plain(context, wifi: true),
                            ],
                          ),
                          if (device.serialNumber.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(
                              '${l10n.devDeviceId} ${device.serialNumber}',
                              style: const TextStyle(color: Color(0xFF8B9098), fontSize: 12),
                            ),
                          ],
                          if (device.sizeModel.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              '${l10n.wifiScreenSize} ${device.sizeModel}',
                              style: const TextStyle(color: Color(0xFF8B9098), fontSize: 12),
                            ),
                          ],
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              if (status.status == WifiOnlineStatus.loading)
                                const WifiMiniSpinner(size: 10)
                              else
                                Container(
                                  width: 7,
                                  height: 7,
                                  decoration: BoxDecoration(color: stateColor, shape: BoxShape.circle),
                                ),
                              const SizedBox(width: 6),
                              Text(status.text(l10n), style: TextStyle(color: stateColor, fontSize: 13)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (known) ...[
                const SizedBox(height: 14),
                FigmaGlassCard(
                  borderRadius: 18,
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
                  child: Column(
                    children: [
                      for (final row in rows)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          child: Row(
                            children: [
                              Text(row.label, style: const TextStyle(color: Color(0xFF5E6470), fontSize: 14)),
                              const Spacer(),
                              if (row.leading != null) ...[row.leading!, const SizedBox(width: 6)],
                              Flexible(
                                child: Text(
                                  row.value.isNotEmpty ? row.value : '--',
                                  textAlign: TextAlign.right,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: Color(0xFF2A2D32), fontSize: 14),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 14),
              WifiActionBar(
                castLabel: l10n.devCast,
                refreshLabel: l10n.wifiRefreshStatus,
                refreshing: status.status == WifiOnlineStatus.loading,
                onCast: () => startWifiCast(context, widget.state, device),
                onRefresh: _refreshTap,
              ),
              const SizedBox(height: 24),
            ],
          ),
        );
      },
    );
  }
}

/// WiFi 版设备的操作栏「投屏 | 刷新状态」（我的设备卡片与 WiFi 设备详情共用，同蓝牙版卡片的操作栏样式）。
class WifiActionBar extends StatelessWidget {
  const WifiActionBar({
    super.key,
    required this.castLabel,
    required this.refreshLabel,
    required this.refreshing,
    required this.onCast,
    required this.onRefresh,
  });

  final String castLabel;
  final String refreshLabel;
  final bool refreshing;
  final VoidCallback onCast;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    Widget action({
      required Widget icon,
      required String label,
      required Color color,
      required VoidCallback onTap,
    }) {
      return Expanded(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              icon,
              const SizedBox(width: 5),
              Text(label, style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.w500, height: 1)),
            ],
          ),
        ),
      );
    }

    return Container(
      height: 42,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.31)),
        boxShadow: const [
          BoxShadow(color: Color.fromRGBO(44, 63, 97, 0.03), offset: Offset(0, 4), blurRadius: 12.1),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          action(
            icon: Image.asset(
              'assets/images/screen-casting-icon01.png',
              width: 20,
              height: 20,
              errorBuilder: (context, error, stackTrace) =>
                  const Icon(Icons.cast_rounded, size: 16, color: Color(0xFFEB5F1B)),
            ),
            label: castLabel,
            color: const Color(0xFFEB5F1B),
            onTap: onCast,
          ),
          const Center(
            child: SizedBox(width: 1, height: 19, child: ColoredBox(color: Color(0xFFDADDDF))),
          ),
          action(
            icon: Opacity(
              opacity: refreshing ? 0.4 : 1,
              child: Image.asset(
                'assets/images/refresh-icon.png',
                width: 18,
                height: 18,
                errorBuilder: (context, error, stackTrace) =>
                    const Icon(Icons.refresh_rounded, size: 16, color: kWifiGreen),
              ),
            ),
            label: refreshLabel,
            color: refreshing ? const Color(0xFF9BA2AD) : kWifiGreen,
            onTap: onRefresh,
          ),
        ],
      ),
    );
  }
}
