import 'package:flutter/material.dart';

import 'package:BoltStar/src/shared/widgets/app_widgets.dart';
import 'package:BoltStar/src/shared/widgets/device_name_dialog.dart';
import 'package:BoltStar/src/shared/widgets/figma_common.dart';
import '../../../device/ble_controller.dart';
import '../../../device/frame_device_protocol.dart';
import '../../../routes/app_routes.dart';
import '../../../shared/permission_gate.dart';
import '../../../shared/widgets/low_battery_tip.dart';
import '../../../state.dart';
import '../../cast/cast_photo_picker.dart';
import '../../cast/presentation/cast_preview_page.dart';
import '../../../shared/l10n/app_l10n.dart';

/// 屏幕物理分辨率文案（展示在「设备ID」下方），如 `680*960`。
///
/// 取值优先级：已连接时用 0x01 读到的真机宽高（`FrameProtocol.screenTypes` 权威表按屏型填出，
/// 见 `FrameDeviceInfo`）→ 后端记录的原始宽高 → `--`。
///
/// 与设备ID/内存不同，分辨率是**产品静态属性**而非实时数据，所以**不跟随连接状态置 `--`**：
/// 未连接时后端记录里的宽高一样准，硬要置 `--` 只会让常态未连接的设备永远看不到分辨率。
///
/// 为什么已连接时不用 `device.screenType` 反查表：它是由后端宽高归一化出来的枚举，后端没下发尺寸时
/// 会回落 5.89 寸（见 [DeviceItem.screenWidth]），反查就会显示一个臆造的 `680*960`。
String _resolutionText(DeviceItem device, bool connected) {
  if (connected) {
    final info = BleController.instance.info;
    // 7.3寸占位型号权威表里是 0×0（固件未实现图传），落到后端宽高继续兜。
    if (info != null && info.width > 0 && info.height > 0) {
      return '${info.width}*${info.height}';
    }
  }
  if (device.screenWidth > 0 && device.screenHeight > 0) {
    return '${device.screenWidth}*${device.screenHeight}';
  }
  return '--';
}

/// 当前会话 BLE 实读的固件版本（`0x03 GET_SW_VER`）。
///
/// 未连接一律空串：这一行讲的是**设备此刻在跑的版本**，而 [DeviceItem.firmwareVersion] 在 App 侧
/// 是**粘性**的（断开后不清，见 `state.dart` `applyDeviceInfo`），直接读它会把上一次连接留下的
/// 版本当成「现在的版本」显示出来——小程序侧断开时会把这个字段清掉，两端由这里对齐。
/// 已连接时优先用当前会话实读的那份，取不到再退回记录里的值（同 OTA 页 `currentVersion` 的口径）。
String _liveFirmwareVersion(DeviceItem device, bool connected) {
  if (!connected) {
    return '';
  }
  final live =
      BleController.instance.sessionMatchesSerial(
        device.serialNumber,
        screenCode: device.screenType.code,
      )
      ? (BleController.instance.info?.firmwareVersion ?? '')
      : '';
  return (live.isNotEmpty ? live : device.firmwareVersion).trim();
}

/// 「固件升级」行右侧文案（2026-08-20 同步小程序）：**只展示设备当前在跑的固件版本号**。
///
/// 改动前显示的是比对结论文案（`有版本可更新` / `已是最新版本`）——用户看不到设备在跑哪个版本，
/// 报障时也说不出版本号。现在结论改由箭头旁的红点表达（见 [_hasFirmwareUpdate]）。
///
/// 读不到（未连接 / `0x03` 失败）时回落 `--`，与本页设备ID、最大照片数量同一套占位约定；
/// **绝不拿接口的 `newVersionNo` 顶上**：那是云端最新版本号，显示出来就是一个假的「当前版本」。
String _firmwareVersionText(DeviceItem device, bool connected) {
  final version = _liveFirmwareVersion(device, connected);
  return version.isEmpty ? '--' : version;
}

