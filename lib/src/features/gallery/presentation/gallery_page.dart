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
import '../../cast/cast_upload_limit.dart';
import '../../cast/presentation/cast_preview_page.dart';
import '../../cast/recast_download.dart';

/// 「我的相册」，对照微信小程序 `photo-album/subpackages/album/list`
/// （2026-08-04 由原「设备照片」+「投屏管理」两个模块合并而来）。
///
/// 口径：
/// - 列表 = **投屏成功**的记录（[PhotoFrameState.refreshCastRecords] 带 `deviceUploadState:1`），
///   按设备分类（顶栏设备下拉即分类器），缩略图就是当次投屏的那张，与设备上的画面一致；
/// - 沿用原「设备照片」页的整套 UI：常驻可选（全选 + 数量 + 每格选择圈 + 底部三枚圆钮）；
/// - 底部第一枚由原「刷新屏幕(0x24)」改为「再次投屏」：单选投一张、多选/全选按批量传输
///   走同一条链路（上限 [CastUploadLimit.batchLimit]）；
/// - 底部第二枚是删除：设备槽位(0x12) + **来源投屏记录**两处一起删。
///
/// ⚠️ 本页（2026-08-17 起）**不再调用任何「我的图库」接口**：数据来源只剩设备列表
///    （[PhotoFrameState.refreshDevices]，铺设备下拉）与投屏成功记录
///    （[PhotoFrameState.refreshCastRecords]，铺网格）。
///    · 删除索引的唯一来源是**这条投屏记录自己的 `imgIndex`**（见
///      [PhotoFrameState.resolveDeleteSlots]）：列表本就是投屏记录铺的，记录里的索引正是投屏成功时
///      `editUserProductImgRecord` 写进去的那份；缺索引整批终止，绝不推算。
///    · 再次投屏的图直接用记录自己的 `img`：2026-07-22 起上传的就是原图，图库照片与这条记录
///      本就是同一次上传的同一张，绕图库那一跳只多一个请求。
///    · 唯一保留的「清空」相关行为是提醒：进页面/切设备时查 `getUserProductClearImg`
///      （[_checkDeviceClearStatus]），它查的是 UserProduct 侧设备状态，不属于图库列表链路。
class GalleryPage extends StatefulWidget {
  const GalleryPage({super.key, required this.state});

  final PhotoFrameState state;

  @override
  State<GalleryPage> createState() => _GalleryPageState();
}

class _GalleryPageState extends State<GalleryPage> with RouteAware {
  /// 已选中的**投屏记录 id**（upirId），不是相册照片 id。
  final Set<String> _selectedIds = <String>{};
  String? _deviceFilter;

  /// 每次拉取记录的本地 loading（区别于 state.castRecordsLoaded 这个「一旦成功就常驻 true」的
  /// stale-while-revalidate 标记）。切设备/首屏期间都显示 loading，避免数据回来前先闪空态。
  /// 与投屏管理页同一套做法。
  bool _loading = true;

  // 一键清除状态查询的防竞态：自增序号标记「最新一次查询」（切换设备时旧结果丢弃），
  // _clearModalShowing 防止提醒弹窗叠加（对齐小程序 clearCheckSeq / clearImgModalShowing）。
  int _clearCheckSeq = 0;
  bool _clearModalShowing = false;

  /// 再次投屏在途锁：连接（可达 10s+）+ 逐张下载（每张超时 20s）期间锁住重复点击，
  /// 否则连点会并发两次 connectDevice 并先后 push 两个预览页（对齐投屏管理页 _recasting）。
  bool _recasting = false;

  PhotoFrameState get state => widget.state;

  @override
  void initState() {
    super.initState();
    // 订阅全局状态：本页原来完全不订阅、只靠交互后的手动 setState，页面打开期间
    // BLE 断链（reconcileConnectionFlags → notify）等外部变化不会反映到界面——
    // 用户会在「看似已连接」的页面发起删除/投屏，多等一轮自动重连超时。
    // 与 devices_page 等页的订阅模式收敛为一种。
    widget.state.addListener(_handleStateChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadAll());
  }

