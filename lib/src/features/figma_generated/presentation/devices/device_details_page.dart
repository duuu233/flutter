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
                FigmaInfoRow(
                  label: '一键清空',
                  value: '清空设备本地所有照片',
                  icon: Icons.cleaning_services_outlined,
                  danger: true,
                  onTap: onClearDevice,
                ),
                const FigmaFormDivider(),
                FigmaInfoRow(
                  label: '删除设备',
                  value: '删除后将无法恢复',
                  icon: Icons.delete_outline_rounded,
                  danger: true,
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
