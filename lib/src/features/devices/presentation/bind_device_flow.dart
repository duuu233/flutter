import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../../../device/ble_controller.dart';
import '../../../device/frame_device_protocol.dart';
import '../../../device/serial_match.dart';
import '../../../native_device_api.dart';
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

enum _Stage { scanning, found, notFound }

class _BindDeviceFlowPageState extends State<BindDeviceFlowPage> {
  final BleController _ble = BleController.instance;
  _Stage _stage = _Stage.scanning;
  List<ScanResult> _results = const [];
  bool _binding = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _startScan());
  }

  Future<void> _startScan() async {
    setState(() {
      _stage = _Stage.scanning;
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
      _toast('当前设备暂不支持蓝牙或未授权：$error');
      return;
    }
    if (!mounted) {
      return;
    }
    if (!status.bluetoothPermissionGranted) {
      setState(() => _stage = _Stage.notFound);
      await _showBluetoothGuide(
        title: '需要蓝牙权限',
        message: '搜索附近相框需要「蓝牙」与「附近设备」权限。请在系统设置中开启后，点「重新扫描」重试。',
        actionLabel: '去设置',
        onAction: NativeDeviceApi.openAppSettings,
      );
      return;
    }
    if (!status.bluetoothEnabled) {
      setState(() => _stage = _Stage.notFound);
      await _showBluetoothGuide(
        title: '请先打开手机蓝牙开关',
        message: '手机蓝牙未开启，无法搜索附近相框。打开蓝牙后，点「重新扫描」重试。',
        actionLabel: '去打开蓝牙',
        onAction: NativeDeviceApi.openBluetoothSettings,
      );
      return;
    }
    List<ScanResult> list;
    try {
      list = await _ble.scan();
    } catch (error) {
      if (!mounted) {
        return;
      }
      _toast('扫描失败：$error');
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
            child: const Text('取消'),
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

  Future<void> _bind(int index) async {
    if (_binding || index < 0 || index >= _results.length) {
      return;
    }
    setState(() => _binding = true);
    _toast('正在连接设备…');
    final result = _results[index];
    final error = await _ble.connect(result);
    if (!mounted) {
      return;
    }
    if (error != null) {
      setState(() => _binding = false);
      _toast('连接失败：$error');
      return;
    }
    // 连接成功（蓝牙会话已建立，可用于投屏）。
    final info = _ble.info;
    final serial = info?.deviceId ?? result.device.remoteId.str;
    final name = BleController.displayName(result);

    // 绑定判重（移植小程序 bind.js findBoundDevice）：把这台设备的两个序列号
    //（广播 4 字节 + 固件 6 字节 Device_ID）与已绑定记录容错比对（互为子串也算同一台），
    // 已绑定的不再新建记录——否则同一台相框会在设备列表反复出现（重复绑定记录）。
    // 先尽力刷新一次列表再判；刷新失败沿用本地列表，不把老设备误判成新设备。
    await widget.state.refreshDevices();
    if (!mounted) {
      return;
    }
    final serials = [_ble.broadcastDeviceId, info?.deviceId ?? '']
        .where((s) => s.isNotEmpty)
        .toList();
    // 本机屏幕类型码（优先固件 0x01 读到的，其次广播）：判重时按型号一票否决，
    // 防广播 4 字节与后端 6 字节偶合，把新设备(如 3.7寸)误判成已绑定的别台(如 5.89寸)而不新建绑定。
    final scannedScreen = info?.screenType ?? _ble.broadcastScreenType;
    DeviceItem? bound;
    for (final device in widget.state.devices) {
      if (!sameScreenCode(scannedScreen, device.screenType.code)) {
        continue;
      }
      if (serials.any((s) => serialsMatch(s, device.serialNumber))) {
        bound = device;
        break;
      }
    }
    if (bound != null) {
      widget.state.selectDevice(bound.id);
      widget.state.reconcileConnectionFlags();
      setState(() => _binding = false);
      _toast('该设备已绑定，已为你直接连接');
      Navigator.of(context).maybePop();
      return;
    }

    // 上报后端绑定。
    // productId 需后端「产品匹配」规则（按机型/SN 配 getProductList），此处用 screenType 占位，待确认。
    final productId = info?.screenType ?? 0;
    final feedback = await widget.state.bindDevice(
      productId: productId,
      productName: name,
      productSerialNo: serial,
    );
    if (!mounted) {
      return;
    }
    setState(() => _binding = false);
    _toast(feedback.message);
    // 无论后端绑定是否成功，蓝牙已连接，退回设备列表。
    Navigator.of(context).maybePop();
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    switch (_stage) {
      case _Stage.scanning:
        return BindDeviceSearching(
          onCancel: () => Navigator.maybePop(context),
        );
      case _Stage.notFound:
        return BindDeviceNotFound(onRetry: _startScan);
      case _Stage.found:
        return BindDeviceFound(
          devices: [for (final result in _results) BleController.displayName(result)],
          onRefresh: _startScan,
          onBindIndex: _bind,
        );
    }
  }
}
