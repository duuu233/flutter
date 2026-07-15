import 'package:flutter/material.dart';

import 'package:BoltStar/src/shared/widgets/app_widgets.dart';
import 'package:BoltStar/src/shared/widgets/figma_common.dart';
import '../../../device/frame_device_protocol.dart';
import '../../../routes/app_routes.dart';
import '../../../state.dart';
import '../../cast/cast_photo_picker.dart';
import '../../cast/presentation/cast_preview_page.dart';
import '../../../shared/l10n/app_l10n.dart';

/// 设备详情页：查看单个设备信息并进入 投屏 / 连接·断开 / 轮播设置 / 清空 / 删除 等操作。
///
/// 对照微信小程序 `photo-album/subpackages/device/detail`：摘要卡 + 顶部操作栏（投屏 / 连接·断开）+
/// 信息列表 + 操作列表（清空 / 删除），删除/清空走二次确认弹窗（见 [DeviceConfirmDialog]）。
/// 展示当前选中设备（`state.selectedDevice`），随 [PhotoFrameState] 变化自动刷新。
class DeviceDetailsPage extends StatefulWidget {
  const DeviceDetailsPage({
    super.key,
    required this.state,
    this.onCarouselSettings,
    this.onClearDevice,
    this.onDeleteDevice,
    this.onOtaUpgrade,
  });

  final PhotoFrameState state;
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

  @override
  void initState() {
    super.initState();
    // 打开即重读一次真机内存/索引（对齐小程序 detail.js onShow→loadDetail→readDeviceInfo，Bug13）。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      state.refreshSelectedDeviceMemory();
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
    state.refreshSelectedDeviceMemory();
  }

  @override
  Widget build(BuildContext context) {
    return FigmaScreen(
      title: AppL10n.of(context).devDetailTitle,
      body: AnimatedBuilder(
        animation: state,
        builder: (context, _) => DeviceDetailsBody(
          state: state,
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
    final device = state.selectedDevice;
    final controller = TextEditingController(text: device.name);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppL10n.of(context).devRenameTitle),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 6,
          decoration: const InputDecoration(hintText: '请输入设备名称（1-6个字符）'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(AppL10n.of(context).cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: Text(AppL10n.of(context).devConfirm),
          ),
        ],
      ),
    );
    if (name == null || name == device.name) {
      return;
    }
    final feedback = await state.renameDevice(device.id, name);
    if (context.mounted && !feedback.success) {
      _snack(context, feedback.message);
    }
  }

  /// 顶部操作栏「连接蓝牙 / 断开连接」（对齐小程序 detail.js `toggleConnection`）。
  Future<void> _toggleConnection(BuildContext context) async {
    final device = state.selectedDevice;
    final wasConnected = device.connected;
    if (!wasConnected) {
      AppLoadingDialog.show(context, '连接设备中');
    }
    final feedback = wasConnected
        ? await state.disconnectDevice(device.id)
        : await state.connectDevice(device.id);
    if (!context.mounted) {
      return;
    }
    if (!wasConnected) {
      AppLoadingDialog.hide(context);
    }
    if (!feedback.success) {
      _snack(context, feedback.message);
    }
  }

