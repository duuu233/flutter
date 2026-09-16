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

/// 两张设备卡之间的间距。与 [_kListViewport] 是同一笔账，改一处必须改另一处。
const double _kCardGap = 12;

/// 设备卡高度。写死在 [FigmaBindDeviceCard] 里（`height: 82`），这里抄一份用来算列表视口；
/// 那边改了高度，这里要跟着改（`bind_device_found` 的注释与它互相指认）。
const double _kCardHeight = 82;

/// 设备列表的**目标可视高度＝4.5 张卡**（2026-09-16 产品要求）：
/// 4 张完整（含 4 条间距）+ 露出半张。露出的那半张就是「还能往下滑」的提示，
/// 比正好切在卡片缝上、看着像「就这么多」强。
/// 对齐小程序 `bind.wxss` 的 `.device-list { max-height: 844rpx }`（=422，两端卡高不同故数字不同）。
const double _kListViewport = _kCardHeight * 4 + _kCardGap * 4 + _kCardHeight / 2;

/// 「已找到 N 台 / 结束搜索 / 重新搜索」那一行的固定高度。
///
/// 固定而不是让它自然高：扫描中是「文字 + 上下各 12 的点击热区」≈42，扫描结束换成
/// 28 的 [IconButton]，不固定的话搜索一停整页会往上跳一下。44 同时也是可点区域的下限。
const double _kCountRowHeight = 44;

/// 雷达尺寸的上下限。上限 280 = 搜索中页的尺寸（两页切换时不缩一圈）；
/// 下限 150 是「还看得出是个雷达」的底线——到这儿还装不下，就轮到列表让高度了。
const double _kRadarMax = 280;
const double _kRadarMin = 150;

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
          // ⚠️ 雷达与列表**一起**放进这个 LayoutBuilder（2026-09-16）：产品要的是
          // 「列表高度 = 4.5 张设备卡，最后一张露一半表示还能滑」，而这一屏的高度是固定的
          // ——列表要长到 4.5 张，只能从雷达那儿要。所以两者的高度在这里一次算完：
          //   · 列表优先拿到 [_kListViewport]（4 张整 + 半张）；
          //   · 雷达拿剩下的，夹在 [_kRadarMin]~[_kRadarMax] 之间；
          //   · 屏幕再矮（小屏 / 分屏 / 系统大字号）连雷达的下限都保不住时，才反过来压列表
          //     ——那是「一屏装不下」的降级，不是把卡片塞到按钮底下。
          // 对齐小程序 `bind.wxss`：那边是同一套做法（`.bind-content` 竖向 flex，
          // 雷达 `flex-shrink: 40`、列表 `max-height: 844rpx` + `flex-shrink: 1`）。
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                // 雷达与统计行之间 20、统计行与列表之间 12，统计行自身固定 [_kCountRowHeight]。
                const double fixed = 20 + _kCountRowHeight + 12;
                final double avail = constraints.maxHeight;
                final double radarSize = (avail - _kListViewport - fixed).clamp(
                  _kRadarMin,
                  _kRadarMax,
                );
                final double listHeight = (avail - radarSize - fixed).clamp(
                  0.0,
                  _kListViewport,
                );
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: SizedBox(
                        // 搜索中页的雷达是 280×280；本页在「还搜得到 4.5 张卡的空间」的前提下
                        // 尽量贴近它，屏幕不够高时才按上面那笔账缩小（下限 [_kRadarMin]）。
                        // 首台设备出现时页面会从 searching 切到 found，尺寸因此可能跳一下，
                        // 这是把高度让给列表的代价（产品这轮明确要列表）。
                        width: radarSize,
                        height: radarSize,
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
                    SizedBox(
                      height: _kCountRowHeight,
                      child: Row(
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
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: listHeight,
                      child: SingleChildScrollView(
                        // ⚠️ 底部留白（2026-08-31）：列表滚到底时，最后一张设备卡会**紧贴**下方
                        // 「立即绑定」按钮——[FigmaScreen] 的 bottom 槽上内边距只有 8，
                        // 加上卡片自带的投影，看起来就是压在按钮上。这里给滚动内容补 16，
                        // 让最后一张能滚到按钮上方留出一指的空档。
                        // ⚠️ 补在**滚动内容**上而不是外面：补在外面会把可视区整体抬高，
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
                              if (i != entries.length - 1) const SizedBox(height: _kCardGap),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              },
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
