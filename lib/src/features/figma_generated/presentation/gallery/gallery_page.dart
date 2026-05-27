import 'package:flutter/material.dart';

import '../../../../state.dart';
import '../widgets/figma_common.dart';

/// 我的图库（图库网格版），对应 UI 稿「我的图库-未选择 / 选择图片 / 删除照片 / 设备照片已被一键清空」。
///
/// 数据来自 [PhotoFrameState.myAlbum]；真实照片资源缺失时使用按颜色生成的占位图块。
class GalleryPage extends StatefulWidget {
  const GalleryPage({super.key, required this.state});

  final PhotoFrameState state;

  @override
  State<GalleryPage> createState() => _GalleryPageState();
}

class _GalleryPageState extends State<GalleryPage> {
  bool _selecting = false;
  final Set<String> _selectedIds = <String>{};
  String? _deviceFilter;

  PhotoFrameState get state => widget.state;

  List<AlbumPhoto> get _photos {
    final all = state.myAlbum;
    if (_deviceFilter == null) {
      return all;
    }
    return all.where((photo) => photo.deviceId == _deviceFilter).toList();
  }

  String get _filterLabel =>
      _deviceFilter == null ? '全部相框' : state.deviceName(_deviceFilter!);

  void _toggleSelecting() {
    setState(() {
      _selecting = !_selecting;
      _selectedIds.clear();
    });
  }

  void _toggleAll() {
    setState(() {
      final ids = _photos.map((photo) => photo.id).toSet();
      if (_selectedIds.length == ids.length) {
        _selectedIds.clear();
      } else {
        _selectedIds
          ..clear()
          ..addAll(ids);
      }
    });
  }

  void _toggleOne(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  Future<void> _pickDeviceFilter() async {
    final selected = await showModalBottomSheet<String?>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: const Text('全部相框'),
                trailing: _deviceFilter == null
                    ? const Icon(Icons.check_rounded, color: Color(0xFFFF6A24))
                    : null,
                onTap: () => Navigator.of(context).pop('__all__'),
              ),
              for (final device in state.devices)
                ListTile(
                  title: Text(device.name),
                  trailing: _deviceFilter == device.id
                      ? const Icon(
                          Icons.check_rounded,
                          color: Color(0xFFFF6A24),
                        )
                      : null,
                  onTap: () => Navigator.of(context).pop(device.id),
                ),
            ],
          ),
        );
      },
    );
    if (selected == null) {
      return;
    }
    setState(() {
      _deviceFilter = selected == '__all__' ? null : selected;
      _selectedIds.clear();
    });
  }

  Future<void> _confirmDelete() async {
    if (_selectedIds.isEmpty) {
      return;
    }
    final count = _selectedIds.length;
    final confirmed = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.32),
      builder: (context) => _DeleteDialog(count: count),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    final feedback = state.deleteAlbumPhotos(_selectedIds);
    setState(() {
      _selectedIds.clear();
      _selecting = false;
    });
    _showFeedback(feedback.message);
  }

  void _castSelected() {
    if (_selectedIds.isEmpty) {
      return;
    }
    final photos = _photos
        .where((photo) => _selectedIds.contains(photo.id))
        .toList();
    var success = 0;
    for (final photo in photos) {
      final result = state.recastAlbumPhoto(photo.id, photo.deviceId);
      if (result.success) {
        success += 1;
      }
    }
    setState(() {
      _selectedIds.clear();
      _selecting = false;
    });
    _showFeedback('已投屏 $success/${photos.length} 张');
  }

  void _showFeedback(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final photos = _photos;
    final isEmpty = photos.isEmpty;

    return FigmaPhoneFrame(
      child: Stack(
        children: [
          const FigmaPageBackground(),
          Positioned(
            left: 0,
            top: 0,
            width: 375,
            height: 90,
            child: FigmaTopNavigation(
              title: '我的图库',
              trailing: isEmpty
                  ? null
                  : _TopActionButton(
                      label: _selecting ? '取消' : '选择',
                      onTap: _toggleSelecting,
                    ),
            ),
          ),
          if (isEmpty)
            const Positioned(
              left: 0,
              top: 90,
              width: 375,
              height: 722,
              child: _GalleryEmptyState(),
            )
          else ...[
            Positioned(
              left: 24,
              top: 100,
              width: 327,
              height: 28,
              child: Row(
                children: [
                  Text(
                    '共 ${photos.length} 张',
                    style: FigmaTextStyles.bodySmall.copyWith(fontSize: 13),
                  ),
                  const Spacer(),
                  if (_selecting)
                    _TopActionButton(label: '全选', onTap: _toggleAll)
                  else
                    _DeviceFilterChip(
                      label: _filterLabel,
                      onTap: _pickDeviceFilter,
                    ),
                ],
              ),
            ),
            Positioned(
              left: 16,
              top: 136,
              right: 16,
              bottom: _selecting ? 96 : 24,
              child: GridView.builder(
                padding: const EdgeInsets.only(bottom: 8),
                physics: const BouncingScrollPhysics(),
                gridDelegate:
                    const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                      childAspectRatio: 0.82,
                    ),
                itemCount: photos.length,
                itemBuilder: (context, index) {
                  final photo = photos[index];
                  return _GalleryTile(
                    photo: photo,
                    selecting: _selecting,
                    selected: _selectedIds.contains(photo.id),
                    onTap: () {
                      if (_selecting) {
                        _toggleOne(photo.id);
                      }
                    },
                  );
                },
              ),
            ),
            if (_selecting)
              Positioned(
                left: 0,
                bottom: 0,
                width: 375,
                height: 88,
                child: _SelectionBar(
                  count: _selectedIds.length,
                  onDelete: _confirmDelete,
                  onCast: _castSelected,
                ),
              ),
          ],
          const FigmaBottomHomeIndicator(),
        ],
      ),
    );
  }
}