  /// 首屏/重入的完整加载：
  /// 1. 先拿设备列表——设备回来才知道默认筛哪台（记录接口要带 userProductId，顺序不能并发）；
  /// 2. 再拉当前设备的投屏成功记录（本页唯一的列表数据源）；
  /// 3. 最后查一次一键清除状态。
  ///
  /// 2026-08-17：第 2 步原本是「相册照片 + 投屏记录」两个接口并发，图库那个已经没有消费方了，
  /// 留着等于让一个用不上的接口有权把整页打成「加载失败」（它和 getDevices 一起进 Future.wait）。
  Future<void> _loadAll() async {
    if (mounted) {
      setState(() => _loading = true);
    }
    await state.refreshDevices();
    if (!mounted) {
      return;
    }
    _ensureDeviceFilter();
    await _refreshRecords();
    if (!mounted) {
      return;
    }
    setState(() => _loading = false);
    // 设备在别处被一键清空过则弹「请重新上传图片」提醒。
    _checkDeviceClearStatus();
  }

  /// 只拉当前设备的**投屏成功**记录。设备为空（未绑定任何设备）时不带 userProductId，
  /// 与原页面「没有设备也展示已有内容」的行为一致。
  Future<void> _refreshRecords() => state.refreshCastRecords(
    userProductId: _deviceFilter,
    deviceUploadState: 1,
  );

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

  /// 被覆盖的页 pop 回来（重入，如再次投屏走完一轮）：回后端重新对账
  /// （对齐小程序 onShow loadPhotos）。再次投屏会新增一条成功记录，必须重拉才能看到。
  @override
  void didPopNext() {
    _reloadFromBackend();
  }

  /// 下拉刷新 / 重入用的静默重拉：不切 _loading（切了会把列表整页换成 loading，
  /// 从预览页返回时白闪一下），数据回来 setState 即可。
  Future<void> _reloadFromBackend() async {
    await state.refreshDevices();
    if (!mounted) {
      return;
    }
    // 期间可能解绑了当前筛选的设备：重新定一次默认设备再拉数据。
    _ensureDeviceFilter();
    await _refreshRecords();
    if (!mounted) {
      return;
    }
    setState(() => _loading = false);
    _checkDeviceClearStatus();
  }

  /// 下拉每次展开前只重拉设备接口，不复用上次进页时的设备列表，也不连带重拉记录。
  Future<void> _refreshDeviceFiltersForMenu() async {
    await state.refreshDevices();
    if (!mounted) {
      return;
    }
    final previous = _deviceFilter;
    _ensureDeviceFilter();
    setState(() {});
    if (previous != _deviceFilter) {
      // 默认设备真的变了才重拉记录：仅仅展开一下下拉不该把列表清成转圈。
      _checkDeviceClearStatus();
      await _reloadRecordsForFilter();
    }
  }

