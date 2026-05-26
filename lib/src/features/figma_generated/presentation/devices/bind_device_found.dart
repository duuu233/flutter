import 'package:flutter/material.dart';

import '../home/home_figma_common.dart';
import '../widgets/figma_common.dart';

class BindDeviceFound extends StatefulWidget {
  const BindDeviceFound({
    super.key,
    this.devices = const ['客厅相框', '卧室相框', '书房相框'],
    this.onBind,
    this.onRefresh,
  });

  final List<String> devices;
  final ValueChanged<String>? onBind;
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

    return FigmaHomePhoneFrame(
      child: Stack(
        children: [
          const Positioned.fill(child: FigmaHomeBackground()),
          const Positioned(
            left: 52,
            top: 91,
            width: 270,
            height: 270,
            child: FigmaBluetoothRadar(state: FigmaRadarState.found),
          ),
          const Positioned(
            left: 0,
            top: 0,
            width: 375,
            height: 90,
            child: FigmaBindDeviceTopBar(),
          ),
          Positioned(
            left: 24,
            top: 379,
            width: 327,
            height: 28,
            child: Row(
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
          ),
          Positioned(
            left: 24,
            top: 406,
            width: 327,
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
          Positioned(
            left: 24,
            top: 702,
            width: 327,
            height: 56,
            child: FigmaHomePrimaryButton(
              label: '立即绑定',
              onPressed: selectedDevice.isEmpty
                  ? null
                  : () {
                      widget.onBind?.call(selectedDevice);
                      ScaffoldMessenger.of(context)
                        ..hideCurrentSnackBar()
                        ..showSnackBar(
                          SnackBar(content: Text('已选择 $selectedDevice')),
                        );
                    },
            ),
          ),
          const FigmaBottomHomeIndicator(),
        ],
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
