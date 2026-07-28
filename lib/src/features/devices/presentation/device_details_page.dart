import 'package:flutter/material.dart';

import 'package:BoltStar/src/shared/widgets/app_dialog.dart';
import 'package:BoltStar/src/shared/widgets/app_widgets.dart';
import 'package:BoltStar/src/shared/widgets/figma_common.dart';
import '../../../device/frame_device_protocol.dart';
import '../../../routes/app_routes.dart';
import '../../../shared/permission_gate.dart';
import '../../../state.dart';
import '../../cast/cast_photo_picker.dart';
import '../../cast/presentation/cast_preview_page.dart';
import '../../../shared/l10n/app_l10n.dart';

/// 设备详情页：查看单个设备信息并进入 投屏 / 连接·断开 / 轮播设置 / 清空 / 删除 等操作。
///
/// 对照微信小程序 `photo-album/subpackages/device/detail`：摘要卡 + 顶部操作栏（投屏 / 连接·断开）+
/// 信息列表 + 操作列表（清空 / 删除），删除/清空走全局统一的二次确认弹窗（见 [AppDialog]）。
/// 展示当前选中设备（`state.selectedDevice`），随 [PhotoFrameState] 变化自动刷新。
class DeviceDetailsPage extends StatefulWidget {
  const DeviceDetailsPage({
    super.key,
    required this.state,
    required this.deviceId,
    this.onCarouselSettings,
    this.onClearDevice,
    this.onDeleteDevice,
    this.onOtaUpgrade,
  });

  final PhotoFrameState state;
  final String deviceId;
  final VoidCallback? onCarouselSettings;
  final VoidCallback? onClearDevice;
  final VoidCallback? onDeleteDevice;
  final VoidCallback? onOtaUpgrade;

  @override
  State<DeviceDetailsPage> createState() => _DeviceDetailsPageState();
}

class _DeviceDetailsPageState extends State<DeviceDetailsPage> with RouteAware {
  // 让本 State 内既有的 `state.xxx` 调用继续可用（无需逐处改成 widget.state）。
  PhotoFrameState get state => widget.state;
  DeviceItem get device => state.deviceById(widget.deviceId);

