import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../routes/app_routes.dart';
import '../../../state.dart';

/// 「我的」页：对照微信小程序 `photo-album/pages/mine` 精准还原。
///
/// 换算约定：小程序 1rpx ≈ 0.5 逻辑像素（750rpx = 屏宽）。
/// 横向留白分区设置：文字/卡片区 48rpx(=24)，常用功能宫格为整宽 space-evenly。
class MinePage extends StatefulWidget {
  const MinePage({super.key, required this.state, required this.onOpenHome});

  final PhotoFrameState state;
  final VoidCallback onOpenHome;

  @override
  State<MinePage> createState() => _MinePageState();
}

class _MinePageState extends State<MinePage> {
  static const _inset = EdgeInsets.symmetric(horizontal: 24);

  @override
  void initState() {
    super.initState();
    // 对齐小程序 mine.onShow：登录后刷新用户资料 + 设备/图库计数（真实数据；未登录则跳过）。
    if (widget.state.isLoggedIn) {
      widget.state.refreshCurrentUser();
      widget.state.refreshDevices();
      widget.state.refreshAlbum();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final onOpenHome = widget.onOpenHome;
    return Stack(
      fit: StackFit.expand,
      children: [
        const _MineBackground(),
        SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: IntrinsicHeight(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // 顶部居中标题（page-nav title="我的"）。
                        const SizedBox(height: 12),
                        const Text(
                          '我的',
                          key: Key('mine-page-title'),
                          textAlign: TextAlign.center,
                          style: _MineTextStyles.navTitle,
                        ),
                        // 个人资料卡：margin-top 72rpx(=36)。
                        const SizedBox(height: 24),
                        Padding(
                          padding: _inset,
                          child: _ProfileCard(
                            nickName: state.currentUser.nickname.isNotEmpty
                                ? state.currentUser.nickname
                                : '未登录',
                            userId: state.currentUser.id,
                            avatarUrl: state.currentUser.avatarUrl,
                            onTap: () {
                              // 未登录点资料卡进登录页（对齐小程序 requireLogin 游客态）；
                              // 已登录进个人资料页。
                              Navigator.of(context).pushNamed<void>(
                                state.isLoggedIn
                                    ? AppRoutes.profile
                                    : AppRoutes.auth,
                              );
                            },
                          ),
                        ),
                        // 常用功能：margin-top 92rpx(=46)，标题底 24rpx(=12)。
                        const SizedBox(height: 46),
                        const Padding(
                          padding: _inset,
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              '常用功能',
                              style: _MineTextStyles.sectionTitle,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        // 宫格整宽 space-evenly，卡片固定 204×296rpx(=102×148)。
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            _FeatureCard(
                              iconAsset: 'assets/images/mine-icon01.png',
                              fallbackIcon:
                                  Icons.photo_size_select_actual_outlined,
                              fallbackColor: const Color(0xFFFF6A24),
                              title: '我的图库',
                              subtitle: '${state.totalPhotoCount}张照片',
                              onTap: () {
                                Navigator.of(
                                  context,
                                ).pushNamed<void>(AppRoutes.figmaGallery);
                              },
                            ),
                            _FeatureCard(
                              iconAsset: 'assets/images/mine-icon02.png',
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
                            _FeatureCard(
                              iconAsset: 'assets/images/mine-icon03.png',
                              fallbackIcon: Icons.view_list_rounded,
                              fallbackColor: const Color(0xFFFF6A24),
                              title: '投屏管理',
                              subtitle: '',
                              onTap: () {
                                Navigator.of(context).pushNamed<void>(
                                  AppRoutes.figmaCastManagement,
                                );
                              },
                            ),
                          ],
                        ),
                        // 服务与帮助：margin-top 86rpx(=43)。
                        const SizedBox(height: 43),
                        const Padding(
                          padding: _inset,
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              '服务与帮助',
                              style: _MineTextStyles.sectionTitle,
                            ),
                          ),
                        ),
                        const SizedBox(height: 9),
                        Padding(
                          padding: _inset,
                          child: _ServiceRow(
                            iconAsset: 'assets/images/mine-icon05.png',
                            fallbackIcon: Icons.menu_book_outlined,
                            title: '操作指南',
                            onTap: () {
                              Navigator.of(
                                context,
                              ).pushNamed<void>(AppRoutes.guide);
                            },
                          ),
                        ),
                        const SizedBox(height: 13),
                        Padding(
                          padding: _inset,
                          child: _ServiceRow(
                            iconAsset: 'assets/images/mine-icon04.png',
                            fallbackIcon: Icons.settings_outlined,
                            title: '设置',
                            onTap: () {
                              Navigator.of(
                                context,
                              ).pushNamed<void>(AppRoutes.settings);
                            },
                          ),
                        ),
                        const Spacer(),
                        Padding(
                          padding: _inset,
                          child: _MineTabBar(onOpenHome: onOpenHome),
                        ),
                        const SizedBox(height: 13),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// 全屏背景：`bg01.png`（小程序 mine 用 bg01）。加载失败回退渐变 + 画笔。
class _MineBackground extends StatelessWidget {
  const _MineBackground();

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/images/bg01.png',
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

/// 个人资料卡（小程序 `.profile-card`）：底图 `mine-header-bg01.png` +
/// 头像 `mine-header.png`（112rpx≈56）+ 昵称/ID + 右侧箭头。
class _ProfileCard extends StatelessWidget {
  const _ProfileCard({
    required this.nickName,
    required this.userId,
    required this.onTap,
    this.avatarUrl = '',
  });

  final String nickName;
  final String userId;
  final String avatarUrl;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AspectRatio(
        // 严格保持背景图比例 327:121，宽度随屏自适应、高度按比例算出。
        aspectRatio: 327 / 121,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 卡片底图铺满。
            Image.asset(
              'assets/images/mine-header-bg01.png',
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                return DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Colors.white.withValues(alpha: 0.82),
                        const Color(0xFFFFEEE6).withValues(alpha: 0.52),
                      ],
                    ),
                  ),
                );
              },
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 17, 0),
              child: Row(
                children: [
                  _Avatar(avatarUrl: avatarUrl),
                  const SizedBox(width: 17),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          nickName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: _MineTextStyles.profileName,
                        ),
                        if (userId.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Text(
                            'ID：$userId',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: _MineTextStyles.profileId,
                          ),
                        ],
                      ],
                    ),
                  ),
                  const Text(
                    '›',
                    style: TextStyle(
                      color: Color(0xFF777E88),
                      fontSize: 29,
                      fontWeight: FontWeight.w300,
                      height: 1,
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

/// 个人资料卡头像（`mine-header.png`，112rpx≈56 圆形）。
class _Avatar extends StatelessWidget {
  const _Avatar({this.avatarUrl = ''});

  /// 后端头像地址（真实用户数据，非静态资源）；为空或加载失败回退本地默认头像。
  final String avatarUrl;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 56,
      height: 56,
      clipBehavior: Clip.antiAlias,
      decoration: const BoxDecoration(shape: BoxShape.circle),
      child: avatarUrl.isNotEmpty
          ? Image.network(
              avatarUrl,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => _defaultAvatar(),
            )
          : _defaultAvatar(),
    );
  }

  Widget _defaultAvatar() {
    return Image.asset(
      'assets/images/mine-header.png',
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) {
        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFFFF7D36),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.person_rounded, color: Colors.white),
        );
      },
    );
  }
}