  /// 切设备后重拉记录：列表区域局部 loading（与投屏管理页切 tab 同一套观感）。
  Future<void> _reloadRecordsForFilter() async {
    if (mounted) {
      setState(() => _loading = true);
    }
    await _refreshRecords();
    if (mounted) {
      setState(() => _loading = false);
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

  /// 默认选中单台设备（对齐小程序 `album/list.js pickDefaultFilter`，2026-08-17 收成三档）：
  ///
  /// 1. **保留用户当前选中的那台**（仍在筛选项里）——本页 `didPopNext` 会重跑，不保留的话
  ///    「点进照片再返回」会把用户手动切过的设备冲掉；
  /// 2. 否则**第一台连接中的**设备（外面刚连上哪台，进来就看哪台）；
  /// 3. 再否则设备列表首台。
  ///
  /// 2026-08-17 删掉了原来夹在 2、3 之间的「第一台有照片的设备」：它的判据取自图库照片的归属
  /// 设备，而本页数据源是投屏记录、图库列表已不再拉。要按「哪台有照片」排就得把每台设备的记录
  /// 都拉一遍（一台一个请求），代价远大于收益——且第 2 档已经覆盖了最常见的场景。
  ///
  /// ⚠️ 连接态**现算**（[PhotoFrameState.isDeviceActuallyConnected] = 真实 BLE 会话 + 身份比对），
  /// 不看 [DeviceItem.connected] 那个缓存标记——它可能是上一次刷新前的旧值，也可能只表示
  /// 「App 连着某台设备」。与小程序 `activeDevice.findConnectedDeviceId` 同一判据。
  /// 单连接下最多命中一台；真出现多台就取设备接口顺序里的第一台。
  ///
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
    // 取值口径与 _filterOptions 一致：只认成得了筛选项的设备，默认值不能落到下拉里没有的项上。
    final selectable = options.map((option) => option.id).toSet();
    final connected = devices.where(
      (device) =>
          selectable.contains(device.id) &&
          state.isDeviceActuallyConnected(device.id),
    );
    _deviceFilter =
        (connected.isNotEmpty ? connected.first : null)?.id ??
        devices
            .firstWhere(
              (device) => selectable.contains(device.id),
              orElse: () => devices.first,
            )
            .id;
  }

  /// 列表数据源 = 当前设备的**投屏成功**记录。
  ///
  /// 后端已按 `userProductId` + `deviceUploadState:1` 过滤；本地再筛一层兜底
  /// （后端忽略过滤参数时也不串设备、不串状态），与投屏管理页同一口径。
  List<CastRecord> get _records {
    final filter = _deviceFilter;
    return state.castRecords
        .where(
          (record) =>
              record.status == CastStatus.success &&
              (filter == null || record.deviceId == filter),
        )
        .toList();
  }

  /// 已选记录，按**网格展示顺序**返回（不是 Set 的迭代顺序）：
  /// 批量再次投屏时预览页的图片顺序要与用户在网格里看到的一致。
  List<CastRecord> get _selectedRecordsInOrder =>
      _records.where((record) => _selectedIds.contains(record.id)).toList();

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
      final ids = _records.map((record) => record.id).toSet();
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
    // 每次切换设备筛选都查一次该设备的一键清除状态（与进入本页同一汇合点）。
    _checkDeviceClearStatus();
    // 记录是按设备向后端筛的，换设备必须重新拉。
    _reloadRecordsForFilter();
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

  /// 顶栏标题位的设备下拉（2026-08-01 从工具栏上移，替代原来的「设备照片」标题；
  /// 2026-08-02 从右上角挪到居中的标题位）。
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

  /// 删除选中照片（对齐小程序 album/list.js confirmDeleteSelected）：
  /// 设备槽位(0x12，含删到屏显图时的补刷屏) → **来源投屏记录**，两处一起删。
  ///
  /// 2026-08-20 口径：两半**互不阻断**——先发设备删除指令，无论它成功、失败还是设备根本没应答，
  /// 都继续删投屏记录；反过来记录接口失败也不回滚设备。两半的结果最后合并成一条提示
  ///（都成功=已删除 / 设备失败=「投屏记录已删除，<原因>」/ 记录失败 / 都失败）。
  /// 唯一的例外是连接前置：连不上这台设备时两半都不执行（[DevicePhotoDeleteOutcome.blocked]）。
  /// 代价（产品已确认接受）：设备真的没删掉时记录先没了，相框上那张图成了只能靠「一键清空」
  /// 清理的幽灵图——删除以「从我的相册里消失」为准，设备侧尽力而为。
  ///
  /// 必须连投屏记录一起删：本页列表就是按成功记录铺的，只删设备侧的话，下次进来这张还在列表里。
  /// 2026-08-17 起端上到此为止，**不再删图库照片**（`delUserProductImg` 已整体下线），
  /// 图库照片的清理归后端。
  Future<void> _confirmDelete() async {
    final records = _selectedRecordsInOrder;
    if (records.isEmpty) {
      return;
    }
    final l10n = AppL10n.of(context);
    final confirmed = await showAppConfirmDialog(
      context,
      icon: Icons.delete_outline_rounded,
      tone: AppDialogTone.danger,
      title: l10n.galDeletePhotos,
      message: l10n.galDeleteConfirm(records.length),
      confirmLabel: l10n.galConfirm,
    );
    if (confirmed != true || !mounted) {
      return;
    }
    // 待删槽位只认**每条投屏记录自己的 imgIndex**：任意一条缺索引/非法就整批终止，
    // 绝不按设备掩码或列表顺序推算位置（推算只会删掉别人的图）。
    final slots = PhotoFrameState.resolveDeleteSlots(records);
    if (slots == null) {
      AppToast.warn(context, l10n.galDeleteNoSlot);
      return;
    }
    // 目标设备 = 当前分类的这台（列表本就是按它向后端筛出来的）；记录带 userProductId 时以它为准。
    final targetDeviceId = records.first.deviceId.isNotEmpty
        ? records.first.deviceId
        : (_deviceFilter ?? '');
    if (targetDeviceId.isEmpty) {
      AppToast.warn(context, l10n.galRecastNoDevice);
      return;
    }
    // 权限门禁：删除会走设备侧 0x12，未连接时 deleteDevicePhotoSlots 内部自动扫连
    // （state.dart `connectDevice`）——扫连**必须**先拿到蓝牙/定位授权。
    // 位置在「用户已确认删除」之后、蒙层 loading 之前：授权框要单独出现，
    // 不能和设备操作同屏（见 PermissionGate 文档）。
    if (!await PermissionGate.ensureBleReady(context) || !mounted) {
      return;
    }
    // 设备侧删除(0x12)可能耗时较久（最长约 180s），期间用蒙层 loading 阻断误操作
    // （对齐小程序 wx.showLoading({title:'删除中', mask:true})）。
    _showBlockingLoading(l10n.galDeleting);
    // dismiss 不做 mounted 门控（hide 本就不依赖 context）：页面在 await 期间被
    // 卸载时也要收掉 root 栈上 canPop:false 的蒙层，否则整个 App 假死。
    // 与 _recastSelected 同一套写法：非空 final 在 try 里赋值，异常时后面的代码本就到不了。
    final DevicePhotoDeleteOutcome deviceOutcome;
    ({int total, int failed})? recordResult;
    try {
      deviceOutcome = await state.deleteDevicePhotoSlots(
        deviceId: targetDeviceId,
        slots: slots,
      );
      // 2026-08-20 口径：设备侧删没删掉**都**照删投屏记录，两半互不阻断。
      // 只有「前置条件不满足」（没选照片 / 设备不存在 / 连不上这台设备）才两半都不执行——
      // 那时端上一条 0x12 都没发出去，照删记录等于用户完全没碰到设备就丢了记录。
      // 允许部分失败：不能因为记录没删干净就回滚设备（设备上的图已经删掉了）。
      if (!deviceOutcome.blocked) {
        recordResult = await state.deleteCastRecords(
          records.map((record) => record.id),
        );
      }
    } finally {
      _dismissBlockingLoading();
    }
    if (!mounted) {
      return;
    }
    if (deviceOutcome.blocked) {
      AppToast.warn(context, deviceOutcome.blockedMessage);
      return;
    }
    setState(_selectedIds.clear);
    // 以后端为准重新对账（张数、记录列表都要跟着变）。
    await _reloadRecordsForFilter();
    if (!mounted) {
      return;
    }
    // 两半的结果合并成一条提示：谁失败就说谁，都失败就都说，都成功才是「已删除」
    //（对齐小程序 confirmDeleteSelected 第 6 步的四分支表）。设备侧的失败**必须**报出来，
    // 否则用户只会看到「已删除」，而相框上那张图其实还在。
    final recordFailed = (recordResult?.failed ?? 0) > 0;
    final deviceError = deviceOutcome.deviceError;
    if (deviceError.isNotEmpty && recordFailed) {
      AppToast.warn(context, l10n.galDeleteBothFailed(deviceError));
      return;
    }
    if (deviceError.isNotEmpty) {
      AppToast.warn(context, l10n.galDeleteRecordOnly(deviceError));
      return;
    }
    if (recordFailed) {
      AppToast.warn(context, l10n.galDeleteRecordPartialFail);
      return;
    }
    // 「刷屏失败」这类「删成功但结果不理想」走警告样式。
    if (deviceOutcome.refreshWarn.isNotEmpty) {
      AppToast.warn(context, deviceOutcome.refreshWarn);
    } else {
      _showFeedback(l10n.galDeleteDone);
    }
  }

  /// 蒙层阻断式 loading（不可返回/不可点透），配合耗时的设备 BLE 操作。
  /// 统一走公共的 [AppLoadingDialog]（原来这里有一份私有实现，遮罩偏黑、文字还会被
  /// Flutter 渲染成黄色双下划线——dialog 路由下没有 Material 祖先）。
  void _showBlockingLoading(String text) =>
      AppLoadingDialog.show(context, text);

  void _dismissBlockingLoading() => AppLoadingDialog.hide(context);

  /// 「再次投屏」（2026-08-04 取代原「刷新屏幕」按钮，对齐小程序底栏第一枚圆钮）。
  ///
  /// 与投屏管理页的「再次投屏」**完全同链路**：连设备 → 把服务器图片下载到本地 →
  /// 进投屏预览页构图 → 点「开始投屏」照常出帧 + BLE 图传 + 建**新记录**。
  /// 所以再次投屏产出的是一张新照片、一条新记录，不改动被选中的那条。
  ///
  /// 单选投一张；多选/全选按批量传输走同一条链路（预览页左右切图逐张构图，
  /// 结果页按张串行图传），张数上限复用 [CastUploadLimit.batchLimit]（常规 10 张）。
  Future<void> _recastSelected() async {
    if (_recasting) {
      return;
    }
    final records = _selectedRecordsInOrder;
    if (records.isEmpty) {
      return;
    }
    final l10n = AppL10n.of(context);
    final limit = CastUploadLimit.batchLimit;
    if (records.length > limit) {
      _showFeedback(l10n.galRecastLimit(limit));
      return;
    }
    // 图源直接取记录自己的 img（2026-08-17：不再按 uProductImgId 回图库找原图）。
    // 那一跳的旧理由是「记录里的 img 是后端按设备尺寸转换过的，直接预览会显得被拉伸」，写于
    // 2026-07-06；自 2026-07-22 `setUserProductUpload` 改传**原图**（只按设备长边等比缩、
    // 不改比例）起就已失效——图库那条照片与这条记录本就是同一次上传的同一张图，绕一圈只多一个
    // 请求。缩略图仅在 img 缺失时兜底。与小程序 doRetryProjection 同口径。
    final urls = <String>[];
    for (final record in records) {
      // 2026-08-20 诊断日志（同步小程序 list.js doRetryProjection）：把「相册选中的记录」
      // 打进「选中记录 → 写入设备的槽位(0x20) → 刷新设备的槽位(0x24)」这条可对账的链。
      // ⚠️ 这里的 imageIndex 是这条记录**当年**写进设备的旧槽位——再次投屏走的是完整链路、
      // 选**新的**空闲槽位、建**新**记录，旧值不参与本次，别拿它去对 0x20 那行的 index。
      debugPrint(
        '[相册再投] 选中记录 id=${record.id} deviceId=${record.deviceId} '
        '旧槽位imgIndex=${record.imageIndex} img=${record.imageUrl ?? ''}',
      );
      final url = record.imageUrl ?? record.thumbUrl ?? '';
      if (url.isNotEmpty) {
        urls.add(url);
      }
    }
    if (urls.isEmpty) {
      _showFeedback(l10n.galRecastNoImage);
      return;
    }
    // 目标设备 = 当前分类的这台（列表本就是按它向后端筛出来的）；记录带 userProductId 时以它为准。
    final targetDeviceId = records.first.deviceId.isNotEmpty
        ? records.first.deviceId
        : (_deviceFilter ?? '');
    if (targetDeviceId.isEmpty) {
      _showFeedback(l10n.galRecastNoDevice);
      return;
    }
    // 重入锁在权限门禁之前上：授权框停留期间用户还能再点，不锁就会并发两次 connectDevice。
    // 整段包在一个 try/finally 里——中途任何一条 return（连不上、下载全失败…）都必须解锁，
    // 否则本页的「再次投屏」会永久点不动。
    _recasting = true;
    try {
      // 权限门禁：下一步就是 connectDevice(扫连)，蓝牙/定位授权必须先拿到，
      // 且必须在 AppLoadingDialog **之前**（授权框与设备操作不同屏，见 PermissionGate 文档）。
      if (!await PermissionGate.ensureBleReady(context) || !mounted) {
        return;
      }
      // 连接与下载分两段 loading：AppLoadingDialog 的文案不能中途改，批量下载可能要几十秒，
      // 一直显示「连接设备中」会让用户以为卡在连接上。
      final ActionFeedback connectFeedback;
      _showBlockingLoading(l10n.castConnectingDevice);
      try {
        connectFeedback = await state.connectDevice(targetDeviceId);
      } finally {
        // 不做 mounted 门控：页面在 await 期间被卸载时也要收掉 root 栈上 canPop:false 的蒙层。
        _dismissBlockingLoading();
      }
      if (!mounted) {
        return;
      }
      if (!connectFeedback.success) {
        _showFeedback(connectFeedback.message);
        return;
      }
      final device = state.deviceById(targetDeviceId);

      // 逐张下载到本地：小程序的预览页能直接吃远程 URL，Flutter 预览页只接受本地路径。
      final paths = <String>[];
      _showBlockingLoading(l10n.galRecastPreparing);
      try {
        for (var i = 0; i < urls.length; i++) {
          final path = await RecastDownload.toTempFile(urls[i], seq: i);
          if (path != null) {
            paths.add(path);
          }
        }
      } finally {
        _dismissBlockingLoading();
      }
      if (!mounted) {
        return;
      }
      if (paths.isEmpty) {
        // 一张都没下下来就只能中止：预览页只接受本地路径，没有第二条路可退。
        _showFeedback(l10n.castRecordImageDownloadFailed);
        return;
      }
      if (paths.length < urls.length) {
        // 部分失败：能投的先投，但要明确告诉用户少了几张，不静默吞掉。
        _showFeedback(l10n.castRecordImageDownloadFailed);
      }
      // 与手选照片完全同链路：进预览页构图 →「开始投屏」出帧 + 建**新**记录。
      await Navigator.of(context).push(
        AppPageRoute(
          builder: (_) =>
              CastPreviewPage(state: state, device: device, imagePaths: paths),
        ),
      );
      if (!mounted) {
        return;
      }
      // 再次投屏会新增成功记录；列表由 didPopNext 重新对账，这里只清掉选中态。
      setState(_selectedIds.clear);
    } finally {
      _recasting = false;
    }
  }

  void _showFeedback(String message) {
    AppToast.show(context, message);
  }

  @override
  Widget build(BuildContext context) {
    final records = _records;
    final hasSelection = _selectedIds.isNotEmpty;

    return FigmaScreen(
      // 2026-08-01 产品要求：去掉页面标题，改由设备下拉承担标题作用（下拉同时是「按设备分类」的分类器）。
      // title 传空串（而不是 null）：null 会连整条顶栏一起不渲染，返回键也没了。
      // 2026-08-02：下拉从 trailing（靠右贴边）挪到 centerContent（标题位、水平居中）。
      title: '',
      centerContent: _filterOptions.isEmpty ? null : _buildDeviceFilterChip(),
      scrollable: false,
      bodyPadding: EdgeInsets.zero,
      // 全ページ共通背景 bg01（小程序は全画面 mock-bg = 単一背景）。
      background: Image.asset('assets/images/bg02.jpg', fit: BoxFit.cover),
      // 四分支互斥链（loading 优先）：接口没回来之前只显示 loading，绝不先渲染空态；
      // 刷新失败且本地无数据 → 「加载失败 + 重试」（断网时不能误显示「还没有照片」）。
      body: _loading || !state.devicesLoaded
          ? const PageLoading()
          : records.isEmpty &&
                (state.castRecordsLoadError || state.devicesLoadError)
          ? PageLoadError(onRetry: _loadAll)
          : records.isEmpty
          ? _buildEmptyBody()
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 工具栏：全选 + 数量（设备下拉已上移到顶栏标题位）。
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
                        AppL10n.of(context).galTotalCount(records.length),
                        style: const TextStyle(
                          color: Color(0xFF777E88),
                          fontSize: 14,
                          height: 1,
                        ),
                      ),
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
                      itemCount: records.length,
                      itemBuilder: (context, index) {
                        final record = records[index];
                        return _GalleryTile(
                          record: record,
                          selected: _selectedIds.contains(record.id),
                          onTap: () => _toggleOne(record.id),
                        );
                      },
                    ),
                  ),
                ),
                if (hasSelection)
                  _SelectionBar(
                    onDelete: _confirmDelete,
                    // 2026-08-04：原「刷新屏幕」改为「再次投屏」，单选/多选都走同一个入口。
                    onRecast: _recastSelected,
                    onCancel: () => setState(_selectedIds.clear),
                  ),
              ],
            ),
    );
  }
}

