import 'package:flutter/material.dart';

import 'package:BoltStar/src/shared/widgets/app_widgets.dart';
import 'package:BoltStar/src/shared/widgets/device_name_dialog.dart';
import 'package:BoltStar/src/shared/widgets/figma_common.dart';
import '../../../shared/l10n/app_l10n.dart';
import '../../../device/device_thumb.dart';
import '../../wifi/presentation/wifi_device_detail_page.dart' show WifiActionBar;
import '../../wifi/wifi_l10n.dart';
import '../../wifi/wifi_status.dart';
import '../../wifi/wifi_widgets.dart';

/// 「我的设备」的 WiFi版 / 蓝牙版 Tab。路由参数用它指定进页默认停在哪个 Tab（2026-11-12 同小程序 `list?tab=`）。
enum MyDevicesTab { wifi, ble }

/// 我的设备列表页面，对应 UI 稿「我的设备」。
///
/// 设备的连接/断开、重命名均为本地伪逻辑（演示用），接入真实蓝牙能力时把
/// [_toggleConnection] / [_rename] 内部替换为实际接口调用即可。
class MyDevicesPage extends StatefulWidget {
  const MyDevicesPage({
    super.key,
    this.devices,
    this.loading = false,
    this.loadError = false,
    this.onRefresh,
    this.onAddDevice,
    this.onOpenDetail,
    this.onCast,
    this.onConnect,
    this.onDisconnect,
    this.onRename,
    this.promotedDeviceId = '',
    this.onWifiCast,
    this.onWifiSlideshow,
    this.initialTab,
  });

  final List<MyDeviceOverview>? devices;

  /// 进页默认 Tab（2026-11-12 同小程序）：首页点 WiFi 版设备卡传 [MyDevicesTab.wifi]、蓝牙版传 [MyDevicesTab.ble]，
  /// 按「用户选过」处理——之后列表刷新不被默认规则改掉，该类没有设备就显示该 Tab 的空态。
  /// 为空（六宫格「我的设备」、我的页入口）按 [_MyDevicesPageState._defaultWifiTab]。
  final MyDevicesTab? initialTab;

  /// WiFi 版卡片的「投屏」「轮播设置」（同步小程序 main-wifi；V1.4 更新说明 1.5：原「刷新状态」改为「轮播设置」，
  /// 状态随进页、状态推送与长连接重连自动重查）。
  final ValueChanged<String>? onWifiCast;
  final ValueChanged<String>? onWifiSlideshow;

  /// 设备列表首屏是否仍在加载。true 时显示 loading，不显示「暂无设备」空态——
  /// 否则接口返回前必然先闪一次空列表（对齐小程序 device/list 的 `loading:true` 门控）。
  final bool loading;

  /// 最近一次刷新是否失败：为 true 且列表为空时显示「加载失败 + 重试」，
  /// 而非误导性的「暂无设备」空态。
  final bool loadError;

  /// 下拉刷新 / 失败重试的回调（由上层接 `state.refreshDevices`）。
  final Future<void> Function()? onRefresh;
  final VoidCallback? onAddDevice;
  final ValueChanged<String>? onOpenDetail;
  final ValueChanged<String>? onCast;
  final ValueChanged<String>? onConnect;
  final ValueChanged<String>? onDisconnect;

  /// 重命名回调：(设备 id, 新名称)。由上层接 `state.renameDevice` 走真实接口。
  final void Function(String id, String name)? onRename;

  /// 刚被切换成「已连接」、需要播一次上移入场动效的设备 id（需求第 6 项）。
  /// 由上层在连接目标变化时置起、560ms 后清空（见 `devices_page.dart`）。
  final String promotedDeviceId;

  @override
  State<MyDevicesPage> createState() => _MyDevicesPageState();
}

