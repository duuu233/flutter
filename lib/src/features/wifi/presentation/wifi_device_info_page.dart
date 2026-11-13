import 'package:flutter/material.dart';

import '../../../routes/app_routes.dart';
import '../../../shared/l10n/app_l10n.dart';
import '../../../shared/widgets/app_widgets.dart';
import '../../../shared/widgets/figma_common.dart';
import '../../../state.dart';
import '../wifi_fpga.dart';
import '../wifi_l10n.dart';
import '../wifi_status.dart';
import '../wifi_widgets.dart';
import 'wifi_ota_page.dart';

/// WiFi 版「设备信息」二级页（2026-10-29，同小程序 `subpackages/device/wifi-info`，原详情页的信息行挪到这里）：
/// WiFi信号、WiFi名称、最后上线、最后心跳、固件版本；不再显示国家码。
/// 数据沿用 [WifiStatusStore]（IoT GET /api/device/info），进页重查一次；非在线时信号不显示（本地模式影子冻结）。
/// 2026-11-13：产品渲染模式 = fpga16 的设备多一个「优雅刷新升级」入口（原名渲染固件管理），直接进 [WifiOtaPage] 安装模式；
/// 2026-11-14 起不做红点。设备不上报 FPGA 版本，不显示版本号。
/// 2026-11-14：入口不再等网络——设备详情页解析过的渲染模式（[PhotoFrameState.cachedRenderMode]）是 fpga16 就进页即显示，
/// 也不随信息行的加载态隐藏；进页仍重新解析一次校正。文字样式与上面信息行的标签一致（灰色、常规字重）。
class WifiDeviceInfoPage extends StatefulWidget {
  const WifiDeviceInfoPage({super.key, required this.state, required this.deviceId});

  final PhotoFrameState state;
  final String deviceId;

  @override
  State<WifiDeviceInfoPage> createState() => _WifiDeviceInfoPageState();
}

class _WifiDeviceInfoPageState extends State<WifiDeviceInfoPage> {
  /// 渲染模式 = fpga16 才显示「优雅刷新升级」。
  bool _fpga = false;

  @override
  void initState() {
    super.initState();
    final cached = widget.state.cachedRenderMode(widget.deviceId);
    if (cached != null && isFpgaRenderMode(cached)) {
      _fpga = true;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final device = widget.state.deviceById(widget.deviceId);
        WifiStatusStore.instance.refresh(device);
        _loadRenderMode(device);
      }
    });
  }

  Future<void> _loadRenderMode(DeviceItem device) async {
    String renderMode;
    try {
      renderMode = await widget.state.resolveRenderMode(device);
    } catch (_) {
      return;
    }
    final fpga = isFpgaRenderMode(renderMode);
    if (mounted && fpga != _fpga) {
      setState(() => _fpga = fpga);
    }
  }

  /// 「优雅刷新升级」：直接进安装步骤页（最新版本与版本说明在那页取设备详情）。
  /// 2026-11-14：点击即判断在线（现查一次），不在线不能进。
  Future<void> _openFpga() async {
    if (!await requireWifiOnline(context, widget.state.deviceById(widget.deviceId), fresh: true) || !mounted) {
      return;
    }
    await Navigator.of(context).push<void>(
      AppPageRoute(builder: (_) => WifiOtaPage(state: widget.state, deviceId: widget.deviceId, fpga: true)),
    );
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
                const Padding(padding: EdgeInsets.only(top: 80), child: PageLoading())
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
                              const SizedBox(width: 12),
                              // 取值吃满标签右边的全部宽度（2026-11-14：原 Spacer + Flexible 各分一半，
                              // 安卓字体略宽时「最后上线 / 最后心跳」的时间被截成 ...）
                              Expanded(
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
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
                    ],
                  ),
                ),
              // 优雅刷新升级（2026-11-13）：只有渲染模式 = fpga16 的设备才有
              if (_fpga) ...[
                const SizedBox(height: 12),
                GestureDetector(
                  key: const ValueKey('wifi-fpga-entry'),
                  behavior: HitTestBehavior.opaque,
                  onTap: _openFpga,
                  child: FigmaGlassCard(
                    borderRadius: 18,
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                    child: Row(
                      children: [
                        Text(
                          l10n.wifiFpgaManage,
                          // 与上面信息行的标签同样式（2026-11-14）
                          style: const TextStyle(color: Color(0xFF5E6470), fontSize: 14),
                        ),
                        const Spacer(),
                        const Icon(Icons.chevron_right_rounded, size: 20, color: Color(0xFF777E88)),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 24),
            ],
          ),
        );
      },
    );
  }
}
