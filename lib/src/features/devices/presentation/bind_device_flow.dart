import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../../../device/ble_controller.dart';
import '../../../device/frame_device_protocol.dart';
import '../../../device/serial_match.dart';
import '../../../native_device_api.dart';
import '../../../routes/app_routes.dart';
import '../../../shared/l10n/app_l10n.dart';
import '../../../shared/widgets/app_toast.dart';
import '../../../shared/widgets/app_widgets.dart';
import '../../../shared/widgets/figma_common.dart';
import '../../../state.dart';
import 'bind_device_found.dart';
import 'bind_device_not_found.dart';
import 'bind_device_searching.dart';

/// 绑定设备流程编排页：权限 → 扫描 → 发现 / 未发现 → 连接 → 绑定。
///
/// 把扫描结果与连接态集中在一个 State 内，按阶段渲染对应的视觉页
/// （[BindDeviceSearching] / [BindDeviceFound] / [BindDeviceNotFound]）。
/// 真正的 BLE 动作走 [BleController]（持久连接，供首页/投屏复用）。
class BindDeviceFlowPage extends StatefulWidget {
  const BindDeviceFlowPage({super.key, required this.state});

  final PhotoFrameState state;

  @override
  State<BindDeviceFlowPage> createState() => _BindDeviceFlowPageState();
}

enum _Stage { permission, scanning, found, notFound }

