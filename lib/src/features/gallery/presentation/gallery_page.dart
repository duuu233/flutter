import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../routes/app_routes.dart';
import '../../../shared/l10n/app_l10n.dart';
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
    // 订阅全局状态：本页原来完全不订阅、只靠交互后的手动 setState，页面打开期间
    // BLE 断链（reconcileConnectionFlags → notify）等外部变化不会反映到界面——
    // 用户会在「看似已连接」的图库页发起删除/刷屏，多等一轮自动重连超时。
    // 与 devices_page 等页的订阅模式收敛为一种。
    widget.state.addListener(_handleStateChanged);
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
    widget.state.removeListener(_handleStateChanged);
    appRouteObserver.unsubscribe(this);
    super.dispose();
  }

  void _handleStateChanged() {
    if (mounted) {
      setState(() {});
    }
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
        : AppL10n.of(context).galFrame;
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
        title: Text(AppL10n.of(context).galTip),
        content: Text(AppL10n.of(context).galDeviceClearedNotice),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(AppL10n.of(context).galConfirm),
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
    _showBlockingLoading(AppL10n.of(context).galDeleting);
    // dismiss 不做 mounted 门控（hide 本就不依赖 context）：页面在 await 期间被
    // 卸载时也要收掉 root 栈上 canPop:false 的蒙层，否则整个 App 假死。
    final ActionFeedback feedback;
    try {
      feedback = await state.deleteAlbumPhotos(_selectedIds);
    } finally {
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
      _showFeedback(AppL10n.of(context).galRefreshSingleOnly);
      return;
    }
    _showBlockingLoading(AppL10n.of(context).galRefreshing);
    final ActionFeedback feedback;
    try {
      feedback = await state.refreshGalleryPhotoOnScreen(_selectedIds.first);
    } finally {
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
      title: AppL10n.of(context).galTitle,
      scrollable: false,
      bodyPadding: EdgeInsets.zero,
      // 全ページ共通背景 bg01（小程序は全画面 mock-bg = 単一背景）。
      background: Image.asset('assets/images/bg01.png', fit: BoxFit.cover),
      // 四分支互斥链（loading 优先）：接口没回来之前只显示 loading，绝不先渲染空态；
      // 刷新失败且本地无数据 → 「加载失败 + 重试」（断网时不能误显示「还没有照片」）。
      body: !state.albumLoaded || !state.devicesLoaded
          ? const PageLoading()
          : photos.isEmpty &&
                (state.albumLoadError || state.devicesLoadError)
          ? PageLoadError(onRetry: _reloadFromBackend)
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
                        child: Text(
                          AppL10n.of(context).galSelectAll,
                          style: const TextStyle(
                            color: Color(0xFFFF5F1F),
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            height: 1,
                          ),
                        ),
                      ),
                      const SizedBox(width: 9),
                      Text(
                        AppL10n.of(context).galTotalCount(photos.length),
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
                  // 下拉刷新：此前数据只在进页/回页时刷新，用户没有任何手动恢复手段。
                  child: RefreshIndicator(
                    onRefresh: _reloadFromBackend,
                    color: const Color(0xFFEB5F1B),
                    child: GridView.builder(
                      padding: EdgeInsets.fromLTRB(
                        23,
                        0,
                        23,
                        hasSelection ? 16 : 17,
                      ),
                      physics: const BouncingScrollPhysics(
                        parent: AlwaysScrollableScrollPhysics(),
                      ),
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
                ),
                if (hasSelection)
                  _SelectionBar(
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
            if (photo.thumbUrl != null)
              Positioned.fill(
                child: CachedNetworkImage(
                  // 列表只取缩略图 imgThumb（无则回退 img），对齐小程序 list.wxml 的 item.imgThumb。
                  imageUrl: photo.thumbUrl!,
                  // aspectFit：完整显示、保持比例不裁切不拉伸（对齐小程序 list.wxml mode=aspectFit），
                  // 留白落在下方色块渐变上；避免 cover 中心裁切与后端记录 img 比例不一致。
                  fit: BoxFit.contain,
                  // 3 列网格瓦片约 120lp，按物理像素解码：原图(≤1920 长边)解码位图
                  // ~11MB/张，一页 100 张远超 ImageCache 100MB 上限，滚动时反复
                  // 解码+重下载；限宽后 ~30 倍内存降幅，可全量驻留缓存。
                  memCacheWidth:
                      (140 * MediaQuery.devicePixelRatioOf(context)).round(),
                  // 磁盘缓存同样限宽：不设的话磁盘存的是服务端原图（≤1920 长边），
                  // 百张相册量级要占几十 MB，逐出后二次解码也更贵；瓦片场景 800 足够。
                  maxWidthDiskCache: 800,
                  errorWidget: (context, url, error) =>
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

/// 选中底栏（小程序 `.album-bottom-bar`）：透明浮层，居中三枚渐变圆按钮 刷新/删除/取消。
/// 无白底、无阴影、无「已选 N 张」文案（对齐小程序 background:transparent + 三圆居中）。
class _SelectionBar extends StatelessWidget {
  const _SelectionBar({
    required this.onDelete,
    this.onRefresh,
    required this.onCancel,
  });

  final VoidCallback onDelete;

  /// 刷屏（0x24）常驻：多选时点击由外部给出「只能选一张」提示（对齐小程序）。
  final VoidCallback? onRefresh;

  /// 取消选择：清空已选（对齐小程序底栏「取消」）。
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    // padding: 24rpx 46rpx calc(24rpx + safe-bottom)；背景透明、无阴影。
    return Padding(
      padding: EdgeInsets.fromLTRB(
        23,
        12,
        23,
        12 + MediaQuery.of(context).padding.bottom,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // 刷新屏幕：橙色渐变（.action-refresh）。
          _CircleAction(
            asset: 'assets/images/album-icon01.png',
            fallback: Icons.cast_rounded,
            iconSize: 28,
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFFFF8B3D), Color(0xFFFF641F)],
            ),
            shadowColor: const Color(0xFFFF641F).withValues(alpha: 0.32),
            onTap: onRefresh,
            label: AppL10n.of(context).galRefreshScreen,
          ),
          const SizedBox(width: 45), // gap:90rpx
          // 删除：红色渐变（.action-delete）。
          _CircleAction(
            asset: 'assets/images/album-icon02.png',
            fallback: Icons.delete_outline_rounded,
            iconSize: 28,
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFFFF5B56), Color(0xFFF5322C)],
            ),
            shadowColor: const Color(0xFFF5322C).withValues(alpha: 0.30),
            onTap: onDelete,
            label: AppL10n.of(context).galDeletePhotos,
          ),
          const SizedBox(width: 45),
          // 取消：深色实底、图标更小（.action-cancel）。
          _CircleAction(
            asset: 'assets/images/album-icon03.png',
            fallback: Icons.close_rounded,
            iconSize: 20,
            color: const Color(0xFF2F3033),
            shadowColor: const Color(0xFF2F3033).withValues(alpha: 0.28),
            onTap: onCancel,
            label: AppL10n.of(context).cancel,
          ),
        ],
      ),
    );
  }
}

