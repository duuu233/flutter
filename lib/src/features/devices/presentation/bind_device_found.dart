import 'package:flutter/material.dart';

import 'package:BoltStar/src/shared/widgets/home_figma_common.dart';
import 'package:BoltStar/src/shared/widgets/figma_common.dart';
import 'bind_device_debug_entry.dart';

/// 绑定设备-发现设备页里展示的单台设备视图模型。
///
/// [id]：本次扫描会话内稳定的设备标识（BLE remoteId），用于单选与回传绑定/调试目标；
/// [name]：展示名（广播名/平台名）；[subtitle]：尺寸 · 电量XX% · 信号XX（对齐小程序 `nearby-sub`）。
class BindDeviceEntry {
  const BindDeviceEntry({
    required this.id,
    required this.name,
    required this.subtitle,
  });

  final String id;
  final String name;
  final String subtitle;
}

/// 绑定设备-发现设备页：展示搜索到的设备并发起绑定，对应 UI 稿「绑定设备-发现设备」。
///
/// 单选逻辑对齐小程序 `bind.js`：默认选中信号最强那台（列表已按 RSSI 降序，第 0 台即最强），
/// 用户点选后保留其选择；底部「立即绑定」绑定当前选中项；长按某行进入该设备的硬件联调调试台。
class BindDeviceFound extends StatefulWidget {
  const BindDeviceFound({
    super.key,
    this.entries = const [],
    this.onBindId,
    this.onRefresh,
    this.onDebugId,
  });

  final List<BindDeviceEntry> entries;

  /// 绑定回调（按选中设备 id），编排页据此映射回真实的 `ScanResult`。
  final ValueChanged<String>? onBindId;
  final VoidCallback? onRefresh;

  /// 长按某台设备进入硬件联调调试台（对齐小程序 `openDebug`）。
  final ValueChanged<String>? onDebugId;

  @override
  State<BindDeviceFound> createState() => _BindDeviceFoundState();
}

class _BindDeviceFoundState extends State<BindDeviceFound> {
  /// 当前选中设备 id（空串表示尚未手动选择，走「默认选中信号最强」）。
  String _selectedId = '';

  @override
  Widget build(BuildContext context) {
    final entries = widget.entries;
    // 默认选中信号最强那台（列表按 RSSI 降序，首台即最强）；用户选过的 id 若仍在列表里则保留，
    // 避免增量刷新（搜出一个显示一个）时选中项来回跳（对齐小程序 applyScanResult 的选中保持）。
    final selectedId = entries.any((e) => e.id == _selectedId)
        ? _selectedId
        : (entries.isNotEmpty ? entries.first.id : '');

    return FigmaScreen(
      title: '绑定设备',
      scrollable: false,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const BindDebugEntryCard(),
          const SizedBox(height: 12),
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
                  for (var i = 0; i < entries.length; i++) ...[
                    FigmaBindDeviceCard(
                      name: entries[i].name,
                      subtitle: entries[i].subtitle,
                      selected: entries[i].id == selectedId,
                      iconColor: _deviceAccent(i),
                      iconBackground: _deviceAccent(i).withValues(alpha: 0.10),
                      onTap: () {
                        setState(() {
                          _selectedId = entries[i].id;
                        });
                      },
                      onLongPress: widget.onDebugId == null
                          ? null
                          : () => widget.onDebugId!(entries[i].id),
                    ),
                    if (i != entries.length - 1) const SizedBox(height: 12),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
      bottom: FigmaHomePrimaryButton(
        label: '立即绑定',
        onPressed: selectedId.isEmpty
            ? null
            : () => widget.onBindId?.call(selectedId),
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
