import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../routes/app_routes.dart';
import '../../../shared/l10n/app_l10n.dart';
import '../../../shared/permission_gate.dart';
import '../../../state.dart';
import 'package:BoltStar/src/shared/widgets/app_dialog.dart';
import 'package:BoltStar/src/shared/widgets/app_widgets.dart';
import 'package:BoltStar/src/shared/widgets/device_filter_chip.dart';
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

  /// 下拉每次展开前只重拉设备接口，不复用上次进页时的设备列表，也不连带重拉整份图库。
  Future<void> _refreshDeviceFiltersForMenu() async {
    await state.refreshDevices();
    if (!mounted) {
      return;
    }
    final previous = _deviceFilter;
    _ensureDeviceFilter();
    setState(() {});
    if (previous != _deviceFilter) {
      _checkDeviceClearStatus();
    }
  }

  /// 设备筛选下拉的选项列表（对齐小程序 2026-07-30 改动）：
  /// **完全以设备接口返回的绑定设备为准**，返回几台就几项（含刚绑定还没照片的），
  /// 按设备ID去重——设备名允许重复，两台同名设备必须各占一项、各筛各的照片。
  ///
  /// (2026-07-30)已删「照片里带的设备ID、但设备列表里没有的（已解绑设备老照片）并入下拉」
  /// 的兜底：这类照片不再单独成筛选项，也不会出现在任何设备的筛选结果里。
  List<DeviceFilterOption> get _filterOptions {
    final options = <DeviceFilterOption>[];
    for (final device in state.devices) {
      if (device.id.isEmpty || options.any((option) => option.id == device.id)) {
        continue;
      }
      options.add(
        DeviceFilterOption(
          id: device.id,
          label: device.name,
          serialTail: deviceSerialTail(device.serialNumber),
        ),
      );
    }
    return disambiguateDeviceFilterLabels(options);
  }

  /// 默认选中单台设备（对齐小程序：无「全部相框」，进入即定位到一台设备的图库）。
  /// 优先当前已连接设备（删除需连接该设备）；否则有照片的首台；再否则设备列表首台。
  /// 筛选项只来自设备接口，所以设备列表为空即无筛选项，_deviceFilter 置空。
  void _ensureDeviceFilter() {
    final options = _filterOptions;
    if (_deviceFilter != null &&
        options.any((option) => option.id == _deviceFilter)) {
      return; // 已选且仍在筛选项里
    }
    final devices = state.devices;
    if (options.isEmpty || devices.isEmpty) {
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
    final filter = _deviceFilter;
    if (filter == null) {
      return all; // 仅在无设备时命中（此时相册本就为空）
    }
    // (2026-07-30)只按设备ID匹配，不再有设备名兜底：设备名可重复，按名匹配会把同名设备的照片混进来。
    // 代价是「后端没回 deviceId 的老照片」筛不出来——这类照片本就无法可靠归属到某台设备。
    return all.where((photo) => photo.deviceId == filter).toList();
  }

  String get _filterLabel {
    final options = _filterOptions;
    final filter = _deviceFilter;
    if (filter != null) {
      final active = options.where((option) => option.id == filter);
      if (active.isNotEmpty) {
        return active.first.label;
      }
      return state.deviceName(filter);
    }
    return options.isNotEmpty
        ? options.first.label
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

  /// 切换设备筛选（下拉菜单选项回调，见 [DeviceFilterChip]）。
  void _pickDeviceFilter(String deviceId) {
    if (deviceId == _deviceFilter) {
      return;
    }
    setState(() {
      _deviceFilter = deviceId;
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
    final userProductId =
        _deviceFilter ??
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
    final confirmed = await showAppConfirmDialog(
      context,
      // 纯告知弹窗：必须点「确认」才复位清除标记，点遮罩不算确认。
      barrierDismissible: false,
      showCancel: false,
      icon: Icons.image_outlined,
      title: AppL10n.of(context).galTip,
      message: AppL10n.of(context).galDeviceClearedNotice,
      confirmLabel: AppL10n.of(context).galConfirm,
    );
    _clearModalShowing = false;
    if (confirmed == true) {
      // 确认后复位清除标记，避免每次进入都弹（失败静默，下次进入会再提醒）。
      await state.resetDeviceClearImgFlag(userProductId);
    }
  }

  /// 顶栏右上角的设备下拉（2026-08-01 从工具栏上移，替代原来的「设备照片」标题）。
  Widget _buildDeviceFilterChip() {
    return DeviceFilterChip(
      label: _filterLabel,
      options: _filterOptions,
      selectedId: _deviceFilter,
      onSelected: _pickDeviceFilter,
      onOpen: _refreshDeviceFiltersForMenu,
    );
  }

  /// 图库为空时的正文：设备接口有数据仍展示当前屏幕照片说明 + 空态引导重新投屏；
  /// 设备也没有则只显示空态（对齐小程序「无照片有设备 / 都空」两态）。
  /// 设备下拉已上移到顶栏，两态下都常驻，不必在这里再摆一份。
  Widget _buildEmptyBody() {
    if (state.devices.isEmpty) {
      return const _GalleryEmptyState();
    }
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(height: 7),
        _ScreenPhotoHint(),
        Expanded(child: _GalleryEmptyState()),
      ],
    );
  }

  Future<void> _confirmDelete() async {
    if (_selectedIds.isEmpty) {
      return;
    }
    final count = _selectedIds.length;
    final confirmed = await showAppConfirmDialog(
      context,
      icon: Icons.delete_outline_rounded,
      tone: AppDialogTone.danger,
      title: AppL10n.of(context).galDeletePhotos,
      message: AppL10n.of(context).galDeleteConfirm(count),
      confirmLabel: AppL10n.of(context).galConfirm,
    );
    if (confirmed != true || !mounted) {
      return;
    }
    // 权限门禁：删除会走设备侧 0x12，未连接时 deleteAlbumPhotos 内部自动扫连
    // （state.dart `connectDevice`）——扫连**必须**先拿到蓝牙/定位授权。
    // 位置在「用户已确认删除」之后、蒙层 loading 之前：授权框要单独出现，
    // 不能和设备操作同屏（见 PermissionGate 文档）。
    if (!await PermissionGate.ensureBleReady(context) || !mounted) {
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
    // 「照片在此设备异常」「刷屏失败」这类「删成功但结果不理想」走警告样式。
    if (feedback.warn) {
      AppToast.warn(context, feedback.message);
    } else {
      _showFeedback(feedback.message);
    }
  }

  /// 蒙层阻断式 loading（不可返回/不可点透），配合耗时的设备 BLE 操作。
  /// 统一走公共的 [AppLoadingDialog]（原来这里有一份私有实现，遮罩偏黑、文字还会被
  /// Flutter 渲染成黄色双下划线——dialog 路由下没有 Material 祖先）。
  void _showBlockingLoading(String text) =>
      AppLoadingDialog.show(context, text);

  void _dismissBlockingLoading() => AppLoadingDialog.hide(context);

  /// 单选照片「刷新屏幕」：把该照片切到相框当前显示（0x24）。未连接会自动扫连，故加蒙层 loading。
  Future<void> _refreshSelectedOnScreen() async {
    if (_selectedIds.length != 1) {
      // 对齐小程序：多选时刷屏给出提示而非静默无反应。
      _showFeedback(AppL10n.of(context).galRefreshSingleOnly);
      return;
    }
    // 同 _confirmDelete：刷屏(0x24)未连接时会自动扫连，授权必须前置于 loading。
    if (!await PermissionGate.ensureBleReady(context) || !mounted) {
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
      // 2026-08-01 产品要求：去掉「设备照片」标题，改由右上角的设备下拉承担标题作用。
      // title 传空串（而不是 null）：null 会连整条顶栏一起不渲染，返回键也没了。
      title: '',
      trailing: _filterOptions.isEmpty ? null : _buildDeviceFilterChip(),
      scrollable: false,
      bodyPadding: EdgeInsets.zero,
      // 全ページ共通背景 bg01（小程序は全画面 mock-bg = 単一背景）。
      background: Image.asset('assets/images/bg01.png', fit: BoxFit.cover),
      // 四分支互斥链（loading 优先）：接口没回来之前只显示 loading，绝不先渲染空态；
      // 刷新失败且本地无数据 → 「加载失败 + 重试」（断网时不能误显示「还没有照片」）。
      body: !state.albumLoaded || !state.devicesLoaded
          ? const PageLoading()
          : photos.isEmpty && (state.albumLoadError || state.devicesLoadError)
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
                      // 设备下拉已上移到顶栏（见 build 的 trailing），这里只留照片操作
                    ],
                  ),
                ),
                const _ScreenPhotoHint(),
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

/// 列表顶部的说明条（小程序 `.album-hint`）：橙点 + 「当前屏幕照片，可指定显示或删除…」。
///
/// 说明这一页看到的是**相框那块屏上的照片**，不是手机相册——用户此前会把它当成
/// 「App 里的相册」，删照片时不理解为什么要连设备。
class _ScreenPhotoHint extends StatelessWidget {
  const _ScreenPhotoHint();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(23, 0, 23, 11),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.5),
          border: Border.all(color: Colors.white.withValues(alpha: 0.82)),
          borderRadius: BorderRadius.circular(9),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 橙点 + 外扩光晕（小程序 .album-hint__dot 的 box-shadow 扩散环）。
            Container(
              width: 5,
              height: 5,
              margin: const EdgeInsets.only(top: 5, left: 3, right: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFFF6725),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFFF6725).withValues(alpha: 0.1),
                    spreadRadius: 3.5,
                  ),
                ],
              ),
            ),
            Expanded(
              child: Text(
                AppL10n.of(context).galScreenHint,
                style: const TextStyle(
                  color: Color(0xFF747D89),
                  fontSize: 11.5,
                  height: 1.45,
                ),
              ),
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
                  memCacheWidth: (140 * MediaQuery.devicePixelRatioOf(context))
                      .round(),
                  // 磁盘缓存同样限宽：不设的话磁盘存的是服务端原图（≤1920 长边），
                  // 百张相册量级要占几十 MB，逐出后二次解码也更贵；瓦片场景 800 足够。
                  maxWidthDiskCache: 800,
                  errorWidget: (context, url, error) => const SizedBox.shrink(),
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
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.88),
          width: 1.5,
        ),
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
