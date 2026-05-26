import 'package:flutter/material.dart';

import '../widgets/figma_common.dart';
import 'home_figma_common.dart';

enum FigmaHomeUnboundSheet { none, bindNow, reconnect }

class FigmaHomeUnboundDevicePage extends StatelessWidget {
  const FigmaHomeUnboundDevicePage({
    super.key,
    this.sheet = FigmaHomeUnboundSheet.none,
    this.onBindDevice,
    this.onCamera,
    this.onAlbum,
  });

  final FigmaHomeUnboundSheet sheet;
  final VoidCallback? onBindDevice;
  final VoidCallback? onCamera;
  final VoidCallback? onAlbum;

  @override
  Widget build(BuildContext context) {
    return FigmaHomePhoneFrame(
      child: Stack(
        children: [
          FigmaHomeScaffoldContent(
            showBoundDevice: false,
            onBindDevice: onBindDevice,
            onCamera: onCamera,
            onAlbum: onAlbum,
          ),
          if (sheet != FigmaHomeUnboundSheet.none)
            _UnboundNoticeOverlay(
              title: sheet == FigmaHomeUnboundSheet.bindNow
                  ? '暂未绑定设备'
                  : '设备连接失败',
              subtitle: sheet == FigmaHomeUnboundSheet.bindNow
                  ? '当前暂无可投屏设备，请先绑定相框设备'
                  : '当前设备未连接，APP需先连接设备后再投屏',
              buttonLabel: sheet == FigmaHomeUnboundSheet.bindNow
                  ? '立即绑定'
                  : '重新连接',
              onPressed: onBindDevice,
            ),
        ],
      ),
    );
  }
}

class FigmaHomeBoundDevicePage extends StatelessWidget {
  const FigmaHomeBoundDevicePage({
    super.key,
    this.showCastSheet = false,
    this.onAddDevice,
    this.onCamera,
    this.onAlbum,
  });

  final bool showCastSheet;
  final VoidCallback? onAddDevice;
  final VoidCallback? onCamera;
  final VoidCallback? onAlbum;

  @override
  Widget build(BuildContext context) {
    return FigmaHomePhoneFrame(
      child: Stack(
        children: [
          FigmaHomeScaffoldContent(
            showBoundDevice: true,
            onAddDevice: onAddDevice,
            onCamera: onCamera,
            onAlbum: onAlbum,
          ),
          if (showCastSheet)
            _CastMethodOverlay(onCamera: onCamera, onAlbum: onAlbum),
        ],
      ),
    );
  }
}

class FigmaHomeScaffoldContent extends StatelessWidget {
  const FigmaHomeScaffoldContent({
    super.key,
    required this.showBoundDevice,
    this.onBindDevice,
    this.onAddDevice,
    this.onCamera,
    this.onAlbum,
  });

  final bool showBoundDevice;
  final VoidCallback? onBindDevice;
  final VoidCallback? onAddDevice;
  final VoidCallback? onCamera;
  final VoidCallback? onAlbum;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const Positioned.fill(child: FigmaHomeBackground()),
        const Positioned(left: 0, top: 0, width: 375, child: FigmaStatusBar()),
        if (showBoundDevice) ...[
          const Positioned(left: 24, top: 56, child: _UserAvatar()),
          Positioned(
            left: 328,
            top: 58,
            width: 30,
            height: 30,
            child: _AddDeviceButton(onTap: onAddDevice),
          ),
          const Positioned(left: 24, top: 136, child: _BoundGreeting()),
          const Positioned(
            left: 24,
            top: 241,
            width: 327,
            height: 186,
            child: _BoundDeviceCard(),
          ),
          const Positioned(
            right: -106,
            top: 267,
            width: 154,
            height: 134,
            child: _PartialDeviceCard(),
          ),
          const Positioned(left: 150, top: 458, child: _CarouselDots()),
        ] else ...[
          const Positioned(
            left: 96,
            top: 188,
            width: 185,
            height: 116,
            child: FigmaHomeAssetImage(
              assetPath: 'assets/images/home_unbound_frame_device.png',
              fallback: _UnboundDeviceFallback(),
              fit: BoxFit.contain,
            ),
          ),
          const Positioned(
            left: 0,
            top: 349,
            width: 375,
            child: Text(
              '请先绑定相框设备后再投屏照片',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0x992A2B2B),
                fontSize: 14,
                fontWeight: FontWeight.w400,
                height: 1.2,
              ),
            ),
          ),
          Positioned(
            left: 88,
            top: 381,
            width: 200,
            height: 44,
            child: FigmaHomePrimaryButton(
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
                  size: 14,
                ),
              ),
              onPressed: onBindDevice,
            ),
          ),
        ],
        const Positioned(
          left: 24,
          top: 498,
          child: Text('选择投屏方式', style: FigmaHomeTextStyles.sectionTitle),
        ),
        Positioned(
          left: 24,
          top: 524,
          child: _CastMethodCards(onCamera: onCamera, onAlbum: onAlbum),
        ),
        const Positioned(left: 24, top: 730, child: FigmaHomeBottomNav()),
        const FigmaBottomHomeIndicator(),
      ],
    );
  }
}