class _BindDeviceFlowPageState extends State<BindDeviceFlowPage> {
  final BleController _ble = BleController.instance;
  // 初始为「权限确认」安静占位态：系统授权框必须**先于**扫描动画单独出现，
  // 不能压在「正在搜索」雷达页上同屏弹出（产品要求：先授权，后设备操作）。
  _Stage _stage = _Stage.permission;
  List<ScanResult> _results = const [];
  bool _binding = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _startScan());
  }

  Future<void> _startScan() async {
    // 权限阶段：页面保持只有导航栏的安静占位，等系统授权框（定位/附近设备）先行处理完。
    setState(() {
      _stage = _Stage.permission;
      _results = const [];
    });
    // 蓝牙开启/权限校验（对齐小程序 utils/bluetooth.js openAdapter + describeAdapterError）：
    // 区分「环境不支持/通道缺失」「权限没给」「蓝牙没开」，分别给明确引导，而不是把所有
    // 失败都静默混成「未发现设备」。try/catch 兜住 iOS 未注册 device_api 通道时的
    // MissingPluginException，避免整条链路卡在 searching。
    DevicePermissionStatus status;
    try {
      status = await NativeDeviceApi.requestBluetoothPermissions();
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _stage = _Stage.notFound);
      // 异常详情进日志，不进 toast（用户读不完也看不懂技术文本）。
      debugPrint('[Bind] 蓝牙权限通道异常: $error');
      _toast(AppL10n.of(context).bindBtUnsupported);
      return;
    }
    if (!mounted) {
      return;
    }
    if (!status.bluetoothPermissionGranted) {
      // 用户拒绝授权：直接弹「去设置」引导框（对齐产品图3），页面落到「未发现设备」可重试。
      setState(() => _stage = _Stage.notFound);
      final l10n = AppL10n.of(context);
      await _showBluetoothGuide(
        title: l10n.bindBtPermissionTitle,
        message: l10n.bindBtPermissionMessage,
        actionLabel: l10n.bindGoSettings,
        onAction: NativeDeviceApi.openAppSettings,
      );
      return;
    }
    if (!status.bluetoothEnabled) {
      setState(() => _stage = _Stage.notFound);
      final l10n = AppL10n.of(context);
      await _showBluetoothGuide(
        title: l10n.bindBtOffTitle,
        message: l10n.bindBtOffMessage,
        actionLabel: l10n.bindGoOpenBt,
        onAction: NativeDeviceApi.openBluetoothSettings,
      );
      return;
    }
    // 权限/开关全就绪，才切入「正在搜索」态开始设备操作（雷达动画 + BLE 扫描同时开始）。
    setState(() => _stage = _Stage.scanning);
    // 扫描：对齐小程序 bind.js —— 白名单只留目标相框（2 个尺寸），12s 窗口给「同时 2 台及以上」
    // 每台足够广播机会被搜到。与小程序 bind.wxml 一致：整段扫描期间保持「正在搜索」页
    //（列表由 `!scanning && devices.length` 门控），扫描结束后才一次性展示搜到的设备列表。
    List<ScanResult> list;
    try {
      list = await _ble.scan(timeout: const Duration(seconds: 12));
    } catch (error) {
      if (!mounted) {
        return;
      }
      debugPrint('[Bind] 扫描失败: $error');
      _toast(AppL10n.of(context).bindScanFailed);
      setState(() => _stage = _Stage.notFound);
      return;
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _results = list;
      _stage = list.isEmpty ? _Stage.notFound : _Stage.found;
    });
  }

  /// 把扫描结果构造成发现页的展示项：名称 + 「尺寸 · 电量XX% · 信号XX」副标题
  /// （对齐小程序 `bind.wxml` 的 `nearby-sub`）。屏型/电量取自广播厂商数据，信号取自 RSSI 档位。
  BindDeviceEntry _entryOf(ScanResult result) {
    final screen = BleController.screenLabelOf(result);
    final battery = BleController.batteryOf(result);
    final level = BleController.rssiToSignalLevel(result.rssi);
    final l10n = AppL10n.of(context);
    final signal = switch (level) {
      BleSignalLevel.veryStrong => l10n.signalVeryStrong,
      BleSignalLevel.strong => l10n.signalStrong,
      BleSignalLevel.normal => l10n.signalNormal,
      BleSignalLevel.weak => l10n.signalWeak,
      BleSignalLevel.veryWeak => l10n.signalVeryWeak,
      null => '--',
    };
    final parts = <String>[
      if (screen.isNotEmpty) screen,
      if (battery != null) l10n.bindBatteryLabel(battery),
      l10n.bindSignalLabel(signal),
    ];
    return BindDeviceEntry(
      id: result.device.remoteId.str,
      name: BleController.displayName(result),
      subtitle: parts.join(' · '),
    );
  }

  /// 蓝牙未开启 / 权限未授予时的引导弹窗：给一个「去设置 / 去打开蓝牙」的直达按钮
  /// （接 [NativeDeviceApi.openBluetoothSettings] / [NativeDeviceApi.openAppSettings]，
  ///  二者在 Android 侧已实现）。对齐小程序 showPermissionGuide 的明确引导，而非模糊 toast。
  Future<void> _showBluetoothGuide({
    required String title,
    required String message,
    required String actionLabel,
    required Future<void> Function() onAction,
  }) async {
    if (!mounted) {
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(AppL10n.of(dialogContext).cancel),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(dialogContext).pop();
              try {
                await onAction();
              } catch (_) {
                // 打开系统设置失败不阻断（如 iOS 通道未实现），用户可手动去设置。
              }
            },
            child: Text(actionLabel),
          ),
        ],
      ),
    );
  }

  /// 绑定当前选中设备（按 id），完整对齐小程序 `bind.js bindById`：
  /// 连接读信息 → 判重（已绑定则复用不新建）→ 绑定 → 回填选中 → 延时返回。
  Future<void> _bind(String id) async {
    if (_binding) {
      return; // 绑定进行中，忽略重复点击，避免重复绑定
    }
    final index = _results.indexWhere((r) => r.device.remoteId.str == id);
    if (index < 0) {
      return;
    }
    final result = _results[index];
    setState(() => _binding = true);

    // 真机设备：先连接读取真实信息（电量/播放/屏幕/固件），连接失败则中止绑定（无模拟兜底）。
    // Bug19：全程只保留这一个 loading，直到跳转设备列表前一刻才 hide——
    // 原实现连接成功后就 hide，随后的绑定网络请求（判重/上报/回查）+ 固定 800/500ms 延时全程无指示，
    // 观感就是「绑定中的框都没了还没跳转」。这里改为连接→绑定全程覆盖、跳转即消失。
    AppLoadingDialog.show(context, AppL10n.of(context).bindConnecting);
    try {
      final error = await _ble.connect(result);
      if (!mounted) {
        return;
      }
      if (error != null) {
        AppLoadingDialog.hide(context);
        setState(() => _binding = false);
        _toast(AppL10n.of(context).bindConnectFailed(error));
        return;
      }
      // 连接读信息成功：不再 hide、也不再 800ms 停留，直接进入绑定（loading 继续覆盖）。

      final info = _ble.info;
      // 提交后端的硬件序列号：对齐小程序 api.bindDevice 的 productDeviceId 优先级 ——
      // 固件 0x01 读到的 6 字节 Device_ID → 扫描广播的 4 字节 Device_ID → BLE deviceId(MAC) 兜底。
      final serial = [
        info?.deviceId ?? '',
        _ble.broadcastDeviceId,
        result.device.remoteId.str,
      ].firstWhere((s) => s.isNotEmpty, orElse: () => result.device.remoteId.str);
      final name = BleController.displayName(result);
      final serials = [
        _ble.broadcastDeviceId,
        info?.deviceId ?? '',
      ].where((s) => s.isNotEmpty).toList();
      // 本机屏幕类型码（优先固件 0x01 读到的，其次广播）：判重时按型号一票否决，
      // 防广播 4 字节与后端 6 字节偶合，把新设备(如 3.7寸)误判成已绑定的别台(如 5.89寸)而不新建绑定。
      final scannedScreen = info?.screenType ?? _ble.broadcastScreenType;

      // 绑定判重（移植小程序 bind.js findBoundDevice）：把这台设备的两个序列号
      //（广播 4 字节 + 固件 6 字节 Device_ID）与已绑定记录容错比对（互为子串也算同一台），
      // 已绑定的不再新建记录——否则同一台相框会在设备列表反复出现（重复绑定记录）。
      // 先尽力刷新一次列表再判；刷新失败沿用本地列表，不把老设备误判成新设备。
      await widget.state.refreshDevices();
      if (!mounted) {
        return;
      }
      final existed = _findBound(serials, scannedScreen);
      if (existed != null) {
        // 已绑定：复用该记录并设为当前选中（沿用刚建立的连接 = 已连接）。
        // 保持 binding=true 直到返回上一页，避免 500ms 窗口内被重复点击触发二次操作。
        widget.state.selectDevice(existed.id);
        widget.state.reconcileConnectionFlags();
        // 跳转前一刻关掉 loading，随即返回设备列表（去掉原 500ms 固定延时）。
        AppLoadingDialog.hide(context);
        _toast(AppL10n.of(context).bindAlreadyBoundConnected);
        Navigator.of(context).maybePop();
        return;
      }

      // 上报后端绑定：productId 由 state.bindDevice 内部拉产品列表按机型匹配解析（对齐小程序 api.bindDevice），
      // 这里把扫描到的型号/屏幕/名称传过去供匹配打分。
      final feedback = await widget.state.bindDevice(
        productName: name,
        productSerialNo: serial,
        model: BleController.modelOf(result),
        screen: BleController.screenLabelOf(result),
        scanName: name,
      );
      if (!mounted) {
        return;
      }
      if (!feedback.success) {
        // 绑定失败仍停留在本页：先关 loading，再断开占用的单连接，避免妨碍重试（对齐小程序 disconnect + 停留）。
        AppLoadingDialog.hide(context);
        await _ble.disconnect();
        if (!mounted) {
          return;
        }
        setState(() => _binding = false);
        _toast(feedback.message);
        return;
      }

      // 绑定成功后回查列表（bindDevice 内已 refreshDevices），用硬件序列号找到这条新记录并设为当前选中，
      // 让各页都能按稳定的 userProductId 认出它（对齐小程序绑定成功后回填 userProductId + setSelectedDevice）。
      final persisted = _findBound(serials, scannedScreen);
      if (persisted != null) {
        widget.state.selectDevice(persisted.id);
      }
      widget.state.reconcileConnectionFlags();
      // 跳转前一刻关掉 loading，随即返回设备列表（去掉原 500ms 固定延时；_binding 保持 true 到本页销毁，防重复点击）。
      AppLoadingDialog.hide(context);
      HapticFeedback.mediumImpact(); // 绑定成功触觉反馈
      _toast(AppL10n.of(context).bindSuccess);
      Navigator.of(context).maybePop();
    } finally {
      // 兜底收口：mounted 早退/异常路径都不把 canPop:false 的蒙层留在 root 栈上
      //（hide 幂等，上面各分支「跳转前一刻 hide」的时序不受影响）。
      AppLoadingDialog.hide(context);
    }
  }

  /// 在已绑定设备列表里按序列号容错交叉匹配 + 型号一票否决，找出这台已绑定记录（无则 null）。
  DeviceItem? _findBound(List<String> serials, int scannedScreen) {
    for (final device in widget.state.devices) {
      if (!sameScreenCode(scannedScreen, device.screenType.code)) {
        continue;
      }
      if (serials.any((s) => serialsMatch(s, device.serialNumber))) {
        return device;
      }
    }
    return null;
  }

  void _toast(String message) {
    AppToast.warn(context, message);
  }

  @override
  Widget build(BuildContext context) {
    switch (_stage) {
      case _Stage.permission:
        // 权限确认中的安静占位页：只有导航栏与背景，系统授权框单独呈现，
        // 不与「正在搜索」的雷达动画同屏。
        return FigmaScreen(
          title: AppL10n.of(context).bindDeviceTitle,
          scrollable: false,
          body: const SizedBox.expand(),
        );
      case _Stage.scanning:
        return BindDeviceSearching(onCancel: () => Navigator.maybePop(context));
      case _Stage.notFound:
        return BindDeviceNotFound(onRetry: _startScan);
      case _Stage.found:
        return BindDeviceFound(
          entries: [for (final result in _results) _entryOf(result)],
          onRefresh: _startScan,
          onBindId: _bind,
          // 长按某台设备进入硬件联调调试台（调试台自行扫描连接，此处仅提供进入入口）。
          onDebugId: (_) =>
              Navigator.of(context).pushNamed<void>(AppRoutes.bleDebug),
        );
    }
  }
}
