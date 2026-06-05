import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../native_device_api.dart';
import '../../../state.dart';
import 'widgets/cast_preview_sheet.dart';

// 首页拆分为同一个库（library）下的多个 part 文件，便于按职责浏览：
part 'home_main_view.dart'; // 首页主视图（已绑定 / 未绑定）
part 'home_bind_device_view.dart'; // 绑定设备流程（搜索 / 未找到 / 已找到）
part 'home_sheets.dart'; // 底部弹层（提示 / 投屏方式 / 扫描帮助）
part 'home_widgets.dart'; // 背景与各类展示型叶子组件、画笔
part 'home_text_styles.dart'; // 统一文字样式

/// 绑定流程所处的子场景。
///
/// - [none]：未进入绑定流程，显示首页主视图 [_HomeMainView]。
/// - [searching]：正在搜索附近设备。
/// - [notFound]：搜索结束但未发现设备。
/// - [found]：已发现附近设备，等待用户选择并绑定。
enum _HomeBindMode { none, searching, notFound, found }

/// 调试用场景枚举：配合 [_HomePageState._debugScene] 强制首页停在某个整页场景，
/// 便于逐个场景调样式（弹层类场景仍可在对应场景里点出来）。
enum _DebugScene {
  /// 首页-已绑定设备
  boundHome,

  /// 首页-未绑定设备
  unboundHome,

  /// 绑定设备-搜索中
  scanSearching,

  /// 绑定设备-未搜索到设备
  scanNotFound,

  /// 绑定设备-已搜索到设备
  scanFound,
}

