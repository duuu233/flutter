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

class _DevicesPageState extends State<DevicesPage> with RouteAware {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _reload();
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute) {
      appRouteObserver.subscribe(this, route);
    }
  }

  @override
  void dispose() {
    appRouteObserver.unsubscribe(this);
    super.dispose();
  }

  /// 从设备详情等页 pop 回来时重新拉数（本页原来只在 initState 拉一次，
  /// 详情页里改名/连接/清空后返回，列表还是旧的）。
  @override
  void didPopNext() {
    _reload();
  }

  /// 后端列表 + 已连接设备的真机实时值。
  ///
  /// 电量/内存是**蓝牙**字段，后端不下发；只调 refreshDevices 的话列表永远显示
  /// 上一次 BLE 读到的缓存值（修好覆盖 bug 之前更是直接显示 0%）。这里对当前
  /// 连接中的那台补一次 0x01 回读，页面进来就是实时电量。
  Future<void> _reload() async {
    await widget.state.refreshDevices();
    if (!mounted) {
      return;
    }
    for (final device in widget.state.devices) {
      if (device.connected) {
        await widget.state.refreshConnectedDeviceInfo(device.id);
        break; // BLE 同时只保持一条会话，最多只有一台是连接态
      }
    }
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
          onRefresh: _reload,
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
            final ActionFeedback feedback;
            try {
              feedback = await state.connectDevice(deviceId);
            } finally {
              // hide 不做 mounted 门控（见 AppLoadingDialog.hide 注释）。
              AppLoadingDialog.hide(context);
            }
            if (!context.mounted) {
              return;
            }
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
      AppPageRoute(
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
    // 统一 hide 收口（精确移除 + 无 mounted 门控），替换掉盲 pop（历史闪退根源）。
    final ActionFeedback feedback;
    try {
      feedback = await widget.state.connectDevice(deviceId);
    } finally {
      AppLoadingDialog.hide(context);
    }
    if (!context.mounted) {
      return false;
    }
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
