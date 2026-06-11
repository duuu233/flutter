import 'package:flutter/material.dart';

import 'package:BoltStar/src/shared/widgets/home_figma_common.dart';
import 'package:BoltStar/src/shared/widgets/figma_common.dart';

/// 绑定设备-发现设备页：展示搜索到的设备并发起绑定，对应 UI 稿「绑定设备-发现设备」。
class BindDeviceFound extends StatefulWidget {
  const BindDeviceFound({
    super.key,
    this.devices = const ['客厅相框', '卧室相框', '书房相框'],
    this.onBind,
    this.onBindIndex,
    this.onRefresh,
  });

  final List<String> devices;
  final ValueChanged<String>? onBind;

  /// 绑定回调（按选中下标），编排页用它映射回真实的扫描结果 / `ScanResult`。
  final ValueChanged<int>? onBindIndex;
  final VoidCallback? onRefresh;

  @override
  State<BindDeviceFound> createState() => _BindDeviceFoundState();
}

class _BindDeviceFoundState extends State<BindDeviceFound> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final safeSelectedIndex = widget.devices.isEmpty
        ? 0
        : _selectedIndex.clamp(0, widget.devices.length - 1);
    final selectedDevice = widget.devices.isEmpty
        ? ''
        : widget.devices[safeSelectedIndex];

    return FigmaScreen(
      title: '绑定设备',
      scrollable: false,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          const Center(
            child: SizedBox(
              width: 240,
              height: 240,
              child: FigmaBluetoothRadar(state: FigmaRadarState.found),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              const Expanded(
                child: Text(
                  '附近设备',
                  style: TextStyle(
                    color: Color(0xFF2A2B2B),
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    height: 1.2,
                  ),
                ),
              ),
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(
                  width: 28,
                  height: 28,
                ),
                icon: const Icon(
                  Icons.refresh_rounded,
                  color: Color(0xFFFF6A24),
                  size: 24,
                ),
                onPressed: widget.onRefresh,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  for (var i = 0; i < widget.devices.length; i++) ...[
                    FigmaBindDeviceCard(
                      name: widget.devices[i],
                      selected: i == safeSelectedIndex,
                      iconColor: _deviceAccent(i),
                      iconBackground: _deviceAccent(i).withValues(alpha: 0.10),
                      onTap: () {
                        setState(() {
                          _selectedIndex = i;
                        });
                      },
                    ),
                    if (i != widget.devices.length - 1)
                      const SizedBox(height: 12),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
      bottom: FigmaHomePrimaryButton(
        label: '立即绑定',
        onPressed: selectedDevice.isEmpty
            ? null
            : () {
                widget.onBind?.call(selectedDevice);
                widget.onBindIndex?.call(safeSelectedIndex);
                if (widget.onBind == null && widget.onBindIndex == null) {
                  ScaffoldMessenger.of(context)
                    ..hideCurrentSnackBar()
                    ..showSnackBar(
                      SnackBar(content: Text('已选择 $selectedDevice')),
                    );
                }
              },
      ),
    );
  }

  Color _deviceAccent(int index) {
    return switch (index) {
      0 => const Color(0xFFFF6A24),
      1 => const Color(0xFF2FB46B),
      _ => const Color(0xFF4A98FF),
    };
  }
}
