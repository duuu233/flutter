import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 设备筛选下拉的一项（对齐小程序 `list.js` 的 `{ label, value }`）。
///
/// [id] 是后端设备ID（userProductId），**筛选与查询一律用它**：设备名允许重复，
/// 按名筛会把两台同名设备的数据混在一起。[label] 仅作展示（重名时带序列号尾号），
/// 不参与任何匹配/合并。
class DeviceFilterOption {
  const DeviceFilterOption({
    required this.id,
    required this.label,
    this.serialTail = '',
  });

  final String id;
  final String label;

  /// 序列号尾 4 位，仅在重名消歧时用于拼 label（见 [disambiguateDeviceFilterLabels]）。
  final String serialTail;
}

/// 设备筛选胶囊的固定宽度（pt）。
/// 小程序 `.nav-device-filter` 为 370rpx，750rpx = 屏宽 → 370/750 × 375 ≈ 185。
/// 图库与投屏管理两页共用同一个值，不允许任一页自己改宽窄。
const double kDeviceFilterChipWidth = 185;

/// 序列号（AA:BB:…:FF）去分隔符后的尾 4 位（如 D428）；无序列号返回 ''。
String deviceSerialTail(String serial) {
  final normalized = serial.replaceAll(RegExp(r'[:\-\s]'), '');
  return normalized.length <= 4
      ? normalized
      : normalized.substring(normalized.length - 4);
}

/// 同名设备消歧：筛选值已按设备ID区分，但下拉里两个一样的名字用户无法分辨，
/// 重名时给 label 补序列号尾 4 位，取不到序列号则按出现次序补 (2)/(3)。
///
/// 设备名只用于展示，不参与任何匹配/合并——数据归属一律按设备ID。
List<DeviceFilterOption> disambiguateDeviceFilterLabels(
  List<DeviceFilterOption> options,
) {
  final counts = <String, int>{};
  for (final option in options) {
    counts[option.label] = (counts[option.label] ?? 0) + 1;
  }
  final seen = <String, int>{};
  final result = <DeviceFilterOption>[];
  for (final option in options) {
    final nth = (seen[option.label] ?? 0) + 1;
    seen[option.label] = nth;
    if ((counts[option.label] ?? 0) < 2) {
      result.add(option);
      continue;
    }
    final suffix = option.serialTail.isNotEmpty ? option.serialTail : '$nth';
    result.add(
      DeviceFilterOption(id: option.id, label: '${option.label}($suffix)'),
    );
  }
  return result;
}

/// 设备筛选胶囊 + 下拉菜单（小程序 `.filter-btn` / `.filter-menu`，rpx ÷ 2）。
///
/// **不是**底部弹层：小程序是贴着胶囊右下角展开的下拉菜单（`.filter-wrap` 相对定位、
/// `.filter-menu` 绝对定位 `top:70rpx; right:0`），白 0.9 + 1px 白边 + 圆角 6，
/// 选中项是橙字 + 橙色淡底药丸（**没有对勾**）。这里用 [OverlayPortal] + [LayerLink]
/// 挂到 Overlay 上，保证菜单能盖住下方内容而不被 Column 裁掉。
///
/// 与小程序唯一有意的差异：多加一层透明全屏点击层，点空白处收起菜单——小程序没有遮罩、
/// 只能再点一次胶囊才收起，在 App 上那是明显的手感缺陷。
///
/// 图库与投屏记录两页共用本组件（需求第 13 项：投屏记录的下拉「样式模仿我的图库」）。
///
/// 2026-08-01 起两页都去掉了页面标题，这颗胶囊改挂在顶栏右上角承担标题作用，
/// 宽度按小程序 `.nav-device-filter` 的 370rpx 钉死（见 [kDeviceFilterChipWidth]），
/// 两页、两端完全一致——此前图库 112~200 自适应、投屏 370rpx 固定，宽度对不上。
class DeviceFilterChip extends StatefulWidget {
  const DeviceFilterChip({
    super.key,
    required this.label,
    required this.options,
    required this.selectedId,
    required this.onSelected,
    required this.onOpen,
  });

  final String label;

  /// 下拉项：调用方按设备ID去重、重名已消歧（见 [disambiguateDeviceFilterLabels]）。
  final List<DeviceFilterOption> options;
  final String? selectedId;
  final ValueChanged<String> onSelected;

  /// 每次展开前重拉设备接口，避免把上一次进页的设备列表当缓存用。
  final Future<void> Function() onOpen;

  @override
  State<DeviceFilterChip> createState() => _DeviceFilterChipState();
}

class _DeviceFilterChipState extends State<DeviceFilterChip> {
  final LayerLink _link = LayerLink();
  final OverlayPortalController _menu = OverlayPortalController();
  bool _open = false;
  bool _loading = false;
  int _openSeq = 0;

  Future<void> _toggle() async {
    if (_open) {
      _close();
      return;
    }
    final seq = ++_openSeq;
    setState(() {
      _open = true;
      _loading = true;
      _menu.show();
    });
    try {
      // 每次展开都走真实设备接口；loading 期间不展示上一轮选项，避免把 state 当缓存使用。
      await widget.onOpen();
    } finally {
      if (mounted && _open && seq == _openSeq) {
        setState(() => _loading = false);
      }
    }
  }

