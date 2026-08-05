import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../routes/app_routes.dart';
import '../../../shared/l10n/app_l10n.dart';
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

class _MinePageState extends State<MinePage> with RouteAware {
  static const _inset = EdgeInsets.symmetric(horizontal: 24);

  @override
  void initState() {
    super.initState();
    // 对齐小程序 mine.onShow：刷新用户资料 + 设备数 + 「我的相册」张数。
    // 不再判 isLoggedIn —— App 是强制登录的（见 bolt_star_app.dart），
    // 本页挂载时必然已登录，加判断只会让下面的 loaded 标记有翻不了身的风险。
    _reload();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 图库/设备/投屏都是 push 到**根** Navigator 的，盖在本页之上，本页不会被卸载；
    // 只有订阅路由事件才能在它们 pop 回来时重新拉数（见 didPopNext）。
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

  /// 被覆盖的页 pop 回来（如投屏/上传完再返回）：重新拉数，等价小程序 mine.onShow。
  ///
  /// 这是「上传图片后回我的，设备数字不更新」的根因：设备数取的是 `getUserInfo` 的
  /// `productCount`（账号级总数），而 `refreshDevices` **不会**更新该字段——
  /// 不重新打 `getUserInfo` 就永远是旧值。
  @override
  void didPopNext() {
    _reload();
  }

  void _reload() {
    // 三个接口并发：
    // · refreshCurrentUser —— 头像/昵称/ID 与设备数（账号级 productCount）；
    // · refreshDevices     —— productCount 缺失时的设备数兜底（state.mineDeviceCount）；
    // · refreshMineCastSuccessCount —— 「我的相册」张数 = 全部设备的投屏成功记录条数
    //   （2026-08-05 起不再用账号级 imgCount，所以这里也不必再拉相册列表）。
    widget.state.refreshCurrentUser();
    widget.state.refreshDevices();
    widget.state.refreshMineCastSuccessCount();
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
                        Text(
                          AppL10n.of(context).tabMine,
                          key: const Key('mine-page-title'),
                          textAlign: TextAlign.center,
                          style: _MineTextStyles.navTitle,
                        ),
                        // 个人资料卡：margin-top 72rpx(=36)。
                        const SizedBox(height: 24),
                        Padding(
                          padding: _inset,
                          child: _ProfileCard(
                            // 强制登录下不存在游客态，昵称为空只意味着 getUserInfo 还没回来，
                            // 用 `--` 占位（同下面的统计数字），不要写「未登录」。
                            nickName: state.currentUser.nickname.isNotEmpty
                                ? state.currentUser.nickname
                                : '--',
                            userId: state.currentUser.id,
                            avatarUrl: state.currentUser.avatarUrl,
                            // 点资料卡进个人资料页（原来还有个「未登录则进登录页」的分支，
                            // 强制登录后已不可达）。
                            onTap: () => Navigator.of(
                              context,
                            ).pushNamed<void>(AppRoutes.profile),
                          ),
                        ),
                        // 常用功能：margin-top 92rpx(=46)，标题底 24rpx(=12)。
                        const SizedBox(height: 46),
                        Padding(
                          padding: _inset,
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              AppL10n.of(context).mineCommonFeatures,
                              style: _MineTextStyles.sectionTitle,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        // 2026-08-04：原「设备照片」「投屏管理」两张卡合并为「我的相册」，
                        // 宫格由三卡变两卡。卡片改为**等分剩余宽度**（原来是 102 定宽 +
                        // space-evenly，两卡时中间会空出一大块），中缝 21rpx≈10.5，
                        // 与小程序 `.quick-grid { gap: 21rpx } .quick-card { flex: 1 1 0 }` 同口径。
                        Padding(
                          padding: _inset,
                          child: Row(
                            children: [
                              Expanded(
                                child: _FeatureCard(
                                  iconAsset: 'assets/images/mine-icon07.png',
                                  iconBackground: const Color(0xFFE7F2FF),
                                  fallbackIcon: Icons.devices_other_outlined,
                                  fallbackColor: const Color(0xFF4A98FF),
                                  title: AppL10n.of(context).mineMyDevices,
                                  subtitle: AppL10n.of(context)
                                      .mineDeviceCountText(
                                        state.userLoaded || state.devicesLoaded,
                                        state.mineDeviceCount,
                                      ),
                                  onTap: () {
                                    Navigator.of(
                                      context,
                                    ).pushNamed<void>(AppRoutes.figmaMyDevices);
                                  },
                                ),
                              ),
                              const SizedBox(width: 10.5),
                              Expanded(
                                child: _FeatureCard(
                                  iconAsset: 'assets/images/mine-icon06.png',
                                  iconBackground: const Color(0x1AFFAF8B),
                                  fallbackIcon:
                                      Icons.photo_size_select_actual_outlined,
                                  fallbackColor: const Color(0xFFFF6A24),
                                  title: AppL10n.of(context).mineMyGallery,
                                  subtitle: AppL10n.of(context)
                                      .minePhotoCountText(
                                        state.mineCastSuccessLoaded,
                                        state.minePhotoCount,
                                      ),
                                  onTap: () {
                                    Navigator.of(
                                      context,
                                    ).pushNamed<void>(AppRoutes.figmaGallery);
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                        // 服务与帮助：margin-top 86rpx(=43)。
                        const SizedBox(height: 43),
                        Padding(
                          padding: _inset,
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              AppL10n.of(context).mineServiceHelp,
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
                            title: AppL10n.of(context).mineGuide,
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
                            title: AppL10n.of(context).mineSettings,
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
/// 头像 `mine-header.jpg`（112rpx≈56）+ 昵称/ID + 右侧箭头。
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
                            AppL10n.of(context).mineUserId(userId),
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

/// 个人资料卡头像（`mine-header.jpg`，112rpx≈56 圆形）。
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
          ? CachedNetworkImage(
              imageUrl: avatarUrl,
              fit: BoxFit.cover,
              // 56lp 圆形头像，按物理像素解码，避免原图全尺寸位图进内存。
              memCacheWidth: (56 * MediaQuery.devicePixelRatioOf(context))
                  .round(),
              errorWidget: (context, url, error) => _defaultAvatar(),
            )
          : _defaultAvatar(),
    );
  }

  Widget _defaultAvatar() {
    return Image.asset(
      'assets/images/mine-header.jpg',
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

/// 常用功能宫格卡片（小程序 `.quick-card`，高 296rpx=148）：
/// 底图 `mine-bg02.png` + 图标（`mine-icon0x.png`，112rpx≈56）+ 标题 + 说明。
///
/// 2026-08-04 起宽度由外层 [Expanded] 等分决定（三卡→两卡），不再写死 102。
class _FeatureCard extends StatelessWidget {
  const _FeatureCard({
    required this.iconAsset,
    required this.iconBackground,
    required this.fallbackIcon,
    required this.fallbackColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final String iconAsset;
  final Color iconBackground;
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
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: iconBackground,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Image.asset(
                    iconAsset,
                    width: 34,
                    height: 34,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) =>
                        Icon(fallbackIcon, color: fallbackColor, size: 28),
                  ),
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
              child: _MineTabItem(
                iconAsset: 'assets/images/tabbar-home01.png',
                fallbackIcon: Icons.home_outlined,
                label: AppL10n.of(context).tabHome,
                color: const Color(0xFF777D86),
              ),
            ),
          ),
          Expanded(
            child: _MineTabItem(
              iconAsset: 'assets/images/tabbar-mine02.png',
              fallbackIcon: Icons.person_rounded,
              label: AppL10n.of(context).tabMine,
              color: const Color(0xFFFF6421),
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
        Image.asset(
          iconAsset,
          width: 24,
          height: 24,
          fit: BoxFit.contain,
          semanticLabel: label,
          errorBuilder: (context, error, stackTrace) =>
              Icon(fallbackIcon, color: color, size: 24),
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