  @override
  void initState() {
    super.initState();
    // 打开即重读一次真机内存/索引（对齐小程序 detail.js onShow→loadDetail→readDeviceInfo，Bug13）。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      state.refreshConnectedDeviceInfo(widget.deviceId);
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

  // 从被覆盖页（投屏预览/清空/删除确认等）返回时再读一次内存（对齐小程序 onShow）。
  @override
  void didPopNext() {
    state.refreshConnectedDeviceInfo(widget.deviceId);
  }

  @override
  Widget build(BuildContext context) {
    return FigmaScreen(
      title: AppL10n.of(context).devDetailTitle,
      body: AnimatedBuilder(
        animation: state,
        builder: (context, _) => DeviceDetailsBody(
          state: state,
          deviceId: widget.deviceId,
          onEditName: () => _renameDevice(context),
          onConnectToggle: () => _toggleConnection(context),
          onCast: () => _startCast(context),
          onCarouselSettings: widget.onCarouselSettings,
          onClearDevice: widget.onClearDevice,
          onDeleteDevice: widget.onDeleteDevice,
          onOtaUpgrade: widget.onOtaUpgrade,
        ),
      ),
    );
  }

  void _snack(BuildContext context, String message) {
    AppToast.warn(context, message);
  }

  /// 摘要卡编辑图标：重命名当前设备（对齐小程序 detail.js `showRenameModal`）。
  Future<void> _renameDevice(BuildContext context) async {
    final device = this.device;
    final controller = TextEditingController(text: device.name);
    final String? name;
    try {
      final confirmed = await showAppConfirmDialog(
        context,
        title: AppL10n.of(context).devRenameTitle,
        icon: Icons.drive_file_rename_outline_rounded,
        confirmLabel: AppL10n.of(context).devConfirm,
        content: AppDialogTextField(
          controller: controller,
          hintText: AppL10n.of(context).devNameHint,
          maxLength: 20,
        ),
      );
      name = confirmed == true ? controller.text.trim() : null;
    } finally {
      // 原来从不 dispose（每次重命名泄漏一个 ChangeNotifier）；退场动画期间 TextField
      // 仍挂着 controller，延迟一个主题动画时长再释放，避免 used-after-dispose 断言。
      Future<void>.delayed(kThemeAnimationDuration, controller.dispose);
    }
    if (name == null || name == device.name) {
      return;
    }
    final feedback = await state.renameDevice(device.id, name);
    if (context.mounted && !feedback.success) {
      _snack(context, feedback.message);
    }
  }

  /// 连接/断开进行中标记：断开方向没有阻断 loading（对齐小程序，断开很快），
  /// 连点会并发两次 disconnect——BLE 层虽幂等，仍锁住避免交错。
  bool _togglingConnection = false;

  /// 顶部操作栏「连接 / 断开」（对齐小程序 detail.js `toggleConnection`）。
  Future<void> _toggleConnection(BuildContext context) async {
    if (_togglingConnection) {
      return;
    }
    _togglingConnection = true;
    try {
      await _doToggleConnection(context);
    } finally {
      _togglingConnection = false;
    }
  }

  Future<void> _doToggleConnection(BuildContext context) async {
    final device = this.device;
    final wasConnected = state.isDeviceActuallyConnected(device.id);
    // 连接方向先单独走授权框，全就绪才弹「连接中」loading（断开无需权限）。
    if (!wasConnected &&
        (!await PermissionGate.ensureBleReady(context) || !context.mounted)) {
      return;
    }
    if (!wasConnected) {
      AppLoadingDialog.show(context, AppL10n.of(context).devConnecting);
    }
    // hide 放 finally 且不做 mounted 门控（见 AppLoadingDialog.hide 注释）：
    // 页面在 await 期间被卸载时也要收掉 root 栈上 canPop:false 的蒙层。
    final ActionFeedback feedback;
    try {
      feedback = wasConnected
          ? await state.disconnectDevice(device.id)
          : await state.connectDevice(device.id);
    } finally {
      if (!wasConnected) {
        AppLoadingDialog.hide(context);
      }
    }
    if (!context.mounted) {
      return;
    }
    if (!feedback.success) {
      _snack(context, feedback.message);
    }
  }

  /// 未连接则蒙层 loading 自动扫连（对齐小程序 detail.js startProjection→connectDevice）；
  /// 连上返回 true，失败提示并返回 false。
  Future<bool> _ensureConnected(BuildContext context, String deviceId) async {
    // 授权框先单独出现，全就绪才弹「连接中」loading。
    if (!await PermissionGate.ensureBleReady(context) || !context.mounted) {
      return false;
    }
    AppLoadingDialog.show(context, AppL10n.of(context).devConnecting);
    // 统一 hide 收口（精确移除 + 无 mounted 门控），替换掉盲 pop（历史闪退根源）。
    final ActionFeedback feedback;
    try {
      feedback = await state.connectDevice(deviceId);
    } finally {
      AppLoadingDialog.hide(context);
    }
    if (!context.mounted) {
      return false;
    }
    if (!feedback.success) {
      _snack(context, feedback.message);
    }
    return feedback.success;
  }

  /// 拍照 / 相册选择面板：走共用卡片式弹层（对齐小程序 `.media-sheet` / 首页同款）。
  Future<ImageSourceType?> _pickCastSource(BuildContext context) {
    return CastPhotoPicker.chooseSource(context);
  }

  /// 顶部操作栏「投屏」：未连接自动扫连 → 拍照/相册 → 真实投屏（对齐小程序 detail.js `startProjection`）。
  Future<void> _startCast(BuildContext context) async {
    final device = this.device;
    if (!state.isDeviceActuallyConnected(device.id)) {
      final connected = await _ensureConnected(context, device.id);
      if (!connected || !context.mounted) {
        return;
      }
    }
    final source = await _pickCastSource(context);
    if (source == null || !context.mounted) {
      return;
    }
    List<String> imagePaths;
    try {
      // 统一走 CastPhotoPicker：选图时就用平台原生解码器把长边降到 1920，
      // 避免把 4~12MB 的相机原图整个传给后端（投屏耗时大头在上传，不在 BLE）。
      imagePaths = (source == ImageSourceType.camera)
          ? await CastPhotoPicker.takePhoto()
          : await CastPhotoPicker.pickFromAlbum(context);
    } catch (_) {
      if (context.mounted) {
        _snack(context, AppL10n.of(context).devPhotoReadFailed);
      }
      return;
    }
    if (!context.mounted || imagePaths.isEmpty) {
      return;
    }
    // 与小程序一致：选图后进入预览，可裁剪、旋转、还原原图，确认后再走后端转码与 BLE 图传。
    await Navigator.of(context).push<void>(
      AppPageRoute(
        // 选图后先进**投屏预览页**（裁剪/旋转/原图），确认后才开始投屏。
        builder: (_) => CastPreviewPage(
          state: state,
          device: state.deviceById(device.id),
          imagePaths: imagePaths,
        ),
      ),
    );
    state.refreshAlbum();
    state.refreshCastRecords();
  }
}

/// 设备详情正文（供详情页与「删除 / 清空确认」页复用）。
class DeviceDetailsBody extends StatelessWidget {
  const DeviceDetailsBody({
    super.key,
    required this.state,
    required this.deviceId,
    this.onEditName,
    this.onConnectToggle,
    this.onCast,
    this.onCarouselSettings,
    this.onClearDevice,
    this.onDeleteDevice,
    this.onOtaUpgrade,
  });

