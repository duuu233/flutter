import 'package:flutter/material.dart';

import 'package:BoltStar/src/shared/widgets/app_widgets.dart';
import 'package:BoltStar/src/shared/widgets/figma_common.dart';
import '../../../shared/l10n/app_l10n.dart';

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
  });

  final List<MyDeviceOverview>? devices;

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

  @override
  State<MyDevicesPage> createState() => _MyDevicesPageState();
}

class MyDeviceOverview {
  MyDeviceOverview({
    required this.id,
    required this.name,
    required this.connected,
    required this.battery,
  });

  final String id;
  String name;
  bool connected;
  String battery;

  MyDeviceOverview copy() => MyDeviceOverview(
    id: id,
    name: name,
    connected: connected,
    battery: battery,
  );
}

class _MyDevicesPageState extends State<MyDevicesPage> {
  // 列表数据以上层传入的 `widget.devices` 为准（单一数据源）；未传入时为空列表（不再用演示数据）。
  List<MyDeviceOverview> get _devices => widget.devices ?? const [];

  @override
  Widget build(BuildContext context) {
    return FigmaScreen(
      title: AppL10n.of(context).devMyDevicesTitle,
      scrollable: false,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 顶部工具栏：右对齐添加按钮（小程序 .device-toolbar，加载中/空态不显示——
          // 空态卡片自带「添加设备」CTA）。
          const SizedBox(height: 20),
          if (!widget.loading && _devices.isNotEmpty)
            Align(
              alignment: Alignment.centerRight,
              child: _AddDeviceButton(onTap: widget.onAddDevice),
            ),
          const SizedBox(height: 12),
          Expanded(
            // 四分支互斥链（loading 优先）：加载中 → 失败重试 → 空态 → 设备列表。
            // 失败且无本地数据时显示「加载失败 + 重试」——断网时不能误显示「暂无设备」。
            child: widget.loading
                ? const PageLoading()
                : _devices.isEmpty && widget.loadError
                ? PageLoadError(
                    onRetry: () => widget.onRefresh?.call(),
                  )
                : _devices.isEmpty
                ? _EmptyDevices(onAddDevice: widget.onAddDevice)
                : RefreshIndicator(
                    // 下拉刷新：此前数据只在进页时刷新，无手动恢复手段。
                    onRefresh: () async => widget.onRefresh?.call(),
                    color: const Color(0xFFEB5F1B),
                    child: ListView.separated(
                      padding: const EdgeInsets.only(bottom: 12),
                      physics: const AlwaysScrollableScrollPhysics(),
                      itemCount: _devices.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final device = _devices[index];
                        return _DeviceCard(
                          device: device,
                          onOpenDetail: () =>
                              widget.onOpenDetail?.call(device.id),
                          onCast: () => widget.onCast?.call(device.id),
                          onRename: () => _rename(device),
                          onToggleConnection: () => _toggleConnection(device),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
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
    final controller = TextEditingController(text: device.name);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppL10n.of(context).devDeviceNameTitle),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 6,
          cursorColor: const Color(0xFFEB5F1B),
          decoration: InputDecoration(hintText: AppL10n.of(context).devNameHint),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(AppL10n.of(context).cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: Text(AppL10n.of(context).confirm),
          ),
        ],
      ),
    );
    // 不立即 dispose：对话框还在退场动画中、TextField 仍挂着 controller，
    // 立刻释放会触发 used-after-dispose 断言；延迟一个主题动画时长再释放。
    Future<void>.delayed(kThemeAnimationDuration, controller.dispose);
    if (name != null) {
      // 通过回调走真实接口；列表名称由上层 state 更新后重建。
      widget.onRename?.call(device.id, name.trim());
    }
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

/// 空态卡片（小程序 `.empty-device glass-panel`）：**全宽**玻璃面板 +
/// 桃色圆角图标盒（内为 CSS 画法复刻的橙色「相框」图形，非图片资源）+
/// 标题 + 说明 + 渐变「添加设备」CTA。
class _EmptyDevices extends StatelessWidget {
  const _EmptyDevices({this.onAddDevice});

  final VoidCallback? onAddDevice;

  @override
  Widget build(BuildContext context) {
    // 面板与小程序一致占满页宽（原实现 Align 收缩包裹内容，卡片只有文字那么宽）。
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FigmaGlassCard(
          borderRadius: 14,
          // .empty-device padding: 76rpx 36rpx = 38 / 18。
          padding: const EdgeInsets.symmetric(vertical: 38, horizontal: 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 桃色圆角图标盒（.empty-device__art，112rpx=56，bg rgba(255,106,32,0.1)，radius 30rpx=15）。
              Container(
                width: 56,
                height: 56,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFFFF6A20).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: const _FrameLogoGlyph(),
              ),
              const SizedBox(height: 13),
              Text(
                AppL10n.of(context).devEmptyTitle,
                style: const TextStyle(
                  color: Color(0xFF2A2D32),
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 7),
              Text(
                AppL10n.of(context).devEmptySubtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFF7E858F),
                  fontSize: 13,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 17),
              // 渐变 CTA「添加设备」（.empty-device__btn，110×36，#ff9140→#ff6a20，radius 999）。
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onAddDevice,
                child: Container(
                  width: 110,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0xFFFF9140), Color(0xFFFF6A20)],
                    ),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    AppL10n.of(context).devAddDevice,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      height: 1.2,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 复刻小程序 app.wxss `.frame-logo`：橙色描边「相框 + 底座」图形
/// （48×40rpx 边框 + 底部 U 形小支架，纯绘制，无图片资源）。
class _FrameLogoGlyph extends StatelessWidget {
  const _FrameLogoGlyph();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 24,
      height: 27,
      child: CustomPaint(painter: _FrameLogoPainter()),
    );
  }
}

class _FrameLogoPainter extends CustomPainter {
  const _FrameLogoPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = const Color(0xFFFF6A20)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    // 相框主体：24×20（rpx 值减半），2 描边、2 圆角。描边居中于路径，内缩 1。
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(1, 1, 22, 18),
        const Radius.circular(2),
      ),
      stroke,
    );