/// 首页：App 主页面，承载「设备绑定 + 投屏」的核心流程。
///
/// 本页根据若干状态组合出多个 UI 场景，对应设计稿如下：
///
/// | 场景 | 触发条件 |
/// | --- | --- |
/// | 首页-已绑定设备 | `_bindMode == none` 且 [_activeDevice] != null |
/// | 首页-未绑定设备 | `_bindMode == none` 且 [_activeDevice] == null |
/// | 首页-已绑定设备-拍照or相册 | 已绑定时点「选择投屏方式」→ [_CastMethodSheet] |
/// | 首页-未绑定设备-立即绑定 | 未绑定时点拍照/相册 → [_DeviceNoticeSheet] |
/// | 首页-未绑定设备-重新连接 | 设备未连接时点拍照/相册 → [_DeviceNoticeSheet] |
/// | 首页-离线断网模式 | `state.isOffline == true` → [_DeviceNoticeSheet]（我知道了） |
/// | 绑定设备-搜索设备 | `_bindMode == searching` |
/// | 绑定设备-未搜索到设备 | `_bindMode == notFound` |
/// | 绑定设备-已搜索到设备 | `_bindMode == found` |
/// | 绑定设备-扫描不到怎么办? | 绑定流程中 `_showScanHelp == true` → [_ScanHelpSheet] |
class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.state, required this.onOpenMine});

  /// 全局业务状态（设备、权限、离线标记等），由根组件统一注入。
  final PhotoFrameState state;

  /// 切换到底部「我的」Tab 的回调。
  final VoidCallback onOpenMine;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  // ================= 调试开关（调样式用，发布前改回 null）=================
  // 把下面的 null 改成想看的场景，例如 `_DebugScene.boundHome`，即可让首页固定
  // 停在该场景。改这个值后请用「热重启 Hot Restart（按大写 R）」生效；
  // 之后改各组件样式用普通「热重载（按小写 r）」即可即时看到。
  //
  // 注意：① 非 null 时会覆盖真实交互逻辑（绑定流程里点返回也会被强制拉回该场景）；
  //      ② boundHome 的「设备轮播指示点」数量取自真正已连接的设备，默认数据里没有
  //         已连接设备，故点点为空；想看圆点可把 state.dart 里某台设备 connected 改 true。
  // ignore: unnecessary_nullable_for_final_variable_declarations  （需保持可空，便于改回 null）
  final _DebugScene? _debugScene = _DebugScene.scanSearching;

  // ---- 关键状态字段 ----

  /// 当前绑定子场景，决定显示主视图还是绑定流程视图。
  _HomeBindMode _bindMode = _HomeBindMode.none;

  /// 「已搜索到设备」列表中当前选中的设备下标。
  int _selectedFoundDeviceIndex = 0;

  /// 是否在绑定流程上叠加「扫描不到怎么办?」帮助弹层。
  bool _showScanHelp = false;

  /// 离线提示是否已弹出，避免同一次离线状态重复弹层。
  bool _offlineNoticeShown = false;

  /// 模拟扫描耗时的计时器。
  Timer? _scanTimer;

  /// 附近可绑定设备（演示数据直接取全部设备）。
  List<DeviceItem> get _nearbyDevices {
    return widget.state.devices.isEmpty
        ? const <DeviceItem>[]
        : widget.state.devices;
  }

  /// 是否存在已连接设备。
  bool get _hasConnectedDevice {
    return widget.state.devices.any((device) => device.connected);
  }

  /// 当前生效的已连接设备；为空即「未绑定」场景的判定依据。
  DeviceItem? get _activeDevice {
    if (!_hasConnectedDevice) {
      return null;
    }
    final selected = widget.state.selectedDevice;
    if (selected.connected) {
      return selected;
    }
    return widget.state.devices.firstWhere((device) => device.connected);
  }

  @override
  void initState() {
    super.initState();
    widget.state.addListener(_handleStateChanged);
    if (widget.state.isOffline) {
      _scheduleOfflineNotice();
    }
  }

  @override
  void dispose() {
    widget.state.removeListener(_handleStateChanged);
    _scanTimer?.cancel();
    super.dispose();
  }

  /// 监听全局状态：进入离线时弹出离线提示，恢复在线时复位标记。
  void _handleStateChanged() {
    if (!mounted) {
      return;
    }
    if (widget.state.isOffline) {
      _scheduleOfflineNotice();
    } else {
      _offlineNoticeShown = false;
    }
  }

  void _scheduleOfflineNotice() {
    if (_offlineNoticeShown) {
      return;
    }
    _offlineNoticeShown = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.state.isOffline) {
        _showOfflineNotice();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // 默认按真实状态/交互显示；_debugScene 非 null 时强制切到对应场景（调样式用）。
    var bindMode = _bindMode;
    var activeDevice = _activeDevice;
    final debugScene = _debugScene;
    if (debugScene != null) {
      switch (debugScene) {
        case _DebugScene.boundHome:
          bindMode = _HomeBindMode.none;
          activeDevice = widget.state.devices.isNotEmpty
              ? widget.state.devices.first
              : null;
          break;
        case _DebugScene.unboundHome:
          bindMode = _HomeBindMode.none;
          activeDevice = null;
          break;
        case _DebugScene.scanSearching:
          bindMode = _HomeBindMode.searching;
          activeDevice = null;
          break;
        case _DebugScene.scanNotFound:
          bindMode = _HomeBindMode.notFound;
          activeDevice = null;
          break;
        case _DebugScene.scanFound:
          bindMode = _HomeBindMode.found;
          activeDevice = null;
          break;
      }
    }

    // 背景图按场景区分：首页主视图（_bindMode == none，含其上各弹层）用 bg02，
    // 绑定设备流程（搜索/未找到/已找到/扫描帮助）用 bg01。
    final backgroundAsset = bindMode == _HomeBindMode.none
        ? 'assets/images/bg02.png'
        : 'assets/images/bg01.png';

    return Stack(
      fit: StackFit.expand,
      children: [
        _HomeBackground(asset: backgroundAsset),
        SafeArea(
          child: bindMode == _HomeBindMode.none
              ? _HomeMainView(
                  state: widget.state,
                  activeDevice: activeDevice,
                  onBindDevice: _startScan,
                  onAddDevice: _startScan,
                  onShowCastSheet: _showCastMethodSheet,
                  onCamera: () => _startCast(ImageSourceType.camera),
                  onAlbum: () => _startCast(ImageSourceType.album),
                  onOpenMine: widget.onOpenMine,
                )
              : _BindDeviceView(
                  mode: bindMode,
                  devices: _nearbyDevices,
                  selectedIndex: _selectedFoundDeviceIndex,
                  showScanHelp: _showScanHelp,
                  onBack: _closeBindFlow,
                  onHelp: () {
                    setState(() {
                      _showScanHelp = true;
                    });
                  },
                  onCloseHelp: () {
                    setState(() {
                      _showScanHelp = false;
                    });
                  },
                  onRetry: _startScan,
                  onCancel: _closeBindFlow,
                  onSelectDevice: (index) {
                    setState(() {
                      _selectedFoundDeviceIndex = index;
                    });
                  },
                  onBind: _bindSelectedDevice,
                ),
        ),
      ],
    );
  }

  /// 开始扫描：进入 searching，1.2s 后按是否有附近设备切到 found / notFound。
  void _startScan() {
    _scanTimer?.cancel();
    setState(() {
      _bindMode = _HomeBindMode.searching;
      _showScanHelp = false;
    });

    _scanTimer = Timer(const Duration(milliseconds: 1200), () {
      if (!mounted || _bindMode != _HomeBindMode.searching) {
        return;
      }
      setState(() {
        _bindMode = _nearbyDevices.isEmpty
            ? _HomeBindMode.notFound
            : _HomeBindMode.found;
        _selectedFoundDeviceIndex = 0;
      });
    });
  }

  /// 退出绑定流程，回到主视图。
  void _closeBindFlow() {
    _scanTimer?.cancel();
    setState(() {
      _bindMode = _HomeBindMode.none;
      _showScanHelp = false;
    });
  }

  /// 绑定当前选中的设备并回到主视图。
  void _bindSelectedDevice() {
    if (_nearbyDevices.isEmpty) {
      return;
    }
    final device =
        _nearbyDevices[_selectedFoundDeviceIndex.clamp(
          0,
          _nearbyDevices.length - 1,
        )];
    widget.state.connectDevice(device.id);
    _closeBindFlow();
  }

  /// 投屏入口：未绑定 / 未连接时先弹提示，否则进入拍照 / 相册流程。
  Future<void> _startCast(ImageSourceType source) async {
    final activeDevice = _activeDevice;
    if (activeDevice == null) {
      await _showDeviceNotice(
        title: '暂未绑定设备',
        message: '当前暂无可投屏设备，请先绑定相框设备',
        buttonLabel: '立即绑定',
        onPressed: _startScan,
      );
      return;
    }
    if (!activeDevice.connected) {
      await _showDeviceNotice(
        title: '设备连接失败',
        message: '当前设备未连接，APP需先连接设备后再投屏',
        buttonLabel: '重新连接',
        onPressed: _startScan,
      );
      return;
    }

    if (source == ImageSourceType.camera) {
      await _startCameraCast();
    } else {
      await _startAlbumCast();
    }
  }

  /// 通用提示弹层（立即绑定 / 重新连接 / 离线模式均复用）。
  Future<void> _showDeviceNotice({
    required String title,
    required String message,
    required String buttonLabel,
    required VoidCallback onPressed,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return _DeviceNoticeSheet(
          title: title,
          message: message,
          buttonLabel: buttonLabel,
          onPressed: () {
            Navigator.of(context).pop();
            onPressed();
          },
        );
      },
    );
  }

  /// 「首页-离线断网模式」提示。
  Future<void> _showOfflineNotice() async {
    await _showDeviceNotice(
      title: '离线模式',
      message: '当前网络异常，app进入离线模式无法同步投屏记录与图库',
      buttonLabel: '我知道了',
      onPressed: () {},
    );
  }

  /// 「选择投屏方式」弹层。
  Future<void> _showCastMethodSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return _CastMethodSheet(
          onCamera: () {
            Navigator.of(context).pop();
            _startCast(ImageSourceType.camera);
          },
          onAlbum: () {
            Navigator.of(context).pop();
            _startCast(ImageSourceType.album);
          },
        );
      },
    );
  }

  Future<void> _startCameraCast() async {
    final status = await NativeDeviceApi.requestCameraPermission();
    _syncPermissionState(status);
    if (!mounted) {
      return;
    }
    if (!status.cameraPermissionGranted) {
      _showFeedback('相机权限未开启，请授权后再使用拍照投屏。');
      return;
    }
    final draft = widget.state.createCameraDraft();
    await _showCastPreview(draft);
  }

  Future<void> _startAlbumCast() async {
    final status = await NativeDeviceApi.requestPhotoPermission();
    _syncPermissionState(status);
    if (!mounted) {
      return;
    }

    final selection = await NativeDeviceApi.openGallery();
    if (!mounted || selection == null) {
      return;
    }
    widget.state.setPermission(PermissionKind.album, true);
    final draft = widget.state.createAlbumDraft(
      title: selection.title,
      width: selection.width,
      height: selection.height,
      uri: selection.uri,
    );
    await _showCastPreview(draft);
  }

  Future<void> _showCastPreview(DraftPhoto draft) async {
    final deviceId = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => CastPreviewSheet(state: widget.state, draft: draft),
    );
    if (!mounted || deviceId == null) {
      return;
    }
    final result = widget.state.castDraft(draft: draft, deviceId: deviceId);
    _showFeedback(result.message);
    if (result.deviceFull) {
      widget.onOpenMine();
    }
  }

  void _syncPermissionState(DevicePermissionStatus status) {
    widget.state.setPermission(
      PermissionKind.location,
      status.locationPermissionGranted,
    );
    widget.state.setPermission(PermissionKind.bluetooth, status.bluetoothReady);
    widget.state.setPermission(
      PermissionKind.album,
      status.photoPermissionGranted,
    );
    widget.state.setPermission(
      PermissionKind.camera,
      status.cameraPermissionGranted,
    );
  }

  void _showFeedback(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}
