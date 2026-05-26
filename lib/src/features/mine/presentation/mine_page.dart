import 'package:flutter/material.dart';

import '../../../routes/app_routes.dart';
import '../../../state.dart';

class MinePage extends StatelessWidget {
  const MinePage({super.key, required this.state, required this.onOpenHome});

  final PhotoFrameState state;
  final VoidCallback onOpenHome;

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
              child: Stack(
                children: [
                  const Positioned.fill(child: _MineBackground()),
                  const Positioned(
                    left: 0,
                    top: 0,
                    width: 375,
                    child: _StatusBar(),
                  ),
                  const Positioned(
                    left: 0,
                    top: 53,
                    width: 375,
                    child: Text(
                      '我的',
                      key: Key('mine-page-title'),
                      textAlign: TextAlign.center,
                      style: _MineTextStyles.navTitle,
                    ),
                  ),
                  Positioned(
                    left: 24,
                    top: 109,
                    width: 327,
                    height: 110,
                    child: _ProfileCard(
                      onTap: () {
                        Navigator.of(
                          context,
                        ).pushNamed<void>(AppRoutes.profile);
                      },
                    ),
                  ),
                  const Positioned(
                    left: 24,
                    top: 248,
                    child: Text('常用功能', style: _MineTextStyles.sectionTitle),
                  ),
                  Positioned(
                    left: 24,
                    top: 276,
                    width: 104,
                    height: 147,
                    child: _FeatureCard(
                      asset: 'assets/images/Group 194925.png',
                      fallbackIcon: Icons.photo_size_select_actual_outlined,
                      fallbackColor: const Color(0xFFFF6A24),
                      title: '我的图库',
                      subtitle: '102张照片',
                      onTap: () {
                        Navigator.of(context).pushNamed<void>(AppRoutes.album);
                      },
                    ),
                  ),
                  Positioned(
                    left: 136,
                    top: 276,
                    width: 104,
                    height: 147,
                    child: _FeatureCard(
                      asset: 'assets/images/Group 194926.png',
                      fallbackIcon: Icons.devices_other_outlined,
                      fallbackColor: const Color(0xFF4A98FF),
                      title: '我的设备',
                      subtitle: '${state.devices.length}个设备',
                      onTap: () {
                        Navigator.of(
                          context,
                        ).pushNamed<void>(AppRoutes.figmaMyDevices);
                      },
                    ),
                  ),
                  Positioned(
                    left: 248,
                    top: 276,
                    width: 104,
                    height: 147,
                    child: _FeatureCard(
                      asset: 'assets/images/Group 194927.png',
                      fallbackIcon: Icons.view_list_rounded,
                      fallbackColor: const Color(0xFFFF6A24),
                      title: '投屏管理',
                      subtitle: '',
                      onTap: () {
                        Navigator.of(
                          context,
                        ).pushNamed<void>(AppRoutes.castManagement);
                      },
                    ),
                  ),
                  const Positioned(
                    left: 24,
                    top: 456,
                    child: Text('服务与帮助', style: _MineTextStyles.sectionTitle),
                  ),
                  Positioned(
                    left: 24,
                    top: 482,
                    width: 327,
                    height: 54,
                    child: _ServiceRow(
                      asset: 'assets/images/Group 194799.png',
                      fallbackIcon: Icons.menu_book_outlined,
                      title: '操作指南',
                      onTap: () {
                        Navigator.of(context).pushNamed<void>(AppRoutes.guide);
                      },
                    ),
                  ),
                  Positioned(
                    left: 24,
                    top: 550,
                    width: 327,
                    height: 54,
                    child: _ServiceRow(
                      asset: 'assets/images/Group 194928.png',
                      fallbackIcon: Icons.settings_outlined,
                      title: '设置',
                      onTap: () {
                        Navigator.of(
                          context,
                        ).pushNamed<void>(AppRoutes.settings);
                      },
                    ),
                  ),
                  Positioned(
                    left: 24,
                    top: 730,
                    width: 327,
                    height: 56,
                    child: _MineTabBar(onOpenHome: onOpenHome),
                  ),
                  const _HomeIndicator(),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _MineBackground extends StatelessWidget {
  const _MineBackground();

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/images/login_bg_image_5130.png',
      width: 375,
      height: 812,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) {
        return DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFEAF3FF), Color(0xFFF8FBFF), Color(0xFFFFF2E8)],
            ),
          ),
          child: CustomPaint(painter: _MineBackgroundPainter()),
        );
      },
    );
  }
}

