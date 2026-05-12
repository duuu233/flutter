import 'package:flutter/material.dart';

import '../../../native_device_api.dart';
import '../../../shared/shared.dart';
import '../../../state.dart';
import 'widgets/cast_preview_sheet.dart';
import 'widgets/native_permission_panel.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key, required this.state, required this.onOpenMine});

  final PhotoFrameState state;
  final VoidCallback onOpenMine;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selectedDevice = state.selectedDevice;
    final usage = state.deviceUsage(selectedDevice.id);

    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 120),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(32),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xFF102A43),
                      Color(0xFF234E52),
                      Color(0xFF2A6F6F),
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.18),
                      blurRadius: 26,
                      offset: const Offset(0, 16),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            state.tr(
                              zh: '相框投屏',
                              en: 'Frame Cast',
                              ja: 'フレーム投映',
                            ),
                            key: const Key('home-title'),
                            style: theme.textTheme.displaySmall?.copyWith(
                              color: Colors.white,
                            ),
                          ),
                        ),
                        StatTag(
                          label: '${selectedDevice.batteryLevel}%',
                          icon: Icons.battery_5_bar_rounded,
                          foreground: Colors.white,
                          background: Colors.white.withValues(alpha: 0.12),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      state.tr(
                        zh: '围绕拍照、相册、设备切换和投屏记录的一体化工作台。',
                        en: 'A unified workspace for capture, album upload, device switching and casting records.',
                        ja: '撮影、アルバム、端末切替、投映履歴をまとめたワークスペース。',
                      ),
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: Colors.white.withValues(alpha: 0.82),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        HeroMetric(
                          label: state.tr(
                            zh: '当前设备',
                            en: 'Active Device',
                            ja: '現在の端末',
                          ),
                          value: selectedDevice.name,
                        ),
                        HeroMetric(
                          label: state.tr(zh: '容量占用', en: 'Capacity', ja: '容量'),
                          value: '$usage/${selectedDevice.capacity}',
                        ),
                        HeroMetric(
                          label: state.tr(
                            zh: '启用权限',
                            en: 'Permissions',
                            ja: '権限',
                          ),
                          value:
                              '${state.activePermissionCount}/${state.totalPermissionCount}',
                        ),
                        HeroMetric(
                          label: state.tr(
                            zh: '成功率',
                            en: 'Success Rate',
                            ja: '成功率',
                          ),
                          value: '${(state.successRate * 100).round()}%',
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: () => _startCameraCast(context),
                            icon: const Icon(Icons.photo_camera_outlined),
                            label: Text(
                              state.tr(
                                zh: '拍照投屏',
                                en: 'Camera Cast',
                                ja: '撮影して投映',
                              ),
                            ),
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFFD97757),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => _showDevicePicker(context),
                            icon: const Icon(Icons.bluetooth_searching_rounded),
                            label: Text(
                              state.tr(
                                zh: '切换设备',
                                en: 'Switch Device',
                                ja: '端末切替',
                              ),
                            ),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white,
                              side: BorderSide(
                                color: Colors.white.withValues(alpha: 0.4),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 16),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              SectionHeader(
                title: state.tr(zh: '投屏入口', en: 'Casting Entries', ja: '投映入口'),
                subtitle: state.tr(
                  zh: '覆盖拍照、相册、权限和蓝牙绑定。',
                  en: 'Cover camera, album, permissions and Bluetooth binding.',
                  ja: '撮影、アルバム、権限、Bluetooth バインドをまとめます。',
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: ActionCard(
                      icon: Icons.collections_outlined,
                      title: state.tr(
                        zh: '相册选图',
                        en: 'Album Picker',
                        ja: 'アルバム選択',
                      ),
                      subtitle: state.tr(
                        zh: '挑选样片并进入设备预览。',
                        en: 'Pick a sample and open device preview.',
                        ja: '画像を選んで端末プレビューへ進みます。',
                      ),
                      accent: const Color(0xFF3D5A80),
                      onTap: () => _startAlbumCast(context),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ActionCard(
                      icon: Icons.verified_user_outlined,
                      title: state.tr(
                        zh: '权限检查',
                        en: 'Permissions',
                        ja: '権限確認',
                      ),
                      subtitle: state.tr(
                        zh: '位置、蓝牙、相机统一配置。',
                        en: 'Manage location, Bluetooth and camera.',
                        ja: '位置情報・Bluetooth・カメラを一括設定。',
                      ),
                      accent: const Color(0xFF6B705C),
                      onTap: () => _showPermissionPanel(context),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ActionCard(
                icon: Icons.route_rounded,
                title: state.tr(zh: '投屏流程', en: 'Casting Flow', ja: '投映フロー'),
                subtitle: state.tr(
                  zh: '选择图片 > 选择设备 > 预览尺寸 > 确认投屏。',
                  en: 'Select image > device > preview size > confirm cast.',
                  ja: '画像選択 > 端末選択 > サイズ確認 > 投映確定。',
                ),
                accent: const Color(0xFFD4A373),
                onTap: () => _showFlowGuide(context),
              ),
              const SizedBox(height: 20),
              SectionHeader(
                title: state.tr(zh: '当前设备', en: 'Current Device', ja: '現在の端末'),
                subtitle: state.tr(
                  zh: '支持设备切换、容量查看和轮播状态查看。',
                  en: 'Switch devices and inspect capacity and carousel state.',
                  ja: '端末切替、容量確認、スライド状態確認に対応。',
                ),
              ),
              const SizedBox(height: 12),
              AppPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        DeviceIllustration(color: const Color(0xFF234E52)),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                selectedDevice.name,
                                style: theme.textTheme.titleLarge,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                selectedDevice.kind,
                                style: theme.textTheme.bodyMedium,
                              ),
                            ],
                          ),
                        ),
                        StatusPill(
                          label: state.roleLabel(selectedDevice.role),
                          active: selectedDevice.role == DeviceRole.owner,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        StatTag(
                          label: '${selectedDevice.batteryLevel}%',
                          icon: Icons.battery_full_rounded,
                          foreground: theme.colorScheme.primary,
                          background: theme.colorScheme.primary.withValues(
                            alpha: 0.10,
                          ),
                        ),
                        StatTag(
                          label: '$usage/${selectedDevice.capacity}',
                          icon: Icons.photo_library_outlined,
                          foreground: const Color(0xFFD97757),
                          background: const Color(
                            0xFFD97757,
                          ).withValues(alpha: 0.12),
                        ),
                        StatTag(
                          label: selectedDevice.carouselEnabled
                              ? state.tr(
                                  zh: '轮播开启',
                                  en: 'Carousel On',
                                  ja: 'スライド ON',
                                )
                              : state.tr(
                                  zh: '轮播关闭',
                                  en: 'Carousel Off',
                                  ja: 'スライド OFF',
                                ),
                          icon: Icons.slideshow_rounded,
                          foreground: const Color(0xFF6B705C),
                          background: const Color(
                            0xFF6B705C,
                          ).withValues(alpha: 0.12),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    LinearProgressIndicator(
                      value: usage / selectedDevice.capacity,
                      minHeight: 10,
                      borderRadius: BorderRadius.circular(999),
                      backgroundColor: Colors.black.withValues(alpha: 0.06),
                      color: theme.colorScheme.secondary,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      state.tr(
                        zh: '设备满载时，会引导用户前往“我的相册”清理照片或联系设备所有者。',
                        en: 'If storage is full, users are directed to My Album or the device owner.',
                        ja: '容量がいっぱいの場合、マイアルバムまたはオーナー連絡へ案内します。',
                      ),
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              SectionHeader(
                title: state.tr(zh: '最近投屏', en: 'Recent Casts', ja: '最近の投映'),
                subtitle: state.tr(
                  zh: '同步展示成功与失败记录。',
                  en: 'Shows both success and failure records.',
                  ja: '成功と失敗の履歴をまとめて表示します。',
                ),
              ),
              const SizedBox(height: 12),
              ...state.castRecords
                  .take(3)
                  .map(
                    (record) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: RecordCard(
                        state: state,
                        record: record,
                        compact: true,
                        onRecast: () async {
                          final deviceId = await _pickDeviceId(context);
                          if (!context.mounted || deviceId == null) {
                            return;
                          }
                          final result = state.recastRecord(
                            record.id,
                            deviceId,
                          );
                          _showFeedback(context, result.message);
                        },
                        onDelete: () => state.deleteCastRecord(record.id),
                      ),
                    ),
                  ),
            ]),
          ),
        ),
      ],
    );
  }

  Future<void> _startCameraCast(BuildContext context) async {
    final status = await NativeDeviceApi.requestCameraPermission();
    _syncPermissionState(status);
    if (!context.mounted) {
      return;
    }
    if (!status.cameraPermissionGranted) {
      _showFeedback(context, '相机权限未开启，请授权后再使用拍照投屏。');
      return;
    }
    final draft = state.createCameraDraft();
    await _showCastPreview(context, draft);
  }

  Future<void> _startAlbumCast(BuildContext context) async {
    final status = await NativeDeviceApi.requestPhotoPermission();
    _syncPermissionState(status);
    if (!context.mounted) {
      return;
    }
    if (!status.photoPermissionGranted) {
      _showFeedback(context, '相册权限未开启，将尝试使用系统相册选择器获取单张照片。');
    }

    final selection = await NativeDeviceApi.openGallery();
    if (!context.mounted || selection == null) {
      return;
    }
    state.setPermission(PermissionKind.album, true);
    final draft = state.createAlbumDraft(
      title: selection.title,
      width: selection.width,
      height: selection.height,
      uri: selection.uri,
    );
    await _showCastPreview(context, draft);
  }

  Future<void> _showCastPreview(BuildContext context, DraftPhoto draft) async {
    final deviceId = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => CastPreviewSheet(state: state, draft: draft),
    );
    if (!context.mounted || deviceId == null) {
      return;
    }
    final result = state.castDraft(draft: draft, deviceId: deviceId);
    _showFeedback(context, result.message);
    if (result.deviceFull) {
      onOpenMine();
    }
  }

  Future<void> _showPermissionPanel(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return BottomSheetFrame(
          title: state.tr(zh: '用户权限', en: 'Permissions', ja: 'ユーザー権限'),
          child: Column(children: [NativePermissionPanel(state: state)]),
        );
      },
    );
  }

  void _syncPermissionState(DevicePermissionStatus status) {
    state.setPermission(
      PermissionKind.location,
      status.locationPermissionGranted,
    );
    state.setPermission(PermissionKind.bluetooth, status.bluetoothReady);
    state.setPermission(PermissionKind.album, status.photoPermissionGranted);
    state.setPermission(PermissionKind.camera, status.cameraPermissionGranted);
  }

  Future<void> _showDevicePicker(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return BottomSheetFrame(
          title: state.tr(zh: '绑定设备', en: 'Bind Device', ja: '端末を接続'),
          child: Column(
            children: state.devices.map((device) {
              final usage = state.deviceUsage(device.id);
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: InkWell(
                  onTap: () {
                    state.connectDevice(device.id);
                    Navigator.of(context).pop();
                  },
                  borderRadius: BorderRadius.circular(24),
                  child: Ink(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(24),
                      color: device.id == state.selectedDevice.id
                          ? Theme.of(
                              context,
                            ).colorScheme.primary.withValues(alpha: 0.10)
                          : Colors.white.withValues(alpha: 0.72),
                    ),
                    child: Row(
                      children: [
                        DeviceIllustration(
                          color: device.id == state.selectedDevice.id
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
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${device.kind} · $usage/${device.capacity}',
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            ],
                          ),
                        ),
                        if (device.connected)
                          const Icon(
                            Icons.check_circle_rounded,
                            color: Color(0xFF2A9D8F),
                          ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        );
      },
    );
  }

  Future<void> _showFlowGuide(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final steps = [
          state.tr(zh: '选择照片来源', en: 'Choose image source', ja: '画像の取得方法を選択'),
          state.tr(
            zh: '选择设备并检查容量',
            en: 'Select device and inspect capacity',
            ja: '端末を選び容量を確認',
          ),
          state.tr(
            zh: '预览处理后尺寸',
            en: 'Preview processed size',
            ja: '処理後サイズを確認',
          ),
          state.tr(
            zh: '确认投屏并写入记录',
            en: 'Confirm cast and save record',
            ja: '投映を確定し履歴へ保存',
          ),
        ];
        return BottomSheetFrame(
          title: state.tr(zh: '投屏流程', en: 'Casting Flow', ja: '投映フロー'),
          child: Column(
            children: [
              for (var index = 0; index < steps.length; index++)
                Padding(
                  padding: EdgeInsets.only(
                    bottom: index == steps.length - 1 ? 0 : 14,
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 16,
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        child: Text(
                          '${index + 1}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: Text(steps[index])),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Future<String?> _pickDeviceId(BuildContext context) async {
    return showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(state.tr(zh: '选择设备', en: 'Choose Device', ja: '端末選択')),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: state.devices.map((device) {
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.desktop_windows_outlined),
                  title: Text(device.name),
                  subtitle: Text(device.kind),
                  onTap: () => Navigator.of(context).pop(device.id),
                );
              }).toList(),
            ),
          ),
        );
      },
    );
  }

  void _showFeedback(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}