/// 「固件升级」行箭头旁的红点：**已连接**且检测到有新版本才亮（2026-08-20 同步小程序）。
///
/// 未连接一律不亮：那时右边就是 `--`，没有任何版本依据，挂个红色角标等于无凭据地报警，
/// 与本页其它 `--` 行自相矛盾。用户想查版本，点这一行照样能查（`startOtaFlow` 会重新拉
/// 详情接口 + 退回后端 `isUpdate`，「不连蓝牙也能查版本」的能力没丢），只是不再由红点催。
///
/// 已连接后判定与点击流程 **完全同源**（[evaluateFirmwareUpdate] + unknown 退回
/// [DeviceItem.hasFirmwareUpdate]，与 `startOtaFlow` 的 `canUpgradeNow` 一字不差），
/// 否则会出现「红点亮着、点进去弹已是最新版本」的自相矛盾。
/// `invalid`（版本不同但缺号/缺地址/非 `.bin`）**不亮**：点进去只会弹原因说明、根本升不了级。
bool _hasFirmwareUpdate(DeviceItem device, bool connected) {
  if (!connected) {
    return false;
  }
  final verdict = evaluateFirmwareUpdate(
    device,
    currentVersion: _liveFirmwareVersion(device, connected),
  );
  if (verdict == FirmwareUpdateVerdict.unknown) {
    return device.hasFirmwareUpdate;
  }
  return verdict == FirmwareUpdateVerdict.update;
}

/// 设备详情页：查看单个设备信息并进入 投屏 / 连接·断开 / 轮播设置 / 清空 / 删除 等操作。
///
/// 对照微信小程序 `photo-album/subpackages/device/detail`：摘要卡 + 顶部操作栏（投屏 / 连接·断开）+
/// 信息列表 + 操作列表（一键清空 / 解除绑定 / 删除设备），三者都走全局统一的二次确认弹窗
///（`AppDialog`，流程分别在 `device_clear_flow.dart` 与 `delete_device_flow.dart`）。
/// 展示当前选中设备（`state.selectedDevice`），随 [PhotoFrameState] 变化自动刷新。
class DeviceDetailsPage extends StatefulWidget {
  const DeviceDetailsPage({
    super.key,
    required this.state,
    required this.deviceId,
    this.onCarouselSettings,
    this.onClearDevice,
    this.onUnbindDevice,
    this.onDeleteDevice,
    this.onOtaUpgrade,
  });

  final PhotoFrameState state;
  final String deviceId;
  final VoidCallback? onCarouselSettings;
  final VoidCallback? onClearDevice;

  /// 「解除绑定」：只解绑，设备照片保留。
  final VoidCallback? onUnbindDevice;

