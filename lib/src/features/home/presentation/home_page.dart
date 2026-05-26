import 'dart:async';

import 'package:flutter/material.dart';

import '../../../native_device_api.dart';
import '../../../state.dart';
import 'widgets/cast_preview_sheet.dart';

enum _HomeBindMode { none, searching, notFound, found }

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.state, required this.onOpenMine});

  final PhotoFrameState state;
  final VoidCallback onOpenMine;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  _HomeBindMode _bindMode = _HomeBindMode.none;
  int _selectedFoundDeviceIndex = 0;
  bool _showScanHelp = false;
  Timer? _scanTimer;

  List<DeviceItem> get _nearbyDevices {
    return widget.state.devices.isEmpty
        ? const <DeviceItem>[]
        : widget.state.devices;
  }

  bool get _hasConnectedDevice {
    return widget.state.devices.any((device) => device.connected);
  }

  DeviceItem? get _activeDevice {
    if (!_hasConnectedDevice) {
      return null;
    }
    final selected = widget.state.selectedDevice;
    if (selected.connected) {
      return selected;
    }
    return widget.state.devices.firstWhere((device) => device.connected);
  }

  @override
  void dispose() {
    _scanTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SizedBox.expand(
          child: FittedBox(
            fit: BoxFit.contain,
            child: SizedBox(
              width: 375,
              height: 812,
              child: SizedBox(
                width: 375,
                height: 812,
                child: Stack(
                  children: [
                    const Positioned.fill(child: _HomeBackground()),
                    const Positioned(
                      left: 0,
                      top: 0,
                      width: 375,
                      child: _StatusBar(),
                    ),
                    if (_bindMode == _HomeBindMode.none)
                      _HomeMainView(
                        state: widget.state,
                        activeDevice: _activeDevice,
                        onBindDevice: _startScan,
                        onAddDevice: _startScan,
                        onShowCastSheet: _showCastMethodSheet,
                        onCamera: () => _startCast(ImageSourceType.camera),
                        onAlbum: () => _startCast(ImageSourceType.album),
                        onOpenMine: widget.onOpenMine,
                      )
                    else
                      _BindDeviceView(
                        mode: _bindMode,
                        devices: _nearbyDevices,
                        selectedIndex: _selectedFoundDeviceIndex,
                        showScanHelp: _showScanHelp,
                        onBack: _closeBindFlow,
                        onHelp: () {
                          setState(() {
                            _showScanHelp = true;
                          });
                        },
                        onCloseHelp: () {
                          setState(() {
                            _showScanHelp = false;
                          });
                        },
                        onRetry: _startScan,
                        onCancel: _closeBindFlow,
                        onSelectDevice: (index) {
                          setState(() {
                            _selectedFoundDeviceIndex = index;
                          });
                        },
                        onBind: _bindSelectedDevice,
                      ),
                    const _HomeIndicator(),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _startScan() {
    _scanTimer?.cancel();
    setState(() {
      _bindMode = _HomeBindMode.searching;
      _showScanHelp = false;
    });

    _scanTimer = Timer(const Duration(milliseconds: 1200), () {
      if (!mounted || _bindMode != _HomeBindMode.searching) {
        return;
      }
      setState(() {
        _bindMode = _nearbyDevices.isEmpty
            ? _HomeBindMode.notFound
            : _HomeBindMode.found;
        _selectedFoundDeviceIndex = 0;
      });
    });
  }

  void _closeBindFlow() {
    _scanTimer?.cancel();
    setState(() {
      _bindMode = _HomeBindMode.none;
      _showScanHelp = false;
    });
  }

  void _bindSelectedDevice() {
    if (_nearbyDevices.isEmpty) {
      return;
    }
    final device =
        _nearbyDevices[_selectedFoundDeviceIndex.clamp(
          0,
          _nearbyDevices.length - 1,
        )];
    widget.state.connectDevice(device.id);
    _closeBindFlow();
  }

  Future<void> _startCast(ImageSourceType source) async {
    final activeDevice = _activeDevice;
    if (activeDevice == null) {
      await _showDeviceNotice(
        title: '暂未绑定设备',
        message: '当前暂无可投屏设备，请先绑定相框设备',
        buttonLabel: '立即绑定',
        onPressed: _startScan,
      );
      return;
    }
    if (!activeDevice.connected) {
      await _showDeviceNotice(
        title: '设备连接失败',
        message: '当前设备未连接，APP需先连接设备后再投屏',
        buttonLabel: '重新连接',
        onPressed: _startScan,
      );
      return;
    }

    if (source == ImageSourceType.camera) {
      await _startCameraCast();
    } else {
      await _startAlbumCast();
    }
  }

  Future<void> _showDeviceNotice({
    required String title,
    required String message,
    required String buttonLabel,
    required VoidCallback onPressed,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return _DeviceNoticeSheet(
          title: title,
          message: message,
          buttonLabel: buttonLabel,
          onPressed: () {
            Navigator.of(context).pop();
            onPressed();
          },
        );
      },
    );
  }

  Future<void> _showCastMethodSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return _CastMethodSheet(
          onCamera: () {
            Navigator.of(context).pop();
            _startCast(ImageSourceType.camera);
          },
          onAlbum: () {
            Navigator.of(context).pop();
            _startCast(ImageSourceType.album);
          },
        );
      },
    );
  }

  Future<void> _startCameraCast() async {
    final status = await NativeDeviceApi.requestCameraPermission();
    _syncPermissionState(status);
    if (!mounted) {
      return;
    }
    if (!status.cameraPermissionGranted) {
      _showFeedback('相机权限未开启，请授权后再使用拍照投屏。');
      return;
    }
    final draft = widget.state.createCameraDraft();
    await _showCastPreview(draft);
  }

  Future<void> _startAlbumCast() async {
    final status = await NativeDeviceApi.requestPhotoPermission();
    _syncPermissionState(status);
    if (!mounted) {
      return;
    }

    final selection = await NativeDeviceApi.openGallery();
    if (!mounted || selection == null) {
      return;
    }
    widget.state.setPermission(PermissionKind.album, true);
    final draft = widget.state.createAlbumDraft(
      title: selection.title,
      width: selection.width,
      height: selection.height,
      uri: selection.uri,
    );
    await _showCastPreview(draft);
  }

  Future<void> _showCastPreview(DraftPhoto draft) async {
    final deviceId = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => CastPreviewSheet(state: widget.state, draft: draft),
    );
    if (!mounted || deviceId == null) {
      return;
    }
    final result = widget.state.castDraft(draft: draft, deviceId: deviceId);
    _showFeedback(result.message);
    if (result.deviceFull) {
      widget.onOpenMine();
    }
  }

  void _syncPermissionState(DevicePermissionStatus status) {
    widget.state.setPermission(
      PermissionKind.location,
      status.locationPermissionGranted,
    );
    widget.state.setPermission(PermissionKind.bluetooth, status.bluetoothReady);
    widget.state.setPermission(
      PermissionKind.album,
      status.photoPermissionGranted,
    );
    widget.state.setPermission(
      PermissionKind.camera,
      status.cameraPermissionGranted,
    );
  }

  void _showFeedback(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

class _HomeMainView extends StatelessWidget {
  const _HomeMainView({
    required this.state,
    required this.activeDevice,
    required this.onBindDevice,
    required this.onAddDevice,
    required this.onShowCastSheet,
    required this.onCamera,
    required this.onAlbum,
    required this.onOpenMine,
  });

  final PhotoFrameState state;
  final DeviceItem? activeDevice;
  final VoidCallback onBindDevice;
  final VoidCallback onAddDevice;
  final VoidCallback onShowCastSheet;
  final VoidCallback onCamera;
  final VoidCallback onAlbum;
  final VoidCallback onOpenMine;

  bool get _bound => activeDevice != null;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        if (_bound) ...[
          const Positioned(left: 24, top: 56, child: _Avatar()),
          Positioned(
            left: 328,
            top: 58,
            width: 30,
            height: 30,
            child: _RoundAddButton(onTap: onAddDevice),
          ),
          const Positioned(left: 24, top: 142, child: _GreetingTitle()),
          Positioned(
            left: 24,
            top: 242,
            width: 327,
            height: 186,
            child: _ConnectedDeviceCard(device: activeDevice!),
          ),
          const Positioned(
            right: -106,
            top: 267,
            width: 154,
            height: 134,
            child: _SideCardHint(),
          ),
          const Positioned(left: 150, top: 459, child: _CarouselDots()),
        ] else ...[
          const Positioned(
            left: 96,
            top: 188,
            width: 185,
            height: 116,
            child: _UnboundDeviceArt(),
          ),
          const Positioned(
            left: 0,
            top: 349,
            width: 375,
            child: Text(
              '请先绑定相框设备后再投屏照片',
              textAlign: TextAlign.center,
              style: _HomeTextStyles.mutedBody,
            ),
          ),
          Positioned(
            left: 88,
            top: 381,
            width: 200,
            height: 44,
            child: _GradientButton(
              label: '绑定设备',
              height: 44,
              fontSize: 16,
              icon: Container(
                width: 16,
                height: 16,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.bluetooth_rounded,
                  color: Color(0xFFFF6A24),
                  size: 13,
                ),
              ),
              onPressed: onBindDevice,
            ),
          ),
        ],
        Positioned(
          left: 24,
          top: 498,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onShowCastSheet,
            child: const Text('选择投屏方式', style: _HomeTextStyles.sectionTitle),
          ),
        ),
        Positioned(
          left: 24,
          top: 524,
          child: Row(
            children: [
              _CastEntryCard(
                title: '拍照',
                subtitle: '拍摄照片并投屏',
                artAsset: 'assets/images/camera_material.png',
                arrowAsset: 'assets/images/Group 194521.png',
                backgroundAsset: 'assets/images/Rectangle 10457.png',
                fallbackColor: const Color(0xFFFFF8F4),
                onTap: onCamera,
              ),
              const SizedBox(width: 11),
              _CastEntryCard(
                title: '相册',
                subtitle: '选择照片并投屏',
                artAsset: 'assets/images/Group 194924.png',
                arrowAsset: 'assets/images/Group 194522.png',
                backgroundAsset: 'assets/images/Rectangle 10403.png',
                fallbackColor: const Color(0xFFEAF4FF),
                onTap: onAlbum,
              ),
            ],
          ),
        ),
        Positioned(
          left: 24,
          top: 730,
          child: _HomeTabBar(onOpenMine: onOpenMine),
        ),
      ],
    );
  }
}