class _TopActionButton extends StatelessWidget {
  const _TopActionButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Text(
          label,
          style: const TextStyle(
            color: Color(0xFFFF6A24),
            fontSize: 15,
            fontWeight: FontWeight.w500,
            height: 1.2,
          ),
        ),
      ),
    );
  }
}

class _DeviceFilterChip extends StatelessWidget {
  const _DeviceFilterChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF2A2B2B),
              fontSize: 14,
              fontWeight: FontWeight.w500,
              height: 1.2,
            ),
          ),
          const SizedBox(width: 4),
          const Icon(
            Icons.keyboard_arrow_down_rounded,
            color: Color(0xFF2A2B2B),
            size: 20,
          ),
        ],
      ),
    );
  }
}

class _GalleryTile extends StatelessWidget {
  const _GalleryTile({
    required this.photo,
    required this.selecting,
    required this.selected,
    required this.onTap,
  });

  final AlbumPhoto photo;
  final bool selecting;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Stack(
          fit: StackFit.expand,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    photo.color.withValues(alpha: 0.92),
                    photo.color.withValues(alpha: 0.5),
                    const Color(0xFFF3F2F0),
                  ],
                ),
              ),
            ),
            Align(
              alignment: Alignment.bottomLeft,
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Icon(
                  photo.source == ImageSourceType.camera
                      ? Icons.photo_camera_outlined
                      : Icons.collections_outlined,
                  color: Colors.white.withValues(alpha: 0.9),
                  size: 14,
                ),
              ),
            ),
            if (selecting)
              Positioned(
                right: 6,
                top: 6,
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: selected
                        ? const Color(0xFFFF6A24)
                        : Colors.black.withValues(alpha: 0.18),
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                  child: selected
                      ? const Icon(
                          Icons.check_rounded,
                          color: Colors.white,
                          size: 15,
                        )
                      : null,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SelectionBar extends StatelessWidget {
  const _SelectionBar({
    required this.count,
    required this.onDelete,
    required this.onCast,
  });

  final int count;
  final VoidCallback onDelete;
  final VoidCallback onCast;

  @override
  Widget build(BuildContext context) {
    final enabled = count > 0;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 14, 24, 14),
        child: Row(
          children: [
            Text(
              '已选 $count 张',
              style: const TextStyle(
                color: Color(0xFF2A2B2B),
                fontSize: 15,
                fontWeight: FontWeight.w500,
                height: 1.2,
              ),
            ),
            const Spacer(),
            _BarButton(
              label: '删除',
              filled: false,
              enabled: enabled,
              onTap: onDelete,
            ),
            const SizedBox(width: 12),
            _BarButton(
              label: '投屏',
              filled: true,
              enabled: enabled,
              onTap: onCast,
            ),
          ],
        ),
      ),
    );
  }
}

class _BarButton extends StatelessWidget {
  const _BarButton({
    required this.label,
    required this.filled,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final bool filled;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final orange = const Color(0xFFFF6A24);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: enabled ? onTap : null,
      child: Opacity(
        opacity: enabled ? 1 : 0.4,
        child: Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 22),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: filled ? orange : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: orange, width: 1.2),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: filled ? Colors.white : orange,
              fontSize: 15,
              fontWeight: FontWeight.w500,
              height: 1.2,
            ),
          ),
        ),
      ),
    );
  }
}

class _DeleteDialog extends StatelessWidget {
  const _DeleteDialog({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 40),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 26, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '删除照片',
              style: TextStyle(
                color: Color(0xFF2A2B2B),
                fontSize: 18,
                fontWeight: FontWeight.w600,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              '确认删除已选的 $count 张照片吗？删除后将从当前设备备份库中移除，且无法找回。',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0x992A2B2B),
                fontSize: 13,
                fontWeight: FontWeight.w400,
                height: 1.6,
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: _DialogButton(
                    label: '取消',
                    filled: false,
                    onPressed: () => Navigator.of(context).pop(false),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: _DialogButton(
                    label: '确认',
                    filled: true,
                    onPressed: () => Navigator.of(context).pop(true),
                  ),
                ),
              ],
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
    required this.filled,
    required this.onPressed,
  });

  final String label;
  final bool filled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: filled ? const Color(0xFFFF6A24) : const Color(0xFFF1F1F3),
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onPressed,
        child: Container(
          height: 46,
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              color: filled ? Colors.white : const Color(0xFF2A2B2B),
              fontSize: 16,
              fontWeight: FontWeight.w500,
              height: 1.2,
            ),
          ),
        ),
      ),
    );
  }
}

class _GalleryEmptyState extends StatelessWidget {
  const _GalleryEmptyState();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 26),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 150,
            height: 150,
            decoration: BoxDecoration(
              color: const Color(0xFFFFF0E6),
              borderRadius: BorderRadius.circular(28),
            ),
            child: const Icon(
              Icons.image_not_supported_outlined,
              color: Color(0xFFFF8A4C),
              size: 64,
            ),
          ),
          const SizedBox(height: 28),
          const Text(
            '当前没有可查看的设备照片',
            style: TextStyle(
              color: Color(0xFF2A2B2B),
              fontSize: 17,
              fontWeight: FontWeight.w600,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            '你可以重新投屏照片到设备',
            style: TextStyle(
              color: Color(0x992A2B2B),
              fontSize: 13,
              fontWeight: FontWeight.w400,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 40),
          SizedBox(
            width: 323,
            child: FigmaPrimaryButton(
              label: '重新投屏',
              onPressed: () => Navigator.maybePop(context),
            ),
          ),
        ],
      ),
    );
  }
}
