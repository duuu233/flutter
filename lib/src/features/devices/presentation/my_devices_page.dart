import 'package:flutter/material.dart';

import 'package:BoltStar/src/shared/widgets/app_widgets.dart';
import 'package:BoltStar/src/shared/widgets/figma_common.dart';

/// 我的设备列表页面，对应 UI 稿「我的设备」。
///
/// 设备的连接/断开、重命名均为本地伪逻辑（演示用），接入真实蓝牙能力时把
/// [_toggleConnection] / [_rename] 内部替换为实际接口调用即可。
class MyDevicesPage extends StatefulWidget {
  const MyDevicesPage({
    super.key,
    this.devices,
    this.loading = false,
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
      title: '我的设备',
      scrollable: false,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 顶部工具栏：右对齐添加按钮（小程序 .device-toolbar，加载中不显示）。
          const SizedBox(height: 20),
          if (!widget.loading)
            Align(
              alignment: Alignment.centerRight,
              child: _AddDeviceButton(onTap: widget.onAddDevice),
            ),
          const SizedBox(height: 12),
          Expanded(
            // 三分支互斥链（loading 优先）：加载中 → 设备列表 → 空态。
            // 原来只有列表一支，没设备时是一片空白（连「暂无设备」都没有）。
            child: widget.loading
                ? const PageLoading()
                : _devices.isEmpty
                ? const EmptyState(
                    title: '暂无设备',
                    message: '还没有绑定相框，点击上方「添加设备」开始绑定。',
                  )
                : ListView.separated(
                    padding: const EdgeInsets.only(bottom: 12),
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
        title: const Text('设备名称'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 6,
          cursorColor: const Color(0xFFEB5F1B),
          decoration: const InputDecoration(hintText: '请输入设备名称（1-6个字符）'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    controller.dispose();
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

/// 电量百分比文案（如 "80%"）→ `BatteryLevel/battery-{档}.png` 资源路径。
String _batteryIconForLabel(String label) {
  final match = RegExp(r'\d+').firstMatch(label);
  final value = match == null ? 100 : int.parse(match.group(0)!).clamp(0, 100);
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
                  // 设备 Logo（连接态 device-list-icon04 / 离线 icon05，92rpx≈46）。
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: device.connected
                          ? const Color(0xFFFFAF8B).withValues(alpha: 0.1)
                          : const Color(0xFF2A2B2B).withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Image.asset(
                      device.connected
                          ? 'assets/images/device-list-icon04.png'
                          : 'assets/images/device-list-icon05.png',
                      width: 46,
                      height: 46,
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) {
                        return Icon(
                          Icons.photo_library_outlined,
                          color: device.connected
                              ? const Color(0xFFEB5F1B)
                              : const Color(0x992A2B2B),
                          size: 30,
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
                              device.connected ? '已连接' : '未连接',
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
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  Colors.white.withValues(alpha: 0.38),
                  Colors.white.withValues(alpha: 0.55),
                ],
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withValues(alpha: 0.31)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _DeviceActionButton(
                    iconAsset: 'assets/images/screen-casting-icon01.png',
                    fallbackIcon: Icons.cast_rounded,
                    iconWidth: 16,
                    iconHeight: 15,
                    label: '投屏',
                    color: const Color(0xFF777E88),
                    onTap: onCast,
                  ),
                ),
                Container(width: 1, height: 19, color: const Color(0xFFDADDDF)),
                Expanded(
                  child: _DeviceActionButton(
                    iconAsset: device.connected
                        ? 'assets/images/disconnect-icon01.png'
                        : 'assets/images/bluetooth-connection.png',
                    fallbackIcon: device.connected
                        ? Icons.link_off_rounded
                        : Icons.bluetooth_rounded,
                    iconWidth: 14,
                    iconHeight: 14,
                    label: device.connected ? '断开' : '连接',
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
              fontSize: 12,
              fontWeight: FontWeight.w500,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}
