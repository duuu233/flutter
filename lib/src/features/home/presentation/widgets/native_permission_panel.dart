import 'package:flutter/material.dart';

import '../../../../native_device_api.dart';
import '../../../../shared/shared.dart';
import '../../../../state.dart';

/// 原生权限申请面板（非独立页面）：引导用户授予相机 / 相册等系统权限。
class NativePermissionPanel extends StatefulWidget {
  const NativePermissionPanel({super.key, required this.state});

  final PhotoFrameState state;

  @override
  State<NativePermissionPanel> createState() => _NativePermissionPanelState();
}

class _NativePermissionPanelState extends State<NativePermissionPanel> {
  DevicePermissionStatus? _status;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _refreshStatus();
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    return Column(
      children: [
        _PermissionStatusTile(
          icon: Icons.bluetooth_connected_rounded,
          title: '蓝牙',
          active: status?.bluetoothReady == true,
          subtitle: _bluetoothText(status),
          actions: [
            FilledButton.tonal(
              onPressed: _loading
                  ? null
                  : () => _request(NativeDeviceApi.requestBluetoothPermissions),
              child: const Text('授权'),
            ),
            TextButton(
              onPressed: _loading
                  ? null
                  : NativeDeviceApi.openBluetoothSettings,
              child: const Text('去开启'),
            ),
          ],
        ),
        const Divider(height: 20),
        _PermissionStatusTile(
          icon: Icons.location_on_outlined,
          title: '位置',
          active: status?.locationPermissionGranted == true,
          subtitle: status?.locationPermissionGranted == true ? '已授权' : '未授权',
          actions: [
            FilledButton.tonal(
              onPressed: _loading
                  ? null
                  : () => _request(NativeDeviceApi.requestLocationPermission),
              child: const Text('授权'),
            ),
          ],
        ),
        const Divider(height: 20),
        _PermissionStatusTile(
          icon: Icons.photo_library_outlined,
          title: '相册',
          active:
              status?.photoPermissionGranted == true ||
              widget.state.permissions[PermissionKind.album] == true,
          subtitle: status?.photoPermissionGranted == true ? '已授权' : '未授权',
          actions: [
            FilledButton.tonal(
              onPressed: _loading
                  ? null
                  : () => _request(NativeDeviceApi.requestPhotoPermission),
              child: const Text('授权'),
            ),
            TextButton(
              onPressed: _loading ? null : _openGallery,
              child: const Text('打开相册'),
            ),
          ],
        ),
        const Divider(height: 20),
        _PermissionStatusTile(
          icon: Icons.photo_camera_outlined,
          title: '相机',
          active: status?.cameraPermissionGranted == true,
          subtitle: status?.cameraPermissionGranted == true ? '已授权' : '未授权',
          actions: [
            FilledButton.tonal(
              onPressed: _loading
                  ? null
                  : () => _request(NativeDeviceApi.requestCameraPermission),
              child: const Text('授权'),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _loading ? null : _refreshStatus,
                icon: _loading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh_rounded),
                label: const Text('刷新状态'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextButton(
                onPressed: _loading ? null : NativeDeviceApi.openAppSettings,
                child: const Text('应用设置'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _refreshStatus() async {
    await _request(NativeDeviceApi.getStatus);
  }

  Future<void> _request(
    Future<DevicePermissionStatus> Function() action,
  ) async {
    setState(() {
      _loading = true;
    });
    try {
      final status = await action();
      _applyStatus(status);
      if (mounted) {
        setState(() {
          _status = status;
        });
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text('系统能力调用失败：$error')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _openGallery() async {
    try {
      final selection = await NativeDeviceApi.openGallery();
      if (!mounted || selection == null) {
        return;
      }
      widget.state.setPermission(PermissionKind.album, true);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('已选择：${selection.title}')));
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text('打开相册失败：$error')));
      }
    }
  }

  void _applyStatus(DevicePermissionStatus status) {
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

  String _bluetoothText(DevicePermissionStatus? status) {
    if (status == null) {
      return '读取系统状态中';
    }
    if (!status.bluetoothAvailable) {
      return '当前设备不支持蓝牙';
    }
    if (!status.bluetoothPermissionGranted) {
      return '蓝牙权限未授权';
    }
    if (!status.bluetoothEnabled) {
      return '蓝牙未开启';
    }
    return '蓝牙已开启';
  }
}

class _PermissionStatusTile extends StatelessWidget {
  const _PermissionStatusTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.active,
    required this.actions,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool active;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final color = active
        ? const Color(0xFF2A9D8F)
        : Theme.of(context).colorScheme.error;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                color: color.withValues(alpha: 0.12),
              ),
              child: Icon(icon, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
                ],
              ),
            ),
            StatusPill(label: active ? '可用' : '未开启', active: active),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: actions),
      ],
    );
  }
}
