import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../routes/app_routes.dart';
import '../../../shared/l10n/app_l10n.dart';
import '../../../state.dart';
import '../../star/star_coin_api.dart';

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
  /// 这是「上传图片后回我的，数字不更新」的根因：两张卡的数字取的都是 `getUserInfo` 的
  /// `productCount` / `imgCount`（账号级总数），别的接口**不会**更新这两个字段——
  /// 不重新打 `getUserInfo` 就永远是旧值。
  @override
  void didPopNext() {
    _reload();
  }

  void _reload() {
    // 只打一个接口：refreshCurrentUser（`GET /Client/User/getUserInfo`）——
    // 头像/昵称/ID、星币余额，以及**两张卡的数字**（设备数 `productCount`、
    // 上传数 `imgCount`）都在这一份出参里（2026-08-24 起，对齐小程序 mine.js）。
    //
    // 原先并发的另两个请求已去掉：`refreshDevices` 只是 productCount 缺失时的设备数兜底，
    // `refreshMineCastSuccessCount` 只是「我的相册」张数的老口径（投屏成功记录条数）。
    // 两个数字现在都只认后端这一份，进/回本页少打两个请求。
    widget.state.refreshCurrentUser().then((_) => _ensureStarBalance());
  }

  /// 「星币管理」行右侧的余额（对齐小程序 `mine.js` 的 `tokenBalance`）。
  ///
  /// 2026-08-11 接口对账起 `getUserInfo` 的出参已带 `availableToken`，本页**不再固定**
  /// 多打一次 `/Client/Order/getUserAccount`；只有该字段缺失（老后端灰度期不下发，
  /// 注意 0 是合法余额、不算缺失）才回退查一次账户。
  int? get _starBalance =>
      widget.state.currentUser.availableToken ?? _starBalanceFallback;

  /// 回退查到的余额。查失败就一直是 null，行里显示 `--`：
  /// 余额是次要信息，取不到不该弹错、更不该把整页打成加载失败。
  int? _starBalanceFallback;

  Future<void> _ensureStarBalance() async {
    // 每次进/回本页都重查一次（同小程序 onShow 口径）：余额会被 AI 生图消耗掉，
    // 缓存住第一次的数字会让用户以为星币没扣。只在 availableToken 缺失时才走到这里，
    // 所以正常后端下这条请求根本不会发出。
    if (!mounted || widget.state.currentUser.availableToken != null) {
      return;
    }
    try {
      final account = await StarCoinApi.fetchAccount();
      if (!mounted) {
        return;
      }
      setState(() => _starBalanceFallback = account.balance);
    } catch (_) {
      // 静默：见上。
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
          // 竖向结构与首页 [_HomeMainView] 一致：
          //   Expanded(滚动区) + 底部 Tab 栏（固定，永远在视口内）。
          // 2026-08-19 修：原来整页（含底栏）都塞在同一个 SingleChildScrollView 里，
          // 底栏只是被 `Spacer()` 顶到列末尾——屏幕够高时看着像固定在底部，一旦内容
          // 高过视口（iOS 刘海/灵动岛机型安全区吃掉一截、或系统字号放大），底栏就跟着
          // 内容一起滚，正是反馈的「底部 tabber 栏和页面滚动融合到一起」。
          child: Column(
            // 必须 stretch：底栏胶囊（`_MineTabBar`）自己不写宽度，靠父级给的紧约束铺满；
            // 默认的 center 会让它按内容缩成一小坨，滚动区也会跟着缩宽。
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return SingleChildScrollView(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: constraints.maxHeight,
                        ),
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
                            // 2026-08-19（同步小程序 08-11）：「常用功能」标题按产品要求
                            // 去掉，原先由标题承担的间距整块挪到宫格自己的 margin-top
                            // （小程序 `.quick-grid { margin: 92rpx 0 0 }` = 46）。
                            const SizedBox(height: 46),
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
                                            // 数字只来自 getUserInfo，所以「已出结果」
                                            // 只看 userLoaded（原先还看设备列表兜底）。
                                            state.userLoaded,
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
                                      title: AppL10n.of(context).mineMyUploads,
                                      subtitle: AppL10n.of(context)
                                          .minePhotoCountText(
                                            // 同上：2026-08-24 起张数取 getUserInfo 的
                                            // imgCount，不再等投屏记录计数出结果。
                                            state.userLoaded,
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
                            // 与小程序 `pages/mine/mine.wxml` 的 `.service-list` 逐行对齐：
                            // **星币管理 → 操作指南 → 设置**，三行不多不少。
                            // ⚠️ 「官方图库」2026-08-19 已挪到底栏第三格、「我的收藏」小程序
                            // 2026-08-12 起常驻在图库页分类条右端 —— 这两行都**不要**在这里
                            // 加回来：两个入口指同一个页面只会让人犹豫点哪个。
                            Padding(
                              padding: _inset,
                              child: _ServiceRow(
                                iconAsset: 'assets/images/mine-icon-token.png',
                                fallbackIcon: Icons.toll_outlined,
                                title: AppL10n.of(context).starCoinTitle,
                                // 右侧余额（小程序 `.service-value`「剩余 N 星币」）。
                                value: AppL10n.of(
                                  context,
                                ).mineStarBalanceText(_starBalance),
                                onTap: () {
                                  Navigator.of(
                                    context,
                                  ).pushNamed<void>(AppRoutes.starCoin);
                                },
                              ),
                            ),
                            const SizedBox(height: 13),
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
                            // 滚动区末尾留一段：内容顶到底时不会贴着下面的固定底栏。
                            const SizedBox(height: 13),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              // 底部 Tab 栏固定在滚动区外（同小程序 `position: fixed` 的 custom-tabbar），
              // 与首页 [_HomeMainView] 同一口径：内容再高，底栏也始终停在视口底部。
              Padding(
                padding: _inset,
                child: _MineTabBar(onOpenHome: onOpenHome),
              ),
              const SizedBox(height: 13),
            ],
          ),
        ),
      ],
    );
  }
}