class MyDeviceOverview {
  MyDeviceOverview({
    required this.id,
    required this.name,
    required this.connected,
    required this.battery,
    this.thumbAsset = DeviceThumb.defaultAsset,
    this.wifi = false,
    this.wifiStatus = WifiDeviceStatus.loading,
    this.sizeModel = '',
    this.serialNumber = '',
    this.wifiSlideshowOn = false,
  });

  final String id;
  String name;
  bool connected;
  String battery;

  /// 设备图（按机型区分，见 [DeviceThumb]）。
  final String thumbAsset;

  /// WiFi 版（按所属产品广播 ID 认）：不走蓝牙，状态取 [wifiStatus]（IoT 云端）。
  final bool wifi;
  final WifiDeviceStatus wifiStatus;

  /// 后台产品配置的尺寸型号（如「5.89寸」）与设备ID：名称下一行「尺寸 · 设备ID xxx」（同小程序 2026-10-27，
  /// 只显示尺寸、不带 WiFi版 / 蓝牙版；没配显示「--寸」）。
  final String sizeModel;
  final String serialNumber;

  /// WiFi 版轮播开启中（2026-11-02，strategy.running）：「轮播设置」旁显示绿点 +「轮播中」。
  final bool wifiSlideshowOn;

  MyDeviceOverview copy() => MyDeviceOverview(
    id: id,
    name: name,
    connected: connected,
    battery: battery,
    thumbAsset: thumbAsset,
    wifi: wifi,
    wifiStatus: wifiStatus,
    sizeModel: sizeModel,
    serialNumber: serialNumber,
    wifiSlideshowOn: wifiSlideshowOn,
  );
}

class _MyDevicesPageState extends State<MyDevicesPage> {
  // 列表数据以上层传入的 `widget.devices` 为准（单一数据源）；未传入时为空列表（不再用演示数据）。
  List<MyDeviceOverview> get _devices => widget.devices ?? const [];

  /// 设备列表滚动位置：新连上的设备排到第一张时要平滑滚回顶部（对齐小程序 2026-11-02）。
  final ScrollController _scroll = ScrollController();

  /// 当前 Tab（2026-11-06 同小程序）：true = WiFi版，false = 蓝牙版。用户点过之前每次按 [_defaultWifiTab] 选，点过之后保持不变（不持久化）。
  bool _wifiTab = true;
  bool _tabChosen = false;

  /// 默认 Tab：WiFi 版在前（同原分组顺序）；WiFi 版没有设备而蓝牙版有，就落到蓝牙版；两类都没有落在 WiFi 版（显示空态 + 添加）。
  bool _defaultWifiTab(int wifiCount, int bleCount) => wifiCount > 0 || bleCount == 0;

  @override
  void initState() {
    super.initState();
    final tab = widget.initialTab;
    if (tab != null) {
      _wifiTab = tab == MyDevicesTab.wifi;
      _tabChosen = true;
    }
  }

  void _switchTab(bool wifi) {
    _tabChosen = true;
    if (wifi == _wifiTab) {
      return;
    }
    setState(() => _wifiTab = wifi);
    // 切过去回到列表顶部（与投屏记录页一样点击即切，本地按类型过滤，不重新请求）
    if (_scroll.hasClients) {
      _scroll.jumpTo(0);
    }
  }