/// 常用功能宫格卡片（小程序 `.quick-card`，204×296rpx=102×148）：
/// 底图 `mine-bg02.png` + 图标（`mine-icon0x.png`，112rpx≈56）+ 标题 + 说明。
class _FeatureCard extends StatelessWidget {
  const _FeatureCard({
    required this.iconAsset,
    required this.fallbackIcon,
    required this.fallbackColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final String iconAsset;
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
      child: SizedBox(
        width: 102,
        height: 148,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 卡片底图铺满（圆角 20）。
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Image.asset(
                'assets/images/mine-bg02.png',
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.40),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.31),
                      ),
                    ),
                  );
                },
              ),
            ),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Image.asset(
                  iconAsset,
                  width: 56,
                  height: 56,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: fallbackColor.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Icon(fallbackIcon, color: fallbackColor, size: 28),
                    );
                  },
                ),
                const SizedBox(height: 11),
                Text(title, style: _MineTextStyles.cardTitle),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(subtitle, style: _MineTextStyles.cardSubtitle),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 服务与帮助行（小程序 `.service-row`，108rpx=54）：图标 + 文案 + 箭头。
class _ServiceRow extends StatelessWidget {
  const _ServiceRow({
    required this.iconAsset,
    required this.fallbackIcon,
    required this.title,
    required this.onTap,
  });