class _CastMethodCards extends StatelessWidget {
  const _CastMethodCards({this.onCamera, this.onAlbum});

  final VoidCallback? onCamera;
  final VoidCallback? onAlbum;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        FigmaCastMethodCard(
          title: '拍照',
          subtitle: '拍摄照片并投屏',
          assetPath: 'assets/images/home_camera_entry.png',
          accentColor: const Color(0xFFFF6A24),
          backgroundColor: const Color(0xFFFFF8F4).withValues(alpha: 0.86),
          fallbackIcon: const FigmaCameraFallbackIcon(),
          onTap: onCamera,
        ),
        const SizedBox(width: 11),
        FigmaCastMethodCard(
          title: '相册',
          subtitle: '选择照片并投屏',
          assetPath: 'assets/images/home_album_entry.png',
          accentColor: const Color(0xFF287BFF),
          backgroundColor: const Color(0xFFEAF4FF).withValues(alpha: 0.88),
          fallbackIcon: const FigmaAlbumFallbackIcon(),
          onTap: onAlbum,
        ),
      ],
    );
  }
}

class _UnboundNoticeOverlay extends StatelessWidget {
  const _UnboundNoticeOverlay({
    required this.title,
    required this.subtitle,
    required this.buttonLabel,
    this.onPressed,
  });

  final String title;
  final String subtitle;
  final String buttonLabel;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: ColoredBox(color: Colors.black.withValues(alpha: 0.42)),
        ),
        Positioned(
          left: 0,
          top: 562,
          width: 375,
          height: 250,
          child: DecoratedBox(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Stack(
              children: [
                Positioned(
                  right: 31,
                  top: 26,
                  width: 22,
                  height: 22,
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(
                      width: 22,
                      height: 22,
                    ),
                    icon: const Icon(
                      Icons.close_rounded,
                      color: Color(0xFF7E7E7E),
                      size: 24,
                    ),
                    onPressed: () => Navigator.maybePop(context),
                  ),
                ),
                Positioned(
                  left: 0,
                  top: 61,
                  width: 375,
                  child: Text(
                    title,
                    textAlign: TextAlign.center,
                    style: FigmaHomeTextStyles.sheetTitle,
                  ),
                ),
                Positioned(
                  left: 0,
                  top: 103,
                  width: 375,
                  child: Text(
                    subtitle,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xCC2A2B2B),
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                      height: 1.2,
                    ),
                  ),
                ),
                Positioned(
                  left: 24,
                  top: 140,
                  width: 327,
                  height: 56,
                  child: FigmaHomePrimaryButton(
                    label: buttonLabel,
                    onPressed: onPressed,
                  ),
                ),
              ],
            ),
          ),
        ),
        const FigmaBottomHomeIndicator(),
      ],
    );
  }
}

class _CastMethodOverlay extends StatelessWidget {
  const _CastMethodOverlay({this.onCamera, this.onAlbum});

  final VoidCallback? onCamera;
  final VoidCallback? onAlbum;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: ColoredBox(color: Colors.black.withValues(alpha: 0.42)),
        ),
        Positioned(
          left: 0,
          top: 459,
          width: 375,
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
                  child: Text('选择投屏方式', style: FigmaHomeTextStyles.sheetTitle),
                ),
                Positioned(
                  left: 24,
                  top: 73,
                  child: FigmaCastMethodRow(
                    title: '拍照',
                    subtitle: '调用手机相机拍照',
                    assetPath: 'assets/images/home_camera_entry.png',
                    accentColor: Color(0xFFFF6A24),
                    fallbackIcon: const FigmaCameraFallbackIcon(size: 48),
                    onTap: onCamera,
                  ),
                ),
                Positioned(
                  left: 24,
                  top: 147,
                  child: FigmaCastMethodRow(
                    title: '相册',
                    subtitle: '从手机相册选择照片',
                    assetPath: 'assets/images/home_album_entry.png',
                    accentColor: Color(0xFF287BFF),
                    fallbackIcon: const FigmaAlbumFallbackIcon(size: 48),
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
                        child: Text(
                          '取消',
                          style: TextStyle(
                            color: Color(0xFF2A2B2B),
                            fontSize: 18,
                            fontWeight: FontWeight.w500,
                            height: 1.2,
                            letterSpacing: 2,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const FigmaBottomHomeIndicator(),
      ],
    );
  }
}

class _UserAvatar extends StatelessWidget {
  const _UserAvatar();

  @override
  Widget build(BuildContext context) {
    return ClipOval(
      child: SizedBox(
        width: 34,
        height: 34,
        child: FigmaHomeAssetImage(
          assetPath: 'assets/images/home_avatar.png',
          fallback: Container(
            color: const Color(0xFFEAF4FF),
            child: const Icon(
              Icons.person_rounded,
              color: Color(0xFF8C9092),
              size: 22,
            ),
          ),
          fit: BoxFit.cover,
        ),
      ),
    );
  }
}