  final PhotoFrameState state;
  final String deviceId;

  /// 摘要卡编辑图标点击（重命名）；为空则不可点（如清空/删除确认页复用正文时）。
  final VoidCallback? onEditName;

  /// 顶部操作栏「连接/断开」；[onConnectToggle] 或 [onCast] 任一非空才渲染操作栏。
  final VoidCallback? onConnectToggle;

  /// 顶部操作栏「投屏」。
  final VoidCallback? onCast;

  final VoidCallback? onCarouselSettings;
  final VoidCallback? onClearDevice;
  final VoidCallback? onDeleteDevice;
  final VoidCallback? onOtaUpgrade;

  String _carouselLabel(BuildContext context) {
    final device = state.deviceById(deviceId);
    final l10n = AppL10n.of(context);
    // 轮播设置是「连接才可信」的实时数据：未连接（含断开设备后）一律 -- 占位，与小程序详情页一致。
    if (!state.isDeviceActuallyConnected(device.id)) {
      return '--';
    }
    // 对齐小程序 getPlaybackLabel：manual 或未启用 → 「未启用」。
    if (device.playbackMode == FramePlaybackMode.manual ||
        !device.carouselEnabled) {
      return l10n.devCarouselDisabled;
    }
    return device.playbackMode == FramePlaybackMode.random
        ? l10n.devCarouselRandom
        : l10n.devCarouselSequential;
  }

  static String _batteryAsset(int level) {
    const levels = <int>[0, 10, 20, 30, 40, 50, 60, 70, 80, 90, 100];
    var nearest = levels.first;
    for (final candidate in levels) {
      if ((candidate - level).abs() < (nearest - level).abs()) {
        nearest = candidate;
      }
    }
    return 'assets/images/BatteryLevel/battery-$nearest.png';
  }