class _BindDeviceView extends StatelessWidget {
  const _BindDeviceView({
    required this.mode,
    required this.devices,
    required this.selectedIndex,
    required this.showScanHelp,
    required this.onBack,
    required this.onHelp,
    required this.onCloseHelp,
    required this.onRetry,
    required this.onCancel,
    required this.onSelectDevice,
    required this.onBind,
  });

  final _HomeBindMode mode;
  final List<DeviceItem> devices;
  final int selectedIndex;
  final bool showScanHelp;
  final VoidCallback onBack;
  final VoidCallback onHelp;
  final VoidCallback onCloseHelp;
  final VoidCallback onRetry;
  final VoidCallback onCancel;
  final ValueChanged<int> onSelectDevice;
  final VoidCallback onBind;

  bool get _found => mode == _HomeBindMode.found;
  bool get _notFound => mode == _HomeBindMode.notFound;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned(
          left: 24,
          top: 47,
          width: 34,
          height: 34,
          child: _CircleIconButton(
            icon: Icons.arrow_back_rounded,
            onTap: onBack,
          ),
        ),
        const Positioned(
          left: 0,
          top: 51,
          width: 375,
          child: Text(
            '绑定设备',
            textAlign: TextAlign.center,
            style: _HomeTextStyles.navTitle,
          ),
        ),
        Positioned(
          left: 52,
          top: 99,
          width: 270,
          height: 225,
          child: _BluetoothRadar(
            failed: _notFound || showScanHelp,
            success: _found,
            dimmed: showScanHelp,
          ),
        ),
        if (mode == _HomeBindMode.searching) ...[
          const Positioned(
            left: 0,
            top: 340,
            width: 375,
            child: Text(
              '正在搜索附近设备',
              textAlign: TextAlign.center,
              style: _HomeTextStyles.bindTitle,
            ),
          ),
          const Positioned(
            left: 0,
            top: 374,
            width: 375,
            child: Text(
              '请尽量将手机靠近需要添加的设备...',
              textAlign: TextAlign.center,
              style: _HomeTextStyles.bindSubtitle,
            ),
          ),
          Positioned(
            left: 0,
            top: 670,
            width: 375,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onHelp,
              child: const Text(
                '扫描不到怎么办?',
                textAlign: TextAlign.center,
                style: _HomeTextStyles.orangeLink,
              ),
            ),
          ),
          Positioned(
            left: 24,
            top: 702,
            width: 327,
            height: 56,
            child: _GradientButton(label: '取消扫描', onPressed: onCancel),
          ),
        ],
        if (_notFound && !showScanHelp) ...[
          const Positioned(
            left: 0,
            top: 340,
            width: 375,
            child: Text(
              '未发现设备',
              textAlign: TextAlign.center,
              style: _HomeTextStyles.bindTitle,
            ),
          ),
          const Positioned(
            left: 0,
            top: 374,
            width: 375,
            child: Text(
              '设备连接中断，请检查设备状态后重试',
              textAlign: TextAlign.center,
              style: _HomeTextStyles.bindSubtitle,
            ),
          ),
          Positioned(
            left: 0,
            top: 670,
            width: 375,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onHelp,
              child: const Text(
                '扫描不到怎么办?',
                textAlign: TextAlign.center,
                style: _HomeTextStyles.orangeLink,
              ),
            ),
          ),
          Positioned(
            left: 24,
            top: 702,
            width: 327,
            height: 56,
            child: _GradientButton(label: '重新扫描', onPressed: onRetry),
          ),
        ],
        if (_found) ...[
          Positioned(
            left: 24,
            top: 376,
            width: 327,
            height: 28,
            child: Row(
              children: [
                const Expanded(
                  child: Text('附近设备', style: _HomeTextStyles.sectionTitle),
                ),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onRetry,
                  child: Image.asset(
                    'assets/images/Frame3.png',
                    width: 22,
                    height: 22,
                    errorBuilder: (context, error, stackTrace) {
                      return const Icon(
                        Icons.refresh_rounded,
                        color: Color(0xFFFF6A24),
                        size: 24,
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            left: 24,
            top: 406,
            width: 327,
            child: Column(
              children: [
                for (var index = 0; index < devices.length; index++) ...[
                  _FoundDeviceTile(
                    device: devices[index],
                    selected: index == selectedIndex,
                    accent: _deviceAccent(index),
                    onTap: () => onSelectDevice(index),
                  ),
                  if (index != devices.length - 1) const SizedBox(height: 12),
                ],
              ],
            ),
          ),
          Positioned(
            left: 24,
            top: 702,
            width: 327,
            height: 56,
            child: _GradientButton(label: '立即绑定', onPressed: onBind),
          ),
        ],
        if (showScanHelp)
          _ScanHelpSheet(onClose: onCloseHelp, onRetry: onRetry),
      ],
    );
  }

  Color _deviceAccent(int index) {
    return switch (index) {
      0 => const Color(0xFFFF6A24),
      1 => const Color(0xFF2FB46B),
      _ => const Color(0xFF4A98FF),
    };
  }
}

class _ScanHelpSheet extends StatelessWidget {
  const _ScanHelpSheet({required this.onClose, required this.onRetry});

  final VoidCallback onClose;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: ColoredBox(color: Colors.black.withValues(alpha: 0.42)),
        ),
        Positioned(
          left: 0,
          top: 346,
          width: 375,
          height: 466,
          child: DecoratedBox(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Stack(
              children: [
                const Positioned(
                  left: 0,
                  top: 25,
                  width: 375,
                  child: Text(
                    '扫描不到怎么办?',
                    textAlign: TextAlign.center,
                    style: _HomeTextStyles.sheetTitle,
                  ),
                ),
                Positioned(
                  right: 28,
                  top: 25,
                  width: 24,
                  height: 24,
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(
                      width: 24,
                      height: 24,
                    ),
                    onPressed: onClose,
                    icon: const Icon(
                      Icons.close_rounded,
                      color: Color(0xFF7E7E7E),
                      size: 25,
                    ),
                  ),
                ),
                Positioned(
                  left: 130,
                  top: 72,
                  width: 115,
                  height: 115,
                  child: Image.asset(
                    'assets/images/scan_help_art.png',
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) {
                      return const _ScanHelpIconFallback();
                    },
                  ),
                ),
                const Positioned(
                  left: 39,
                  top: 213,
                  child: Text('请检查：', style: _HomeTextStyles.helpTitle),
                ),
                const Positioned(
                  left: 39,
                  top: 248,
                  width: 306,
                  child: Text(
                    '1.设备是否有电?\n'
                    '2.当前设备是否被占用?\n'
                    '3.设备蓝牙是否工作正常，手机蓝牙是否打开\n'
                    '4.设备是否与手机距离过远，隔离或有其他遮挡物',
                    style: _HomeTextStyles.helpBody,
                  ),
                ),
                Positioned(
                  left: 24,
                  top: 356,
                  width: 327,
                  height: 56,
                  child: _GradientButton(label: '重新扫描', onPressed: onRetry),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _DeviceNoticeSheet extends StatelessWidget {
  const _DeviceNoticeSheet({
    required this.title,
    required this.message,
    required this.buttonLabel,
    required this.onPressed,
  });

  final String title;
  final String message;
  final String buttonLabel;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 250,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Stack(
          children: [
            Positioned(
              right: 32,
              top: 27,
              width: 22,
              height: 22,
              child: IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(
                  width: 22,
                  height: 22,
                ),
                onPressed: () => Navigator.maybePop(context),
                icon: const Icon(
                  Icons.close_rounded,
                  color: Color(0xFF7E7E7E),
                  size: 24,
                ),
              ),
            ),
            Positioned(
              left: 0,
              top: 61,
              width: 375,
              child: Text(
                title,
                textAlign: TextAlign.center,
                style: _HomeTextStyles.sheetTitle,
              ),
            ),
            Positioned(
              left: 0,
              top: 103,
              width: 375,
              child: Text(
                message,
                textAlign: TextAlign.center,
                style: _HomeTextStyles.sheetBody,
              ),
            ),
            Positioned(
              left: 24,
              top: 140,
              width: 327,
              height: 56,
              child: _GradientButton(label: buttonLabel, onPressed: onPressed),
            ),
          ],
        ),
      ),
    );
  }
}

