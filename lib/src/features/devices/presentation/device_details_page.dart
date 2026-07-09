import 'package:flutter/material.dart';

import 'package:BoltStar/src/shared/widgets/figma_common.dart';
import '../../../device/frame_device_protocol.dart';
import '../../../state.dart';

/// 设备详情页：查看单个设备信息并进入轮播设置 / 清空 / 删除等操作。
///
/// 对照微信小程序 `photo-album/subpackages/device/detail`：摘要卡 + 信息列表 +
/// 操作列表（清空 / 删除），删除/清空走二次确认弹窗（见 [DeviceConfirmDialog]）。
/// 展示当前选中设备（`state.selectedDevice`），随 [PhotoFrameState] 变化自动刷新。
class DeviceDetailsPage extends StatelessWidget {
  const DeviceDetailsPage({
    super.key,
    required this.state,
    this.onCarouselSettings,
    this.onClearDevice,
    this.onDeleteDevice,
    this.onOtaUpgrade,
  });

  final PhotoFrameState state;
  final VoidCallback? onCarouselSettings;
  final VoidCallback? onClearDevice;
  final VoidCallback? onDeleteDevice;
  final VoidCallback? onOtaUpgrade;

  @override
  Widget build(BuildContext context) {
    return FigmaScreen(
      title: '设备详情',
      body: AnimatedBuilder(
        animation: state,
        builder: (context, _) => DeviceDetailsBody(
          state: state,
          onCarouselSettings: onCarouselSettings,
          onClearDevice: onClearDevice,
          onDeleteDevice: onDeleteDevice,
          onOtaUpgrade: onOtaUpgrade,
        ),
      ),
    );
  }
}

/// 设备详情正文（供详情页与「删除 / 清空确认」页复用）。
class DeviceDetailsBody extends StatelessWidget {
  const DeviceDetailsBody({
    super.key,
    required this.state,
    this.onCarouselSettings,
    this.onClearDevice,
    this.onDeleteDevice,
    this.onOtaUpgrade,
  });

  final PhotoFrameState state;
  final VoidCallback? onCarouselSettings;
  final VoidCallback? onClearDevice;
  final VoidCallback? onDeleteDevice;
  final VoidCallback? onOtaUpgrade;

  String get _carouselLabel {
    final device = state.selectedDevice;
    // 轮播设置是「连接才可信」的实时数据：未连接（含断开设备后）一律 -- 占位，与小程序详情页一致。
    if (!device.connected) {
      return '--';
    }
    if (!device.carouselEnabled) {
      return '已关闭';
    }
    return device.playbackMode == FramePlaybackMode.sequence ? '顺序轮播' : '随机轮播';
  }

  static String _batteryAsset(int level) {
    const levels = <int>[0, 10, 20, 30, 40, 50, 60, 70, 80, 90, 100];
    var nearest = levels.first;
    for (final candidate in levels) {
      if ((candidate - level).abs() < (nearest - level).abs()) {
        nearest = candidate;
      }
    }
    return 'assets/images/BatteryLevel/battery-$nearest.png';
  }