  /// 未连接则蒙层 loading 自动扫连（对齐小程序 detail.js startProjection→connectDevice）；
  /// 连上返回 true，失败提示并返回 false。
  Future<bool> _ensureConnected(BuildContext context, String deviceId) async {
    AppLoadingDialog.show(context, AppL10n.of(context).devConnecting);
    final feedback = await state.connectDevice(deviceId);
    if (!context.mounted) {
      return false;
    }
    Navigator.of(context, rootNavigator: true).pop();
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
    final device = state.selectedDevice;
    if (!device.connected) {
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
          : await CastPhotoPicker.pickFromAlbum();
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
      MaterialPageRoute(
        // 选图后先进**投屏预览页**（裁剪/旋转/原图），确认后才开始投屏。
        builder: (_) => CastPreviewPage(
          state: state,
          device: device,
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
    this.onEditName,
    this.onConnectToggle,
    this.onCast,
    this.onCarouselSettings,
    this.onClearDevice,
    this.onDeleteDevice,
    this.onOtaUpgrade,
  });

  final PhotoFrameState state;

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
    final device = state.selectedDevice;
    final l10n = AppL10n.of(context);
    // 轮播设置是「连接才可信」的实时数据：未连接（含断开设备后）一律 -- 占位，与小程序详情页一致。
    if (!device.connected) {
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
    final device = state.selectedDevice;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        // 摘要卡：设备图标 + 名称 + 连接状态 / 电量。
        FigmaGlassCard(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: const Color(0xFFFF6A20).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Image.asset(
                  'assets/images/device-list-icon01.png',
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
                        const SizedBox(width: 3),
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: onEditName,
                          child: Image.asset(
                            'assets/images/edit-icon01.png',
                            width: 18,
                            height: 18,
                            fit: BoxFit.contain,
                            errorBuilder: (context, error, stackTrace) =>
                                const Icon(
                                  Icons.edit_outlined,
                                  size: 16,
                                  color: Color(0x992A2B2B),
                                ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 9),
                    Row(
                      children: [
                        Image.asset(
                          device.connected
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
                          device.connected
                              ? AppL10n.of(context).devConnected
                              : AppL10n.of(context).devDisconnected,
                          style: TextStyle(
                            color: device.connected
                                ? const Color(0xFF287DFF)
                                : const Color(0xFF9BA2AD),
                            fontSize: 12,
                            height: 1,
                          ),
                        ),
                        if (device.connected) ...[
                          const SizedBox(width: 15),
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
                          Text(
                            '${device.batteryLevel}%',
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
        if (onConnectToggle != null || onCast != null) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              if (onCast != null)
                Expanded(
                  child: _DeviceActionButton(
                    label: AppL10n.of(context).devCast,
                    primary: true,
                    onTap: onCast,
                  ),
                ),
              if (onCast != null && onConnectToggle != null)
                const SizedBox(width: 12),
              if (onConnectToggle != null)
                Expanded(
                  child: _DeviceActionButton(
                    label: device.connected
                        ? AppL10n.of(context).devDisconnect
                        : AppL10n.of(context).devConnectBluetooth,
                    primary: false,
                    onTap: onConnectToggle,
                  ),
                ),
            ],
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
                value: device.serialNumber.isEmpty
                    ? device.id
                    : device.serialNumber,
              ),
              const _ThinDivider(),
              _DetailRow(
                iconAsset: 'assets/images/device-detail-icon03.png',
                fallbackIcon: Icons.sd_storage_outlined,
                label: AppL10n.of(context).devDeviceMemory,
                // 内存占用是连接才读得到的实时数据（0x01 的 IMG_MASK）：未连接（含断开设备后）一律 --，
                // 避免未连接时显示后端不下发而回落的 0/容量，误导用户（对齐小程序断开后内存变 --）。
                value: device.connected
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
            // 左侧标题占弹性宽度、超长才省略（对齐小程序 .row-left flex:1）。
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: labelColor,
                  fontSize: 14,
                  fontWeight: labelWeight,
                  height: 1.2,
                ),
              ),
            ),
            const SizedBox(width: 11),
            // 右侧取值：不收缩、最多 ~193（对齐小程序 .row-right flex-shrink:0 / max-width:386rpx）。
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 193),
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

/// 详情页顶部操作按钮：投屏=橙色渐变主按钮，连接/断开=白底橙描边次按钮。
class _DeviceActionButton extends StatelessWidget {
  const _DeviceActionButton({
    required this.label,
    required this.primary,
    this.onTap,
  });

  final String label;
  final bool primary;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      decoration: BoxDecoration(
        gradient: primary
            ? const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFFFF9140), Color(0xFFFF6A20)],
              )
            : null,
        color: primary ? null : Colors.white.withValues(alpha: 0.86),
        borderRadius: BorderRadius.circular(22),
        border: primary ? null : Border.all(color: const Color(0xFFFF6A20)),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(22),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: primary ? Colors.white : const Color(0xFFFF6A20),
                fontSize: 15,
                fontWeight: FontWeight.w600,
                height: 1,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 设备「删除 / 清空」二次确认弹窗（小程序 `.confirm-dialog`）。
///
/// 左侧彩色图标盒 + 右侧标题/说明，底部「取消 / 确认」胶囊按钮。
class DeviceConfirmDialog extends StatelessWidget {
  const DeviceConfirmDialog({
    super.key,
    required this.iconAsset,
    required this.fallbackIcon,
    required this.accent,
    required this.title,
    required this.message,
    required this.onCancel,
    required this.onConfirm,
  });

  final String iconAsset;
  final IconData fallbackIcon;
  final Color accent;
  final String title;
  final String message;
  final VoidCallback onCancel;
  final VoidCallback? onConfirm;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 30, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Image.asset(
                    iconAsset,
                    width: 24,
                    height: 24,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) =>
                        Icon(fallbackIcon, color: accent, size: 24),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: Color(0xFF25282D),
                          fontSize: 19,
                          fontWeight: FontWeight.w700,
                          height: 1.15,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        message,
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
              padding: const EdgeInsets.only(left: 59),
              child: Row(
                children: [
                  Expanded(
                    child: _DialogButton(
                      label: AppL10n.of(context).cancel,
                      textColor: const Color(0xFF32363C),
                      background: const Color(0xFFEEEEEE),
                      onTap: onCancel,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _DialogButton(
                      label: AppL10n.of(context).devConfirm,
                      textColor: Colors.white,
                      gradient: const LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0xFFFF9140), Color(0xFFFF6A20)],
                      ),
                      onTap: onConfirm,
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
  final VoidCallback? onTap;
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