class _StatusBar extends StatelessWidget {
  const _StatusBar();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 15, 14, 0),
      child: Row(
        children: [
          const Text('9:41', style: _MineTextStyles.status),
          const Spacer(),
          Icon(
            Icons.signal_cellular_alt_rounded,
            size: 17,
            color: Colors.black,
          ),
          const SizedBox(width: 4),
          Icon(Icons.wifi_rounded, size: 17, color: Colors.black),
          const SizedBox(width: 4),
          Container(
            width: 24,
            height: 11,
            padding: const EdgeInsets.all(1.2),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.black, width: 1),
              borderRadius: BorderRadius.circular(2.5),
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Container(
                width: 18,
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(1.5),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.white.withValues(alpha: 0.82),
              Colors.white.withValues(alpha: 0.62),
              const Color(0xFFFFEEE6).withValues(alpha: 0.52),
            ],
          ),
          border: Border.all(color: Colors.white.withValues(alpha: 0.72)),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF97AEC8).withValues(alpha: 0.10),
              blurRadius: 22,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 18, 22, 18),
          child: Row(
            children: [
              const _Avatar(),
              const SizedBox(width: 20),
              const Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('江江', style: _MineTextStyles.profileName),
                    SizedBox(height: 9),
                    Text('ID：123456', style: _MineTextStyles.profileId),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: const Color(0xFF7C7E82),
                size: 30,
              ),
            ],
          ),
        ),
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
        width: 65,
        height: 65,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          return Container(
            width: 65,
            height: 65,
            decoration: const BoxDecoration(
              color: Color(0xFFFF7D36),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.person_rounded, color: Colors.white),
          );
        },
      ),
    );
  }
}

class _FeatureCard extends StatelessWidget {
  const _FeatureCard({
    required this.asset,
    required this.fallbackIcon,
    required this.fallbackColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final String asset;
  final IconData fallbackIcon;
  final Color fallbackColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.68),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withValues(alpha: 0.66)),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF97AEC8).withValues(alpha: 0.08),
              blurRadius: 18,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          children: [
            const SizedBox(height: 21),
            Image.asset(
              asset,
              width: 55,
              height: 55,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) {
                return Container(
                  width: 55,
                  height: 55,
                  decoration: BoxDecoration(
                    color: fallbackColor.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Icon(fallbackIcon, color: fallbackColor, size: 28),
                );
              },
            ),
            const SizedBox(height: 15),
            Text(title, style: _MineTextStyles.cardTitle),
            if (subtitle.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(subtitle, style: _MineTextStyles.cardSubtitle),
            ],
          ],
        ),
      ),
    );
  }
}

class _ServiceRow extends StatelessWidget {
  const _ServiceRow({
    required this.asset,
    required this.fallbackIcon,
    required this.title,
    required this.onTap,
  });

  final String asset;
  final IconData fallbackIcon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.70),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.64)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(23, 10, 18, 10),
          child: Row(
            children: [
              Image.asset(
                asset,
                width: 32,
                height: 32,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) {
                  return Icon(
                    fallbackIcon,
                    color: const Color(0xFF4A98FF),
                    size: 24,
                  );
                },
              ),
              const SizedBox(width: 18),
              Expanded(child: Text(title, style: _MineTextStyles.rowTitle)),
              const Icon(
                Icons.chevron_right_rounded,
                color: Color(0xFF7D8186),
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MineTabBar extends StatelessWidget {
  const _MineTabBar({required this.onOpenHome});

  final VoidCallback onOpenHome;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.74),
        borderRadius: BorderRadius.circular(35),
        border: Border.all(color: Colors.white.withValues(alpha: 0.55)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF97AEC8).withValues(alpha: 0.10),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onOpenHome,
              child: const _MineTabItem(
                icon: Icons.home_outlined,
                label: '首页',
                color: Color(0xFF7A7D80),
              ),
            ),
          ),
          const Expanded(
            child: _MineTabItem(
              icon: Icons.person_rounded,
              label: '我的',
              color: Color(0xFFFF6A24),
            ),
          ),
        ],
      ),
    );
  }
}

class _MineTabItem extends StatelessWidget {
  const _MineTabItem({
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

class _MineBackgroundPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = Colors.white.withValues(alpha: 0.58);

    canvas.drawOval(
      Rect.fromCenter(center: const Offset(48, -18), width: 360, height: 190),
      paint,
    );
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(330, 180), width: 94, height: 180),
      Paint()..color = const Color(0xFFFFE2CE).withValues(alpha: 0.22),
    );
    canvas.drawArc(
      const Rect.fromLTWH(-70, 700, 520, 132),
      3.05,
      2.85,
      false,
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _MineTextStyles {
  const _MineTextStyles._();

  static const status = TextStyle(
    color: Colors.black,
    fontSize: 14,
    fontWeight: FontWeight.w600,
    height: 1,
  );

  static const navTitle = TextStyle(
    color: Color(0xFF111111),
    fontSize: 18,
    fontWeight: FontWeight.w600,
    height: 1.2,
  );

  static const profileName = TextStyle(
    color: Color(0xFF2A2B2B),
    fontSize: 20,
    fontWeight: FontWeight.w600,
    height: 1.2,
  );

  static const profileId = TextStyle(
    color: Color(0x992A2B2B),
    fontSize: 12,
    fontWeight: FontWeight.w400,
    height: 1.2,
  );

  static const sectionTitle = TextStyle(
    color: Color(0xFF2A2B2B),
    fontSize: 17,
    fontWeight: FontWeight.w600,
    height: 1.2,
  );

  static const cardTitle = TextStyle(
    color: Color(0xFF2A2B2B),
    fontSize: 15,
    fontWeight: FontWeight.w500,
    height: 1.2,
  );

  static const cardSubtitle = TextStyle(
    color: Color(0x992A2B2B),
    fontSize: 12,
    fontWeight: FontWeight.w400,
    height: 1.2,
  );

  static const rowTitle = TextStyle(
    color: Color(0xFF2A2B2B),
    fontSize: 15,
    fontWeight: FontWeight.w600,
    height: 1.2,
  );
}