class _CastMethodSheet extends StatelessWidget {
  const _CastMethodSheet({required this.onCamera, required this.onAlbum});

  final VoidCallback onCamera;
  final VoidCallback onAlbum;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 353,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Stack(
          children: [
            const Positioned(
              left: 24,
              top: 24,
              child: Text('选择投屏方式', style: _HomeTextStyles.sheetTitle),
            ),
            Positioned(
              left: 24,
              top: 73,
              child: _CastSheetRow(
                title: '拍照',
                subtitle: '调用手机相机拍照',
                artAsset: 'assets/images/camera_material.png',
                arrowAsset: 'assets/images/Group 194521.png',
                onTap: onCamera,
              ),
            ),
            Positioned(
              left: 24,
              top: 147,
              child: _CastSheetRow(
                title: '相册',
                subtitle: '从手机相册选择照片',
                artAsset: 'assets/images/Group 194924.png',
                arrowAsset: 'assets/images/Group 194522.png',
                onTap: onAlbum,
              ),
            ),
            Positioned(
              left: 24,
              top: 244,
              width: 327,
              height: 56,
              child: Material(
                color: const Color(0xFFEDEDED),
                borderRadius: BorderRadius.circular(28),
                child: InkWell(
                  borderRadius: BorderRadius.circular(28),
                  onTap: () => Navigator.maybePop(context),
                  child: const Center(
                    child: Text('取消', style: _HomeTextStyles.cancelButton),
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

class _HomeBackground extends StatelessWidget {
  const _HomeBackground();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: const [
        Positioned.fill(child: ColoredBox(color: Color(0xFFF5F9FF))),
        Positioned(
          left: 0,
          top: 0,
          width: 376,
          height: 812,
          child: _AssetImage(
            path: 'assets/images/login_bg_image_5130.png',
            fallback: _SoftBackgroundPainterWidget(),
          ),
        ),
      ],
    );
  }
}

class _SoftBackgroundPainterWidget extends StatelessWidget {
  const _SoftBackgroundPainterWidget();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _SoftBackgroundPainter());
  }
}

class _SoftBackgroundPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFEAF4FF), Color(0xFFF8FBFF), Color(0xFFFFF6F0)],
          stops: [0, 0.58, 1],
        ).createShader(rect),
    );

    final haze = Paint()
      ..color = Colors.white.withValues(alpha: 0.44)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 20);
    canvas.drawCircle(const Offset(118, 0), 122, haze);
    canvas.drawCircle(const Offset(58, 277), 176, haze);

    canvas.drawCircle(
      const Offset(366, 184),
      126,
      Paint()
        ..shader =
            RadialGradient(
              colors: [
                const Color(0xFFFFC39A).withValues(alpha: 0.62),
                const Color(0x00FFC39A),
              ],
            ).createShader(
              Rect.fromCircle(center: const Offset(366, 184), radius: 126),
            ),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _AssetImage extends StatelessWidget {
  const _AssetImage({required this.path, required this.fallback});

  final String path;
  final Widget fallback;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      path,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) => fallback,
    );
  }
}

