import 'package:flutter/material.dart';

import '../../../features/figma_generated/figma_generated_pages.dart';
import '../../../routes/app_routes.dart';
import '../../../state.dart';

class DevicesPage extends StatelessWidget {
  const DevicesPage({super.key, required this.state});

  final PhotoFrameState state;

  @override
  Widget build(BuildContext context) {
    return MyDevicesPage(
      devices: state.devices
          .map(
            (device) => MyDeviceOverview(
              id: device.id,
              name: device.name,
              connected: device.connected,
              battery: '${device.batteryLevel}%',
              action: device.connected ? '断开' : '连接',
            ),
          )
          .toList(),
      onAddDevice: () {
        Navigator.of(
          context,
        ).pushNamed<void>(AppRoutes.figmaBindDeviceSearching);
      },
      onOpenDetail: (_) {
        Navigator.of(context).pushNamed<void>(AppRoutes.figmaDeviceDetails);
      },
      onCarouselSettings: (_) {
        Navigator.of(context).pushNamed<void>(AppRoutes.figmaCarouselSettings);
      },
      onConnect: (deviceId) {
        state.connectDevice(deviceId);
        _showMessage(context, '已切换连接设备');
      },
      onDisconnect: (_) {
        _showMessage(context, '当前版本暂未提供断开接口');
      },
    );
  }

  void _showMessage(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}
