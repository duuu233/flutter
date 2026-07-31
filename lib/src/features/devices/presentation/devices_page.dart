import 'dart:async';

import 'package:flutter/material.dart';

import '../../../device/recently_bound_device.dart';
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
  /// 上一帧处于「已连接」的设备 id。用来识别「切换了连接设备」这一刻——
  /// 新连上的那台会被排到最上面，同时给它一次上移入场动效（需求第 6 项）。
  String _lastConnectedId = '';

  /// 正在播放上移动效的设备 id（560ms 后清空，与小程序 `reorderingDeviceId` 同一时长）。
  String _promotedId = '';
  Timer? _promotionTimer;

  /// 首帧只记录当前连接目标、不播动效：动效表达的是「**切换**了连接设备」，
  /// 每次进页都对已连接那台放一遍就成了无意义的入场噪音。
  bool _promotionPrimed = false;

  @override
  void initState() {
    super.initState();
    // 「最近绑定」是排序的第二优先级，进页先把它从本机读回来。
    RecentlyBoundDevice.instance.load().then((_) {
      if (mounted) {
        setState(() {});
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _reload();
      }
    });
  }

  /// 排序（对齐小程序 `list.js sortDevices`）：
  /// ① 真实连接中的设备永远置顶 → ② 最近绑定的设备 → ③ 其余保持接口原有顺序。
  ///
  /// 连接态只认 [PhotoFrameState.isDeviceActuallyConnected] 校验过的活动会话，
  /// 不能用后端记录里的 connected 字段——那只是上一次刷新的缓存。
  List<DeviceItem> _sortedDevices() {
    final recentId = RecentlyBoundDevice.instance.value;
    final indexed = <(int, DeviceItem)>[
      for (var i = 0; i < widget.state.devices.length; i++)
        (i, widget.state.devices[i]),
    ];
    indexed.sort((a, b) {
      final ac = widget.state.isDeviceActuallyConnected(a.$2.id) ? 1 : 0;
      final bc = widget.state.isDeviceActuallyConnected(b.$2.id) ? 1 : 0;
      if (ac != bc) {
        return bc - ac;
      }
      final ar = recentId.isNotEmpty && a.$2.id == recentId ? 1 : 0;
      final br = recentId.isNotEmpty && b.$2.id == recentId ? 1 : 0;
      if (ar != br) {
        return br - ar;
      }
      return a.$1 - b.$1; // 其余保持接口原有顺序（稳定排序）
    });
    return [for (final entry in indexed) entry.$2];
  }

  /// 连接设备发生切换时，给新连上的那台标记一次上移动效。
  ///
  /// 在 build 里检测（连接是异步完成的，没有单一回调能覆盖「列表页连接 / 详情页连接 /
  /// 自动重连」三条路径），所以用 postFrame 回调改状态，避免在 build 期间 setState。
  void _notePromotion(String connectedId) {
    if (connectedId == _lastConnectedId) {
      return;
    }
    _lastConnectedId = connectedId;
    final primed = _promotionPrimed;
    _promotionPrimed = true;
    if (connectedId.isEmpty || !primed) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      setState(() => _promotedId = connectedId);
      _promotionTimer?.cancel();
      _promotionTimer = Timer(const Duration(milliseconds: 560), () {
        if (mounted) {
          setState(() => _promotedId = '');
        }
      });
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
    _promotionTimer?.cancel();
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
  /// 电量/内存是**蓝牙**字段，后端不下发。这里对当前连接设备补一次核心信息刷新；
  /// 内存走 0x01，电量由状态层按 15 秒缓存策略在后台走 0x04，旧值持续可见。
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
        final ordered = _sortedDevices();
        // 已连接的那台排序后必然在第一位（若有）；连接目标变了就播一次上移动效。
        // 判据与排序用同一个（真实会话），不看记录里可能过期的 connected 缓存。
        final connectedId =
            ordered.isNotEmpty &&
                state.isDeviceActuallyConnected(ordered.first.id)
            ? ordered.first.id
            : '';
        _notePromotion(connectedId);
        return MyDevicesPage(
          // 首屏未出结果前显示 loading，不先闪空列表。
          loading: !state.devicesLoaded,
          loadError: state.devicesLoadError,
          onRefresh: _reload,
          promotedDeviceId: _promotedId,
          devices: ordered
              .map(
                (device) => MyDeviceOverview(
                  id: device.id,
                  name: device.name,
                  connected: device.connected,
                  battery: device.batteryLabel,
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
            Navigator.of(context).pushNamed<void>(
              AppRoutes.figmaDeviceDetails,
              arguments: deviceId,
            );
          },
          onCast: (deviceId) => _startCast(context, deviceId),
          onRename: (deviceId, name) async {
            AppLoadingDialog.show(context, AppL10n.of(context).saving);
            final ActionFeedback feedback;
            try {
              feedback = await state.renameDevice(deviceId, name);
            } finally {
              // iOS / Android 共用此 Flutter 流程；即使页面状态变化也要收掉 root 蒙层。
              // ignore: use_build_context_synchronously
              AppLoadingDialog.hide(context);
            }
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
    if (!state.isDeviceActuallyConnected(deviceId)) {
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
          : await CastPhotoPicker.pickFromAlbum();
    } catch (_) {
      if (context.mounted) {
        _showMessage(context, AppL10n.of(context).devicesReadPhotoFailed);
      }
      return;
    }
    if (!context.mounted || imagePaths.isEmpty) {
      return;
    }
    final device = state.deviceById(deviceId);
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
