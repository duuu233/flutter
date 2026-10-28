import 'dart:async';

import 'package:flutter/material.dart';

import '../../../network/iot/iot_api.dart';
import '../../../network/iot/iot_ws.dart';
import '../../../routes/app_routes.dart';
import '../../../shared/l10n/app_l10n.dart';
import '../../../shared/widgets/figma_common.dart';
import '../../../state.dart';
import '../wifi_cast_entry.dart';
import '../wifi_l10n.dart';
import '../wifi_status.dart';
import '../wifi_widgets.dart';
import 'wifi_messages_page.dart';
import 'wifi_sleep_page.dart';
import 'wifi_slideshow_page.dart';

/// WiFi 版设备详情，同步小程序 `subpackages/device/wifi-detail`（对接进度 STEP 4 设备查询 + STEP 3 投屏入口）。
///
/// 蓝牙版详情（[DeviceDetailsPage]）全是蓝牙能力（连接、读 0x01、轮播、清空、OTA），WiFi 版一个都用不上，单独成页：
///   · 设备记录：设备列表里的这一条（名称、设备 ID、尺寸、设备图）；
///   · 状态：IoT GET /api/device/info（在线、最后上线、固件版本、影子：电量 / WiFi 信号与名称 / TF / 国家码 / 最后心跳）；
///     订阅 WS device.status，上下线时自动重查（只推信号不推详情）；
///   · 操作：「投屏」（拍照 / 相册 → 预览构图 → WiFi 投屏结果页）、「轮播设置」（V1.4 更新说明 1.5，取代原「刷新状态」，
///     进 [WifiSlideshowPage]；状态随进页与 WS device.status 自动重查）；
///   · 入口（V1.4 实现报告反馈二 / 三）：「休眠设置」进 [WifiSleepPage]；「消息中心」进 [WifiMessagesPage]，带未读角标
///     （IoT GET /api/notification/unread-count，进页时、从消息中心返回时查，收到本设备 WS notification.new 再查）。
/// 刷新屏幕、TF、OTA 等设备控制属于后续 STEP，未接；App 也没有删除 / 重新配网操作。
class WifiDeviceDetailPage extends StatefulWidget {
  const WifiDeviceDetailPage({super.key, required this.state, required this.deviceId});

  final PhotoFrameState state;
  final String deviceId;

  @override
  State<WifiDeviceDetailPage> createState() => _WifiDeviceDetailPageState();
}

class _WifiDeviceDetailPageState extends State<WifiDeviceDetailPage> {
  StreamSubscription<Map<String, dynamic>>? _statusSub;
  StreamSubscription<Map<String, dynamic>>? _noticeSub;
  String _subscribed = '';
  int _unreadCount = 0;

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
    // 新消息只推信号：收到就重查未读数
    _noticeSub = IotWs.instance.on('notification.new').listen((event) {
      if (IotApi.plainDeviceNo(event['deviceNo']) == _deviceNo) {
        _refreshUnread();
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
        _refreshUnread();
      }
    });
  }

  @override
  void dispose() {
    unawaited(_statusSub?.cancel());
    unawaited(_noticeSub?.cancel());
    if (_subscribed.isNotEmpty) {
      IotWs.instance.unsubscribe(_subscribed);
    }
    super.dispose();
  }

  /// 消息中心未读角标；查不到不显示，不弹错。
  Future<void> _refreshUnread() async {
    final deviceNo = _deviceNo;
    if (deviceNo.isEmpty) {
      return;
    }
    int count;
    try {
      count = (num.tryParse('${(await IotApi.getUnreadCount(deviceNo))['unreadCount'] ?? 0}') ?? 0).toInt();
    } catch (error) {
      debugPrint('[WiFi消息] 未读数查询失败 $error');
      return;
    }
    if (mounted) {
      setState(() => _unreadCount = count);
    }
  }

  /// 「轮播设置」：查询离线也能看，不拦状态；保存时由接口裁决。
  void _openSlideshow() {
    Navigator.of(context).push<void>(
      AppPageRoute(builder: (_) => WifiSlideshowPage(state: widget.state, deviceId: widget.deviceId)),
    );
  }

  void _openSleep() {
    Navigator.of(context).push<void>(
      AppPageRoute(builder: (_) => WifiSleepPage(state: widget.state, deviceId: widget.deviceId)),
    );
  }

  Future<void> _openMessages() async {
    await Navigator.of(context).push<void>(
      AppPageRoute(builder: (_) => WifiMessagesPage(deviceNo: _deviceNo)),
    );
    // 消息中心里标了已读：回来重查角标
    if (mounted) {
      _refreshUnread();
    }
  }

  Widget _buildEntries(AppL10n l10n) {
    Widget entry(String label, VoidCallback onTap, {Widget? trailing}) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          height: 50,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(color: Color(0xFF33373D), fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ),
              if (trailing != null) ...[trailing, const SizedBox(width: 8)],
              const Icon(Icons.chevron_right_rounded, size: 20, color: Color(0xFF777E88)),
            ],
          ),
        ),
      );
    }

    return FigmaGlassCard(
      borderRadius: 18,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Column(
        children: [
          entry(l10n.wifiSleepSettings, _openSleep),
          const Divider(height: 1, thickness: 0.5, color: Color(0x0F2A2B2B)),
          entry(
            l10n.wifiMessageCenter,
            _openMessages,
            trailing: _unreadCount > 0
                ? Container(
                    constraints: const BoxConstraints(minWidth: 18),
                    height: 18,
                    padding: const EdgeInsets.symmetric(horizontal: 5),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: const Color(0xFFE5533D), borderRadius: BorderRadius.circular(999)),
                    child: Text(
                      _unreadCount > 99 ? '99+' : '$_unreadCount',
                      style: const TextStyle(color: Colors.white, fontSize: 11, height: 1),
                    ),
                  )
                : null,
          ),
        ],
      ),
    );
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
        final known = status.status != WifiOnlineStatus.loading && status.status != WifiOnlineStatus.unknown;
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
          WifiOnlineStatus.sleeping => kWifiSleepBlue,
          WifiOnlineStatus.offline || WifiOnlineStatus.shutdown => const Color(0xFF9BA2AD),
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
                slideshowLabel: l10n.wifiSlideshowSettings,
                onCast: () => startWifiCast(context, widget.state, device),
                onSlideshow: _openSlideshow,
              ),
              const SizedBox(height: 14),
              _buildEntries(l10n),
              const SizedBox(height: 24),
            ],
          ),
        );
      },
    );
  }
}

/// WiFi 版设备的操作栏「投屏 | 轮播设置」（我的设备卡片与 WiFi 设备详情共用，同蓝牙版卡片的操作栏样式）。
/// V1.4 更新说明 1.5：原「刷新状态」改为「轮播设置」；状态随进页与 WS device.status 自动重查。
class WifiActionBar extends StatelessWidget {
  const WifiActionBar({
    super.key,
    required this.castLabel,
    required this.slideshowLabel,
    required this.onCast,
    required this.onSlideshow,
  });

  final String castLabel;
  final String slideshowLabel;
  final VoidCallback onCast;
  final VoidCallback onSlideshow;

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
            icon: Image.asset(
              'assets/images/device-detail-icon01.png',
              width: 18,
              height: 18,
              errorBuilder: (context, error, stackTrace) =>
                  const Icon(Icons.slideshow_rounded, size: 16, color: kWifiGreen),
            ),
            label: slideshowLabel,
            color: kWifiGreen,
            onTap: onSlideshow,
          ),
        ],
      ),
    );
  }
}