  void _close() {
    if (!_open) {
      return;
    }
    _openSeq++;
    setState(() {
      _open = false;
      _loading = false;
      _menu.hide();
    });
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _link,
      child: OverlayPortal(
        controller: _menu,
        overlayChildBuilder: (context) => Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _close,
              ),
            ),
            CompositedTransformFollower(
              link: _link,
              // 菜单右边缘与胶囊右边缘对齐，间隔 4（小程序 top:70rpx − 胶囊 62rpx）。
              targetAnchor: Alignment.bottomRight,
              followerAnchor: Alignment.topRight,
              offset: const Offset(0, 4),
              child: _FilterMenu(
                options: widget.options,
                selectedId: widget.selectedId,
                loading: _loading,
                onSelected: (id) {
                  _close();
                  widget.onSelected(id);
                },
              ),
            ),
          ],
        ),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _toggle,
          child: Container(
            height: 30,
            // 2026-08-01 起宽度钉死（不再自适应）：图库与投屏管理两页必须一模一样宽，
            // 自适应会让两页因设备名长短不同而宽窄不一，也与小程序对不上。
            // 长设备名单行省略号收尾，绝不把顶栏撑宽/换行。
            width: kDeviceFilterChipWidth,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.86),
              border: Border.all(color: Colors.white.withValues(alpha: 0.94)),
              borderRadius: BorderRadius.circular(999),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF7E96B8).withValues(alpha: 0.08),
                  blurRadius: 14,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: Text(
                    widget.label,
                    maxLines: 1,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF3B4149),
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      height: 1,
                    ),
                  ),
                ),
                const SizedBox(width: 9),
                _FilterArrow(open: _open),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 小程序 `.filter-arrow`：7×7 方块只留右/下 1px 边，旋转 45°（展开时 225°）成箭头。
class _FilterArrow extends StatelessWidget {
  const _FilterArrow({required this.open});

  final bool open;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 10,
      child: Center(
        child: Transform.rotate(
          angle: open ? 225 * math.pi / 180 : 45 * math.pi / 180,
          child: Transform.translate(
            offset: const Offset(0, -1.5),
            child: Container(
              width: 7,
              height: 7,
              decoration: const BoxDecoration(
                border: Border(
                  right: BorderSide(color: Color(0xFF777E88)),
                  bottom: BorderSide(color: Color(0xFF777E88)),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 小程序 `.filter-menu`：白 0.9、1px 白边、圆角 6、上下留白 4/6。
///
/// 宽度随最长设备名自适应（`width: max-content`），下限对齐胶囊宽度、上限 420rpx = 210：
/// 菜单绝不能比胶囊窄（看着像掉了一截），也不能宽到盖住半屏。
/// 超出上限的名字仍由 [_FilterOption] 单行省略号收尾。
class _FilterMenu extends StatelessWidget {
  const _FilterMenu({
    required this.options,
    required this.selectedId,
    required this.loading,
    required this.onSelected,
  });

  final List<DeviceFilterOption> options;
  final String? selectedId;
  final bool loading;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: Container(
        constraints: const BoxConstraints(
          minWidth: kDeviceFilterChipWidth,
          maxWidth: 210,
        ),
        padding: const EdgeInsets.only(top: 4, bottom: 6),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.9),
          border: Border.all(color: Colors.white.withValues(alpha: 0.95)),
          borderRadius: BorderRadius.circular(6),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF7E746A).withValues(alpha: 0.18),
              blurRadius: 20,
              offset: const Offset(0, 9),
            ),
          ],
        ),
        // IntrinsicWidth = CSS 的 `width: max-content`：菜单宽度取最长选项的自然宽度，
        // 再由上面的 constraints 夹到 140~240。少了它，选项里的 Container(alignment:center)
        // 会把自己撑满 maxWidth，菜单就永远是 240 宽（短名字时右侧一大片空白）。
        child: IntrinsicWidth(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            // 无「全部设备」项：对齐小程序单设备模型（图库跨设备选中会删错槽位；
            // 投屏记录也按设备分档查看）。选中态与回调都按设备ID，label 仅用于显示。
            children: [
              if (loading)
                const SizedBox(
                  height: 28,
                  child: Center(
                    child: SizedBox.square(
                      dimension: 13,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        color: Color(0xFFFF6A24),
                      ),
                    ),
                  ),
                )
              else
                for (final option in options)
                  _FilterOption(
                    label: option.label,
                    active: option.id == selectedId,
                    onTap: () => onSelected(option.id),
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 小程序 `.filter-option`：高 28、左右内缩 6、圆角 4；选中为橙字 + 橙淡底。
class _FilterOption extends StatelessWidget {
  const _FilterOption({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 28,
        margin: const EdgeInsets.symmetric(horizontal: 6),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? const Color(0xFFFF7436).withValues(alpha: 0.12) : null,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: active ? const Color(0xFFFF5F1F) : const Color(0xFF777E88),
              fontSize: 13,
              height: 1,
            ),
          ),
        ),
      ),
    );
  }
}