/// 列表顶部的说明条（小程序 `.album-hint`）：橙点 + 「选中照片可再次投屏或删除…」。
///
/// 说明这一页看到的是**投屏成功、当前还在相框那块屏上的照片**，不是手机相册——
/// 用户此前会把它当成「App 里的相册」，删照片时不理解为什么要连设备。
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

/// 网格瓦片。2026-08-04 数据源由相册照片改为**投屏成功记录**：
/// 缩略图取记录的 `imgThumb`，就是当次投屏到设备上的那张，与屏幕画面一致。
class _GalleryTile extends StatelessWidget {
  const _GalleryTile({
    required this.record,
    required this.selected,
    required this.onTap,
  });

  final CastRecord record;
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
                    record.color.withValues(alpha: 0.92),
                    record.color.withValues(alpha: 0.5),
                    const Color(0xFFF3F2F0),
                  ],
                ),
              ),
            ),
            if (record.thumbUrl != null)
              Positioned.fill(
                child: CachedNetworkImage(
                  // 列表只取缩略图 imgThumb（无则回退 img），对齐小程序 list.wxml 的 item.imgThumb。
                  imageUrl: record.thumbUrl!,
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
                  record.source == ImageSourceType.camera
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

/// 选中底栏（小程序 `.album-bottom-bar`）：透明浮层，居中三枚渐变圆按钮 再次投屏/删除/取消。
/// 无白底、无阴影、无「已选 N 张」文案（对齐小程序 background:transparent + 三圆居中）。
class _SelectionBar extends StatelessWidget {
  const _SelectionBar({
    required this.onDelete,
    this.onRecast,
    required this.onCancel,
  });

  final VoidCallback onDelete;

  /// 再次投屏（2026-08-04 取代原「刷新屏幕 0x24」）：单选投一张，多选/全选按批量传输走。
  final VoidCallback? onRecast;

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
          // 再次投屏：橙色渐变（.action-retry，2026-08-04 前是「刷新屏幕」）。
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
            onTap: onRecast,
            label: AppL10n.of(context).galRecast,
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

/// 「我的相册」空态，对照小程序 `.album-empty`：插图 + 标题 + 描述，**无按钮**
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