  @override
  Widget build(BuildContext context) {
    final device = state.deviceById(deviceId);
    final connected = state.isDeviceActuallyConnected(device.id);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        // 摘要卡：设备图标 + 名称 + 连接状态 / 电量。
        FigmaGlassCard(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
          child: Row(
            children: [
              // 设备图统一用首页那张 home-icon02（原来是 device-list-icon01，另一张小图）。
              // 该图四角 alpha=0 自带圆角，故去掉原先的橙色底色容器与圆角裁剪——
              // 首页没有底色，留着会在四角露出色晕，三处就不一致了。
              SizedBox(
                width: 46,
                height: 46,
                child: Image.asset(
                  'assets/images/home-icon02.png',
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) => const Icon(
                    Icons.photo_library_outlined,
                    color: Color(0xFFEB5F1B),
                    size: 28,
                  ),
                ),
              ),
              const SizedBox(width: 17),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            device.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFF2A2D32),
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              height: 1.2,
                            ),
                          ),
                        ),
                        // 点击区 40×40（见 FigmaEditIconButton）：原来是 18×18 的裸
                        // Image，用户反馈「很难点击到」。图标自带 11px 留白，
                        // 原先的 SizedBox(width: 3) / SizedBox(height: 9) 一并去掉。
                        FigmaEditIconButton(onTap: onEditName),
                      ],
                    ),
                    Row(
                      children: [
                        Image.asset(
                          connected
                              ? 'assets/images/bluetooth-icon.png'
                              : 'assets/images/bluetooth-icon-not.png',
                          width: 11,
                          height: 14,
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) =>
                              const SizedBox(width: 11, height: 14),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          connected
                              ? AppL10n.of(context).devConnected
                              : AppL10n.of(context).devDisconnected,
                          style: TextStyle(
                            color: connected
                                ? const Color(0xFF287DFF)
                                : const Color(0xFF9BA2AD),
                            fontSize: 12,
                            height: 1,
                          ),
                        ),
                        if (connected) ...[
                          const SizedBox(width: 15),
                          if (device.hasBatteryReading) ...[
                            Image.asset(
                              _batteryAsset(device.batteryLevel),
                              width: 24,
                              fit: BoxFit.contain,
                              errorBuilder: (context, error, stackTrace) =>
                                  const Icon(
                                    Icons.battery_4_bar_rounded,
                                    size: 16,
                                    color: Color(0xFF777E88),
                                  ),
                            ),
                            const SizedBox(width: 5),
                          ],
                          Text(
                            device.batteryLabel,
                            style: const TextStyle(
                              color: Color(0xFF777E88),
                              fontSize: 12,
                              height: 1,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        // 顶部操作栏：投屏 / 连接·断开（仅详情页渲染；清空/删除确认页复用正文时无这些回调，不渲染）。
        // 样式对齐小程序 detail.wxss `.device-actions glass-panel`（与「我的设备」列表卡同款）：
        // 一条玻璃面板（84rpx=42 高 / 28rpx=14 圆角）内两个等宽图文按钮，中间 38rpx=19 高竖分割线；
        // 投屏恒橙色 #eb5f1b，连接蓝 #2079fc / 断开橙 #eb5f1b。
        if (onConnectToggle != null || onCast != null) ...[
          const SizedBox(height: 12),
          Container(
            height: 42,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withValues(alpha: 0.86)),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF7991B2).withValues(alpha: 0.13),
                  blurRadius: 27,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            // stretch：让按钮铺满 42 高度，点击区覆盖整颗按钮。
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (onCast != null)
                  Expanded(
                    child: _DeviceActionButton(
                      iconAsset: 'assets/images/screen-casting-icon01.png',
                      fallbackIcon: Icons.cast_rounded,
                      iconSize: 20,
                      label: AppL10n.of(context).devCast,
                      color: const Color(0xFFEB5F1B),
                      onTap: onCast,
                    ),
                  ),
                if (onCast != null && onConnectToggle != null)
                  const Center(
                    child: SizedBox(
                      width: 1,
                      height: 19,
                      child: ColoredBox(color: Color(0xFFDADDDF)),
                    ),
                  ),
                if (onConnectToggle != null)
                  Expanded(
                    child: _DeviceActionButton(
                      iconAsset: connected
                          ? 'assets/images/disconnect-icon01.png'
                          : 'assets/images/bluetooth-connection.png',
                      fallbackIcon: connected
                          ? Icons.link_off_rounded
                          : Icons.bluetooth_rounded,
                      iconSize: 16,
                      label: connected
                          ? AppL10n.of(context).devDisconnectShort
                          : AppL10n.of(context).devConnectShort,
                      color: connected
                          ? const Color(0xFFEB5F1B)
                          : const Color(0xFF2079FC),
                      onTap: onConnectToggle,
                    ),
                  ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 12),
        // 信息列表：轮播设置 / 设备ID / 设备内存 / OTA升级。
        FigmaGlassCard(
          padding: const EdgeInsets.symmetric(horizontal: 19),
          child: Column(
            children: [
              _DetailRow(
                iconAsset: 'assets/images/device-detail-icon01.png',
                fallbackIcon: Icons.tune_rounded,
                label: AppL10n.of(context).devCarouselSetting,
                value: _carouselLabel(context),
                showChevron: true,
                onTap: onCarouselSettings,
              ),
              const _ThinDivider(),
              _DetailRow(
                iconAsset: 'assets/images/device-detail-icon02.png',
                fallbackIcon: Icons.tag_rounded,
                label: AppL10n.of(context).devDeviceId,
                // 设备ID只在已连接时展示（用户定版：未连接一律 -- 占位）。
                // 也**不再回退 device.id**——那是后端记录主键 userProductId，
                // 不是设备ID，回退显示会让用户以为设备有个「默认ID」。
                value: connected && device.serialNumber.isNotEmpty
                    ? device.serialNumber
                    : '--',
              ),
              const _ThinDivider(),
              _DetailRow(
                iconAsset: 'assets/images/device-detail-icon03.png',
                fallbackIcon: Icons.sd_storage_outlined,
                label: AppL10n.of(context).devDeviceMemory,
                // 内存占用是连接才读得到的实时数据（0x01 的 IMG_MASK）：未连接（含断开设备后）一律 --，
                // 避免未连接时显示后端不下发而回落的 0/容量，误导用户（对齐小程序断开后内存变 --）。
                value: connected
                    ? '${device.imageCount}/${device.capacity}'
                    : '--',
              ),
              const _ThinDivider(),
              _DetailRow(
                iconAsset: 'assets/images/device-detail-icon04.png',
                fallbackIcon: Icons.system_update_alt_rounded,
                label: AppL10n.of(context).devOtaUpgrade,
                value: device.hasFirmwareUpdate
                    ? AppL10n.of(
                        context,
                      ).devFirmwareNewVersion(device.newVersionNo)
                    : (device.firmwareVersion.isEmpty
                          ? '-'
                          : device.firmwareVersion),
                showChevron: true,
                onTap: onOtaUpgrade,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // 操作列表：一键清空 / 删除设备。
        FigmaGlassCard(
          padding: const EdgeInsets.symmetric(horizontal: 19),
          child: Column(
            children: [
              _DetailRow(
                iconAsset: 'assets/images/device-detail-icon05.png',
                fallbackIcon: Icons.cleaning_services_outlined,
                label: AppL10n.of(context).devClearAll,
                labelColor: const Color(0xFFFF6A20),
                labelWeight: FontWeight.w500,
                value: AppL10n.of(context).devClearAllValue,
                showChevron: true,
                onTap: onClearDevice,
              ),
              const _ThinDivider(),
              _DetailRow(
                iconAsset: 'assets/images/device-detail-icon06.png',
                fallbackIcon: Icons.delete_outline_rounded,
                label: AppL10n.of(context).devDeleteDevice,
                labelColor: const Color(0xFFFF3045),
                labelWeight: FontWeight.w500,
                value: AppL10n.of(context).devDeleteDeviceValue,
                showChevron: true,
                onTap: onDeleteDevice,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 详情/操作列表的单行：左侧图标 + 标题，右侧取值（+ 可选箭头）。
class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.iconAsset,
    required this.fallbackIcon,
    required this.label,
    required this.value,
    this.labelColor = const Color(0xFF33373D),
    this.labelWeight = FontWeight.w600,
    this.showChevron = false,
    this.onTap,
  });

  final String iconAsset;
  final IconData fallbackIcon;
  final String label;
  final String value;
  final Color labelColor;
  final FontWeight labelWeight;
  final bool showChevron;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        height: 60,
        child: Row(
          children: [
            Image.asset(
              iconAsset,
              width: 20,
              height: 20,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) =>
                  Icon(fallbackIcon, size: 20, color: labelColor),
            ),
            const SizedBox(width: 15),
            // 左侧标题按内容宽度（短标签），纯 Text 不占弹性——把中间空间全部让给右侧
            // 取值。原来 label 用 Expanded 会强占一大块，value 再硬限 maxWidth:193，
            // 中间空着也不给 value，长内容一直 `...`（用户反馈问题，2026-07-17）。
            Text(
              label,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: labelColor,
                fontSize: 14,
                fontWeight: labelWeight,
                height: 1.2,
              ),
            ),
            const SizedBox(width: 11),
            // 右侧取值右对齐、占据 label 之外的全部剩余空间：中间够宽就多显示，
            // 真超出剩余宽度才 `...`（不再硬限 193）。
            Expanded(
              child: Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: const TextStyle(
                  color: Color(0xFF777E88),
                  fontSize: 14,
                  height: 1.2,
                ),
              ),
            ),
            if (showChevron) ...[
              const SizedBox(width: 8),
              const Icon(
                Icons.chevron_right_rounded,
                color: Color(0xFF777E88),
                size: 18,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 细分割线（小程序 `.thin-divider`，rgba(42,43,43,0.08)）。
class _ThinDivider extends StatelessWidget {
  const _ThinDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 1,
      color: const Color(0xFF2A2B2B).withValues(alpha: 0.08),
    );
  }
}

/// 详情页顶部操作条内的图文按钮（小程序 `.device-action`）：图标 + 文案居中，
/// 文字 28rpx=14 / w500，颜色随按钮语义（投屏橙 / 连接蓝 / 断开橙）。
class _DeviceActionButton extends StatelessWidget {
  const _DeviceActionButton({
    required this.iconAsset,
    required this.fallbackIcon,
    required this.iconSize,
    required this.label,
    required this.color,
    this.onTap,
  });

  final String iconAsset;
  final IconData fallbackIcon;
  final double iconSize;
  final String label;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Image.asset(
            iconAsset,
            width: iconSize,
            height: iconSize,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) =>
                Icon(fallbackIcon, size: 16, color: color),
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 14,
              fontWeight: FontWeight.w500,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}
