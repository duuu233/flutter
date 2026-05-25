import 'package:flutter/material.dart';

import '../widgets/figma_common.dart';

class BindDeviceFound extends StatefulWidget {
  const BindDeviceFound({
    super.key,
    this.devices = const ['客厅相框', '卧室相框', '书房相框'],
    this.onBind,
  });

  final List<String> devices;
  final ValueChanged<String>? onBind;

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

    return FigmaPhoneFrame(
      child: Stack(
        children: [
          const FigmaPageBackground(),
          const Positioned(
            left: -1,
            top: 22,
            width: 378,
            height: 378,
            child: FigmaDeviceRadar(state: FigmaRadarState.found),
          ),
          const Positioned(
            left: 0,
            top: 0,
            width: 375,
            height: 90,
            child: FigmaTopNavigation(title: '绑定设备'),
          ),
          Positioned(
            left: 24,
            top: 370,
            width: 327,
            height: 28,
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    '附近设备',
                    style: TextStyle(
                      color: Color(0xFF2A2B2B),
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      height: 1.4,
                    ),
                  ),
                ),
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(
                    width: 28,
                    height: 28,
                  ),
                  icon: const Icon(Icons.refresh_rounded, size: 22),
                  onPressed: () {},
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
                  FigmaDeviceListCard(
                    name: widget.devices[i],
                    selected: i == safeSelectedIndex,
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
            child: FigmaPrimaryButton(
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
}
