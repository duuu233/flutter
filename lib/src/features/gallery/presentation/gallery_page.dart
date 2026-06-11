import 'package:flutter/material.dart';

import '../../../state.dart';
import 'package:BoltStar/src/shared/widgets/figma_common.dart';

/// 我的图库，对照微信小程序 `photo-album/subpackages/album/list`。
///
/// 采用小程序的「常驻可选」模型：工具栏含全选 + 数量 + 设备筛选；每个图块带选择圈；
/// 选中任意张后底部出现操作栏（删除 / 投屏）。数据来自 [PhotoFrameState.myAlbum]。
class GalleryPage extends StatefulWidget {
  const GalleryPage({super.key, required this.state});

  final PhotoFrameState state;

  @override
  State<GalleryPage> createState() => _GalleryPageState();
}

class _GalleryPageState extends State<GalleryPage> {
  final Set<String> _selectedIds = <String>{};
  String? _deviceFilter;

  PhotoFrameState get state => widget.state;

  @override
  void initState() {
    super.initState();
    // 打开时刷新设备 + 图库（失败保留本地数据）。
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await state.refreshDevices();
      if (!mounted) {
        return;
      }
      await state.refreshAlbum();
      if (mounted) {
        setState(() {});
      }
    });
  }

  List<AlbumPhoto> get _photos {
    final all = state.myAlbum;
    if (_deviceFilter == null) {
      return all;
    }
    return all.where((photo) => photo.deviceId == _deviceFilter).toList();
  }

  String get _filterLabel =>
      _deviceFilter == null ? '全部相框' : state.deviceName(_deviceFilter!);

  void _toggleAll() {
    setState(() {
      final ids = _photos.map((photo) => photo.id).toSet();
      if (_selectedIds.length == ids.length && ids.isNotEmpty) {
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
      if (!_selectedIds.remove(id)) {
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
      barrierColor: Colors.black.withValues(alpha: 0.4),
      builder: (context) => _DeleteDialog(count: count),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    final feedback = await state.deleteAlbumPhotos(_selectedIds);
    if (!mounted) {
      return;
    }
    setState(_selectedIds.clear);
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
    setState(_selectedIds.clear);
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
    final hasSelection = _selectedIds.isNotEmpty;

    return FigmaScreen(
      title: '我的图库',
      scrollable: false,
      bodyPadding: EdgeInsets.zero,
      // 图库背景用 bg02（小程序 album 用 bg02，非 bg01）。
      background: Image.asset('assets/images/bg02.png', fit: BoxFit.cover),
      body: photos.isEmpty
          ? const _GalleryEmptyState()
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 工具栏：全选 + 数量 + 设备筛选。
                Padding(
                  padding: const EdgeInsets.fromLTRB(23, 7, 23, 11),
                  child: Row(
                    children: [
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: _toggleAll,
                        child: const Text(
                          '全选',
                          style: TextStyle(
                            color: Color(0xFFFF5F1F),
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            height: 1,
                          ),
                        ),
                      ),
                      const SizedBox(width: 9),
                      Text(
                        '共 ${photos.length} 张',
                        style: const TextStyle(
                          color: Color(0xFF777E88),
                          fontSize: 14,
                          height: 1,
                        ),
                      ),
                      const Spacer(),
                      _DeviceFilterChip(
                        label: _filterLabel,
                        onTap: _pickDeviceFilter,
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: GridView.builder(
                    padding: EdgeInsets.fromLTRB(23, 0, 23, hasSelection ? 16 : 17),
                    physics: const BouncingScrollPhysics(),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          mainAxisSpacing: 7,
                          crossAxisSpacing: 7,
                          childAspectRatio: 1,
                        ),
                    itemCount: photos.length,
                    itemBuilder: (context, index) {
                      final photo = photos[index];
                      return _GalleryTile(
                        photo: photo,
                        selected: _selectedIds.contains(photo.id),
                        onTap: () => _toggleOne(photo.id),
                      );
                    },
                  ),
                ),
                if (hasSelection)
                  _SelectionBar(
                    count: _selectedIds.length,
                    onDelete: _confirmDelete,
                    onCast: _castSelected,
                  ),
              ],
            ),
    );
  }
}

/// 设备筛选胶囊（小程序 `.filter-btn`）：白 0.78 胶囊 + 文案 + 下拉箭头。
class _DeviceFilterChip extends StatelessWidget {
  const _DeviceFilterChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 31,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.78),
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
          children: [
            Text(
              label,
              style: const TextStyle(
                color: Color(0xFF777E88),
                fontSize: 13,
                height: 1,
              ),
            ),
            const SizedBox(width: 8),
            const Icon(
              Icons.keyboard_arrow_down_rounded,
              color: Color(0xFF777E88),
              size: 18,
            ),
          ],
        ),
      ),
    );
  }
}

