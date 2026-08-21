import 'package:flutter/material.dart';

import '../../state.dart';
import '../l10n/app_l10n.dart';

/// 「选择投屏设备」底部弹层（2026-08-13 同步小程序需求 2/3）。
///
/// **AI 对话页与官方图库详情页共用同一份**：两处此前各抄了一份弹层与样式，交互也同构，
/// 改一处必漏另一处 —— 本轮「不默认选中 + 加连接按钮」正是两处都要改的那种需求。
///
/// 交互与旧版有意不同：
/// - **不默认选中任何一台**。投屏是往设备写图且不可撤销，端上替用户选好、他顺手一点
///   就投到了别的设备上；
/// - **点一行只选中**，真正连接要按下面的主按钮（旧版是点中即刻连接投屏）；
/// - 未选中时主按钮置灰**且点击直接 return**：观感与行为必须一致，不留哑按钮。
///
/// 选中态由弹层自己持有（页面只关心「按下按钮时选了哪台」），每次打开都从空开始。
/// 列表版式照搬绑定页的「搜索到的设备」行：`home-icon02` 设备图 + 设备名 + 设备ID +
/// 右侧对勾，选中态是橙描边 + 浅橙底 + 橙色设备名。
///
/// 返回值：用户按下主按钮时返回选中的设备；取消 / 点遮罩返回 null。
Future<DeviceItem?> showDevicePickerSheet(
  BuildContext context, {
  required List<DeviceItem> devices,
}) {
  return showModalBottomSheet<DeviceItem>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: const Color(0x6B1E1D1B),
    // 设备多时列表自己滚，主按钮不会被顶出屏幕
    isScrollControlled: true,
    builder: (sheetContext) => _DevicePickerSheet(devices: devices),
  );
}

class _DevicePickerSheet extends StatefulWidget {
  const _DevicePickerSheet({required this.devices});

  final List<DeviceItem> devices;

  @override
  State<_DevicePickerSheet> createState() => _DevicePickerSheetState();
}

class _DevicePickerSheetState extends State<_DevicePickerSheet> {
  /// 这一屏内部的临时选中项（设备记录主键）。空串＝未选中，主按钮此时是灰的。
  String _selectedId = '';

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final media = MediaQuery.of(context);
    final selected = _selectedId.isNotEmpty;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(20, 16, 20, 13 + media.padding.bottom),
      decoration: BoxDecoration(
        color: const Color(0xFFFAF8F4).withValues(alpha: 0.98),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(21)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1F322B22),
            blurRadius: 20,
            offset: Offset(0, -7),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            l10n.devicePickerTitle,
            style: const TextStyle(
              color: Color(0xFF252525),
              fontSize: 19,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            l10n.devicePickerDesc,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFF8D8984), fontSize: 12.5),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(0, 12.5, 0, 10),
            child: Divider(height: 1, thickness: 1, color: Color(0xFFDFDBD5)),
          ),
          ConstrainedBox(
            // 上限按屏高给，横屏/小屏上主按钮与取消都还留得住
            constraints: BoxConstraints(maxHeight: media.size.height * 0.46),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: widget.devices.length,
              itemBuilder: (context, index) {
                final device = widget.devices[index];
                return _DevicePickerRow(
                  device: device,
                  selected: device.id == _selectedId,
                  onTap: () => setState(() => _selectedId = device.id),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          _ConfirmButton(
            label: l10n.devicePickerConfirm,
            enabled: selected,
            onTap: () {
              // 置灰态：没选设备时什么都不做（观感与行为一致）
              if (_selectedId.isEmpty) {
                return;
              }
              for (final device in widget.devices) {
                if (device.id == _selectedId) {
                  Navigator.of(context).pop(device);
                  return;
                }
              }
            },
          ),
          const SizedBox(height: 6),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              height: 44,
              alignment: Alignment.center,
              child: Text(
                l10n.cancel,
                style: const TextStyle(color: Color(0xFF6F6B66), fontSize: 15),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 单台设备行（对齐绑定页 `.nearby-device`）。
class _DevicePickerRow extends StatelessWidget {
  const _DevicePickerRow({
    required this.device,
    required this.selected,
    required this.onTap,
  });

  final DeviceItem device;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 64),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            color: selected
                ? const Color(0xFFFFF7F2)
                : Colors.white.withValues(alpha: 0.72),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected
                  ? const Color(0xFFFF6421)
                  : Colors.white.withValues(alpha: 0.88),
            ),
          ),
          child: Row(
            children: [
              // 设备图与首页/设备列表/详情/搜索四处同一张（该图四角透明自带圆角，别再套底色块）
              SizedBox(
                width: 44,
                height: 44,
                child: Image.asset(
                  'assets/images/home-icon02.png',
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) => const Icon(
                    Icons.photo_library_outlined,
                    color: Color(0xFFEB5F1B),
                    size: 26,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      device.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: selected
                            ? const Color(0xFFFF5A1E)
                            : const Color(0xFF2A2D32),
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    // 设备ID：同型号同名设备靠它区分（后端记录里的完整 6 字节）。
                    // 老记录可能没有，缺就不画这一行，不写「--」占位。
                    if (device.serialNumber.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        '${l10n.devDeviceId} ${device.serialNumber}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF8B9098),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 22,
                height: 22,
                child: selected
                    ? Image.asset(
                        'assets/images/selected-icon.png',
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stackTrace) => const Icon(
                          Icons.check_circle,
                          color: Color(0xFFFF6421),
                          size: 22,
                        ),
                      )
                    : DecoratedBox(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: const Color(0xFFC8CDD5),
                            width: 1.5,
                          ),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 主按钮：与绑定页「立即绑定」同款渐变胶囊；未选设备时灰底且不响应。
class _ConfirmButton extends StatelessWidget {
  const _ConfirmButton({
    required this.label,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 52,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: enabled ? null : const Color(0xFFD8D4CF),
          gradient: enabled
              ? const LinearGradient(
                  colors: [Color(0xFFFF8338), Color(0xFFFF621F)],
                )
              : null,
          borderRadius: BorderRadius.circular(999),
          boxShadow: enabled
              ? [
                  BoxShadow(
                    color: const Color(0xFFFF621F).withValues(alpha: 0.2),
                    blurRadius: 18,
                    offset: const Offset(0, 9),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
