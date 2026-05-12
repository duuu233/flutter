import 'package:flutter/material.dart';

import '../../../shared/shared.dart';
import '../../../state.dart';

class DevicesPage extends StatelessWidget {
  const DevicesPage({super.key, required this.state});

  final PhotoFrameState state;

  @override
  Widget build(BuildContext context) {
    return SubPageScaffold(
      title: state.tr(zh: '我的设备', en: 'My Devices', ja: 'マイデバイス'),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          AppPanel(
            child: Text(
              state.tr(
                zh: '支持蓝牙搜索、连接切换、名称编辑、SN 码录入、所有者 / 使用者权限切换、设备一键清空和轮播模式控制。',
                en: 'Supports Bluetooth scan, connection switching, rename, SN code entry, owner/user role change, one-tap clear and carousel control.',
                ja: 'Bluetooth 検索、接続切替、名称編集、SN 入力、オーナー / 利用者切替、一括クリア、スライド制御に対応しています。',
              ),
            ),
          ),
          const SizedBox(height: 12),
          ...state.devices.map((device) {
            final usage = state.deviceUsage(device.id);
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: AppPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        DeviceIllustration(
                          color: device.connected
                              ? Theme.of(context).colorScheme.primary
                              : const Color(0xFF6B705C),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                device.name,
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              const SizedBox(height: 4),
                              Text('${device.kind} · ${device.serialNumber}'),
                            ],
                          ),
                        ),
                        StatusPill(
                          label: device.connected
                              ? state.tr(zh: '已连接', en: 'Connected', ja: '接続中')
                              : state.tr(zh: '未连接', en: 'Idle', ja: '未接続'),
                          active: device.connected,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        StatTag(
                          label: '${device.batteryLevel}%',
                          icon: Icons.battery_4_bar_rounded,
                          foreground: Theme.of(context).colorScheme.primary,
                          background: Theme.of(
                            context,
                          ).colorScheme.primary.withValues(alpha: 0.10),
                        ),
                        StatTag(
                          label: '$usage/${device.capacity}',
                          icon: Icons.photo_library_outlined,
                          foreground: const Color(0xFFD97757),
                          background: const Color(
                            0xFFD97757,
                          ).withValues(alpha: 0.12),
                        ),
                        StatTag(
                          label: state.roleLabel(device.role),
                          icon: Icons.lock_outline_rounded,
                          foreground: const Color(0xFF6B705C),
                          background: const Color(
                            0xFF6B705C,
                          ).withValues(alpha: 0.12),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        FilledButton.tonal(
                          onPressed: () => state.connectDevice(device.id),
                          child: Text(
                            device.connected
                                ? state.tr(
                                    zh: '当前设备',
                                    en: 'Current',
                                    ja: '現在の端末',
                                  )
                                : state.tr(zh: '连接设备', en: 'Connect', ja: '接続'),
                          ),
                        ),
                        FilledButton.tonal(
                          onPressed: () async {
                            final nextName = await promptText(
                              context,
                              title: state.tr(
                                zh: '修改设备名称',
                                en: 'Rename Device',
                                ja: '端末名を変更',
                              ),
                              initialValue: device.name,
                            );
                            if (nextName != null) {
                              state.renameDevice(device.id, nextName);
                            }
                          },
                          child: Text(
                            state.tr(zh: '编辑名称', en: 'Rename', ja: '名称編集'),
                          ),
                        ),
                        FilledButton.tonal(
                          onPressed: () async {
                            final nextSn = await promptText(
                              context,
                              title: state.tr(
                                zh: '输入设备 SN 码',
                                en: 'Input SN Code',
                                ja: 'SN コード入力',
                              ),
                              initialValue: device.serialNumber,
                            );
                            if (nextSn != null) {
                              state.updateDeviceSerial(device.id, nextSn);
                            }
                          },
                          child: Text(
                            state.tr(zh: 'SN 码', en: 'SN Code', ja: 'SN コード'),
                          ),
                        ),
                        FilledButton.tonal(
                          onPressed: () {
                            state.setDeviceRole(
                              device.id,
                              device.role == DeviceRole.owner
                                  ? DeviceRole.user
                                  : DeviceRole.owner,
                            );
                          },
                          child: Text(
                            device.role == DeviceRole.owner
                                ? state.tr(
                                    zh: '切换为使用者',
                                    en: 'Set as User',
                                    ja: '利用者に変更',
                                  )
                                : state.tr(
                                    zh: '设为所有者',
                                    en: 'Set as Owner',
                                    ja: 'オーナーに設定',
                                  ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SwitchListTile.adaptive(
                      value: device.carouselEnabled,
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        state.tr(
                          zh: '轮播模式',
                          en: 'Carousel Mode',
                          ja: 'スライドモード',
                        ),
                      ),
                      subtitle: Text(
                        state.tr(
                          zh: '开启后按启用时间起算 24 小时轮播下一张。',
                          en: 'After enabling, the next photo is shown every 24 hours.',
                          ja: '有効化後、24 時間ごとに次の写真へ切り替わります。',
                        ),
                      ),
                      onChanged: (value) =>
                          state.toggleCarousel(device.id, value),
                    ),
                    const SizedBox(height: 6),
                    TextButton.icon(
                      onPressed: () {
                        final feedback = state.clearDeviceMemory(device.id);
                        ScaffoldMessenger.of(context)
                          ..hideCurrentSnackBar()
                          ..showSnackBar(
                            SnackBar(content: Text(feedback.message)),
                          );
                      },
                      icon: const Icon(Icons.cleaning_services_outlined),
                      label: Text(
                        state.tr(zh: '一键清空', en: 'One-Tap Clear', ja: '一括クリア'),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}
