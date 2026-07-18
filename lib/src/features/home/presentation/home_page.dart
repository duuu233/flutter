import 'dart:async';
import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../shared/l10n/app_l10n.dart';

import '../../../routes/app_routes.dart';
import '../../../shared/avatar_upload.dart';
import '../../../shared/permission_gate.dart';
import '../../../shared/widgets/app_toast.dart';
import '../../../shared/widgets/app_widgets.dart';
import '../../../state.dart';
import '../../cast/cast_photo_picker.dart';
import '../../cast/presentation/cast_preview_page.dart';

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
/// | 绑定设备-搜索设备 | `_bindMode == searching` |
/// | 绑定设备-未搜索到设备 | `_bindMode == notFound` |
/// | 绑定设备-已搜索到设备 | `_bindMode == found` |
/// | 绑定设备-扫描不到怎么办? | 绑定流程中 `_showScanHelp == true` → [_ScanHelpSheet] |
class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.state, required this.onOpenMine});

  /// 全局业务状态（设备、权限、登录态等），由根组件统一注入。
  final PhotoFrameState state;

  /// 切换到底部「我的」Tab 的回调。
  final VoidCallback onOpenMine;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String? _pendingAvatarPath;
  bool _updatingAvatar = false;
  bool _openingDeviceList = false;

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


  /// 模拟扫描耗时的计时器。
  Timer? _scanTimer;

  /// 附近可绑定设备（演示数据直接取全部设备）。
  List<DeviceItem> get _nearbyDevices {
    return widget.state.devices.isEmpty
        ? const <DeviceItem>[]
        : widget.state.devices;
  }

  /// 首页当前展示的设备；为 null 即「未绑定」场景。
  ///
  /// 判定依据是**是否绑定过设备（设备列表非空）**，不是「蓝牙是否连着」——
  /// 对齐小程序 `home.js loadHomeState`：`hasRealDevice = normalizedList.length > 0`，
  /// 据此 `setScene(BOUND / UNBOUND)`，连接状态只决定卡片里显示「已连接/未连接」。
  /// 原来这里要求 `connected == true`，于是「已绑定但蓝牙没连」（冷启动的常态，
  /// 因为后端根本不存连接态）会被误判成「未绑定」，首页一直显示绑定引导空态。
  ///
  /// 展示优先级：用户刚在轮播中选中的 → 已连接的 → 第一台。
  /// 否则用户滑到一台未连接设备后，状态刷新会立刻把轮播弹回已连接设备。
  DeviceItem? get _activeDevice {
    final devices = widget.state.devices;
    if (devices.isEmpty) {
      return null;
    }
    final selectedId = widget.state.selectedDeviceId;
    final selected = devices.where((device) => device.id == selectedId);
    if (selected.isNotEmpty) {
      return selected.first;
    }
    final connected = devices.where((device) => device.connected);
    return connected.isNotEmpty ? connected.first : devices.first;
  }

  @override
  void initState() {
    super.initState();
    // 不再 addListener：首页在根部 AnimatedBuilder（bolt_star_app `home:`）之下，
    // 任何 state 通知本就会重建本页；原监听只服务于已删除的「离线弹层」死路径
    //（setOffline 从无调用方，isOffline 永 false）。
    // 进入首页即回后端刷新设备列表（对齐小程序 home.js onShow→loadHomeState）：
    // 否则登录后直接落到首页、其它 tab 尚未刷新时，已绑定设备会误显示「未绑定」空态。
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) {
        return;
      }
      await widget.state.refreshDevices();
      if (!mounted) {
        return;
      }
      // 电量/内存是蓝牙字段、后端不下发：列表刷完再对连接中的那台补一次 0x01 回读，
      // 首页卡片进来就是实时电量，而不是上一次读到的缓存值。
      for (final device in widget.state.devices) {
        if (device.connected) {
          await widget.state.refreshConnectedDeviceInfo(device.id);
          break; // BLE 同时只保持一条会话
        }
      }
    });
  }

  @override
  void dispose() {
    _scanTimer?.cancel();
    super.dispose();
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

    // 设备列表首屏还没回来时先显示 loading：否则首帧必然先渲染一次「未绑定」绑定引导页，
    // 接口回来再跳成设备卡片（对齐小程序 home.js 的 pageLoading:true 门控）。
    // 不判 isLoggedIn —— App 强制登录（见 bolt_star_app.dart），能进到首页就一定已登录。
    final waitingDevices = !widget.state.devicesLoaded;

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
                        devices: widget.state.devices,
                        onBindDevice: _startScan,
                        onAddDevice: _startScan,
                        pendingAvatarPath: _pendingAvatarPath,
                        onChangeAvatar: _changeAvatar,
                        onDeviceChanged: (device) {
                          widget.state.selectDevice(device.id);
                        },
                        onOpenDevices: _openDeviceList,
                        onConnectDevice: (device) {
                          _ensureConnected(device.id);
                        },
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
    Navigator.of(
      context,
    ).pushNamed<void>(AppRoutes.figmaBindDeviceSearching).then((_) {
      if (mounted) {
        widget.state.refreshDevices();
      }
    });
  }

  /// 首页头像入口：选择后立即本地回显并上传，对齐小程序 `onChooseAvatar`。
  Future<void> _changeAvatar() async {
    if (_updatingAvatar) {
      return;
    }
    // 进相册前先过照片权限（拒绝弹「去设置」引导并中止）。
    if (!await PermissionGate.ensurePhotoAccess(context) || !mounted) {
      return;
    }
    XFile? file;
    try {
      // 与「账户资料」页同参数（AvatarUpload）：原生降采样到 512px/JPEG85。
      // 原来不带参数直接取相机原图（4~12MB），解码后是 ~48MB 位图瞬间进内存，
      // 且原图整个上传——头像只在 36lp 圆圈里展示，两个入口必须同一行为。
      file = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: AvatarUpload.maxEdge,
        maxHeight: AvatarUpload.maxEdge,
        imageQuality: 85,
      );
    } catch (_) {
      if (mounted) {
        AppToast.warn(context, AppL10n.of(context).accAvatarUpdateFailed);
      }
      return;
    }
    if (file == null || !mounted) {
      return;
    }
    // 兜底压缩到 ≤100KB（与「账户资料」页同一逻辑），再本地回显并上传。
    final path = await AvatarUpload.ensureUnderLimit(file.path);
    if (!mounted) {
      return;
    }

    _updatingAvatar = true;
    setState(() => _pendingAvatarPath = path);
    final feedback = await widget.state.updateAvatar(path);
    if (!mounted) {
      return;
    }
    _updatingAvatar = false;
    setState(() => _pendingAvatarPath = null);
    if (feedback.success) {
      AppToast.show(context, AppL10n.of(context).accAvatarUpdated);
    } else {
      AppToast.warn(context, AppL10n.of(context).accAvatarUpdateFailed);
    }
  }

  /// 设备卡面积较大，锁住重复点击，避免同一列表页被连续压栈。
  Future<void> _openDeviceList() async {
    if (_openingDeviceList) {
      return;
    }
    _openingDeviceList = true;
    await Navigator.of(context).pushNamed<void>(AppRoutes.figmaMyDevices);
    _openingDeviceList = false;
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
      final l10n = AppL10n.of(context);
      await _showDeviceNotice(
        title: l10n.homeNoDeviceTitle,
        message: l10n.homeNoDeviceMessage,
        buttonLabel: l10n.homeBindNow,
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

    List<String> imagePaths;
    try {
      // 统一走 CastPhotoPicker：选图时就用平台原生解码器把长边降到 1920，
      // 避免把 4~12MB 的相机原图整个传给后端（投屏耗时大头在上传，不在 BLE）。
      imagePaths = (source == ImageSourceType.camera)
          ? await CastPhotoPicker.takePhoto()
          : await CastPhotoPicker.pickFromAlbum(context);
    } catch (_) {
      if (mounted) {
        _showFeedback(AppL10n.of(context).homeReadPhotoFailed);
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

    // 与小程序一致：选图后先进入投屏预览，可选择裁剪、旋转或保留原图，确认后再投屏。
    await Navigator.of(context).push<void>(
      AppPageRoute(
        // 选图后先进**投屏预览页**（裁剪/旋转/原图），确认后才开始投屏。
        builder: (_) => CastPreviewPage(
          state: widget.state,
          device: activeDevice,
          imagePaths: imagePaths,
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

  /// 确保设备已连接：蒙层 loading 自动扫连（对齐小程序 ensureActiveDeviceConnection），
  /// 连上返回 true；失败弹提示并返回 false。供投屏入口在未连接时自动重连。
  Future<bool> _ensureConnected(String deviceId) async {
    // 先单独走授权框（蓝牙/附近设备，部分系统为定位），全就绪才弹「连接中」loading——
    // 授权框不与设备操作同屏出现；拒绝时 ensureBleReady 内部已弹「去设置」引导。
    if (!await PermissionGate.ensureBleReady(context) || !mounted) {
      return false;
    }
    AppLoadingDialog.show(context, AppL10n.of(context).homeConnectingDevice);
    // 收口统一走 hide（精确移除自己的路由）且不做 mounted 门控：
    // 盲 pop 在并发 show 被静默忽略时会弹掉底下的业务页（历史闪退根源）；
    // mounted 门控则在页面被外力卸载时把 canPop:false 的蒙层永久留在 root 栈上。
    final ActionFeedback feedback;
    try {
      feedback = await widget.state.connectDevice(deviceId);
    } finally {
      AppLoadingDialog.hide(context);
    }
    if (!mounted) {
      return false;
    }
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
    AppToast.warn(context, message);
  }
}