  /// 「删除设备」：一键清空 + 断开 + 解除绑定。
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
          onUnbindDevice: widget.onUnbindDevice,
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
    // 统一样式的设备名称弹窗（列表页与绑定成功后的命名引导用的是同一个）。
    final name = await showDeviceNameDialog(
      context,
      initialValue: device.name,
      title: AppL10n.of(context).devRenameTitle,
    );
    if (name == null || name == device.name) {
      return;
    }
    if (!context.mounted) {
      return;
    }
    AppLoadingDialog.show(context, AppL10n.of(context).saving);
    final ActionFeedback feedback;
    try {
      feedback = await state.renameDevice(device.id, name);
    } finally {
      // 公共 Flutter 页面同时覆盖 iOS / Android；无论接口成功失败都关闭蒙层。
      // ignore: use_build_context_synchronously
      AppLoadingDialog.hide(context);
    }
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
      return;
    }
    // 主动点「连接」连上之后，电量 ≤10% 先提醒一次
    // （2026-08-27 补齐 08-21 那轮遗留的入口，对齐小程序 ensureConnectedForAction）。
    // 只在**连接**方向弹：断开不需要电量做判断，弹了也没有可操作的下一步。
    if (!wasConnected) {
      await showLowBatteryTipIfNeeded(context, state, device.id);
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
      return false;
    }
    // 主动点「投屏」自动扫连上之后，电量 ≤10% 先提醒一次（与设备列表页 _ensureConnected 同一套）。
    await showLowBatteryTipIfNeeded(context, state, deviceId);
    return true;
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
    } else {
      // 已连接这一支没走连接流程，低电量提醒在这里补（对齐首页 _startCast 的同名分支）。
      await showLowBatteryTipIfNeeded(context, state, device.id);
      if (!context.mounted) {
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
      AppPageRoute(
        // 选图后先进**投屏预览页**（裁剪/旋转/原图），确认后才开始投屏。
        builder: (_) => CastPreviewPage(
          state: state,
          device: state.deviceById(device.id),
          imagePaths: imagePaths,
        ),
      ),
    );
    // 2026-08-17：图库列表接口已下线，投屏后只需重拉投屏记录。
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
    this.onUnbindDevice,
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

  /// 「解除绑定」：只解绑，设备照片保留。
  final VoidCallback? onUnbindDevice;

  /// 「删除设备」：一键清空 + 断开 + 解除绑定。
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
    // 2026-08-21 同步小程序：开着一律「已开启」，不再显示「顺序轮播/随机轮播」——
    // 这一行只回答「开没开」，把顺序/随机这个二选一摆在概览行上反而看不出开关状态，
    // 具体模式进轮播设置页看（devCarouselSequential/devCarouselRandom 仍由那一页使用）。
    return l10n.devCarouselEnabled;
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
                  'assets/images/home-device-thumb.png',
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
              // 屏幕物理尺寸（如 680*960），紧跟设备ID：产品静态属性，
              // 不随连接状态置 --（见 [_resolutionText]）。
              // 图标不复用「设备ID」那张标签图：这一行讲的是屏幕，用专门画的相框+尺寸标注
              //（对齐小程序 device-detail-screen-size.svg；Flutter 无 SVG 依赖，故用 CustomPaint）。
              _DetailRow(
                iconAsset: '',
                iconWidget: const _ScreenSizeGlyph(),
                fallbackIcon: Icons.aspect_ratio_rounded,
                label: AppL10n.of(context).devScreenSize,
                value: _resolutionText(device, connected),
              ),
              const _ThinDivider(),
              _DetailRow(
                iconAsset: 'assets/images/device-detail-icon03.png',
                fallbackIcon: Icons.sd_storage_outlined,
                label: AppL10n.of(context).devMaxPhotoCount,
                // 内存占用是连接才读得到的实时数据（0x01 的 IMG_MASK）：未连接（含断开设备后）一律 --，
                // 避免未连接时显示后端不下发而回落的 0/容量，误导用户（对齐小程序断开后内存变 --）。
                // 2026-08-02：行文案回到「最大照片数量」，值定为分数式 `已用/上限`（如 8/51，
                // 对齐小程序 detail.js memoryText），两端同一口径。
                value: connected
                    ? '${device.imageCount}/${device.capacity}'
                    : '--',
              ),
              const _ThinDivider(),
              _DetailRow(
                iconAsset: 'assets/images/device-detail-icon04.png',
                fallbackIcon: Icons.system_update_alt_rounded,
                label: AppL10n.of(context).devOtaUpgrade,
                // 2026-08-20（两端同改）：右侧回到**设备当前在跑的版本号**（`0x03 GET_SW_VER`），
                // 「有没有新版本」改由箭头旁的一颗红点表达——原来那两句结论文案
                //（有版本可更新 / 已是最新版本）占着右侧，用户反而看不到自己在跑哪个版本、
                // 报障时也说不出版本号。读不到（未连接 / 0x03 失败）时给 `--`，与本页设备ID、
                // 最大照片数量同一套占位约定，绝不拿云端的 `newVersionNo` 冒充当前版本。
                // 未连接时整行就是 `--` 且红点不亮：没有版本依据就不报警（见 [_hasFirmwareUpdate]）。
                value: _firmwareVersionText(device, connected),
                showDot: _hasFirmwareUpdate(device, connected),
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
              // 解除绑定：只断账号关系，设备上的照片保留（与下面的「删除设备」不是一回事）。
              _DetailRow(
                iconAsset: 'assets/images/device-detail-icon06.png',
                fallbackIcon: Icons.link_off_rounded,
                label: AppL10n.of(context).devUnbindDevice,
                labelColor: const Color(0xFFFF3045),
                labelWeight: FontWeight.w500,
                value: AppL10n.of(context).devUnbindDeviceValue,
                showChevron: true,
                onTap: onUnbindDevice,
              ),
            ],
          ),
        ),
        // 「删除设备」是最重的破坏性操作（一键清空 + 断开连接 + 解除绑定，需已连接）。
        // 2026-08-01 产品要求：从卡片行改成页面最底部的独立入口；同日二次调整——去掉描边、
        // 字号字重与上面各行 label 拉平、再往下移，避免像主按钮一样引导用户去删除。
        const SizedBox(height: 32),
        _OutlineDeleteDeviceButton(
          label: AppL10n.of(context).devDeleteDevice,
          onTap: onDeleteDevice,
        ),
      ],
    );
  }
}