class _StatusBar extends StatelessWidget {
  const _StatusBar();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: Stack(
        children: [
          const Positioned(
            left: 21,
            top: 12,
            width: 54,
            height: 21,
            child: Center(child: Text('9:41', style: _HomeTextStyles.status)),
          ),
          Positioned(
            right: 14,
            top: 16,
            child: Row(
              children: const [
                Icon(Icons.signal_cellular_alt_rounded, size: 16),
                SizedBox(width: 4),
                Icon(Icons.wifi_rounded, size: 16),
                SizedBox(width: 4),
                Icon(Icons.battery_full_rounded, size: 21),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar();

  @override
  Widget build(BuildContext context) {
    return ClipOval(
      child: Image.asset(
        'assets/images/logo.png',
        width: 34,
        height: 34,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          return Container(
            width: 34,
            height: 34,
            color: const Color(0xFFEAF4FF),
            child: const Icon(
              Icons.person_rounded,
              color: Color(0xFF8C9092),
              size: 22,
            ),
          );
        },
      ),
    );
  }
}

class _RoundAddButton extends StatelessWidget {
  const _RoundAddButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Image.asset(
        'assets/images/Group 194746.png',
        width: 30,
        height: 30,
        errorBuilder: (context, error, stackTrace) {
          return Container(
            decoration: const BoxDecoration(
              color: Color(0xFFFF7D36),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.add_rounded, color: Colors.white, size: 24),
          );
        },
      ),
    );
  }
}

class _GreetingTitle extends StatelessWidget {
  const _GreetingTitle();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 310,
      height: 75,
      child: Column(
        key: const Key('home-title'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Hi', style: _HomeTextStyles.hi),
          const SizedBox(height: 7),
          Row(
            children: [
              const Text('欢迎使用 ', style: _HomeTextStyles.welcome),
              Image.asset(
                'assets/images/logo.png',
                width: 100,
                height: 25,
                fit: BoxFit.contain,
                alignment: Alignment.centerLeft,
                errorBuilder: (context, error, stackTrace) {
                  return const Text(
                    'BoltStar',
                    style: _HomeTextStyles.brandFallback,
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ConnectedDeviceCard extends StatelessWidget {
  const _ConnectedDeviceCard({required this.device});

  final DeviceItem device;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.76),
        borderRadius: BorderRadius.circular(29),
        border: Border.all(color: Colors.white.withValues(alpha: 0.85)),
      ),
      child: Stack(
        children: [
          const Positioned(
            left: 41,
            top: 24,
            width: 136,
            height: 136,
            child: _DeviceOrbitMark(),
          ),
          Positioned(
            left: 195,
            top: 58,
            child: Text(device.name, style: _HomeTextStyles.deviceCardTitle),
          ),
          const Positioned(
            left: 195,
            top: 103,
            child: Row(
              children: [
                Icon(
                  Icons.bluetooth_rounded,
                  color: Color(0xFF4A98FF),
                  size: 17,
                ),
                SizedBox(width: 6),
                Text('已连接', style: _HomeTextStyles.deviceMeta),
              ],
            ),
          ),
          Positioned(
            left: 195,
            top: 132,
            child: Row(
              children: [
                Image.asset(
                  'assets/images/Frame.png',
                  width: 18,
                  height: 12,
                  errorBuilder: (context, error, stackTrace) {
                    return const Icon(
                      Icons.battery_2_bar_rounded,
                      color: Color(0xFFFF6A24),
                      size: 18,
                    );
                  },
                ),
                const SizedBox(width: 8),
                Text(
                  '${device.batteryLevel}%',
                  style: _HomeTextStyles.deviceMeta,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SideCardHint extends StatelessWidget {
  const _SideCardHint();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white.withValues(alpha: 0.65)),
      ),
    );
  }
}

class _DeviceOrbitMark extends StatelessWidget {
  const _DeviceOrbitMark();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _DeviceOrbitMarkPainter());
  }
}

class _DeviceOrbitMarkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = const Color(0xFFFFD7C0).withValues(alpha: 0.45);
    canvas.drawCircle(center, 43, ringPaint);
    canvas.drawCircle(center, 58, ringPaint);

    final glow = Paint()
      ..color = const Color(0xFFFFE9DD).withValues(alpha: 0.75)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);
    canvas.drawCircle(center, 48, glow);

    final iconRect = Rect.fromCenter(center: center, width: 43, height: 43);
    canvas.drawRRect(
      RRect.fromRectAndRadius(iconRect, const Radius.circular(12)),
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xFFFF8C4B), Color(0xFFFF5B1F)],
        ).createShader(iconRect),
    );

    final cutPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.88)
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      center + const Offset(-17, -3),
      center + const Offset(17, -10),
      cutPaint,
    );
    canvas.drawLine(
      center + const Offset(-4, -18),
      center + const Offset(4, 18),
      cutPaint,
    );

    final dotPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFFFFD3B8), Color(0xFFFF9B66)],
      ).createShader(Offset.zero & size);
    canvas.drawCircle(center + const Offset(39, -50), 7, dotPaint);
    canvas.drawCircle(center + const Offset(-52, 35), 7, dotPaint);
    canvas.drawCircle(center + const Offset(54, 51), 4, dotPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _CarouselDots extends StatelessWidget {
  const _CarouselDots();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: const [
        _Dot(width: 18, color: Color(0xFFFF6A24)),
        SizedBox(width: 12),
        _Dot(width: 18, color: Color(0xFFD7DADD)),
        SizedBox(width: 12),
        _Dot(width: 18, color: Color(0xFFD7DADD)),
      ],
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.width, required this.color});

  final double width;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: 3,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
      ),
    );
  }
}

