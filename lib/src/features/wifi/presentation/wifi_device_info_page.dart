import 'package:flutter/material.dart';

import '../../../shared/l10n/app_l10n.dart';
import '../../../shared/widgets/figma_common.dart';
import '../../../state.dart';
import '../wifi_l10n.dart';
import '../wifi_status.dart';
import '../wifi_widgets.dart';

/// WiFi 版「设备信息」二级页（2026-10-29，同小程序 `subpackages/device/wifi-info`，原详情页的信息行挪到这里）：
/// WiFi信号、WiFi名称、最后上线、最后心跳、固件版本；不再显示国家码。
/// 数据沿用 [WifiStatusStore]（IoT GET /api/device/info），进页重查一次；非在线时信号不显示（本地模式影子冻结）。
class WifiDeviceInfoPage extends StatefulWidget {
  const WifiDeviceInfoPage({super.key, required this.state, required this.deviceId});

  final PhotoFrameState state;
  final String deviceId;

  @override
  State<WifiDeviceInfoPage> createState() => _WifiDeviceInfoPageState();
}

class _WifiDeviceInfoPageState extends State<WifiDeviceInfoPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        WifiStatusStore.instance.refresh(widget.state.deviceById(widget.deviceId));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    return ListenableBuilder(
      listenable: WifiStatusStore.instance,
      builder: (context, _) {
        final status = WifiStatusStore.instance.of(widget.deviceId);
        final shadow = status.shadow;
        final info = status.info;
        final online = status.online;
        final rssi = num.tryParse('${shadow['wifiRssi'] ?? ''}');
        final rows = <({String label, String value, Widget? leading})>[
          (
            label: l10n.wifiRowSignal,
            value: online && rssi != null && rssi < 0 ? '${rssi.round()}dBm' : '',
            leading: online && status.signalBars > 0 ? SignalBars(level: status.signalBars) : null,
          ),
          (label: l10n.wifiRowName, value: '${shadow['wifiName'] ?? ''}', leading: null),
          (label: l10n.wifiRowLastOnline, value: '${info['lastOnlineAt'] ?? ''}', leading: null),
          (label: l10n.wifiRowLastHeart, value: '${shadow['lastHeartAt'] ?? ''}', leading: null),
          (
            label: l10n.wifiRowVersion,
            value: '${info['firmwareVersion'] ?? shadow['espVersion'] ?? shadow['version'] ?? ''}',
            leading: null,
          ),
        ];
        return FigmaScreen(
          title: l10n.wifiDeviceInfo,
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 16),
              if (status.status == WifiOnlineStatus.loading)
                const Padding(padding: EdgeInsets.only(top: 80), child: Center(child: CircularProgressIndicator()))
              else
                FigmaGlassCard(
                  borderRadius: 18,
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
                  child: Column(
                    children: [
                      for (final row in rows)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Row(
                            children: [
                              Text(row.label, style: const TextStyle(color: Color(0xFF5E6470), fontSize: 14)),
                              const Spacer(),
                              if (row.leading != null) ...[row.leading!, const SizedBox(width: 6)],
                              Flexible(
                                child: Text(
                                  row.value.isNotEmpty && row.value != 'null' ? row.value : '--',
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
              const SizedBox(height: 24),
            ],
          ),
        );
      },
    );
  }
}