  @override
  Widget build(BuildContext context) {
    final device = state.selectedDevice;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        // 摘要卡：设备图标 + 名称 + 连接状态 / 电量。
        FigmaGlassCard(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: const Color(0xFFFF6A20).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Image.asset(
                  'assets/images/device-list-icon01.png',
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) => const Icon(
                    Icons.photo_library_outlined,
                    color: Color(0xFFEB5F1B),
                    size: 28,
                  ),
                ),
              ),
              const SizedBox(width: 17),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            device.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFF2A2D32),
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              height: 1.2,
                            ),
                          ),
                        ),
                        const SizedBox(width: 3),
                        Image.asset(
                          'assets/images/edit-icon01.png',
                          width: 18,
                          height: 18,
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) =>
                              const Icon(
                                Icons.edit_outlined,
                                size: 16,
                                color: Color(0x992A2B2B),
                              ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 9),
                    Row(
                      children: [
                        Image.asset(
                          device.connected
                              ? 'assets/images/bluetooth-icon.png'
                              : 'assets/images/bluetooth-icon-not.png',
                          width: 11,
                          height: 14,
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) =>
                              const SizedBox(width: 11, height: 14),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          device.connected ? '已连接' : '未连接',
                          style: TextStyle(
                            color: device.connected
                                ? const Color(0xFF287DFF)
                                : const Color(0xFF9BA2AD),
                            fontSize: 12,
                            height: 1,
                          ),
                        ),
                        if (device.connected) ...[
                          const SizedBox(width: 15),
                          Image.asset(
                            _batteryAsset(device.batteryLevel),
                            width: 24,
                            fit: BoxFit.contain,
                            errorBuilder: (context, error, stackTrace) =>
                                const Icon(
                                  Icons.battery_4_bar_rounded,
                                  size: 16,
                                  color: Color(0xFF777E88),
                                ),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            '${device.batteryLevel}%',
                            style: const TextStyle(
                              color: Color(0xFF777E88),
                              fontSize: 12,
                              height: 1,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // 信息列表：轮播设置 / 设备ID / 设备内存 / OTA升级。
        FigmaGlassCard(
          padding: const EdgeInsets.symmetric(horizontal: 19),
          child: Column(
            children: [
              _DetailRow(
                iconAsset: 'assets/images/device-detail-icon01.png',
                fallbackIcon: Icons.tune_rounded,
                label: '轮播设置',
                value: _carouselLabel,
                showChevron: true,
                onTap: onCarouselSettings,
              ),
              const _ThinDivider(),
              _DetailRow(
                iconAsset: 'assets/images/device-detail-icon02.png',
                fallbackIcon: Icons.tag_rounded,
                label: '设备ID',
                value: device.serialNumber.isEmpty
                    ? device.id
                    : device.serialNumber,
              ),
              const _ThinDivider(),
              _DetailRow(
                iconAsset: 'assets/images/device-detail-icon03.png',
                fallbackIcon: Icons.sd_storage_outlined,
                label: '设备内存',
                // 内存占用是连接才读得到的实时数据（0x01 的 IMG_MASK）：未连接（含断开设备后）一律 --，
                // 避免未连接时显示后端不下发而回落的 0/容量，误导用户（对齐小程序断开后内存变 --）。
                value: device.connected
                    ? '${device.imageCount}/${device.capacity}'
                    : '--',
              ),
              const _ThinDivider(),
              _DetailRow(
                iconAsset: 'assets/images/device-detail-icon04.png',
                fallbackIcon: Icons.system_update_alt_rounded,
                label: 'OTA升级',
                value: device.hasFirmwareUpdate
                    ? '发现新版本 ${device.newVersionNo}'
                    : (device.firmwareVersion.isEmpty
                        ? '-'
                        : device.firmwareVersion),
                showChevron: true,
                onTap: onOtaUpgrade,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // 操作列表：一键清空 / 删除设备。
        FigmaGlassCard(
          padding: const EdgeInsets.symmetric(horizontal: 19),
          child: Column(
            children: [
              _DetailRow(
                iconAsset: 'assets/images/device-detail-icon05.png',
                fallbackIcon: Icons.cleaning_services_outlined,
                label: '一键清空',
                labelColor: const Color(0xFFFF6A20),
                labelWeight: FontWeight.w500,
                value: '清空设备本地所有照片',
                showChevron: true,
                onTap: onClearDevice,
              ),
              const _ThinDivider(),
              _DetailRow(
                iconAsset: 'assets/images/device-detail-icon06.png',
                fallbackIcon: Icons.delete_outline_rounded,
                label: '删除设备',
                labelColor: const Color(0xFFFF3045),
                labelWeight: FontWeight.w500,
                value: '删除后将无法恢复',
                showChevron: true,
                onTap: onDeleteDevice,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 详情/操作列表的单行：左侧图标 + 标题，右侧取值（+ 可选箭头）。
class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.iconAsset,
    required this.fallbackIcon,
    required this.label,
    required this.value,
    this.labelColor = const Color(0xFF33373D),
    this.labelWeight = FontWeight.w600,
    this.showChevron = false,
    this.onTap,
  });

  final String iconAsset;
  final IconData fallbackIcon;
  final String label;
  final String value;
  final Color labelColor;
  final FontWeight labelWeight;
  final bool showChevron;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        height: 60,
        child: Row(
          children: [
            Image.asset(
              iconAsset,
              width: 20,
              height: 20,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) =>
                  Icon(fallbackIcon, size: 20, color: labelColor),
            ),
            const SizedBox(width: 15),
            Text(
              label,
              style: TextStyle(
                color: labelColor,
                fontSize: 14,
                fontWeight: labelWeight,
                height: 1.2,
              ),
            ),
            const Spacer(),
            Flexible(
              child: Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: const TextStyle(
                  color: Color(0xFF777E88),
                  fontSize: 14,
                  height: 1.2,
                ),
              ),
            ),
            if (showChevron) ...[
              const SizedBox(width: 8),
              const Icon(
                Icons.chevron_right_rounded,
                color: Color(0xFF777E88),
                size: 18,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 细分割线（小程序 `.thin-divider`，rgba(42,43,43,0.08)）。
class _ThinDivider extends StatelessWidget {
  const _ThinDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 1,
      color: const Color(0xFF2A2B2B).withValues(alpha: 0.08),
    );
  }
}

/// 设备「删除 / 清空」二次确认弹窗（小程序 `.confirm-dialog`）。
///
/// 左侧彩色图标盒 + 右侧标题/说明，底部「取消 / 确认」胶囊按钮。
class DeviceConfirmDialog extends StatelessWidget {
  const DeviceConfirmDialog({
    super.key,
    required this.iconAsset,
    required this.fallbackIcon,
    required this.accent,
    required this.title,
    required this.message,
    required this.onCancel,
    required this.onConfirm,
  });

  final String iconAsset;
  final IconData fallbackIcon;
  final Color accent;
  final String title;
  final String message;
  final VoidCallback onCancel;
  final VoidCallback? onConfirm;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 30, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Image.asset(
                    iconAsset,
                    width: 24,
                    height: 24,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) =>
                        Icon(fallbackIcon, color: accent, size: 24),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: Color(0xFF25282D),
                          fontSize: 19,
                          fontWeight: FontWeight.w700,
                          height: 1.15,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        message,
                        style: const TextStyle(
                          color: Color(0xFF6F7782),
                          fontSize: 12,
                          height: 1.45,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 21),
            Padding(
              padding: const EdgeInsets.only(left: 59),
              child: Row(
                children: [
                  Expanded(
                    child: _DialogButton(
                      label: '取消',
                      textColor: const Color(0xFF32363C),
                      background: const Color(0xFFEEEEEE),
                      onTap: onCancel,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _DialogButton(
                      label: '确认',
                      textColor: Colors.white,
                      gradient: const LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0xFFFF9140), Color(0xFFFF6A20)],
                      ),
                      onTap: onConfirm,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DialogButton extends StatelessWidget {
  const _DialogButton({
    required this.label,
    required this.textColor,
    required this.onTap,
    this.background,
    this.gradient,
  });

  final String label;
  final Color textColor;
  final VoidCallback? onTap;
  final Color? background;
  final Gradient? gradient;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: background,
          gradient: gradient,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: textColor,
            fontSize: 14,
            fontWeight: FontWeight.w500,
            height: 1,
          ),
        ),
      ),
    );
  }
}