  @override
  void didUpdateWidget(MyDevicesPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // promotedDeviceId 由空变为某台 = 连接设备刚切换、那台已被排到第一张并开始播上移动效；
    // 用户停在列表下方时看不到它，所以同时把列表平滑滚回顶部。
    final promoted = widget.promotedDeviceId;
    if (promoted.isNotEmpty && promoted != oldWidget.promotedDeviceId) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToTop());
    }
  }

  void _scrollToTop() {
    if (!mounted || !_scroll.hasClients || _scroll.offset <= 0) {
      return;
    }
    _scroll.animateTo(
      0,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final wifiCount = _devices.where((device) => device.wifi).length;
    final bleCount = _devices.length - wifiCount;
    if (!_tabChosen) {
      _wifiTab = _defaultWifiTab(wifiCount, bleCount);
    }
    final failed = _devices.isEmpty && widget.loadError;
    return FigmaScreen(
      title: l10n.devMyDevicesTitle,
      scrollable: false,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 20),
          // WiFi 版 / 蓝牙版改为 Tab 切换（2026-11-06 同小程序，样式与交互同投屏记录页的胶囊 Tab：白底 + 滑动橙色指示器，点击即切），
          // 取代 2026-10-27 的上下分组标题。添加按钮常驻（原只在有设备时显示），单独一行右对齐，Tab 在下一行占满宽度。
          if (!widget.loading && !failed) ...[
            Align(
              alignment: Alignment.centerRight,
              child: _AddDeviceButton(onTap: widget.onAddDevice),
            ),
            const SizedBox(height: 12),
            _DeviceTypeTabs(
              wifi: _wifiTab,
              wifiLabel: l10n.wifiBadge,
              bleLabel: l10n.bleBadge,
              onChanged: _switchTab,
            ),
          ],
          const SizedBox(height: 12),
          Expanded(
            // 三分支互斥链（loading 优先）：加载中 → 失败重试 → 当前 Tab 的设备列表 / 空态。
            // 失败且无本地数据时显示「加载失败 + 重试」——断网时不能误显示「暂无设备」。
            child: widget.loading
                ? const PageLoading()
                : failed
                ? PageLoadError(
                    onRetry: () => widget.onRefresh?.call(),
                  )
                : RefreshIndicator(
                    // 下拉刷新：此前数据只在进页时刷新，无手动恢复手段。
                    onRefresh: () async => widget.onRefresh?.call(),
                    color: const Color(0xFFEB5F1B),
                    // 组内仍按上层排好的顺序（已连接 → 最近绑定 → 接口原序）。
                    child: ListView(
                      controller: _scroll,
                      padding: const EdgeInsets.only(bottom: 12),
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: _tabCards(context, _wifiTab ? wifiCount : bleCount),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  List<Widget> _tabCards(BuildContext context, int count) {
    final l10n = AppL10n.of(context);
    // 当前 Tab 没有设备：默认设备图 + 右下角加号，整块点击进搜索设备页
    if (count == 0) {
      return [
        _EmptyTab(
          title: _wifiTab ? l10n.devEmptyWifiTab : l10n.devEmptyBleTab,
          desc: l10n.devEmptyTabAdd,
          onTap: widget.onAddDevice,
        ),
      ];
    }
    final children = <Widget>[
      // 与投屏记录页「共 N 条记录」同款
      Padding(
        padding: const EdgeInsets.only(top: 6, bottom: 0),
        child: Text(
          l10n.devTotalDevices(count),
          style: const TextStyle(color: Color(0xFF777E88), fontSize: 12, height: 1),
        ),
      ),
    ];
    if (_wifiTab) {
      for (final device in _devices.where((device) => device.wifi)) {
        children
          ..add(const SizedBox(height: 12))
          ..add(
            _WifiDeviceCard(
              key: ValueKey('wifi-card-${device.id}'),
              device: device,
              onOpenDetail: () => widget.onOpenDetail?.call(device.id),
              onRename: () => _rename(device),
              onCast: () => widget.onWifiCast?.call(device.id),
              onSlideshow: () => widget.onWifiSlideshow?.call(device.id),
            ),
          );
      }
      return children;
    }
    for (final device in _devices.where((device) => !device.wifi)) {
      children
        ..add(const SizedBox(height: 12))
        ..add(
          _PromotionTransition(
            // key 带上设备 id：列表重排后 Flutter 才不会把动画状态
            // 复用给恰好排在同一位置的另一台设备。
            key: ValueKey('device-card-${device.id}'),
            active: device.id == widget.promotedDeviceId,
            child: _DeviceCard(
              device: device,
              onOpenDetail: () => widget.onOpenDetail?.call(device.id),
              onCast: () => widget.onCast?.call(device.id),
              onRename: () => _rename(device),
              onToggleConnection: () => _toggleConnection(device),
            ),
          ),
        );
    }
    return children;
  }

  void _toggleConnection(MyDeviceOverview device) {
    // 连接态由上层状态维护（state.connectDevice 等会 notify 触发重建）。
    if (device.connected) {
      widget.onDisconnect?.call(device.id);
    } else {
      widget.onConnect?.call(device.id);
    }
  }

  Future<void> _rename(MyDeviceOverview device) async {
    // 统一样式的设备名称弹窗（详情页与绑定成功后的命名引导用的是同一个）。
    final name = await showDeviceNameDialog(
      context,
      initialValue: device.name,
      title: AppL10n.of(context).devDeviceNameTitle,
      thumbAsset: device.thumbAsset,
    );
    if (name != null && name != device.name) {
      // 通过回调走真实接口（上层带保存中 loading）；列表名称由 state 更新后重建。
      widget.onRename?.call(device.id, name);
    }
  }
}

/// 「切换连接设备」时新连上那台的上移入场动效。
///
/// 复刻小程序 `.device-card--promoted` 的 `@keyframes devicePromoted`：
/// 520ms 内从「下方 16px / 缩 0.985 / 半透明」升到位，中途 58% 处轻微过冲（上 3.5px / 1.008）
/// 再回落——用户能看清「这台被提到最上面了」，而不是列表突然重排。
///
/// [active] 由 false→true 时播一次；期间列表若重排，外层的 ValueKey 保证动画跟着设备走。
class _PromotionTransition extends StatefulWidget {
  const _PromotionTransition({
    super.key,
    required this.active,
    required this.child,
  });

  final bool active;
  final Widget child;

  @override
  State<_PromotionTransition> createState() => _PromotionTransitionState();
}

class _PromotionTransitionState extends State<_PromotionTransition>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
    value: 1, // 默认停在终态：没被提升的卡片不做任何变换
  );

  @override
  void initState() {
    super.initState();
    if (widget.active) {
      _controller.forward(from: 0);
    }
  }

  @override
  void didUpdateWidget(_PromotionTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      // child 只建一次，动画每帧只重跑变换（卡片内部有若干 Image.asset，别每帧重建）。
      child: widget.child,
      builder: (context, child) {
        final t = _controller.value;
        if (t >= 1) {
          return child!;
        }
        // 0 → 0.58：16px 上移并轻微过冲到 -3.5px；0.58 → 1：回落到 0。
        final double dy;
        final double scale;
        if (t <= 0.58) {
          final p = Curves.easeOut.transform(t / 0.58);
          dy = 16 + (-3.5 - 16) * p;
          scale = 0.985 + (1.008 - 0.985) * p;
        } else {
          final p = Curves.easeOut.transform((t - 0.58) / 0.42);
          dy = -3.5 + 3.5 * p;
          scale = 1.008 + (1 - 1.008) * p;
        }
        return Opacity(
          opacity: 0.45 + 0.55 * t,
          child: Transform.translate(
            offset: Offset(0, dy),
            child: Transform.scale(scale: scale, child: child),
          ),
        );
      },
    );
  }
}

/// 添加设备按钮（小程序 `.device-add-btn`，64rpx≈32，用 `home-add-icon.png`）。
class _AddDeviceButton extends StatelessWidget {
  const _AddDeviceButton({this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFFF661F).withValues(alpha: 0.18),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Image.asset(
          'assets/images/home-add-icon.png',
          width: 32,
          height: 32,
          errorBuilder: (context, error, stackTrace) {
            return Container(
              width: 32,
              height: 32,
              decoration: const BoxDecoration(
                color: Color(0xFFFF6A24),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.add_rounded,
                color: Colors.white,
                size: 22,
              ),
            );
          },
        ),
      ),
    );
  }
}