/// 全屏背景：`bg02.jpg`（2026-08-21 起全站统一这张，见 figma_common.FigmaScreenBackground 的说明）。
/// 加载失败回退渐变 + 画笔。
class _MineBackground extends StatelessWidget {
  const _MineBackground();

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/images/bg02.jpg',
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
    this.value,
  });

  final String iconAsset;
  final IconData fallbackIcon;
  final String title;

  /// 右侧数值（小程序 `.service-value`，目前只有「星币管理」用）。null＝不画。
  final String? value;
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
            // 标题与数值同处一个 Expanded 里（2026-08-28 修「星币管理行的箭头没和上下对齐」）：
            // 原来是外层 Row 直接放 `Expanded(标题) + Flexible(数值) + 箭头`，两个 flex 子节点
            // 各分到一半余宽，而 Flexible 是 loose——数值只占自己那点宽，**没用完的那半**
            // 不会还给标题，Row 的 MainAxisAlignment.start 把它甩到最后，箭头因此被顶得
            // 离右边缘还差二三十像素，与没有数值的「操作指南 / 设置」两行对不齐。
            // 改成：外层只有一个 Expanded 吃满余宽，箭头必然贴在右内边距上（三行同一条线）；
            // 标题与数值在内层 Row 里 spaceBetween 分居两端，多余空隙落在两者之间。
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(child: Text(title, style: _MineTextStyles.rowTitle)),
                  if (value != null)
                    // 与小程序同款取舍：数值**过长时省略**（余额位数多、英文「stars left」更长），
                    // 而不是把标题或右侧箭头顶出行外。左右留白 24rpx/16rpx(=12/8)。
                    Flexible(
                      child: Padding(
                        padding: const EdgeInsets.only(left: 12, right: 8),
                        child: Text(
                          value!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.right,
                          style: _MineTextStyles.rowValue,
                        ),
                      ),
                    ),
                ],
              ),
            ),
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

/// 底部导航栏（与首页一致的胶囊样式，**两格**；「我的」高亮）。
///
/// ⚠️ 2026-08-21 同步小程序：中间的「AI助手」「官方图库」两格取消，入口收进首页六宫格。
/// 两个 tab **各画各的栏**，所以底栏的改动永远要同时改首页的 `_HomeTabBar`。
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
          // 2026-08-21 同步小程序：中间两格「AI助手」「官方图库」取消，
          // 入口都在首页六宫格（见 home_main_view._castSection）。底栏回到两格。
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
        // 2026-08-19 底栏由两格扩到四格后，每格只剩屏宽的四分之一：中文放得下，
        // 英/日的「Gallery / AIアシスタント」在窄屏上会顶出格子（Flutter 的表现是
        // 黄黑条纹的 overflow 警示）。FittedBox 只在真放不下时按比例缩，中文一律原样，
        // 比切成省略号（「AIアシス…」）好读。
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              maxLines: 1,
              softWrap: false,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w400,
                height: 1.2,
              ),
            ),
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

  // .service-row .service-value → 26rpx(=13) / weight 400 / #777e88
  static const rowValue = TextStyle(
    color: Color(0xFF777E88),
    fontSize: 13,
    fontWeight: FontWeight.w400,
    height: 1.2,
  );
}