class _UnboundDeviceArt extends StatelessWidget {
  const _UnboundDeviceArt();

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/images/Group 194671.png',
      fit: BoxFit.contain,
      errorBuilder: (context, error, stackTrace) {
        return const _UnboundDeviceFallback();
      },
    );
  }
}

class _UnboundDeviceFallback extends StatelessWidget {
  const _UnboundDeviceFallback();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _UnboundDevicePainter());
  }
}

class _UnboundDevicePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(center.dx, size.height - 10),
        width: size.width * 0.76,
        height: 20,
      ),
      Paint()
        ..color = const Color(0xFF9FB0C4).withValues(alpha: 0.18)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
    );

    final bodyRect = Rect.fromLTWH(36, 7, 108, 94);
    canvas.drawRRect(
      RRect.fromRectAndRadius(bodyRect, const Radius.circular(22)),
      Paint()..color = const Color(0xFFF8FAFD),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(bodyRect, const Radius.circular(22)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = const Color(0xFFDDE6F0),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _CastEntryCard extends StatelessWidget {
  const _CastEntryCard({
    required this.title,
    required this.subtitle,
    required this.artAsset,
    required this.arrowAsset,
    required this.backgroundAsset,
    required this.fallbackColor,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final String artAsset;
  final String arrowAsset;
  final String backgroundAsset;
  final Color fallbackColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        width: 158,
        height: 155,
        child: Stack(
          children: [
            Positioned.fill(
              child: Image.asset(
                backgroundAsset,
                fit: BoxFit.fill,
                errorBuilder: (context, error, stackTrace) {
                  return DecoratedBox(
                    decoration: BoxDecoration(
                      color: fallbackColor,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.7),
                      ),
                    ),
                  );
                },
              ),
            ),
            Positioned(
              left: 34,
              top: 22,
              width: 55,
              height: 55,
              child: Image.asset(
                artAsset,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) {
                  return Icon(
                    title == '拍照'
                        ? Icons.photo_camera_rounded
                        : Icons.photo_library_rounded,
                    color: title == '拍照'
                        ? const Color(0xFFFF6A24)
                        : const Color(0xFF287BFF),
                    size: 38,
                  );
                },
              ),
            ),
            Positioned(
              left: 13,
              top: 100,
              child: Text(title, style: _HomeTextStyles.cardTitle),
            ),
            Positioned(
              left: 13,
              top: 126,
              child: Text(subtitle, style: _HomeTextStyles.cardSubtitle),
            ),
            Positioned(
              right: 25,
              bottom: 22,
              width: 36,
              height: 36,
              child: Image.asset(
                arrowAsset,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) {
                  return Icon(
                    Icons.arrow_forward_rounded,
                    color: title == '拍照'
                        ? const Color(0xFFFF6A24)
                        : const Color(0xFF287BFF),
                    size: 26,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CastSheetRow extends StatelessWidget {
  const _CastSheetRow({
    required this.title,
    required this.subtitle,
    required this.artAsset,
    required this.arrowAsset,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final String artAsset;
  final String arrowAsset;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: 327,
        height: 61,
        padding: const EdgeInsets.fromLTRB(12, 8, 18, 8),
        decoration: BoxDecoration(
          color: const Color(0xFFF5F6F8),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Image.asset(
              artAsset,
              width: 48,
              height: 48,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) {
                return Icon(
                  title == '拍照'
                      ? Icons.photo_camera_rounded
                      : Icons.photo_library_rounded,
                  color: title == '拍照'
                      ? const Color(0xFFFF6A24)
                      : const Color(0xFF287BFF),
                  size: 34,
                );
              },
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: _HomeTextStyles.sheetOptionTitle),
                  const SizedBox(height: 2),
                  Text(subtitle, style: _HomeTextStyles.sheetOptionBody),
                ],
              ),
            ),
            Image.asset(
              arrowAsset,
              width: 36,
              height: 36,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) {
                return Icon(
                  Icons.arrow_forward_rounded,
                  color: title == '拍照'
                      ? const Color(0xFFFF6A24)
                      : const Color(0xFF287BFF),
                  size: 26,
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeTabBar extends StatelessWidget {
  const _HomeTabBar({required this.onOpenMine});

  final VoidCallback onOpenMine;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 327,
      height: 56,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.74),
        borderRadius: BorderRadius.circular(35),
        border: Border.all(color: Colors.white.withValues(alpha: 0.55)),
      ),
      child: Row(
        children: [
          const Expanded(
            child: _HomeTabItem(
              icon: Icons.home_rounded,
              label: '首页',
              color: Color(0xFFFF6A24),
            ),
          ),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onOpenMine,
              child: const _HomeTabItem(
                icon: Icons.person_outline_rounded,
                label: '我的',
                color: Color(0xFF7A7D80),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeTabItem extends StatelessWidget {
  const _HomeTabItem({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, color: color, size: 28),
        const SizedBox(height: 1),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.w400,
            height: 1.2,
          ),
        ),
      ],
    );
  }
}

class _BluetoothRadar extends StatelessWidget {
  const _BluetoothRadar({
    required this.failed,
    required this.success,
    required this.dimmed,
  });

  final bool failed;
  final bool success;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final asset = success
        ? 'assets/images/device_found_art.png'
        : 'assets/images/device_scanning_art.png';
    return Opacity(
      opacity: dimmed ? 0.56 : 1,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Image.asset(
            asset,
            width: 224,
            height: 224,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) {
              return const _RadarFallback();
            },
          ),
          if (failed)
            const Positioned(
              left: 151,
              top: 125,
              width: 22,
              height: 22,
              child: _FailBadge(),
            ),
        ],
      ),
    );
  }
}

class _RadarFallback extends StatelessWidget {
  const _RadarFallback();

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        CustomPaint(
          size: const Size(224, 224),
          painter: _RadarFallbackPainter(),
        ),
        Container(
          width: 62,
          height: 62,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFFFF9759), Color(0xFFFF5E20)],
            ),
          ),
          child: const Icon(
            Icons.bluetooth_rounded,
            color: Colors.white,
            size: 34,
          ),
        ),
      ],
    );
  }
}

