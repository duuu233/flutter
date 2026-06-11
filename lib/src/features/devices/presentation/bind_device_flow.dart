import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../../../device/ble_controller.dart';
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
    final ok = await _ble.ensurePermission();
    if (!mounted) {
      return;
    }
    if (!ok) {
      _toast('请先打开手机蓝牙并授予蓝牙权限');
      setState(() => _stage = _Stage.notFound);
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
    // 连接成功（蓝牙会话已建立，可用于投屏）。上报后端绑定。
    // productId 需后端「产品匹配」规则（按机型/SN 配 getProductList），此处用 screenType 占位，待确认。
    final info = _ble.info;
    final serial = info?.deviceId ?? result.device.remoteId.str;
    final name = BleController.displayName(result);
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
