import 'dart:async';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../routes/app_routes.dart';
import '../../../shared/widgets/app_toast.dart';
import '../../../shared/widgets/app_widgets.dart';
import '../../../state.dart';
import '../../cast/presentation/casting_progress_page.dart';

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
  final _DebugScene? _debugScene = null;

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

  /// 首页当前展示的设备；为 null 即「未绑定」场景。
  ///
  /// 判定依据是**是否绑定过设备（设备列表非空）**，不是「蓝牙是否连着」——
  /// 对齐小程序 `home.js loadHomeState`：`hasRealDevice = normalizedList.length > 0`，
  /// 据此 `setScene(BOUND / UNBOUND)`，连接状态只决定卡片里显示「已连接/未连接」。
  /// 原来这里要求 `connected == true`，于是「已绑定但蓝牙没连」（冷启动的常态，
  /// 因为后端根本不存连接态）会被误判成「未绑定」，首页一直显示绑定引导空态。
  ///
  /// 展示优先级同小程序：已连接的 → 上次选中的 → 第一台。
  DeviceItem? get _activeDevice {
    final devices = widget.state.devices;
    if (devices.isEmpty) {
      return null;
    }
    final connected = devices.where((device) => device.connected);
    if (connected.isNotEmpty) {
      return connected.first;
    }
    final selectedId = widget.state.selectedDeviceId;
    final selected = devices.where((device) => device.id == selectedId);
    return selected.isNotEmpty ? selected.first : devices.first;
  }

  @override
  void initState() {
    super.initState();
    widget.state.addListener(_handleStateChanged);
    if (widget.state.isOffline) {
      _scheduleOfflineNotice();
    }
    // 进入首页即回后端刷新设备列表（对齐小程序 home.js onShow→loadHomeState）：
    // 否则登录后直接落到首页、其它 tab 尚未刷新时，已绑定设备会误显示「未绑定」空态。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        widget.state.refreshDevices();
      }
    });
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

    // 全ページ共通背景 bg01（小程序は首页/绑定流程とも同一 mock-bg 背景）。
    const backgroundAsset = 'assets/images/bg01.png';

    // 已登录但设备列表首屏还没回来时先显示 loading：否则首帧必然先渲染一次「未绑定」
    // 绑定引导页，接口回来再跳成设备卡片（对齐小程序 home.js 的 pageLoading:true 门控）。
    // 未登录（游客）不等接口，直接按未绑定展示，与小程序一致。
    final waitingDevices =
        widget.state.isLoggedIn && !widget.state.devicesLoaded;

    return Stack(
      fit: StackFit.expand,
      children: [
        _HomeBackground(asset: backgroundAsset),
        SafeArea(
          child: bindMode == _HomeBindMode.none
              ? (waitingDevices && _debugScene == null
                    ? const PageLoading()
                    : _HomeMainView(
                  state: widget.state,
                  activeDevice: activeDevice,
                  onBindDevice: _startScan,
                  onAddDevice: _startScan,
                  onShowCastSheet: _showCastMethodSheet,
                  onCamera: () => _startCast(ImageSourceType.camera),
                  onAlbum: () => _startCast(ImageSourceType.album),
                  onOpenMine: widget.onOpenMine,
                ))
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

  /// 开始绑定设备：跳转到真·蓝牙扫描绑定流程页（[BindDeviceFlowPage]）。
  ///
  /// 早期首页内嵌的是 mock 假扫描（`Timer(1200ms)` + 取后端已绑定列表当「附近设备」），
  /// 既不扫蓝牙也不校验蓝牙是否开启，这正是「搜索不到设备」的根因。现改为进入真链路：
  /// 权限/蓝牙开启校验 → `FlutterBluePlus` 扫描 → 连接 → 绑定。返回后刷新设备列表，
  /// 绑定成功的设备立即出现在首页。
  ///
  /// （首页内嵌的 mock 绑定视图 [_BindDeviceView] 仅保留给 [_debugScene] 调样式用，
  ///  正常交互不再触发。）
  void _startScan() {
    Navigator.of(context)
        .pushNamed<void>(AppRoutes.figmaBindDeviceSearching)
        .then((_) {
          if (mounted) {
            widget.state.refreshDevices();
          }
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
      // 未连接则自动扫连再投（对齐小程序 ensureActiveDeviceConnection）；连不上提示并中止。
      final connected = await _ensureConnected(activeDevice.id);
      if (!connected || !mounted) {
        return;
      }
    }

    // 拍照/相册选真实照片（image_picker 返回可上传的本地文件路径；content:// 无法直接上传）。
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
      if (mounted) {
        _showFeedback('无法读取照片，请检查相机/相册权限后重试。');
      }
      return;
    }
    if (!mounted || imagePaths.isEmpty) {
      return;
    }
    widget.state.setPermission(
      source == ImageSourceType.camera
          ? PermissionKind.camera
          : PermissionKind.album,
      true,
    );

    // 投屏「无预览 / 无中心裁切」：选好图直接进入真实投屏。
    // 与小程序一致的最小可用链路——原图交后端接口，后端按设备分辨率转码出 .raw 再 BLE 直传设备；
    // App 端不做预览、不做端上裁切/旋转编辑（既定方针）。
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => CastingProgressPage(
          userProductId: activeDevice.id,
          imagePaths: imagePaths,
          compressImage: widget.state.projectionCompress,
        ),
      ),
    );
    if (!mounted) {
      return;
    }
    // 投屏返回后刷新相册 / 投屏记录（真实数据同步）。
    widget.state.refreshAlbum();
    widget.state.refreshCastRecords();
  }

  /// 「重新连接」按钮：用户**手动**发起的连接（非投屏入口的自动重连）。
  /// 连接结果以吐司提示，连上后由用户再次点投屏——投屏本身不触发连接。
  /// 确保设备已连接：蒙层 loading 自动扫连（对齐小程序 ensureActiveDeviceConnection），
  /// 连上返回 true；失败弹提示并返回 false。供投屏入口在未连接时自动重连。
  Future<bool> _ensureConnected(String deviceId) async {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    final feedback = await widget.state.connectDevice(deviceId);
    if (!mounted) {
      return false;
    }
    Navigator.of(context, rootNavigator: true).pop(); // 关闭连接中 loading
    if (!feedback.success) {
      _showFeedback(feedback.message);
    }
    return feedback.success;
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

  void _showFeedback(String message) {
    AppToast.show(context, message);
  }
}
