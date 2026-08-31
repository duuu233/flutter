import 'package:flutter/material.dart';

import 'package:BoltStar/src/shared/widgets/home_figma_common.dart';
import 'package:BoltStar/src/shared/widgets/figma_common.dart';
import '../../../shared/l10n/app_l10n.dart';
import 'bind_device_debug_entry.dart';

/// 绑定设备-发现设备页里展示的单台设备视图模型。
///
/// [id]：本次扫描会话内稳定的设备标识（BLE remoteId），用于单选与回传绑定/调试目标；
/// [name]：展示名（广播名/平台名）；[subtitle]：尺寸 · 电量XX% · 信号XX（对齐小程序 `nearby-sub`）；
/// [deviceId]：展示用设备ID（广播 Device_ID，带冒号；新固件 6 字节、老固件 4 字节，不截断）——
/// **与 [id] 不是一回事**，[id] 是平台给的 MAC/UUID、只作选中键从不展示，
/// [deviceId] 才是给用户看、用来区分同型号同名设备的那个。
class BindDeviceEntry {
  const BindDeviceEntry({
    required this.id,
    required this.name,
    required this.subtitle,
    this.deviceId = '',
  });

  final String id;
  final String name;
  final String subtitle;
  final String deviceId;
}

/// 绑定设备-发现设备页：展示搜索到的设备并发起绑定，对应 UI 稿「绑定设备-发现设备」。
///
/// 单选逻辑对齐小程序 `bind.js`：默认选中**最先搜到**那台（列表按首见先后排，第 0 台即最先），
/// 用户点选后保留其选择；底部「立即绑定」绑定当前选中项；长按某行进入该设备的硬件联调调试台。
///
/// [scanning]=true 时本页是「边搜边显示」态：雷达继续转、标题显示已找到台数、隐藏重新搜索按钮
/// （还在搜，重搜没意义）、在台数后显示「结束搜索」文字链。此时也能直接点「立即绑定」，
/// 编排页会先停扫再连。
class BindDeviceFound extends StatefulWidget {
  const BindDeviceFound({
    super.key,
    this.entries = const [],
    this.scanning = false,
    this.onBindId,
    this.onRefresh,
    this.onStopScan,
    this.onDebugId,
  });

  final List<BindDeviceEntry> entries;

  /// 扫描是否仍在进行（决定雷达转不转、标题文案、是否显示「结束搜索」）。
  final bool scanning;

  /// 绑定回调（按选中设备 id），编排页据此映射回真实的 `ScanResult`。
  final ValueChanged<String>? onBindId;
  final VoidCallback? onRefresh;

  /// 「结束搜索」：立刻收手，保留已搜到的列表（不退出本页）。
  final VoidCallback? onStopScan;

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
    final l10n = AppL10n.of(context);
    // 默认选中最先搜到那台（列表按首见先后排，首台即最先）；用户选过的 id 若仍在列表里则保留，
    // 避免增量刷新（搜出一个显示一个）时选中项来回跳（对齐小程序 applyScanResult 的选中保持）。
    final selectedId = entries.any((e) => e.id == _selectedId)
        ? _selectedId
        : (entries.isNotEmpty ? entries.first.id : '');

    return FigmaScreen(
      title: l10n.bindDeviceTitle,
      scrollable: false,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const BindDebugEntryCard(),
          const SizedBox(height: 12),
          Center(
            child: SizedBox(
              // 与 BindDeviceSearching 保持同一 280×280 尺寸。首台设备出现时页面会从
              // searching 切到 found；此前这里是 240，导致同一 GIF 在“刚开始搜到设备”
              // 的瞬间肉眼可见地缩小一圈。
              width: 280,
              height: 280,
              // 搜索期间雷达一直转（哪怕已经搜到设备）：下面的列表同步追加，两者并存才是
              // 「边搜边显示」。用的是搜索中页那张同款 gif，两页视觉连续、不闪一下静态图。
              child: widget.scanning
                  ? const Image(
                      image: AssetImage('assets/images/search-devices.gif'),
                      fit: BoxFit.contain,
                    )
                  : const FigmaBluetoothRadar(state: FigmaRadarState.found),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Text(
                      l10n.bindFoundCount(entries.length),
                      style: const TextStyle(
                        color: Color(0xFF8B9098),
                        fontSize: 13,
                        fontWeight: FontWeight.w400,
                        height: 1.4,
                      ),
                    ),
                    if (widget.scanning)
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: widget.onStopScan,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Text(
                            l10n.bindEndSearchInline,
                            style: const TextStyle(
                              color: Color(0xFFFF6421),
                              fontSize: 13,
                              fontWeight: FontWeight.w400,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              // 还在搜的时候不给「重新搜索」：列表正在自己长，重搜只会把已搜到的清光重来。
              if (!widget.scanning)
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
              // ⚠️ 底部留白（2026-08-31）：列表滚到底时，最后一张设备卡会**紧贴**下方
              // 「立即绑定」按钮——[FigmaScreen] 的 bottom 槽上内边距只有 8，
              // 加上卡片自带的投影，看起来就是压在按钮上。这里给滚动内容补 16，
              // 让最后一张能滚到按钮上方留出一指的空档。
              // ⚠️ 补在**滚动内容**上而不是 Expanded 外面：补在外面会把可视区整体抬高，
              // 列表短的时候上方会莫名多出一截空白。
              padding: const EdgeInsets.only(bottom: 16),
              child: Column(
                children: [
                  for (var i = 0; i < entries.length; i++) ...[
                    FigmaBindDeviceCard(
                      name: entries[i].name,
                      subtitle: entries[i].subtitle,
                      deviceId: entries[i].deviceId,
                      selected: entries[i].id == selectedId,
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
        label: l10n.bindBindNow,
        // 「立即绑定」文字加粗对齐小程序 bind.wxss 的 .primary-action(font-weight:700)。
        fontWeight: FontWeight.w700,
        onPressed: selectedId.isEmpty
            ? null
            : () => widget.onBindId?.call(selectedId),
      ),
    );
  }
}