/// 页面最底部的「删除设备」入口（2026-08-01，对齐小程序 `.outline-delete-device`）。
///
/// 产品要求「不要引导用户去删除」：无描边、无底色，字号/字重与上方各行 label 一致
/// （14 / w500，见 [_DetailRow]），只留危险红提示后果。高度 56 仅作点击热区。
class _OutlineDeleteDeviceButton extends StatelessWidget {
  const _OutlineDeleteDeviceButton({required this.label, this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    const danger = Color(0xFFFF3045);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        height: 56,
        child: Center(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: danger,
              fontSize: 14,
              fontWeight: FontWeight.w500,
              height: 1.2,
            ),
          ),
        ),
      ),
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
    this.iconWidget,
    this.labelColor = const Color(0xFF33373D),
    this.labelWeight = FontWeight.w600,
    this.showDot = false,
    this.showChevron = false,
    this.onTap,
  });

  final String iconAsset;

  /// 直接给一个绘制型图标（无切图资源时用，如「屏幕尺寸」）；给了就不再读 [iconAsset]。
  final Widget? iconWidget;
  final IconData fallbackIcon;
  final String label;
  final String value;
  final Color labelColor;
  final FontWeight labelWeight;

  /// 取值与箭头之间的红点（目前只有「固件升级」行用：检测到新版本时亮）。
  /// 纯提示、不承载点击——整行本来就可点。
  final bool showDot;
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
            SizedBox(
              width: 20,
              height: 20,
              child:
                  iconWidget ??
                  Image.asset(
                    iconAsset,
                    width: 20,
                    height: 20,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) =>
                        Icon(fallbackIcon, size: 20, color: labelColor),
                  ),
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
            // 新版本红点（2026-08-20，对齐小程序 `.firmware-dot`）：14rpx 圆点 ≈ 7dp、#FF3B30。
            // 小程序那边 `.row-right` 的 gap 是 16rpx(8dp)，对「贴着箭头」来说太散，用
            // `margin-right:-8rpx` 往箭头收一半——Flutter 没有负 margin，等价写法是把红点与
            // 箭头之间的间距直接给成 4，取值与红点之间仍是 8。
            if (showDot) ...[
              const SizedBox(width: 8),
              Container(
                width: 7,
                height: 7,
                decoration: const BoxDecoration(
                  color: Color(0xFFFF3B30),
                  shape: BoxShape.circle,
                ),
              ),
            ],
            if (showChevron) ...[
              SizedBox(width: showDot ? 4 : 8),
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

/// 「屏幕尺寸」行图标：相框 + 底座 + 顶部橙色双向标注箭头。
///
/// 1:1 复刻小程序 `assets/images/device-detail-screen-size.svg`（48×48 视图盒）。
/// Flutter 侧没有 SVG 依赖，也不值得为一枚图标引入 flutter_svg，故按同一组坐标绘制
///（同 `_FrameLogoPainter` 的做法），按 20/48 缩放到行内 20×20。
class _ScreenSizeGlyph extends StatelessWidget {
  const _ScreenSizeGlyph();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 20,
      height: 20,
      child: CustomPaint(painter: _ScreenSizePainter()),
    );
  }
}

class _ScreenSizePainter extends CustomPainter {
  const _ScreenSizePainter();

  @override
  void paint(Canvas canvas, Size size) {
    // SVG 视图盒是 48×48，这里等比缩放到实际绘制尺寸，坐标可直接照抄 SVG。
    final scale = size.width / 48;
    canvas.scale(scale);

    final frame = Paint()
      ..color = const Color(0xFF5D6672)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    // 屏幕主体 rect(9,11,30×23) rx=3.5。
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(9, 11, 30, 23),
        const Radius.circular(3.5),
      ),
      frame,
    );
    // 底座：立柱 + 横杆。
    canvas.drawLine(const Offset(24, 34), const Offset(24, 40), frame);
    canvas.drawLine(const Offset(18, 40), const Offset(30, 40), frame);

    // 顶部橙色尺寸标注：一条横线 + 两端向外的箭头。
    final measure = Paint()
      ..color = const Color(0xFFFF6A20)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawLine(const Offset(10, 5), const Offset(38, 5), measure);
    canvas.drawPath(
      Path()
        ..moveTo(13, 7)
        ..lineTo(10, 4)
        ..lineTo(7, 7)
        ..moveTo(35, 7)
        ..lineTo(38, 4)
        ..lineTo(41, 7),
      measure,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
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