class _RadarFallbackPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    for (final radius in <double>[52, 76, 100]) {
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = Colors.white.withValues(alpha: 0.76),
      );
    }
    canvas.drawCircle(
      center,
      62,
      Paint()..color = const Color(0xFFFFE8D9).withValues(alpha: 0.26),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _FailBadge extends StatelessWidget {
  const _FailBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
      ),
      child: const Icon(
        Icons.close_rounded,
        color: Color(0xFFFF6A24),
        size: 18,
      ),
    );
  }
}

class _FoundDeviceTile extends StatelessWidget {
  const _FoundDeviceTile({
    required this.device,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  final DeviceItem device;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: 327,
        height: 64,
        padding: const EdgeInsets.fromLTRB(20, 8, 18, 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: selected ? 0.76 : 0.58),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? const Color(0xFFFF6A24) : Colors.white,
            width: selected ? 1 : 0.8,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(Icons.videocam_outlined, color: accent, size: 26),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Text(
                _displayDeviceName(device),
                style: _HomeTextStyles.deviceName,
              ),
            ),
            Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: selected ? const Color(0xFFFF7D36) : Colors.transparent,
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected
                      ? const Color(0xFFFF7D36)
                      : const Color(0xFFB7BBC0),
                  width: selected ? 0 : 1,
                ),
              ),
              child: selected
                  ? const Icon(
                      Icons.check_rounded,
                      color: Colors.white,
                      size: 22,
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  String _displayDeviceName(DeviceItem device) {
    if (device.name.contains('Aurora')) {
      return '客厅相框';
    }
    if (device.name.contains('Gallery')) {
      return '卧室相框';
    }
    if (device.name.contains('Pocket')) {
      return '书房相框';
    }
    return device.name;
  }
}