class _GalleryTile extends StatelessWidget {
  const _GalleryTile({
    required this.photo,
    required this.selected,
    required this.onTap,
  });

  final AlbumPhoto photo;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(11),
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
            if (photo.imageUrl != null)
              Positioned.fill(
                child: Image.network(
                  photo.imageUrl!,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) =>
                      const SizedBox.shrink(),
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
            Positioned(
              right: 7,
              top: 7,
              child: _SelectCircle(selected: selected),
            ),
          ],
        ),
      ),
    );
  }
}

/// 选择圈（小程序 `.select-circle`）：未选空心白环，选中 `selected-icon.png`。
class _SelectCircle extends StatelessWidget {
  const _SelectCircle({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    if (selected) {
      return SizedBox(
        width: 21,
        height: 21,
        child: Image.asset(
          'assets/images/selected-icon.png',
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) {
            return Container(
              decoration: const BoxDecoration(
                color: Color(0xFFFF6A24),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_rounded,
                color: Colors.white,
                size: 14,
              ),
            );
          },
        ),
      );
    }
    return Container(
      width: 21,
      height: 21,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withValues(alpha: 0.14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.88), width: 1.5),
      ),
    );
  }
}

/// 选中底栏（小程序 `.album-bottom-bar`）：删除按钮 + 已选数量 + 投屏。
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
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF7E96B8).withValues(alpha: 0.14),
            blurRadius: 17,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(23, 16, 23, 16),
        child: Row(
          children: [
            // 删除按钮（圆形白底 + del-icon.png）。
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onDelete,
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF7E96B8).withValues(alpha: 0.15),
                      blurRadius: 13,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: Center(
                  child: Image.asset(
                    'assets/images/del-icon.png',
                    width: 24,
                    height: 24,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) => const Icon(
                      Icons.delete_outline_rounded,
                      color: Color(0xFF777E88),
                      size: 22,
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: Center(
                child: Text.rich(
                  TextSpan(
                    style: const TextStyle(
                      color: Color(0xFF2A2D32),
                      fontSize: 14,
                      height: 1.2,
                    ),
                    children: [
                      const TextSpan(text: '已选 '),
                      TextSpan(
                        text: '$count',
                        style: const TextStyle(color: Color(0xFFFF5F1F)),
                      ),
                      const TextSpan(text: ' 张'),
                    ],
                  ),
                ),
              ),
            ),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onCast,
              child: Container(
                width: 105,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xFFFF8B3D), Color(0xFFFF641F)],
                  ),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Text(
                  '投屏',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    height: 1,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 删除照片确认弹窗（小程序 `.confirm-dialog`）：图标盒 + 标题/说明 + 取消/确认。
class _DeleteDialog extends StatelessWidget {
  const _DeleteDialog({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 30, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 32,
                  height: 32,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF6A20).withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: const Icon(
                    Icons.image_outlined,
                    color: Color(0xFFFF5F1F),
                    size: 18,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '删除照片',
                        style: TextStyle(
                          color: Color(0xFF25282D),
                          fontSize: 19,
                          fontWeight: FontWeight.w700,
                          height: 1.15,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '确认删除已选的$count张照片吗？删除后将从当前设备图库中移除，且无法恢复',
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
              padding: const EdgeInsets.only(left: 46),
              child: Row(
                children: [
                  Expanded(
                    child: _DialogButton(
                      label: '取消',
                      textColor: const Color(0xFF32363C),
                      background: const Color(0xFFEEEEEE),
                      onTap: () => Navigator.of(context).pop(false),
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
                      onTap: () => Navigator.of(context).pop(true),
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
  final VoidCallback onTap;
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

/// 空态（小程序 `.album-empty`）：插画 + 标题 + 说明 + 重新投屏。
class _GalleryEmptyState extends StatelessWidget {
  const _GalleryEmptyState();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 23),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 130,
            height: 130,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFF8FBFF), Color(0xFFDBE8FF)],
              ),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: const Color(0xFFEDF3FF), width: 4),
            ),
            child: const Icon(
              Icons.image_outlined,
              color: Color(0xFFB9CCF0),
              size: 56,
            ),
          ),
          const SizedBox(height: 27),
          const Text(
            '当前没有可查看的设备照片',
            style: TextStyle(
              color: Color(0xFF25282D),
              fontSize: 19,
              fontWeight: FontWeight.w700,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            '你可以重新投屏照片到设备',
            style: TextStyle(
              color: Color(0xFF777E88),
              fontSize: 13,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 40),
          SizedBox(
            width: double.infinity,
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
