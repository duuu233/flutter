import 'package:flutter/material.dart';

import '../../../routes/app_routes.dart';
import '../../../state.dart';
import 'package:BoltStar/src/shared/widgets/app_widgets.dart';
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

class _GalleryPageState extends State<GalleryPage> with RouteAware {
  final Set<String> _selectedIds = <String>{};
  String? _deviceFilter;

  // 一键清除状态查询的防竞态：自增序号标记「最新一次查询」（切换设备时旧结果丢弃），
  // _clearModalShowing 防止提醒弹窗叠加（对齐小程序 clearCheckSeq / clearImgModalShowing）。
  int _clearCheckSeq = 0;
  bool _clearModalShowing = false;

  PhotoFrameState get state => widget.state;

  @override
  void initState() {
    super.initState();
    // 打开时刷新设备 + 图库，随后查一次当前设备的一键清除状态。
    // 两个接口并发（原来是串行 await，空态/loading 要多等一个完整往返；它们之间没有依赖）。
    // 首屏在 state.albumLoaded 之前显示 loading，不会先闪一下空态（对齐小程序 list.js loading:true）。
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future.wait([state.refreshDevices(), state.refreshAlbum()]);
      if (!mounted) {
        return;
      }
      _ensureDeviceFilter();
      setState(() {});
      // 进入图库即查一次一键清除状态：设备在别处被清空过则弹「请重新上传图片」提醒。
      _checkDeviceClearStatus();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute) {
      appRouteObserver.subscribe(this, route);
    }
  }

  @override
  void dispose() {
    appRouteObserver.unsubscribe(this);
    super.dispose();
  }

  /// 被覆盖的页 pop 回来（重入）：回后端刷新图库（对齐小程序 onShow loadPhotos）。
  @override
  void didPopNext() {
    _reloadFromBackend();
  }

  Future<void> _reloadFromBackend() async {
    await state.refreshDevices();
    if (!mounted) {
      return;
    }
    await state.refreshAlbum();
    if (!mounted) {
      return;
    }
    _ensureDeviceFilter();
    setState(() {});
    _checkDeviceClearStatus();
  }

  /// 默认选中单台设备（对齐小程序：无「全部相框」，进入即定位到一台设备的图库）。
  /// 优先当前已连接设备（删除需连接该设备）；否则有照片的首台；再否则设备列表首台。
  void _ensureDeviceFilter() {
    if (_deviceFilter != null &&
        state.devices.any((device) => device.id == _deviceFilter)) {
      return; // 已选且设备仍存在
    }
    final devices = state.devices;
    if (devices.isEmpty) {
      _deviceFilter = null;
      return;
    }
    final connected = devices.where((device) => device.connected);
    final hasPhotos = state.myAlbum.map((photo) => photo.deviceId).toSet();
    _deviceFilter =
        (connected.isNotEmpty ? connected.first : null)?.id ??
        devices
            .firstWhere(
              (device) => hasPhotos.contains(device.id),
              orElse: () => devices.first,
            )
            .id;
  }

  List<AlbumPhoto> get _photos {
    final all = state.myAlbum;
    if (_deviceFilter == null) {
      return all; // 仅在无设备时命中（此时相册本就为空）
    }
    return all.where((photo) => photo.deviceId == _deviceFilter).toList();
  }

  String get _filterLabel {
    if (_deviceFilter != null) {
      return state.deviceName(_deviceFilter!);
    }
    return state.devices.isNotEmpty
        ? state.deviceName(state.devices.first.id)
        : '相框';
  }

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
              // 无「全部相框」：对齐小程序单设备图库模型（避免跨设备选中删错槽位）。
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
      _deviceFilter = selected;
      _selectedIds.clear();
    });
    // 每次切换设备筛选都查一次该设备的一键清除状态（与进入图库同一汇合点）。
    _checkDeviceClearStatus();
  }

  /// 查询当前设备的一键清除状态并按需弹「请重新上传图片」提醒（对齐小程序 checkDeviceClearStatus）。
  ///
  /// 进入图库 / 每次切换设备筛选时调用。取查询设备：优先当前筛选设备；筛选为「全部相框」或图库为空
  /// （设备被清空后图库自然为空）时，回退用设备列表第一台——正需靠它弹「重新上传」提醒；设备也没有则不查。
  /// 自增序号防切换竞态（查询期间又切了设备则丢弃旧结果），_clearModalShowing 防叠弹窗。
  Future<void> _checkDeviceClearStatus() async {
    final userProductId = _deviceFilter ??
        (state.devices.isNotEmpty ? state.devices.first.id : null);
    if (userProductId == null || userProductId.isEmpty) {
      return;
    }
    final seq = ++_clearCheckSeq;
    final cleared = await state.fetchDeviceClearImgStatus(userProductId);
    if (!mounted || seq != _clearCheckSeq || _clearModalShowing) {
      return;
    }
    if (cleared != true) {
      return;
    }
    _clearModalShowing = true;
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('提示'),
        content: const Text('当前设备已被执行清空操作，请重新上传图片'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('确认'),
          ),
        ],
      ),
    );
    _clearModalShowing = false;
    if (confirmed == true) {
      // 确认后复位清除标记，避免每次进入都弹（失败静默，下次进入会再提醒）。
      await state.resetDeviceClearImgFlag(userProductId);
    }
  }

  /// 图库为空时的正文：设备接口有数据则顶部仍展示设备筛选载体（filter-wrap，不因无照片而隐藏）+
  /// 空态引导重新投屏；设备也没有则只显示空态（对齐小程序「无照片有设备 / 都空」两态）。
  Widget _buildEmptyBody() {
    if (state.devices.isEmpty) {
      return const _GalleryEmptyState();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(23, 7, 23, 11),
          child: Row(
            children: [
              const Spacer(),
              _DeviceFilterChip(label: _filterLabel, onTap: _pickDeviceFilter),
            ],
          ),
        ),
        const Expanded(child: _GalleryEmptyState()),
      ],
    );
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
    // 设备侧删除(0x12)可能耗时较久（最长约 180s），期间用蒙层 loading 阻断误操作
    // （对齐小程序 wx.showLoading({title:'删除中', mask:true})）。
    _showBlockingLoading('删除中');
    final feedback = await state.deleteAlbumPhotos(_selectedIds);
    if (mounted) {
      _dismissBlockingLoading();
    }
    if (!mounted) {
      return;
    }
    setState(_selectedIds.clear);
    _showFeedback(feedback.message);
  }

  /// 蒙层阻断式 loading（不可返回/不可点透），配合耗时的设备 BLE 操作。
  /// 统一走公共的 [AppLoadingDialog]（原来这里有一份私有实现，遮罩偏黑、文字还会被
  /// Flutter 渲染成黄色双下划线——dialog 路由下没有 Material 祖先）。
  void _showBlockingLoading(String text) => AppLoadingDialog.show(context, text);

  void _dismissBlockingLoading() => AppLoadingDialog.hide(context);

  /// 单选照片「刷新屏幕」：把该照片切到相框当前显示（0x24）。未连接会自动扫连，故加蒙层 loading。
  Future<void> _refreshSelectedOnScreen() async {
    if (_selectedIds.length != 1) {
      // 对齐小程序：多选时刷屏给出提示而非静默无反应。
      _showFeedback('刷新屏幕只能选中一张图片');
      return;
    }
    _showBlockingLoading('刷新中');
    final feedback = await state.refreshGalleryPhotoOnScreen(_selectedIds.first);
    if (mounted) {
      _dismissBlockingLoading();
    }
    if (!mounted) {
      return;
    }
    _showFeedback(feedback.message);
  }

  void _showFeedback(String message) {
    AppToast.show(context, message);
  }

  @override
  Widget build(BuildContext context) {
    final photos = _photos;
    final hasSelection = _selectedIds.isNotEmpty;

    return FigmaScreen(
      title: '我的图库',
      scrollable: false,
      bodyPadding: EdgeInsets.zero,
      // 全ページ共通背景 bg01（小程序は全画面 mock-bg = 単一背景）。
      background: Image.asset('assets/images/bg01.png', fit: BoxFit.cover),
      // 三分支互斥链（loading 优先）：接口没回来之前只显示 loading，绝不先渲染空态。
      body: !state.albumLoaded || !state.devicesLoaded
          ? const PageLoading()
          : photos.isEmpty
          ? _buildEmptyBody()
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
                    // 刷屏常驻（对齐小程序）：多选时点它给出「只能选一张」提示。
                    onRefresh: _refreshSelectedOnScreen,
                    onCancel: () => setState(_selectedIds.clear),
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
                  // aspectFit：完整显示原图、保持比例不裁切不拉伸（对齐小程序 list.wxml mode=aspectFit），
                  // 留白落在下方色块渐变上；避免 cover 中心裁切与后端记录 img 比例不一致。
                  fit: BoxFit.contain,
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
    this.onRefresh,
    required this.onCancel,
  });

  final int count;
  final VoidCallback onDelete;

  /// 刷屏（0x24）常驻：多选时点击由外部给出「只能选一张」提示（对齐小程序）。
  final VoidCallback? onRefresh;

  /// 取消选择：清空已选（对齐小程序底栏「取消」）。
  final VoidCallback onCancel;

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
            if (onRefresh != null) ...[
              const SizedBox(width: 14),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onRefresh,
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
                  child: const Center(
                    child: Icon(
                      Icons.cast_rounded,
                      color: Color(0xFFFF5F1F),
                      size: 22,
                    ),
                  ),
                ),
              ),
            ],
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
            // 取消选择按钮（对齐小程序底栏「取消」）。
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onCancel,
              child: Container(
                height: 44,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                alignment: Alignment.center,
                child: const Text(
                  '取消',
                  style: TextStyle(color: Color(0xFF777E88), fontSize: 14),
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
/// 蒙层阻断式 loading 卡片：居中黑底圆角 + 转圈 + 文案（对齐小程序 wx.showLoading mask）。
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
