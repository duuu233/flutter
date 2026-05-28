part of 'home_page.dart';

// =============================================================================
// 首页系列的展示型（dumb）组件集合：无业务逻辑，只负责画 UI。
// 按使用场景分区：背景 / 通用控件 / 已绑定主视图 / 未绑定主视图 / 投屏入口 /
// 绑定设备流程。所有控件均为私有，仅供本 home_page 库内部使用。
// =============================================================================

// -----------------------------------------------------------------------------
// 背景：所有首页场景共用，铺满整屏。
// -----------------------------------------------------------------------------

/// 全屏背景：底色 + `bg02.png`（加载失败时回退到渐变光晕画笔）。
class _HomeBackground extends StatelessWidget {
  const _HomeBackground();

  @override
  Widget build(BuildContext context) {
    return const Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: Color(0xFFF5F9FF)),
        _AssetImage(
          path: 'assets/images/bg02.png',
          fallback: _SoftBackgroundPainterWidget(),
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

/// 通用图片：`BoxFit.cover` 加载资源，失败时显示 [fallback]。
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

// -----------------------------------------------------------------------------
// 通用控件：跨场景复用（按钮、圆形图标按钮、底部 Tab 栏）。
// -----------------------------------------------------------------------------

/// 橙色渐变主按钮（绑定/重新扫描/我知道了等场景的主操作）。
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

/// 半透明圆形图标按钮（绑定流程顶部返回键）。
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

/// 底部导航栏（首页主视图底部，「首页 / 我的」两个 Tab）。
class _HomeTabBar extends StatelessWidget {
  const _HomeTabBar({required this.onOpenMine});

  final VoidCallback onOpenMine;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
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

// -----------------------------------------------------------------------------
// 「首页-已绑定设备」场景专用组件。
// -----------------------------------------------------------------------------

/// 顶部用户头像。
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

/// 右上角「添加设备」圆形按钮。
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

/// 问候语「Hi / 欢迎使用 BoltStar」。带 Key('home-title') 供测试定位。
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

/// 已连接设备卡片：设备名、连接状态、电量。
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

/// 设备卡右侧露出的「下一张卡」提示（暗示可左右切换的设备轮播）。
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

/// 设备轮播指示点（3 点，首点高亮）。
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

// -----------------------------------------------------------------------------
// 「首页-未绑定设备」场景专用组件。
// -----------------------------------------------------------------------------

/// 未绑定时的空设备插画（加载失败回退到 [_UnboundDeviceFallback]）。
class _UnboundDeviceArt extends StatelessWidget {
  const _UnboundDeviceArt();

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/images/empty_device_art.png',

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

// -----------------------------------------------------------------------------
// 投屏入口组件：主视图底部「选择投屏方式」卡片 + 弹层里的行。
// -----------------------------------------------------------------------------

/// 主视图底部「拍照 / 相册」投屏入口大卡片。
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

/// 「选择投屏方式」底部弹层里的单行（拍照 / 相册）。
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
        width: double.infinity,
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

// -----------------------------------------------------------------------------
// 「绑定设备」流程专用组件：蓝牙雷达、已发现设备列表项、扫描帮助插画。
// -----------------------------------------------------------------------------

/// 蓝牙搜索雷达插画。[success] 显示找到态，[failed] 叠加失败角标，
/// [dimmed] 在弹出扫描帮助时压暗。
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

/// 雷达中心的「未找到」失败角标。
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

/// 「已搜索到设备」列表里的单台设备项，可选中。
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

/// 「扫描不到怎么办」弹层里的插画（加载失败时的回退图标）。
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