/// WiFi版 / 蓝牙版 Tab（2026-11-06 同小程序 `.device-tabs`，样式同投屏记录页的胶囊 Tab）：白色胶囊底 + 橙色滑动指示器。
class _DeviceTypeTabs extends StatelessWidget {
  const _DeviceTypeTabs({
    required this.wifi,
    required this.wifiLabel,
    required this.bleLabel,
    required this.onChanged,
  });

  final bool wifi;
  final String wifiLabel;
  final String bleLabel;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget tab(String label, bool value) => Expanded(
      child: GestureDetector(
        key: ValueKey(value ? 'device-tab-wifi' : 'device-tab-ble'),
        behavior: HitTestBehavior.opaque,
        onTap: () => onChanged(value),
        child: Center(
          child: AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 320),
            style: TextStyle(
              color: wifi == value ? Colors.white : const Color(0xFF858B94),
              fontSize: 14,
              fontWeight: FontWeight.w500,
              height: 1.2,
            ),
            child: Text(label),
          ),
        ),
      ),
    );

    return Container(
      height: 41,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.84),
        borderRadius: BorderRadius.circular(999),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF7E96B8).withValues(alpha: 0.08),
            blurRadius: 19,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Stack(
        children: [
          AnimatedAlign(
            duration: const Duration(milliseconds: 360),
            curve: const Cubic(0.22, 0.61, 0.36, 1),
            alignment: wifi ? Alignment.centerLeft : Alignment.centerRight,
            child: FractionallySizedBox(
              widthFactor: 0.5,
              heightFactor: 1,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xFFFF6A20),
                  borderRadius: BorderRadius.circular(999),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFFF6A20).withValues(alpha: 0.32),
                      blurRadius: 12,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Row(children: [tab(wifiLabel, true), tab(bleLabel, false)]),
        ],
      ),
    );
  }
}