class _AddDeviceButton extends StatelessWidget {
  const _AddDeviceButton({this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFFF7D36),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: const Icon(Icons.add_rounded, color: Colors.white, size: 24),
      ),
    );
  }
}

class _BoundGreeting extends StatelessWidget {
  const _BoundGreeting();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 310,
      height: 82,
      child: Stack(
        children: [
          const Positioned(
            left: 0,
            top: 0,
            child: Text(
              'Hi',
              style: TextStyle(
                color: Color(0xFF2A2B2B),
                fontSize: 43,
                fontWeight: FontWeight.w500,
                height: 1,
              ),
            ),
          ),
          Positioned(
            left: 0,
            top: 55,
            child: Text.rich(
              const TextSpan(
                children: [
                  TextSpan(text: '欢迎使用 '),
                  TextSpan(
                    text: 'BoltStar',
                    style: TextStyle(
                      color: Color(0xFFFF7D36),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              style: const TextStyle(
                color: Color(0xFF2A2B2B),
                fontSize: 21,
                fontWeight: FontWeight.w400,
                height: 1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BoundDeviceCard extends StatelessWidget {
  const _BoundDeviceCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.74),
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
          const Positioned(
            left: 195,
            top: 58,
            child: Text(
              '房间相册',
              style: TextStyle(
                color: Color(0xFF2A2B2B),
                fontSize: 23,
                fontWeight: FontWeight.w600,
                height: 1.2,
              ),
            ),
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
                Text(
                  '已连接',
                  style: TextStyle(
                    color: Color(0x992A2B2B),
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
          const Positioned(
            left: 195,
            top: 132,
            child: Row(
              children: [
                Icon(
                  Icons.battery_2_bar_rounded,
                  color: Color(0xFFFF6A24),
                  size: 18,
                ),
                SizedBox(width: 8),
                Text(
                  '30%',
                  style: TextStyle(
                    color: Color(0x992A2B2B),
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PartialDeviceCard extends StatelessWidget {
  const _PartialDeviceCard();

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
    final iconPaint = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFFFF8C4B), Color(0xFFFF5B1F)],
      ).createShader(iconRect);
    final rrect = RRect.fromRectAndRadius(iconRect, const Radius.circular(12));
    canvas.drawRRect(rrect, iconPaint);

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
      children: [
        Container(
          width: 18,
          height: 3,
          decoration: BoxDecoration(
            color: const Color(0xFFFF6A24),
            borderRadius: BorderRadius.circular(999),
          ),
        ),
        const SizedBox(width: 12),
        Container(
          width: 18,
          height: 3,
          decoration: BoxDecoration(
            color: const Color(0xFFD7DADD),
            borderRadius: BorderRadius.circular(999),
          ),
        ),
        const SizedBox(width: 12),
        Container(
          width: 18,
          height: 3,
          decoration: BoxDecoration(
            color: const Color(0xFFD7DADD),
            borderRadius: BorderRadius.circular(999),
          ),
        ),
      ],
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
    final shadowPaint = Paint()
      ..color = const Color(0xFF9FB0C4).withValues(alpha: 0.18)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(center.dx, size.height - 10),
        width: size.width * 0.76,
        height: 20,
      ),
      shadowPaint,
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

    final photoRect = Rect.fromLTWH(54, 22, 70, 46);
    canvas.drawRRect(
      RRect.fromRectAndRadius(photoRect, const Radius.circular(8)),
      Paint()..color = const Color(0xFFEAF0F8),
    );
    final mountainPaint = Paint()..color = const Color(0xFFD6E0EC);
    final mountain = Path()
      ..moveTo(photoRect.left, photoRect.bottom)
      ..lineTo(photoRect.left + 25, photoRect.top + 20)
      ..lineTo(photoRect.left + 50, photoRect.bottom)
      ..close();
    canvas.drawPath(mountain, mountainPaint);
    final mountain2 = Path()
      ..moveTo(photoRect.left + 35, photoRect.bottom)
      ..lineTo(photoRect.left + 55, photoRect.top + 30)
      ..lineTo(photoRect.right, photoRect.bottom)
      ..close();
    canvas.drawPath(mountain2, Paint()..color = const Color(0xFFC9D6E6));

    canvas.drawCircle(
      Offset(bodyRect.right - 16, bodyRect.bottom - 20),
      14,
      Paint()..color = const Color(0xFFEAF0F8),
    );
    canvas.drawCircle(
      Offset(bodyRect.right - 16, bodyRect.bottom - 20),
      11,
      Paint()..color = Colors.white.withValues(alpha: 0.62),
    );
    final strapRect = Rect.fromLTWH(bodyRect.right - 6, 56, 31, 21);
    canvas.drawRRect(
      RRect.fromRectAndRadius(strapRect, const Radius.circular(5)),
      Paint()..color = const Color(0xFFE4EBF5),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