  final String iconAsset;
  final IconData fallbackIcon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 54,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.70),
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: Colors.white.withValues(alpha: 0.88)),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF7D94B5).withValues(alpha: 0.10),
              blurRadius: 19,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            Image.asset(
              iconAsset,
              width: 26,
              height: 26,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) {
                return Icon(
                  fallbackIcon,
                  color: const Color(0xFF4A98FF),
                  size: 24,
                );
              },
            ),
            const SizedBox(width: 14),
            Expanded(child: Text(title, style: _MineTextStyles.rowTitle)),
            const Text(
              '›',
              style: TextStyle(
                color: Color(0xFF777E88),
                fontSize: 26,
                fontWeight: FontWeight.w300,
                height: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}


/// 底部导航栏（与首页一致的胶囊样式；「我的」高亮）。
class _MineTabBar extends StatelessWidget {
  const _MineTabBar({required this.onOpenHome});

  final VoidCallback onOpenHome;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.74),
        borderRadius: BorderRadius.circular(999),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF7E96B8).withValues(alpha: 0.14),
            blurRadius: 25,
            offset: const Offset(0, 9),
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
                iconAsset: 'assets/images/tabbar-home01.svg',
                fallbackIcon: Icons.home_outlined,
                label: '首页',
                color: Color(0xFF777D86),
              ),
            ),
          ),
          const Expanded(
            child: _MineTabItem(
              iconAsset: 'assets/images/tabbar-mine02.svg',
              fallbackIcon: Icons.person_rounded,
              label: '我的',
              color: Color(0xFFFF6421),
            ),
          ),
        ],
      ),
    );
  }
}

class _MineTabItem extends StatelessWidget {
  const _MineTabItem({
    required this.iconAsset,
    required this.fallbackIcon,
    required this.label,
    required this.color,
  });

  final String iconAsset;
  final IconData fallbackIcon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SvgPicture.asset(
          iconAsset,
          width: 28,
          height: 28,
          placeholderBuilder: (context) =>
              Icon(fallbackIcon, color: color, size: 28),
        ),
        const SizedBox(height: 2),
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

  // page-nav title → 34rpx(=17) / weight 700 / #111111
  static const navTitle = TextStyle(
    color: Color(0xFF111111),
    fontSize: 17,
    fontWeight: FontWeight.w700,
    height: 1.2,
  );

  // .profile-name → 40rpx(=20) / weight 700 / #2a2d32
  static const profileName = TextStyle(
    color: Color(0xFF2A2D32),
    fontSize: 20,
    fontWeight: FontWeight.w700,
    height: 1,
  );

  // .profile-id → 24rpx(=12) / #808690
  static const profileId = TextStyle(
    color: Color(0xFF808690),
    fontSize: 12,
    fontWeight: FontWeight.w400,
    height: 1,
  );

  // .section-title → 32rpx(=16) / weight 700 / #2a2d32
  static const sectionTitle = TextStyle(
    color: Color(0xFF2A2D32),
    fontSize: 16,
    fontWeight: FontWeight.w700,
    height: 1,
  );

  // .quick-title → 28rpx(=14) / weight 500 / #2a2d32
  static const cardTitle = TextStyle(
    color: Color(0xFF2A2D32),
    fontSize: 14,
    fontWeight: FontWeight.w500,
    height: 1,
  );

  // .quick-desc → 22rpx(=11) / #777e88
  static const cardSubtitle = TextStyle(
    color: Color(0xFF777E88),
    fontSize: 11,
    fontWeight: FontWeight.w400,
    height: 1,
  );

  // .service-row text → 30rpx(=15) / weight 600 / #2a2d32
  static const rowTitle = TextStyle(
    color: Color(0xFF2A2D32),
    fontSize: 15,
    fontWeight: FontWeight.w600,
    height: 1.2,
  );
}