/// 当前 Tab 没有设备（2026-11-06 同小程序 `.empty-tab`）：默认设备图 + 右下角加号 + 「暂无XX版设备」「点击添加设备」，
/// 整块点击进搜索设备页。取代原来全页的「暂无设备 + 添加设备」空态卡片。
class _EmptyTab extends StatelessWidget {
  const _EmptyTab({required this.title, required this.desc, this.onTap});

  final String title;
  final String desc;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: FigmaGlassCard(
          borderRadius: 14,
          padding: const EdgeInsets.fromLTRB(18, 28, 18, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 180,
                height: 142,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: Image.asset(
                        'assets/images/empty_device_art.png',
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stackTrace) =>
                            const Icon(Icons.photo_library_outlined, color: Color(0xFFEB5F1B), size: 56),
                      ),
                    ),
                    Positioned(
                      right: 18,
                      bottom: 12,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFFF661F).withValues(alpha: 0.24),
                              blurRadius: 12,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Image.asset(
                          'assets/images/home-add-icon.png',
                          width: 36,
                          height: 36,
                          errorBuilder: (context, error, stackTrace) =>
                              const Icon(Icons.add_circle_rounded, color: Color(0xFFFF6A24), size: 36),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFF2A2D32), fontSize: 16, fontWeight: FontWeight.w700, height: 1.2),
              ),
              const SizedBox(height: 6),
              Text(desc, style: const TextStyle(color: Color(0xFFFF6A20), fontSize: 13, height: 1.2)),
            ],
          ),
        ),
      ),
    );
  }
}

