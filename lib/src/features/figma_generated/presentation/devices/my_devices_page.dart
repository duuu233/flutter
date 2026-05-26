import 'package:flutter/material.dart';

import '../widgets/figma_common.dart';

/// 我的设备列表页面，对应 UI 稿「我的设备」。
///
/// 设备的连接/断开、重命名均为本地伪逻辑（演示用），接入真实蓝牙能力时把
/// [_toggleConnection] / [_rename] 内部替换为实际接口调用即可。
class MyDevicesPage extends StatefulWidget {
  const MyDevicesPage({
    super.key,
    this.devices,
    this.onAddDevice,
    this.onOpenDetail,
    this.onCarouselSettings,
    this.onConnect,
    this.onDisconnect,
  });

  final List<MyDeviceOverview>? devices;
  final VoidCallback? onAddDevice;
  final ValueChanged<String>? onOpenDetail;
  final ValueChanged<String>? onCarouselSettings;
  final ValueChanged<String>? onConnect;
  final ValueChanged<String>? onDisconnect;

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
  late final List<MyDeviceOverview> _devices =
      (widget.devices ?? _seedDevices()).map((device) => device.copy()).toList();

  static List<MyDeviceOverview> _seedDevices() => [
    MyDeviceOverview(
      id: 'room-album',
      name: '房间相册',
      connected: true,
      battery: '80%',
    ),
    MyDeviceOverview(
      id: 'living-room-album',
      name: '客厅相册',
      connected: false,
      battery: '60%',
    ),
    MyDeviceOverview(
      id: 'study-album',
      name: '书房相框',
      connected: false,
      battery: '45%',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return FigmaPhoneFrame(
      child: Stack(
        children: [
          const FigmaPageBackground(),
          Positioned(
            left: 0,
            top: 0,
            width: 375,
            height: 90,
            child: FigmaTopNavigation(
              title: '我的设备',
              trailing: _AddDeviceButton(onTap: widget.onAddDevice),
            ),
          ),
          Positioned(
            left: 24,
            top: 102,
            right: 24,
            bottom: 20,
            child: ListView.separated(
              padding: const EdgeInsets.only(bottom: 12),
              itemCount: _devices.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final device = _devices[index];
                return _DeviceCard(
                  device: device,
                  onOpenDetail: () => widget.onOpenDetail?.call(device.id),
                  onCarouselSettings: () =>
                      widget.onCarouselSettings?.call(device.id),
                  onRename: () => _rename(device),
                  onToggleConnection: () => _toggleConnection(device),
                );
              },
            ),
          ),
          const FigmaBottomHomeIndicator(),
        ],
      ),
    );
  }

  void _toggleConnection(MyDeviceOverview device) {
    setState(() => device.connected = !device.connected);
    if (device.connected) {
      widget.onConnect?.call(device.id);
    } else {
      widget.onDisconnect?.call(device.id);
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
          maxLength: 20,
          cursorColor: const Color(0xFFEB5F1B),
          decoration: const InputDecoration(hintText: '请输入设备名称'),
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
    if (name != null && name.trim().isNotEmpty) {
      setState(() => device.name = name.trim());
    }
  }
}

class _AddDeviceButton extends StatelessWidget {
  const _AddDeviceButton({this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFFF6A24),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: const SizedBox(
          width: 34,
          height: 34,
          child: Icon(Icons.add_rounded, color: Colors.white, size: 22),
        ),
      ),
    );
  }
}

class _DeviceCard extends StatelessWidget {
  const _DeviceCard({
    required this.device,
    required this.onOpenDetail,
    required this.onCarouselSettings,
    required this.onRename,
    required this.onToggleConnection,
  });

  final MyDeviceOverview device;
  final VoidCallback onOpenDetail;
  final VoidCallback onCarouselSettings;
  final VoidCallback onRename;
  final VoidCallback onToggleConnection;

  @override
  Widget build(BuildContext context) {
    return FigmaGlassCard(
      child: SizedBox(
        height: 155,
        child: Stack(
          children: [
            Positioned(
              left: 18,
              top: 27,
              width: 60,
              height: 60,
              child: Container(
                decoration: BoxDecoration(
                  color: device.connected
                      ? const Color(0xFFFFAF8B).withValues(alpha: 0.1)
                      : const Color(0xFF2A2B2B).withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  Icons.photo_library_outlined,
                  color: device.connected
                      ? const Color(0xFFEB5F1B)
                      : const Color(0x992A2B2B),
                  size: 32,
                ),
              ),
            ),
            Positioned(
              left: 101,
              top: 25,
              right: 44,
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      device.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF2A2B2B),
                        fontSize: 20,
                        fontWeight: FontWeight.w500,
                        height: 1.4,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: onRename,
                    child: const Icon(
                      Icons.edit_outlined,
                      size: 16,
                      color: Color(0x992A2B2B),
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              left: 101,
              top: 62,
              child: Row(
                children: [
                  Icon(
                    Icons.circle,
                    size: 10,
                    color: device.connected
                        ? const Color(0xFF1AC27F)
                        : const Color(0xFFD9D9D9),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    device.connected ? '已连接' : '未连接',
                    style: FigmaTextStyles.bodySmall,
                  ),
                  if (device.connected && device.battery.isNotEmpty) ...[
                    const SizedBox(width: 20),
                    const Icon(
                      Icons.battery_4_bar_rounded,
                      size: 18,
                      color: Color(0x992A2B2B),
                    ),
                    const SizedBox(width: 6),
                    Text(device.battery, style: FigmaTextStyles.bodySmall),
                  ],
                ],
              ),
            ),
            Positioned(
              right: 11,
              top: 44,
              child: IconButton(
                icon: const Icon(Icons.chevron_right_rounded, size: 22),
                color: const Color(0x992A2B2B),
                onPressed: onOpenDetail,
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: 42,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.55),
                  borderRadius: const BorderRadius.vertical(
                    bottom: Radius.circular(20),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextButton.icon(
                        onPressed: onCarouselSettings,
                        icon: const Icon(Icons.tune_rounded, size: 18),
                        label: const Text('轮播设置'),
                        style: TextButton.styleFrom(
                          foregroundColor: const Color(0xCC2A2B2B),
                        ),
                      ),
                    ),
                    Container(
                      width: 1,
                      height: 18,
                      color: const Color(0x1A2A2B2B),
                    ),
                    Expanded(
                      child: TextButton.icon(
                        onPressed: onToggleConnection,
                        icon: Icon(
                          device.connected
                              ? Icons.link_off_rounded
                              : Icons.bluetooth_rounded,
                          size: 18,
                        ),
                        label: Text(device.connected ? '断开' : '连接'),
                        style: TextButton.styleFrom(
                          foregroundColor: device.connected
                              ? const Color(0xFFEB5F1B)
                              : const Color(0xFF2079FC),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