class _GradientButton extends StatelessWidget {
  const _GradientButton({
    required this.label,
    required this.onPressed,
    this.icon,
    this.height = 56,
    this.fontSize = 18,
  });

  final String label;
  final VoidCallback onPressed;
  final Widget? icon;
  final double height;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(height / 2),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFF7D36), Color(0xFFFF621F)],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFEB5F1B).withValues(alpha: 0.26),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(height / 2),
        child: InkWell(
          borderRadius: BorderRadius.circular(height / 2),
          onTap: onPressed,
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[icon!, const SizedBox(width: 14)],
                Text(
                  label,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: fontSize,
                    fontWeight: FontWeight.w500,
                    height: 1.2,
                    letterSpacing: label.length <= 4 ? 2 : 1,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CircleIconButton extends StatelessWidget {
  const _CircleIconButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.52),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Icon(icon, color: const Color(0xFF2A2B2B), size: 20),
      ),
    );
  }
}

class _ScanHelpIconFallback extends StatelessWidget {
  const _ScanHelpIconFallback();

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        Container(
          width: 115,
          height: 115,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFFFFEAD9).withValues(alpha: 0.34),
          ),
        ),
        Container(
          width: 57,
          height: 57,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFFFFB287), Color(0xFFFF8B62)],
            ),
          ),
          child: const Icon(
            Icons.center_focus_weak_rounded,
            color: Colors.white,
            size: 28,
          ),
        ),
      ],
    );
  }
}