/// 电量百分比文案（如 "80%"）→ `BatteryLevel/battery-{档}.png` 资源路径。
String _batteryIconForLabel(String label) {
  final match = RegExp(r'\d+').firstMatch(label);
  // tryParse：超长数字串（>19 位）会让 int.parse 抛 FormatException。
  final value = (match == null ? 100 : int.tryParse(match.group(0)!) ?? 100)
      .clamp(0, 100);
  const levels = <int>[0, 10, 20, 30, 40, 50, 60, 70, 80, 90, 100];
  var nearest = levels.first;
  for (final candidate in levels) {
    if ((candidate - value).abs() < (nearest - value).abs()) {
      nearest = candidate;
    }
  }
  return 'assets/images/BatteryLevel/battery-$nearest.png';
}

class _DeviceCard extends StatelessWidget {
  const _DeviceCard({
    required this.device,
    required this.onOpenDetail,
    required this.onCast,
    required this.onRename,
    required this.onToggleConnection,
  });

  final MyDeviceOverview device;
  final VoidCallback onOpenDetail;
  final VoidCallback onCast;
  final VoidCallback onRename;
  final VoidCallback onToggleConnection;

  @override
  Widget build(BuildContext context) {
    // ⚠️ 「进详情」的点击区**只覆盖上半区（信息区）**，不再包整张卡片。
    //
    // 原来是整卡一个 GestureDetector(onTap: onOpenDetail)，底部「投屏 / 连接」按钮嵌在它里面。
    // 虽然理论上内层 GestureDetector 会在手势竞技场里胜出，但实测点按钮却跳去了详情页——
    // 与其去赌手势竞技场的解析顺序，不如**结构上让按钮栏根本不在详情点击区之下**：
    // 详情手势只包住信息区，按钮栏是它的兄弟节点，物理上不可能被它抢走。
    //
    // 这也更贴近小程序：list.wxml 里卡片是 bindtap，两个按钮是 catchtap（显式阻止冒泡）。
    return FigmaGlassCard(
      // 卡片圆角 40rpx=20；上半区图标 + 文字信息（可点进详情），下半区操作栏。
      borderRadius: 20,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onOpenDetail,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 17, 0),
              child: Row(
                children: [
                  // 设备图与首页同口径（2026-07-19 产品要求：首页/设备列表/设备详情同一张，
                  // 且**不区分连接状态**，连接状态由蓝牙角标与状态文案表达）。
                  // 2026-10-22 起按机型区分（EB-169 圆屏 / EC-370 / 其余默认），见 DeviceThumb。
                  // 该图 166×166、四角 alpha=0 自带圆角，所以**不再加底色容器**——
                  // 首页本身就没有底色，加了会在四角露出色晕，三处就不一致了。
                  Image.asset(
                    device.thumbAsset,
                    width: 60,
                    height: 60,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) {
                      return const Icon(
                        Icons.photo_library_outlined,
                        color: Color(0xFFEB5F1B),
                        size: 34,
                      );
                    },
                  ),
                  const SizedBox(width: 22),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
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
                                  fontSize: 20,
                                  fontWeight: FontWeight.w700,
                                  height: 1.15,
                                ),
                              ),
                            ),
                            // 点击区 40×40（见 FigmaEditIconButton）：原来是 18×18 的
                            // 裸 Image，用户反馈「很难点击到」。图标自带 11px 留白，
                            // 原先的 SizedBox(width: 3) / SizedBox(height: 7) 一并去掉。
                            FigmaEditIconButton(onTap: onRename),
                          ],
                        ),
                        _SizeIdLine(device: device),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            // 连接状态：蓝牙图标 + 文案。
                            Image.asset(
                              device.connected
                                  ? 'assets/images/bluetooth-icon.png'
                                  : 'assets/images/bluetooth-icon-not.png',
                              width: 11,
                              height: 14,
                              fit: BoxFit.contain,
                              errorBuilder: (context, error, stackTrace) =>
                                  const SizedBox(width: 11, height: 14),
                            ),
                            const SizedBox(width: 5),
                            Text(
                              device.connected
                                  ? AppL10n.of(context).devConnected
                                  : AppL10n.of(context).devDisconnected,
                              style: TextStyle(
                                color: device.connected
                                    ? const Color(0xFF287DFF)
                                    : const Color(0xFF9BA2AD),
                                fontSize: 12,
                                height: 1,
                              ),
                            ),
                            if (device.connected &&
                                device.battery.isNotEmpty) ...[
                              const SizedBox(width: 13),
                              Image.asset(
                                _batteryIconForLabel(device.battery),
                                width: 24,
                                fit: BoxFit.contain,
                                errorBuilder: (context, error, stackTrace) =>
                                    const Icon(
                                      Icons.battery_4_bar_rounded,
                                      size: 16,
                                      color: Color(0xFF737B86),
                                    ),
                              ),
                              const SizedBox(width: 5),
                              Text(
                                device.battery,
                                style: const TextStyle(
                                  color: Color(0xFF737B86),
                                  fontSize: 12,
                                  height: 1,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right_rounded,
                    size: 20,
                    color: Color(0xFF777E88),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 17),
          // 操作栏（投屏 | 连接/断开）：与上面的详情点击区是**兄弟节点**，
          // 不在它的手势范围内，所以这两个按钮的点击不可能被「进详情」抢走。
          Container(
            height: 42,
            // 对齐小程序 .device-actions：白 0.4 平底 + 轻投影（原来是左右白渐变、无阴影）。
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withValues(alpha: 0.31)),
              boxShadow: const [
                BoxShadow(
                  color: Color.fromRGBO(44, 63, 97, 0.03),
                  offset: Offset(0, 4),
                  blurRadius: 12.1,
                ),
              ],
            ),
            // crossAxisAlignment.stretch：让两个按钮铺满 42 高度，点击区覆盖整颗按钮（Bug20）。
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _DeviceActionButton(
                    iconAsset: 'assets/images/screen-casting-icon01.png',
                    fallbackIcon: Icons.cast_rounded,
                    iconWidth: 20,
                    iconHeight: 20,
                    label: AppL10n.of(context).devCast,
                    // 投屏文案/图标为橙色（对齐小程序 .projection-action #eb5f1b）。
                    color: const Color(0xFFEB5F1B),
                    onTap: onCast,
                  ),
                ),
                const Center(
                  child: SizedBox(
                    width: 1,
                    height: 19,
                    child: ColoredBox(color: Color(0xFFDADDDF)),
                  ),
                ),
                Expanded(
                  child: _DeviceActionButton(
                    iconAsset: device.connected
                        ? 'assets/images/disconnect-icon01.png'
                        : 'assets/images/bluetooth-connection.png',
                    fallbackIcon: device.connected
                        ? Icons.link_off_rounded
                        : Icons.bluetooth_rounded,
                    iconWidth: 20,
                    iconHeight: 20,
                    label: device.connected
                        ? AppL10n.of(context).devDisconnectShort
                        : AppL10n.of(context).devConnectShort,
                    color: device.connected
                        ? const Color(0xFFEB5F1B)
                        : const Color(0xFF2079FC),
                    onTap: onToggleConnection,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 设备卡底部操作按钮（图标 + 文案）。
class _DeviceActionButton extends StatelessWidget {
  const _DeviceActionButton({
    required this.iconAsset,
    required this.fallbackIcon,
    required this.iconWidth,
    required this.iconHeight,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final String iconAsset;
  final IconData fallbackIcon;
  final double iconWidth;
  final double iconHeight;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Image.asset(
            iconAsset,
            width: iconWidth,
            height: iconHeight,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) =>
                Icon(fallbackIcon, size: 16, color: color),
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 14,
              fontWeight: FontWeight.w500,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}

/// 名称下一行「尺寸 · 设备ID xxx」（同小程序 list.wxml `.device-id`）：尺寸没配显示「--寸」，设备ID 为空时只剩尺寸。
class _SizeIdLine extends StatelessWidget {
  const _SizeIdLine({required this.device});

  final MyDeviceOverview device;

  @override
  Widget build(BuildContext context) {
    final size = device.sizeModel.trim().isNotEmpty ? device.sizeModel.trim() : '--寸';
    final id = device.serialNumber.trim();
    return Text(
      id.isEmpty ? size : '$size · ${AppL10n.of(context).devDeviceId} $id',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(color: Color(0xFF8B9098), fontSize: 12, height: 1.3),
    );
  }
}

/// WiFi 版设备卡（同小程序 list.wxml `device-card--wifi`）：不走蓝牙，状态来自 IoT 设备信息
/// （在线 / 休眠中 / 已关机 / 离线、信号、电量）；按钮：投屏、轮播设置（没有连接 / 断开：WiFi 不经手机蓝牙）。
/// 设备图、改名同蓝牙版。
class _WifiDeviceCard extends StatelessWidget {
  const _WifiDeviceCard({
    super.key,
    required this.device,
    required this.onOpenDetail,
    required this.onRename,
    required this.onCast,
    required this.onSlideshow,
  });

  final MyDeviceOverview device;
  final VoidCallback onOpenDetail;
  final VoidCallback onRename;
  final VoidCallback onCast;
  final VoidCallback onSlideshow;

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final status = device.wifiStatus;
    final online = status.online;
    final stateColor = switch (status.status) {
      WifiOnlineStatus.online => kWifiGreen,
      WifiOnlineStatus.sleeping => kWifiSleepBlue,
      WifiOnlineStatus.local => kWifiLocalPurple,
      _ => const Color(0xFF9BA2AD),
    };
    final battery = status.battery;
    return FigmaGlassCard(
      borderRadius: 20,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onOpenDetail,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 17, 0),
              child: Row(
                children: [
                  Image.asset(
                    device.thumbAsset,
                    width: 60,
                    height: 60,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) => const Icon(
                      Icons.photo_library_outlined,
                      color: Color(0xFFEB5F1B),
                      size: 34,
                    ),
                  ),
                  const SizedBox(width: 22),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
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
                                  fontSize: 20,
                                  fontWeight: FontWeight.w700,
                                  height: 1.15,
                                ),
                              ),
                            ),
                            FigmaEditIconButton(onTap: onRename),
                          ],
                        ),
                        _SizeIdLine(device: device),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            if (status.status == WifiOnlineStatus.loading)
                              const WifiMiniSpinner(size: 11)
                            else
                              Icon(Icons.wifi_rounded, size: 14, color: stateColor),
                            const SizedBox(width: 5),
                            Text(
                              status.text(l10n),
                              style: TextStyle(color: stateColor, fontSize: 12, height: 1),
                            ),
                            if (online && status.signalBars > 0) ...[
                              const SizedBox(width: 8),
                              SignalBars(level: status.signalBars),
                            ],
                            if (battery != null) ...[
                              const SizedBox(width: 13),
                              Image.asset(
                                _batteryIconForLabel('$battery%'),
                                width: 24,
                                fit: BoxFit.contain,
                                errorBuilder: (context, error, stackTrace) => const Icon(
                                  Icons.battery_4_bar_rounded,
                                  size: 16,
                                  color: Color(0xFF737B86),
                                ),
                              ),
                              const SizedBox(width: 5),
                              Text(
                                '$battery%',
                                style: const TextStyle(color: Color(0xFF737B86), fontSize: 12, height: 1),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded, size: 20, color: Color(0xFF777E88)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 17),
          WifiActionBar(
            castLabel: l10n.devCast,
            slideshowLabel: l10n.wifiSlideshowSettings,
            onCast: onCast,
            onSlideshow: onSlideshow,
            // 轮播中标记只在 running 且设备在线时显示（2026-11-05，同小程序）
            slideshowOn: device.wifiSlideshowOn && status.status == WifiOnlineStatus.online,
          ),
        ],
      ),
    );
  }
}
