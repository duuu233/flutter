import 'package:flutter/material.dart';

import '../../../routes/app_routes.dart';
import '../../../shared/l10n/app_l10n.dart';
import '../../../shared/permission_gate.dart';
import '../../../shared/widgets/app_toast.dart';
import '../../../shared/widgets/app_widgets.dart';
import '../../cast/cast_photo_picker.dart';
import '../../cast/presentation/cast_preview_page.dart';
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
          loadError: state.devicesLoadError,
          onRefresh: () async {
            await state.refreshDevices();
          },
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
            if (!feedback.success) {
              _showMessage(context, feedback.message);
            }
          },
          onConnect: (deviceId) async {
            // 授权框先单独出现，全就绪才弹「连接中」loading（拒绝时内部已弹「去设置」引导）。
            if (!await PermissionGate.ensureBleReady(context) ||
                !context.mounted) {
              return;
            }
            // 真实 BLE 连接：复用活动会话或扫描匹配（只认序列号，改名不影响连接）。
            AppLoadingDialog.show(context, AppL10n.of(context).devConnecting);
            final feedback = await state.connectDevice(deviceId);
            if (!context.mounted) {
              return;
            }
            AppLoadingDialog.hide(context);
            if (!feedback.success) {
              _showMessage(context, feedback.message);
            }
          },
          onDisconnect: (deviceId) async {
            final feedback = await state.disconnectDevice(deviceId);
            if (!context.mounted) {
              return;
            }
            if (!feedback.success) {
              _showMessage(context, feedback.message);
            }
          },
        );
      },
    );
  }

  void _showMessage(BuildContext context, String message) {
    AppToast.warn(context, message);
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
    List<String> imagePaths;
    try {
      // 统一走 CastPhotoPicker：选图时就用平台原生解码器把长边降到 1920，
      // 避免把 4~12MB 的相机原图整个传给后端（投屏耗时大头在上传，不在 BLE）。
      imagePaths = (source == ImageSourceType.camera)
          ? await CastPhotoPicker.takePhoto()
          : await CastPhotoPicker.pickFromAlbum(context);
    } catch (_) {
      if (context.mounted) {
        _showMessage(context, AppL10n.of(context).devicesReadPhotoFailed);
      }
      return;
    }
    if (!context.mounted || imagePaths.isEmpty) {
      return;
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        // 选图后先进**投屏预览页**（裁剪/旋转/原图），确认后才开始投屏。
        builder: (_) => CastPreviewPage(
          state: widget.state,
          device: device,
          imagePaths: imagePaths,
        ),
      ),
    );
    state.refreshAlbum();
    state.refreshCastRecords();
  }

  /// 未连接则蒙层 loading 自动扫连（对齐小程序 ensureConnectedForAction）；连上 true，失败提示 false。
  Future<bool> _ensureConnected(BuildContext context, String deviceId) async {
    // 授权框先单独出现，全就绪才弹「连接中」loading。
    if (!await PermissionGate.ensureBleReady(context) || !context.mounted) {
      return false;
    }
    AppLoadingDialog.show(context, AppL10n.of(context).bindConnecting);
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

  /// 拍照 / 相册选择面板：走共用卡片式弹层（对齐小程序 `.media-sheet` / 首页同款）。
  Future<ImageSourceType?> _pickCastSource(BuildContext context) {
    return CastPhotoPicker.chooseSource(context);
  }
}
