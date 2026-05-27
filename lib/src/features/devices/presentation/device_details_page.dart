import 'package:flutter/material.dart';

import 'package:BoltStar/src/shared/widgets/figma_common.dart';

/// 设备详情页：查看单个设备信息并进入轮播设置 / 清空 / 删除等操作。
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
    return FigmaScreen(
      title: '设备详情',
      body: DeviceDetailsBody(
        onCarouselSettings: onCarouselSettings,
        onClearDevice: onClearDevice,
        onDeleteDevice: onDeleteDevice,
      ),
    );
  }
}

/// 设备详情正文（供详情页与「删除 / 清空确认」页复用）。
class DeviceDetailsBody extends StatelessWidget {
  const DeviceDetailsBody({
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        FigmaGlassCard(
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
        const SizedBox(height: 16),
        FigmaGlassCard(
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
        const SizedBox(height: 16),
        FigmaGlassCard(
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
