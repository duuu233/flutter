import 'package:flutter/material.dart';

import '../../../routes/app_routes.dart';
import 'my_devices_page.dart';
import '../../../state.dart';

/// 设备页：展示已绑定的相框设备，并提供进入设备相关页面的入口。
///
/// 打开时拉取后端设备列表（`getUserProductList`）；重命名走 `editUserProduct`。
/// 通过 [AnimatedBuilder] 监听 [PhotoFrameState]，设备增删改后自动刷新列表。
class DevicesPage extends StatefulWidget {
  const DevicesPage({super.key, required this.state});

  final PhotoFrameState state;

  @override
  State<DevicesPage> createState() => _DevicesPageState();
}

class _DevicesPageState extends State<DevicesPage> {
  @override
  void initState() {
    super.initState();
    // 进入页面后拉取一次后端设备列表（失败则保留当前列表）。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        widget.state.refreshDevices();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    return AnimatedBuilder(
      animation: state,
      builder: (context, _) {
        return MyDevicesPage(
          devices: state.devices
              .map(
                (device) => MyDeviceOverview(
                  id: device.id,
                  name: device.name,
                  connected: device.connected,
                  battery: '${device.batteryLevel}%',
                ),
              )
              .toList(),
          onAddDevice: () {
            Navigator.of(
              context,
            ).pushNamed<void>(AppRoutes.figmaBindDeviceSearching);
          },
          onOpenDetail: (deviceId) {
            state.selectDevice(deviceId);
            Navigator.of(context).pushNamed<void>(AppRoutes.figmaDeviceDetails);
          },
          onCarouselSettings: (_) {
            Navigator.of(
              context,
            ).pushNamed<void>(AppRoutes.figmaCarouselSettings);
          },
          onRename: (deviceId, name) async {
            final feedback = await state.renameDevice(deviceId, name);
            if (!context.mounted) {
              return;
            }
            _showMessage(context, feedback.message);
          },
          onConnect: (deviceId) {
            state.connectDevice(deviceId);
            _showMessage(context, '已切换连接设备');
          },
          onDisconnect: (_) {
            _showMessage(context, '当前版本暂未提供断开接口');
          },
        );
      },
    );
  }

  void _showMessage(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}
