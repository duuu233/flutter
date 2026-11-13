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
import '../wifi_ota.dart';
import '../wifi_share.dart';
import '../wifi_status.dart';
import '../wifi_tf.dart';
import '../wifi_widgets.dart';
import 'wifi_device_info_page.dart';
import 'wifi_messages_page.dart';
import 'wifi_ota_page.dart';
import 'wifi_remove_flow.dart';
import 'wifi_share_page.dart';
import 'wifi_tf_page.dart';
import '../../../shared/tap_guard.dart';
import '../../devices/firmware_gate.dart';

/// WiFi 版设备详情，同步小程序 `subpackages/device/wifi-detail`（2026-10-27 建页；2026-10-29 按产品要求改版，布局与蓝牙版详情对齐）。
///
/// 蓝牙版详情（[DeviceDetailsPage]）全是蓝牙能力，WiFi 版单独成页：
///   · 设备记录：设备列表里的这一条（名称、设备 ID、尺寸、设备图）；所有者身份另查 getUserProductDetail（isToHave / shareUserId）；
///   · 状态：IoT GET /api/device/info，订阅 WS device.status，上下线时自动重查；电量放在在线状态那一栏（仅在线时显示）；
///   · 设备卡下方「投屏 | 轮播设置」（与蓝牙版位置一致）；
///   · 功能栏依次：设备信息（[WifiDeviceInfoPage]）、设备ID、屏幕尺寸、消息中心（未读红点，2026-11-06 起不显示数字）、
///     固件升级、TF卡（未插卡不可点；有卡显示已用/总量，进 [WifiTfPage]）、共享设备（2026-11-05 起所有者与接收者都显示，
///     [WifiSharePage]，接收者只看不改）。休眠设置入口 2026-11-09 按产品要求隐藏（[WifiSleepPage] 保留，恢复时把入口加回功能栏即可）；
///   · 功能栏下一张卡片（2026-11-09，布局样式同蓝牙版详情的操作卡片）：一键清空（仅所有者：清相册记录 → 删全部云端图片 →
///     恢复内置图片，设备记录保留）+ 解除绑定（只删设备记录）；页底「删除设备」（仅所有者，样式与弹窗同蓝牙版，
///     先删云端图片、再恢复内置图片（2026-11-06）、最后删设备，见 wifi_remove_flow.dart）；
///   · 轮播中标记（2026-11-05，同小程序）：只在 running 且设备在线时显示，图标换绿色版 + 右上角绿点，去掉「轮播中」文字；
///   · 本地模式（status=LOCAL_TF）：投屏 / 轮播设置 / TF卡 可以点，但只提示「当前设备状态：本地模式，请恢复设备网络再试」；
///     设备信息、休眠设置、消息中心、分享、解绑、删除照常。
///   · 固件升级（2026-11-02，同小程序）：「消息中心」之后，右侧当前固件版本，有新版本亮红点；本机有进行中的升级显示「升级中」，进 [WifiOtaPage]。
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
  StreamSubscription<Map<String, dynamic>>? _otaSub;

  /// 本机有这台设备进行中的固件升级（ota_inflight 记录）：「固件升级」行显示「升级中」、不亮红点。
  bool _otaInflight = false;
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
    // 升级状态推送：本地进行中的记录随之更新 / 清掉，「固件升级」行跟着刷新（2026-11-02 同小程序）
    _otaSub = IotWs.instance.on('ota.result').listen((event) {
      if (IotApi.plainDeviceNo(event['deviceNo']) == _deviceNo) {
        _refreshOta(query: true);
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
        final status = WifiStatusStore.instance.refresh(_device);
        // 轮播中标记：每次进页查一次（2026-11-02 同小程序）
        WifiSlideshowStore.instance.refresh(_device);
        // 固件升级行：目标版本 / 升级包来自设备详情接口，先核对本地进行中的升级
        final firmware = widget.state.fetchDeviceFirmwareInfo(widget.deviceId);
        // 先解析一次渲染模式（会话内按设备记下）：设备信息页据此进页即显示「优雅刷新升级」入口，不用等网络
        unawaited(widget.state.resolveRenderMode(_device).catchError((Object _) => ''));
        final ota = _refreshOta(query: true);
        _refreshUnread();
        _loadOwner();
        // 固件升级强提醒（2026-11-13）：状态、版本、进行中记录三样都回来后判断一次（进入后）
        unawaited(_checkFirmwareOnEnter(Future.wait<Object?>([status, firmware, ota])));
      }
    });
  }

  @override
  void dispose() {
    unawaited(_statusSub?.cancel());
    unawaited(_noticeSub?.cancel());
    unawaited(_otaSub?.cancel());
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

  /// 「固件升级」行。[query]=true 时先向服务端核对本地进行中的升级（终态 / 4044 会清掉记录）。
  Future<void> _refreshOta({bool query = false}) async {
    final deviceNo = _deviceNo;
    if (deviceNo.isEmpty) {
      return;
    }
    var inflight = await WifiOtaStore.read(deviceNo);
    if (inflight != null && query) {
      inflight = (await WifiOtaStore.refresh(deviceNo)).record;
    }
    if (mounted && _otaInflight != (inflight != null)) {
      setState(() => _otaInflight = inflight != null);
    }
  }

  // ── 固件升级强提醒（2026-11-13 产品改口，规则见 features/devices/firmware_gate.dart）──
  // 强制升级已去掉，功能按钮不再判断。在线才判断，进入后判断一次；判定与「固件升级」行红点同一套（进行中的升级不弹）。

  /// 进入后那一次判断过就不再补（回到本页、状态推送重查都不再弹）。
  bool _fwEntered = false;

  Future<void> _checkFirmwareOnEnter(Future<void> loaded) async {
    try {
      await loaded;
    } catch (_) {
      return; // 查不到就不判断
    }
    if (!mounted || _fwEntered) {
      return;
    }
    _fwEntered = true;
    final status = WifiStatusStore.instance.of(widget.deviceId);
    if (!status.online) {
      return;
    }
    // 只判强提醒（每台设备每次启动 App 只弹一次）
    final device = _device;
    await checkFirmwareGateOnEnter(context, widget.state, device,
        ready: true, hasUpdate: !_otaInflight && wifiFirmwareHasUpdate(device, wifiFirmwareVersion(status.info)));
  }

  /// 「固件升级」：进步骤页（版本检查、下发与进度都在那页；那页下发前还会再判断一次），回来刷新这一行。
  /// 2026-11-14：点击即判断在线（现查一次），不在线不能进。
  Future<void> _openOta() async {
    if (!await requireWifiOnline(context, _device, fresh: true) || !mounted) {
      return;
    }
    await Navigator.of(context).push<void>(
      AppPageRoute(builder: (_) => WifiOtaPage(state: widget.state, deviceId: widget.deviceId)),
    );
    _refreshOta();
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
          entry(
            l10n.wifiDeviceInfo,
            () => _push(WifiDeviceInfoPage(state: widget.state, deviceId: widget.deviceId)),
          ),
          // 设备信息下：设备ID、屏幕尺寸两行，只展示不可点（2026-11-02 同小程序 / 蓝牙版详情样式）；
          // 设备ID 没有显示「--」，屏幕尺寸没配整行不展示；顶部卡片不再重复显示这两项
          divider,
          entry(l10n.devDeviceId, () {}, value: _device.serialNumber.isNotEmpty ? _device.serialNumber : '--', chevron: false),
          if (_device.sizeModel.isNotEmpty) ...[
            divider,
            entry(l10n.wifiScreenSize, () {}, value: _device.sizeModel, chevron: false),
          ],
          // 休眠设置入口 2026-11-09 按产品要求隐藏（WifiSleepPage 保留，恢复时把入口加回这里即可）
          divider,
          entry(
            l10n.wifiMessageCenter,
            _openMessages,
            // 有未读只亮红点、不显示具体数字（2026-11-06，同小程序），样式同固件升级行；消息列表页不变
            trailing: _unreadCount > 0
                ? Container(
                    key: const ValueKey('wifi-unread-dot'),
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(color: Color(0xFFE5533D), shape: BoxShape.circle),
                  )
                : null,
          ),
          divider,
          // 固件升级（2026-11-02 同小程序）：右侧当前固件版本（读不到「--」）；有新版本亮红点；本机有进行中的升级显示「升级中」
          Builder(
            builder: (context) {
              final firmware = wifiFirmwareVersion(status.info);
              final hasUpdate = !_otaInflight &&
                  evaluateWifiOta(firmware, _device.newVersionNo, _device.downloadPath).state == WifiOtaCheckState.available;
              return entry(
                l10n.wifiOtaTitle,
                _openOta,
                value: _otaInflight ? l10n.wifiOtaInProgress : (firmware.isNotEmpty ? firmware : '--'),
                trailing: hasUpdate
                    ? Container(
                        key: const ValueKey('wifi-ota-dot'),
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(color: Color(0xFFE5533D), shape: BoxShape.circle),
                      )
                    : null,
              );
            },
          ),
          divider,
          // TF卡：未插卡不可点；有卡显示已用/总量 + 箭头
          entry(
            l10n.wifiRowTf,
            () => _openTf(status.status, tf.state),
            value: tf.text,
            chevron: tf.state == WifiTfState.present,
          ),
          // 共享设备（2026-11-05，同小程序）：接收者也显示；身份由 [WifiSharePage] 自己查，接收者没有移除 / 分享按钮
          divider,
          entry(l10n.wifiSharedDevice, () => _push(WifiSharePage(state: widget.state, deviceId: widget.deviceId))),
        ],
      ),
    );
  }

  /// 一键清空 + 解除绑定（2026-11-09，同小程序）：布局样式同蓝牙版详情的操作卡片（图标 + 橙 / 红字，中间细分隔线）。
  /// 2026-11-14 产品要求：两行随页面一起显示，不等所有者查询（[_loadOwner] 约 1 秒）回来再冒出来；
  /// 一键清空仅所有者能用（会删掉这台设备全部云端照片），身份没查到或是接收者时点了无反应。
  Widget _buildActions(AppL10n l10n) {
    return FigmaGlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 19),
      child: Column(
        children: [
          _WifiActionRow(
            iconAsset: 'assets/images/device-detail-icon05.png',
            fallbackIcon: Icons.cleaning_services_outlined,
            label: l10n.devClearAll,
            labelColor: const Color(0xFFFF6A20),
            value: l10n.devClearAllValue,
            onTap: () {
              if (!_isOwner) {
                return; // 接收者 / 身份还没查到：点了无反应
              }
              unawaited(startWifiClearFlow(
                context,
                widget.state,
                _device,
                // 照片删了，服务端会把轮播里对应的图移掉：重查一次轮播标记
                onCleared: () {
                  if (mounted) {
                    WifiSlideshowStore.instance.refresh(_device);
                  }
                },
              ));
            },
          ),
          Container(height: 1, color: const Color(0xFF2A2B2B).withValues(alpha: 0.08)),
          // 解除绑定：只删设备记录，照片保留
          _WifiActionRow(
            iconAsset: 'assets/images/device-detail-icon06.png',
            fallbackIcon: Icons.link_off_rounded,
            label: l10n.devUnbindDevice,
            labelColor: const Color(0xFFFF3045),
            value: l10n.devUnbindDeviceValue,
            onTap: () => startWifiUnbindFlow(context, widget.state, _device),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([widget.state, WifiStatusStore.instance, WifiSlideshowStore.instance]),
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
                          // 设备ID、屏幕尺寸移到下方功能栏「设备信息」后（2026-11-02 同小程序）
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
                // 防重复点击（2026-11-04 同小程序 tapGuard，key projection）
                onCast: () => TapGuard.run(this, 'projection', () => startWifiCast(context, widget.state, device)),
                // 轮播中标记只在 running 且设备在线时显示（2026-11-05，同小程序）
                slideshowOn: WifiSlideshowStore.instance.of(device.id) && status.status == WifiOnlineStatus.online,
                // 从轮播设置页保存 / 暂停回来重查轮播中标记
                onSlideshow: () => openWifiSlideshow(context, widget.state, device).then((_) {
                  if (mounted) {
                    WifiSlideshowStore.instance.refresh(_device);
                  }
                }),
              ),
              const SizedBox(height: 14),
              _buildEntries(l10n, status),
              const SizedBox(height: 12),
              _buildActions(l10n),
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
    this.slideshowOn = false,
  });

  final String castLabel;
  final String slideshowLabel;
  final VoidCallback onCast;
  final VoidCallback onSlideshow;

  /// 轮播开启中（2026-11-02，strategy.running）：「轮播设置」图标换绿色版 + 右上角绿点。
  /// 2026-11-05 起（同小程序）去掉「轮播中」文字标签，调用方只在 running 且设备在线时传 true。
  final bool slideshowOn;

  @override
  Widget build(BuildContext context) {
    Widget action({
      required Widget icon,
      required String label,
      required Color color,
      required VoidCallback onTap,
      Widget? trailing,
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
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.w500, height: 1),
                ),
              ),
              if (trailing != null) ...[const SizedBox(width: 4), trailing],
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
            icon: Stack(
              clipBehavior: Clip.none,
              children: [
                Image.asset(
                  slideshowOn ? 'assets/images/device-detail-icon01-on.png' : 'assets/images/device-detail-icon01.png',
                  width: 18,
                  height: 18,
                  errorBuilder: (context, error, stackTrace) =>
                      const Icon(Icons.slideshow_rounded, size: 16, color: kWifiGreen),
                ),
                if (slideshowOn)
                  Positioned(
                    key: const ValueKey('wifi-slideshow-on-dot'),
                    top: -2,
                    right: -3,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: kWifiGreen,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 1.5),
                      ),
                    ),
                  ),
              ],
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

/// 详情页操作卡片的一行（同蓝牙版详情 _DetailRow 的样式：20 图标 + 14 / w500 标签 + 右对齐说明 + 箭头）。
class _WifiActionRow extends StatelessWidget {
  const _WifiActionRow({
    required this.iconAsset,
    required this.fallbackIcon,
    required this.label,
    required this.labelColor,
    required this.value,
    required this.onTap,
  });

  final String iconAsset;
  final IconData fallbackIcon;
  final String label;
  final Color labelColor;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        height: 60,
        child: Row(
          children: [
            Image.asset(
              iconAsset,
              width: 20,
              height: 20,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) => Icon(fallbackIcon, size: 20, color: labelColor),
            ),
            const SizedBox(width: 15),
            Text(
              label,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: labelColor, fontSize: 14, fontWeight: FontWeight.w500, height: 1.2),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: const TextStyle(color: Color(0xFF777E88), fontSize: 14, height: 1.2),
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right_rounded, color: Color(0xFF777E88), size: 18),
          ],
        ),
      ),
    );
  }
}
