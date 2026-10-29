import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../network/boltfox_api.dart';
import '../../../network/iot/iot_api.dart';
import '../../../network/iot/iot_ws.dart';
import '../../../routes/app_routes.dart';
import '../../../shared/l10n/app_l10n.dart';
import '../../../shared/widgets/app_toast.dart';
import '../../../shared/widgets/figma_common.dart';
import '../../../state.dart';
import '../wifi_cast_entry.dart';
import '../wifi_l10n.dart';
import '../wifi_share.dart';
import '../wifi_status.dart';
import '../wifi_tf.dart';
import '../wifi_widgets.dart';
import 'wifi_device_info_page.dart';
import 'wifi_messages_page.dart';
import 'wifi_remove_flow.dart';
import 'wifi_share_page.dart';
import 'wifi_sleep_page.dart';
import 'wifi_tf_page.dart';

/// WiFi 版设备详情，同步小程序 `subpackages/device/wifi-detail`（2026-10-27 建页；2026-10-29 按产品要求改版，布局与蓝牙版详情对齐）。
///
/// 蓝牙版详情（[DeviceDetailsPage]）全是蓝牙能力，WiFi 版单独成页：
///   · 设备记录：设备列表里的这一条（名称、设备 ID、尺寸、设备图）；所有者身份另查 getUserProductDetail（isToHave / shareUserId）；
///   · 状态：IoT GET /api/device/info，订阅 WS device.status，上下线时自动重查；电量放在在线状态那一栏（仅在线时显示）；
///   · 设备卡下方「投屏 | 轮播设置」（与蓝牙版位置一致）；
///   · 功能栏依次：设备信息（[WifiDeviceInfoPage]）、休眠设置、消息中心（未读角标）、TF卡（未插卡不可点；有卡显示已用/总量，
///     进 [WifiTfPage]）、分享设备（仅所有者，[WifiSharePage]）、解除绑定（只删设备）；页底「删除设备」（仅所有者，
///     样式与弹窗同蓝牙版，先删云端图片再删设备，见 wifi_remove_flow.dart）；
///   · 本地模式（status=LOCAL_TF）：投屏 / 轮播设置 / TF卡 可以点，但只提示「当前设备状态：本地模式，请恢复设备网络再试」；
///     设备信息、休眠设置、消息中心、分享、解绑、删除照常。WiFi 版暂无 OTA 入口。
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

  /// 是否所有者：查到详情前按否（分享 / 删除入口先不出），避免成员误删所有者的云端照片。
  bool _isOwner = false;

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
        _loadOwner();
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

  /// 查设备详情里的 isToHave / shareUserId 判定所有者；查不到保持「否」。
  Future<void> _loadOwner() async {
    bool owner;
    try {
      final data = await BoltFoxApi.getUserProductDetail(userProductId: widget.deviceId);
      if (data is! Map) {
        return;
      }
      owner = wifiIsOwner(data.map((k, v) => MapEntry(k.toString(), v)));
    } catch (error) {
      debugPrint('[WiFi详情] 所有者查询失败 $error');
      return;
    }
    if (mounted) {
      setState(() => _isOwner = owner);
    }
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

  void _push(Widget page) {
    Navigator.of(context).push<void>(AppPageRoute(builder: (_) => page));
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

  /// 「TF卡」：未插卡 / 没上报过不可点；本地模式只提示；有卡进 TF 卡设置。
  void _openTf(WifiOnlineStatus status, WifiTfState tf) {
    if (tf != WifiTfState.present) {
      return;
    }
    if (status == WifiOnlineStatus.local) {
      AppToast.warn(context, AppL10n.of(context).wifiLocalTip);
      return;
    }
    _push(WifiTfPage(state: widget.state, deviceId: widget.deviceId));
  }

  Widget _buildEntries(AppL10n l10n, WifiDeviceStatus status) {
    final tf = wifiTfState(l10n, status.shadow);
    Widget entry(
      String label,
      VoidCallback onTap, {
      Widget? trailing,
      String value = '',
      bool chevron = true,
      Color labelColor = const Color(0xFF33373D),
      FontWeight labelWeight = FontWeight.w600,
    }) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          height: 50,
          child: Row(
            children: [
              Text(label, style: TextStyle(color: labelColor, fontSize: 14, fontWeight: labelWeight)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  value,
                  textAlign: TextAlign.right,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Color(0xFF777E88), fontSize: 13),
                ),
              ),
              if (trailing != null) ...[const SizedBox(width: 8), trailing],
              if (chevron) ...[
                const SizedBox(width: 6),
                const Icon(Icons.chevron_right_rounded, size: 20, color: Color(0xFF777E88)),
              ],
            ],
          ),
        ),
      );
    }

    const divider = Divider(height: 1, thickness: 0.5, color: Color(0x0F2A2B2B));
    return FigmaGlassCard(
      borderRadius: 18,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Column(
        children: [
          entry(l10n.wifiDeviceInfo, () => _push(WifiDeviceInfoPage(state: widget.state, deviceId: widget.deviceId))),
          divider,
          entry(l10n.wifiSleepSettings, () => _push(WifiSleepPage(state: widget.state, deviceId: widget.deviceId))),
          divider,
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
          divider,
          // TF卡：未插卡不可点；有卡显示已用/总量 + 箭头
          entry(
            l10n.wifiRowTf,
            () => _openTf(status.status, tf.state),
            value: tf.text,
            chevron: tf.state == WifiTfState.present,
          ),
          if (_isOwner) ...[
            divider,
            entry(l10n.wifiShareDevice, () => _push(WifiSharePage(state: widget.state, deviceId: widget.deviceId))),
          ],
          divider,
          // 解除绑定：红字，同蓝牙版；只删设备记录，照片保留
          entry(
            l10n.devUnbindDevice,
            () => startWifiUnbindFlow(context, widget.state, _device),
            value: l10n.devUnbindDeviceValue,
            labelColor: const Color(0xFFFF3045),
            labelWeight: FontWeight.w500,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([widget.state, WifiStatusStore.instance]),
      builder: (context, _) {
        final device = _device;
        final status = WifiStatusStore.instance.of(device.id);
        final battery = status.online ? status.battery : null;
        final stateColor = switch (status.status) {
          WifiOnlineStatus.online => kWifiGreen,
          WifiOnlineStatus.sleeping => kWifiSleepBlue,
          WifiOnlineStatus.local => kWifiLocalPurple,
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
                          // 状态与电量一栏（2026-10-29，与蓝牙版一致），电量仅在线时显示
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
                              if (battery != null) ...[
                                const SizedBox(width: 14),
                                Image.asset(
                                  _batteryAsset(battery),
                                  width: 24,
                                  fit: BoxFit.contain,
                                  errorBuilder: (context, error, stackTrace) =>
                                      const Icon(Icons.battery_std_rounded, size: 14, color: Color(0xFF2A2D32)),
                                ),
                                const SizedBox(width: 4),
                                Text('$battery%', style: const TextStyle(color: Color(0xFF2A2D32), fontSize: 13)),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              // 投屏 / 轮播设置放在设备卡与功能栏之间（与蓝牙版位置一致）
              const SizedBox(height: 14),
              WifiActionBar(
                castLabel: l10n.devCast,
                slideshowLabel: l10n.wifiSlideshowSettings,
                onCast: () => startWifiCast(context, widget.state, device),
                onSlideshow: () => openWifiSlideshow(context, widget.state, device),
              ),
              const SizedBox(height: 14),
              _buildEntries(l10n, status),
              // 删除设备（仅所有者）：页底独立入口，样式同蓝牙版 _OutlineDeleteDeviceButton
              if (_isOwner) ...[
                const SizedBox(height: 32),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => startWifiDeleteFlow(context, widget.state, device),
                  child: SizedBox(
                    height: 56,
                    child: Center(
                      child: Text(
                        l10n.devDeleteDevice,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFFFF3045),
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          height: 1.2,
                        ),
                      ),
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

/// 电量 → `BatteryLevel/battery-{档}.png`（按 10 取最近档，同我的设备卡片）。
String _batteryAsset(int battery) => 'assets/images/BatteryLevel/battery-${((math.min(100, math.max(0, battery)) + 5) ~/ 10) * 10}.png';

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