    // 底座：相框下方 2 间隙处的开口朝上 U 形（.frame-logo::before，border-top: 0）。
    const double left = 3, right = 21, top = 22, bottom = 26, radius = 2;
    final path = Path()
      ..moveTo(left, top)
      ..lineTo(left, bottom - radius)
      ..quadraticBezierTo(left, bottom, left + radius, bottom)
      ..lineTo(right - radius, bottom)
      ..quadraticBezierTo(right, bottom, right, bottom - radius)
      ..lineTo(right, top);
    canvas.drawPath(path, stroke);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
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
                  // 设备 Logo（连接态 device-list-icon04 / 离线 icon05，120rpx≈60）。
                  // 对齐小程序：连接态底色 rgba(255,175,139,0.1)，离线无底色，图标不缩小。
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: device.connected
                          ? const Color(0xFFFFAF8B).withValues(alpha: 0.1)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Image.asset(
                      device.connected
                          ? 'assets/images/device-list-icon04.png'
                          : 'assets/images/device-list-icon05.png',
                      width: 60,
                      height: 60,
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) {
                        return Icon(
                          Icons.photo_library_outlined,
                          color: device.connected
                              ? const Color(0xFFEB5F1B)
                              : const Color(0x992A2B2B),
                          size: 34,
                        );
                      },
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
                            const SizedBox(width: 3),
                            GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: onRename,
                              child: Image.asset(
                                'assets/images/edit-icon01.png',
                                width: 18,
                                height: 18,
                                fit: BoxFit.contain,
                                errorBuilder: (context, error, stackTrace) {
                                  return const Icon(
                                    Icons.edit_outlined,
                                    size: 16,
                                    color: Color(0x992A2B2B),
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 7),
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
