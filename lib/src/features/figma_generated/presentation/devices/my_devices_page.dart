import 'package:flutter/material.dart';

import '../widgets/figma_common.dart';

class MyDevicesPage extends StatelessWidget {
  const MyDevicesPage({
    super.key,
    this.devices = _defaultDevices,
    this.onAddDevice,
    this.onOpenDetail,
    this.onCarouselSettings,
    this.onConnect,
    this.onDisconnect,
  });

  final List<MyDeviceOverview> devices;
  final VoidCallback? onAddDevice;
  final ValueChanged<String>? onOpenDetail;
  final ValueChanged<String>? onCarouselSettings;
  final ValueChanged<String>? onConnect;
  final ValueChanged<String>? onDisconnect;

  static const _defaultDevices = <MyDeviceOverview>[
    MyDeviceOverview(
      id: 'room-album',
      name: '房间相册',
      connected: true,
      battery: '80%',
      action: '断开',
    ),
    MyDeviceOverview(
      id: 'living-room-album',
      name: '客厅相册',
      connected: false,
      battery: '',
      action: '连接',
    ),
    MyDeviceOverview(
      id: 'study-album',
      name: '书房厅相册',
      connected: false,
      battery: '',
      action: '连接',
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
              trailing: FigmaRoundIconButton(
                icon: Icons.add_rounded,
                onTap: onAddDevice,
              ),
            ),
          ),
          Positioned(
            left: 24,
            top: 102,
            width: 327,
            child: Column(
              children: [
                for (final device in devices) ...[
                  _DeviceCard(
                    device: device,
                    onOpenDetail: () => onOpenDetail?.call(device.id),
                    onCarouselSettings: () =>
                        onCarouselSettings?.call(device.id),
                    onAction: () {
                      if (device.connected) {
                        onDisconnect?.call(device.id);
                      } else {
                        onConnect?.call(device.id);
                      }
                    },
                  ),
                  if (device != devices.last) const SizedBox(height: 12),
                ],
              ],
            ),
          ),
          const FigmaBottomHomeIndicator(),
        ],
      ),
    );
  }
}

class MyDeviceOverview {
  const MyDeviceOverview({
    required this.id,
    required this.name,
    required this.connected,
    required this.battery,
    required this.action,
  });

  final String id;
  final String name;
  final bool connected;
  final String battery;
  final String action;
}

class _DeviceCard extends StatelessWidget {
  const _DeviceCard({
    required this.device,
    required this.onOpenDetail,
    required this.onCarouselSettings,
    required this.onAction,
  });

  final MyDeviceOverview device;
  final VoidCallback onOpenDetail;
  final VoidCallback onCarouselSettings;
  final VoidCallback onAction;

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
              width: 180,
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
                  if (device.battery.isNotEmpty) ...[
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
                        onPressed: onAction,
                        icon: Icon(
                          device.connected
                              ? Icons.link_off_rounded
                              : Icons.link_rounded,
                          size: 18,
                        ),
                        label: Text(device.action),
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
