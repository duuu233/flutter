import 'package:flutter/material.dart';

import '../widgets/figma_common.dart';

class DeviceDetailsPage extends StatelessWidget {
  const DeviceDetailsPage({
    super.key,
    this.onCarouselSettings,
    this.onClearDevice,
    this.onDeleteDevice,
  });

  final VoidCallback? onCarouselSettings;
  final VoidCallback? onClearDevice;
  final VoidCallback? onDeleteDevice;

  @override
  Widget build(BuildContext context) {
    return FigmaPhoneFrame(
      child: Stack(
        children: [
          DeviceDetailsScene(
            onCarouselSettings: onCarouselSettings,
            onClearDevice: onClearDevice,
            onDeleteDevice: onDeleteDevice,
          ),
          const FigmaBottomHomeIndicator(),
        ],
      ),
    );
  }
}

class DeviceDetailsScene extends StatelessWidget {
  const DeviceDetailsScene({
    super.key,
    this.onCarouselSettings,
    this.onClearDevice,
    this.onDeleteDevice,
  });

  final VoidCallback? onCarouselSettings;
  final VoidCallback? onClearDevice;
  final VoidCallback? onDeleteDevice;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const FigmaPageBackground(),
        const Positioned(
          left: 0,
          top: 0,
          width: 375,
          height: 90,
          child: FigmaTopNavigation(title: '设备详情'),
        ),
        Positioned(
          left: 24,
          top: 109,
          width: 327,
          height: 104,
          child: FigmaGlassCard(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFAF8B).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(
                    Icons.photo_library_outlined,
                    color: Color(0xFFEB5F1B),
                    size: 32,
                  ),
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text(
                        '客厅相框',
                        style: TextStyle(
                          color: Color(0xFF2A2B2B),
                          fontSize: 20,
                          fontWeight: FontWeight.w500,
                          height: 1.35,
                        ),
                      ),
                      SizedBox(height: 7),
                      Text('已连接   80%', style: FigmaTextStyles.bodySmall),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        Positioned(
          left: 24,
          top: 235,
          width: 327,
          height: 300,
          child: FigmaGlassCard(
            child: Column(
              children: [
                FigmaInfoRow(
                  label: '轮播设置',
                  value: '顺序轮播',
                  onTap: onCarouselSettings,
                ),
                const FigmaFormDivider(),
                const FigmaInfoRow(label: '设备ID', value: '123456'),
                const FigmaFormDivider(),
                const FigmaInfoRow(label: '设备内存', value: '68/100'),
                const FigmaFormDivider(),
                const FigmaInfoRow(label: 'MAC地址', value: '123456'),
                const FigmaFormDivider(),
                const FigmaInfoRow(label: 'OTA升级', value: '版本1.2.0'),
              ],
            ),
          ),
        ),
        Positioned(
          left: 24,
          top: 563,
          width: 327,
          height: 122,
          child: FigmaGlassCard(
            child: Column(
              children: [
                _DangerActionRow(
                  label: '一键清空',
                  description: '清空设备本地所有照片',
                  icon: Icons.cleaning_services_outlined,
                  color: const Color(0xFFEB5F1B),
                  onTap: onClearDevice,
                ),
                const FigmaFormDivider(),
                _DangerActionRow(
                  label: '删除设备',
                  description: '删除后将无法恢复',
                  icon: Icons.delete_outline_rounded,
                  color: const Color(0xFFFF3B30),
                  onTap: onDeleteDevice,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _DangerActionRow extends StatelessWidget {
  const _DangerActionRow({
    required this.label,
    required this.description,
    required this.icon,
    required this.color,
    this.onTap,
  });

  final String label;
  final String description;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        height: 60,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              Icon(icon, size: 20, color: color),
              const SizedBox(width: 10),
              Text(
                label,
                style: FigmaTextStyles.formLabel.copyWith(color: color),
              ),
              const Spacer(),
              Text(
                description,
                style: FigmaTextStyles.formHint.copyWith(
                  color: const Color(0x992A2B2B),
                ),
              ),
              const SizedBox(width: 6),
              const Icon(
                Icons.chevron_right_rounded,
                color: Color(0x992A2B2B),
                size: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