class _HomeIndicator extends StatelessWidget {
  const _HomeIndicator();

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 120,
      bottom: 8,
      width: 135,
      height: 5,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(100),
        ),
      ),
    );
  }
}

class _HomeTextStyles {
  const _HomeTextStyles._();

  static const status = TextStyle(
    color: Colors.black,
    fontSize: 14,
    fontWeight: FontWeight.w600,
    height: 1,
  );

  static const navTitle = TextStyle(
    color: Color(0xFF2A2B2B),
    fontSize: 17,
    fontWeight: FontWeight.w600,
    height: 1.2,
  );

  static const hi = TextStyle(
    color: Color(0xFF2A2B2B),
    fontSize: 43,
    fontWeight: FontWeight.w500,
    height: 1,
  );

  static const welcome = TextStyle(
    color: Color(0xFF2A2B2B),
    fontSize: 21,
    fontWeight: FontWeight.w400,
    height: 1,
  );

  static const brandFallback = TextStyle(
    color: Color(0xFFFF7D36),
    fontSize: 22,
    fontWeight: FontWeight.w700,
    height: 1,
  );

  static const sectionTitle = TextStyle(
    color: Color(0xFF2A2B2B),
    fontSize: 17,
    fontWeight: FontWeight.w600,
    height: 1.2,
  );

  static const mutedBody = TextStyle(
    color: Color(0x992A2B2B),
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 1.2,
  );

  static const cardTitle = TextStyle(
    color: Color(0xFF2A2B2B),
    fontSize: 18,
    fontWeight: FontWeight.w600,
    height: 1.2,
  );

  static const cardSubtitle = TextStyle(
    color: Color(0x992A2B2B),
    fontSize: 12,
    fontWeight: FontWeight.w400,
    height: 1.2,
  );

  static const deviceCardTitle = TextStyle(
    color: Color(0xFF2A2B2B),
    fontSize: 23,
    fontWeight: FontWeight.w600,
    height: 1.2,
  );

  static const deviceMeta = TextStyle(
    color: Color(0x992A2B2B),
    fontSize: 13,
    fontWeight: FontWeight.w400,
    height: 1.2,
  );

  static const bindTitle = TextStyle(
    color: Color(0xFF2A2B2B),
    fontSize: 20,
    fontWeight: FontWeight.w600,
    height: 1.2,
  );

  static const bindSubtitle = TextStyle(
    color: Color(0x992A2B2B),
    fontSize: 12,
    fontWeight: FontWeight.w400,
    height: 1.2,
  );

  static const orangeLink = TextStyle(
    color: Color(0xFFFF6A24),
    fontSize: 13,
    fontWeight: FontWeight.w400,
    height: 1.2,
  );

  static const sheetTitle = TextStyle(
    color: Color(0xFF2A2B2B),
    fontSize: 22,
    fontWeight: FontWeight.w600,
    height: 1.2,
  );

  static const sheetBody = TextStyle(
    color: Color(0xCC2A2B2B),
    fontSize: 13,
    fontWeight: FontWeight.w400,
    height: 1.2,
  );

  static const helpTitle = TextStyle(
    color: Color(0xFF2A2B2B),
    fontSize: 16,
    fontWeight: FontWeight.w600,
    height: 1.5,
  );

  static const helpBody = TextStyle(
    color: Color(0xCC2A2B2B),
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 1.55,
  );

  static const deviceName = TextStyle(
    color: Color(0xFF2A2B2B),
    fontSize: 16,
    fontWeight: FontWeight.w600,
    height: 1.2,
  );

  static const sheetOptionTitle = TextStyle(
    color: Color(0xFF2A2B2B),
    fontSize: 16,
    fontWeight: FontWeight.w600,
    height: 1.15,
  );

  static const sheetOptionBody = TextStyle(
    color: Color(0x992A2B2B),
    fontSize: 12,
    fontWeight: FontWeight.w400,
    height: 1.2,
  );

  static const cancelButton = TextStyle(
    color: Color(0xFF2A2B2B),
    fontSize: 18,
    fontWeight: FontWeight.w500,
    height: 1.2,
    letterSpacing: 2,
  );
}
