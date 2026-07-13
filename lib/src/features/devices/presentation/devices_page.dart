import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../routes/app_routes.dart';
import '../../../shared/widgets/app_toast.dart';
import '../../cast/presentation/casting_progress_page.dart';
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
          // 首屏未出结果前显示 loading，不先闪空列表。
          loading: !state.devicesLoaded,
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
          onCast: (deviceId) => _startCast(context, deviceId),
          onRename: (deviceId, name) async {
            final feedback = await state.renameDevice(deviceId, name);
            if (!context.mounted) {
              return;
            }
            _showMessage(context, feedback.message);
          },
          onConnect: (deviceId) async {
            // 真实 BLE 连接：复用活动会话或扫描匹配（只认序列号，改名不影响连接）。
            _showMessage(context, '连接设备中…');
            final feedback = await state.connectDevice(deviceId);
            if (!context.mounted) {
              return;
            }
            _showMessage(context, feedback.message);
          },
          onDisconnect: (deviceId) async {
            final feedback = await state.disconnectDevice(deviceId);
            if (!context.mounted) {
              return;
            }
            _showMessage(context, feedback.message);
          },
        );
      },
    );
  }

  void _showMessage(BuildContext context, String message) {
    AppToast.show(context, message);
  }

  /// 列表项「投屏」：选中设备 → 未连接自动扫连 → 拍照/相册 → 真实投屏（对齐小程序 list.js startProjection）。
  Future<void> _startCast(BuildContext context, String deviceId) async {
    final state = widget.state;
    state.selectDevice(deviceId);
    final device = state.devices.firstWhere(
      (d) => d.id == deviceId,
      orElse: () => state.selectedDevice,
    );
    if (!device.connected) {
      final connected = await _ensureConnected(context, deviceId);
      if (!connected || !context.mounted) {
        return;
      }
    }
    final source = await _pickCastSource(context);
    if (source == null || !context.mounted) {
      return;
    }
    final picker = ImagePicker();
    List<String> imagePaths;
    try {
      if (source == ImageSourceType.camera) {
        final file = await picker.pickImage(source: ImageSource.camera);
        imagePaths = file == null ? const [] : [file.path];
      } else {
        // 单批投屏上限 5 张，对齐小程序 media.chooseFromAlbum(count:5)。
        final files = await picker.pickMultiImage(limit: 5);
        imagePaths = files.map((file) => file.path).toList();
      }
    } catch (_) {
      if (context.mounted) {
        _showMessage(context, '无法读取照片，请检查相机/相册权限后重试。');
      }
      return;
    }
    if (!context.mounted || imagePaths.isEmpty) {
      return;
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => CastingProgressPage(
          userProductId: deviceId,
          deviceName: state.deviceName(deviceId),
          imagePaths: imagePaths,
          compressImage: state.projectionCompress,
        ),
      ),
    );
    state.refreshAlbum();
    state.refreshCastRecords();
  }

  /// 未连接则蒙层 loading 自动扫连（对齐小程序 ensureConnectedForAction）；连上 true，失败提示 false。
  Future<bool> _ensureConnected(BuildContext context, String deviceId) async {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    final feedback = await widget.state.connectDevice(deviceId);
    if (!context.mounted) {
      return false;
    }
    Navigator.of(context, rootNavigator: true).pop();
    if (!feedback.success) {
      _showMessage(context, feedback.message);
    }
    return feedback.success;
  }

  /// 拍照 / 相册选择面板（对齐小程序 media 选择 sheet）。
  Future<ImageSourceType?> _pickCastSource(BuildContext context) {
    return showModalBottomSheet<ImageSourceType>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('拍照'),
              onTap: () =>
                  Navigator.of(sheetContext).pop(ImageSourceType.camera),
            ),
            ListTile(
              leading: const Icon(Icons.collections_outlined),
              title: const Text('从相册选择'),
              onTap: () =>
                  Navigator.of(sheetContext).pop(ImageSourceType.album),
            ),
          ],
        ),
      ),
    );
  }
}