/// 单枚圆形操作按钮（小程序 `.bottom-action`）：48 圆，渐变/实底 + 彩色投影。
class _CircleAction extends StatelessWidget {
  const _CircleAction({
    required this.asset,
    required this.fallback,
    required this.iconSize,
    required this.shadowColor,
    required this.onTap,
    required this.label,
    this.gradient,
    this.color,
  });

  final String asset;
  final IconData fallback;
  final double iconSize;
  final Color shadowColor;
  final VoidCallback? onTap;

  /// 无障碍语义标签：纯图标按钮对读屏器不可见，必须显式标注。
  final String label;
  final Gradient? gradient;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          gradient: gradient,
          color: color,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: shadowColor,
              blurRadius: 13,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Center(
          child: Image.asset(
            asset,
            width: iconSize,
            height: iconSize,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) =>
                Icon(fallback, color: Colors.white, size: iconSize),
          ),
        ),
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
                      Text(
                        AppL10n.of(context).galDeletePhotos,
                        style: const TextStyle(
                          color: Color(0xFF25282D),
                          fontSize: 19,
                          fontWeight: FontWeight.w700,
                          height: 1.15,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        AppL10n.of(context).galDeleteConfirm(count),
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
                      label: AppL10n.of(context).cancel,
                      textColor: const Color(0xFF32363C),
                      background: const Color(0xFFEEEEEE),
                      onTap: () => Navigator.of(context).pop(false),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _DialogButton(
                      label: AppL10n.of(context).galConfirm,
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

/// 图库空态，对照小程序 `.album-empty`：插图 + 标题 + 描述，**无按钮**
/// （wxml 只有 image/title/desc 三个元素；`.empty-action` 样式已废弃不渲染）。
/// rpx→dp 按 0.5 折算：padding-top 250rpx→125、插图 350x342rpx→175x171、
/// 标题 margin 54rpx→27、描述 margin 20rpx→10。
class _GalleryEmptyState extends StatelessWidget {
  const _GalleryEmptyState();

  @override
  Widget build(BuildContext context) {
    // 小程序为固定顶距顶部对齐（非垂直居中）；SingleChildScrollView 兜底小屏溢出。
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(23, 125, 23, 24),
      child: Column(
        children: [
          Image.asset(
            'assets/images/album-bg01.png',
            width: 175,
            height: 171,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) => const Icon(
              Icons.image_outlined,
              color: Color(0xFFB9CCF0),
              size: 88,
            ),
          ),
          const SizedBox(height: 27),
          Text(
            AppL10n.of(context).galEmptyTitle,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF25282D),
              fontSize: 19,
              fontWeight: FontWeight.w700,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            AppL10n.of(context).galEmptySubtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF777E88),
              fontSize: 13,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}
