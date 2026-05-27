import 'package:flutter/material.dart';

import '../../../shared/shared.dart';
import '../../../state.dart';

/// 相册页：浏览与管理本地照片，作为投屏图片的来源。
class AlbumPage extends StatefulWidget {
  const AlbumPage({super.key, required this.state});

  final PhotoFrameState state;

  @override
  State<AlbumPage> createState() => _AlbumPageState();
}

class _AlbumPageState extends State<AlbumPage> {
  final Set<String> _selectedIds = <String>{};

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final photos = state.myAlbum;

    return SubPageScaffold(
      title: state.tr(zh: '我的相册', en: 'My Album', ja: 'マイアルバム'),
      actions: [
        if (_selectedIds.length == 1)
          IconButton(
            icon: const Icon(Icons.cast_connected_outlined),
            onPressed: () => _recastSelected(context),
          ),
        if (_selectedIds.isNotEmpty)
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () {
              final feedback = state.deleteAlbumPhotos(_selectedIds);
              setState(_selectedIds.clear);
              _showFeedback(context, feedback.message);
            },
          ),
      ],
      child: photos.isEmpty
          ? EmptyState(
              title: state.tr(
                zh: '还没有可显示的照片',
                en: 'No photos to show yet',
                ja: '表示できる写真はまだありません',
              ),
              message: state.tr(
                zh: '这里只保留成功投屏到设备的数据。',
                en: 'Only photos successfully written to devices appear here.',
                ja: 'ここには端末への書き込み成功分のみ表示されます。',
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
              children: [
                AppPanel(
                  child: Text(
                    state.tr(
                      zh: '支持多选删除；当前实现按“设备物理存储”为准，设备一键清空后照片不会继续留在我的相册。',
                      en: 'Multi-select delete is supported. This build treats device storage as the source of truth, so cleared device photos disappear from My Album.',
                      ja: '複数削除に対応しています。この実装では端末ストレージを正とし、一括クリア後はマイアルバムからも消えます。',
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                ...photos.map((photo) {
                  final selected = _selectedIds.contains(photo.id);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: AppPanel(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          PhotoArtwork(
                            color: photo.color,
                            source: photo.source,
                            width: 88,
                            height: 108,
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        photo.title,
                                        style: Theme.of(
                                          context,
                                        ).textTheme.titleLarge,
                                      ),
                                    ),
                                    Checkbox(
                                      value: selected,
                                      onChanged: (_) {
                                        setState(() {
                                          if (selected) {
                                            _selectedIds.remove(photo.id);
                                          } else {
                                            _selectedIds.add(photo.id);
                                          }
                                        });
                                      },
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${state.deviceName(photo.deviceId)} · ${state.formatDateTime(photo.uploadedAt)}',
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  state.tr(
                                    zh:
                                        '设备槽位 ${photo.imageIndex} · ${photo.targetWidth}×${photo.targetHeight} · ${state.formatBytes(photo.transferBytes)}',
                                    en:
                                        'Slot ${photo.imageIndex} · ${photo.targetWidth}×${photo.targetHeight} · ${state.formatBytes(photo.transferBytes)}',
                                    ja:
                                        'スロット ${photo.imageIndex} · ${photo.targetWidth}×${photo.targetHeight} · ${state.formatBytes(photo.transferBytes)}',
                                  ),
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                                const SizedBox(height: 6),
                                Text(photo.note),
                                const SizedBox(height: 12),
                                Wrap(
                                  spacing: 10,
                                  runSpacing: 10,
                                  children: [
                                    FilledButton.tonal(
                                      onPressed: () =>
                                          _recastSingle(context, photo.id),
                                      child: Text(
                                        state.tr(
                                          zh: '投屏',
                                          en: 'Cast',
                                          ja: '投映',
                                        ),
                                      ),
                                    ),
                                    TextButton(
                                      onPressed: () {
                                        final feedback = state
                                            .deleteAlbumPhotos({photo.id});
                                        _showFeedback(
                                          context,
                                          feedback.message,
                                        );
                                      },
                                      child: Text(
                                        state.tr(
                                          zh: '删除',
                                          en: 'Delete',
                                          ja: '削除',
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
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

  Future<void> _recastSelected(BuildContext context) async {
    final photoId = _selectedIds.first;
    await _recastSingle(context, photoId);
  }

  Future<void> _recastSingle(BuildContext context, String photoId) async {
    final deviceId = await _pickDevice(context, widget.state);
    if (!context.mounted || deviceId == null) {
      return;
    }
    final result = widget.state.recastAlbumPhoto(photoId, deviceId);
    _showFeedback(context, result.message);
  }

  Future<String?> _pickDevice(BuildContext context, PhotoFrameState state) {
    return showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(
            state.tr(zh: '选择投屏设备', en: 'Choose Target Device', ja: '投映先の端末を選択'),
          ),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: state.devices.map((device) {
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(device.name),
                  subtitle: Text(
                    '${device.kind} · ${state.deviceUsage(device.id)}/${device.capacity}',
                  ),
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
