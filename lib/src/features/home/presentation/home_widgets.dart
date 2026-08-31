part of 'home_page.dart';

// =============================================================================
// 首页系列的展示型（dumb）组件集合：无业务逻辑，只负责画 UI。
// 按使用场景分区：背景 / 通用控件 / 已绑定主视图 / 未绑定主视图 / 投屏入口 /
// 绑定设备流程。所有控件均为私有，仅供本 home_page 库内部使用。
// =============================================================================

// -----------------------------------------------------------------------------
// 背景：所有首页场景共用，铺满整屏。
// -----------------------------------------------------------------------------

/// 全屏背景：底色 + 背景图（[asset]，加载失败时回退到渐变光晕画笔）。
///
/// 全部页面统一用同一张背景 `bg02.jpg`（对应小程序全屏 `.mock-bg__image`）。
class _HomeBackground extends StatelessWidget {
  const _HomeBackground({required this.asset});

  final String asset;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: Color(0xFFF5F9FF)),
        _AssetImage(
          path: asset,
          fallback: const _SoftBackgroundPainterWidget(),
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

/// 底部导航栏（首页主视图底部，「首页 / AI助手 / 官方图库 / 我的」四格）。
///
/// 对齐小程序 `custom-tabbar`：白色半透明胶囊（圆角全圆 + 柔和投影），
/// 图标用 `tabbar-*.png`，首页态高亮 #ff6421、未选态 #777d86。
///
/// ⚠️ 2026-08-21 同步小程序：由四格收回**两格（首页 / 我的）**。原来中间两格是
/// 「AI助手」「官方图库」，它们本就不是 tab（各自 push 一个页面），现在入口统一收进
/// 首页六宫格（见 `home_main_view._castSection`），灰度开关 [kAiEntryEnabled] /
/// [kGalleryEntryEnabled] 跟着搬到那里，仍然有效。
/// ⚠️ 两个 tab **各画各的栏**，底栏的改动永远要同时改 `_MineTabBar`。
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
            child: _HomeTabItem(
              iconAsset: 'assets/images/tabbar-home02.png',
              fallbackIcon: Icons.home_rounded,
              label: AppL10n.of(context).tabHome,
              color: const Color(0xFFFF6421),
            ),
          ),
          // 2026-08-21 同步小程序：中间两格「AI助手」「官方图库」取消，
          // 两个入口都搬到首页六宫格（见 home_main_view._castSection）。底栏回到两格。
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onOpenMine,
              child: _HomeTabItem(
                iconAsset: 'assets/images/tabbar-mine01.png',
                fallbackIcon: Icons.person_outline_rounded,
                label: AppL10n.of(context).tabMine,
                color: const Color(0xFF777D86),
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

/// 顶部导航标题栏：与小程序 `page-nav` 一致，居中显示「首页」，背景透明。
class _HomeNavBar extends StatelessWidget {
  const _HomeNavBar({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: Center(
        child: Text(
          title,
          style: const TextStyle(
            color: Color(0xFF111111),
            fontSize: 17,
            fontWeight: FontWeight.w700,
            height: 1.25,
          ),
        ),
      ),
    );
  }
}

/// 电量百分比 → `BatteryLevel/battery-{档位}.png` 资源路径（每 10% 一档，就近取整）。
/// 与小程序 `utils/battery.js` 的 getBatteryIcon 一致。
String _batteryIconAsset(int level) {
  final value = level.clamp(0, 100);
  const levels = <int>[0, 10, 20, 30, 40, 50, 60, 70, 80, 90, 100];
  var nearest = levels.first;
  for (final candidate in levels) {
    if ((candidate - value).abs() < (nearest - value).abs()) {
      nearest = candidate;
    }
  }
  return 'assets/images/BatteryLevel/battery-$nearest.png';
}

// -----------------------------------------------------------------------------
// 「首页-已绑定设备」场景专用组件。
// -----------------------------------------------------------------------------

/// 顶部用户头像（小程序 `.avatar-btn`：72rpx=36 白底圆形）。
///
/// 优先显示真实头像 [avatarUrl]（网络图，对齐小程序 `home.js loadUserAvatar`）；无地址 /
/// 加载失败时回退本地 `mine-header.jpg`，再失败回退占位图标。[onTap] 非空时可点（换头像上传）。
class _Avatar extends StatelessWidget {
  const _Avatar({this.avatarUrl, this.localPath, this.onTap});

  final String? avatarUrl;
  final String? localPath;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final url = avatarUrl?.trim() ?? '';
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        clipBehavior: Clip.antiAlias,
        decoration: const BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
        ),
        child: localPath != null
            ? Image.file(
                File(localPath!),
                fit: BoxFit.cover,
                // 36lp 圆形头像，按物理像素解码（与下方网络头像 memCacheWidth 同理），
                // 避免本地回显把整张原尺寸位图解进内存。
                cacheWidth: (36 * MediaQuery.devicePixelRatioOf(context))
                    .round(),
                errorBuilder: (context, error, stackTrace) => _fallback(),
              )
            : url.isEmpty
            ? Image.asset(
                'assets/images/mine-header.jpg',
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => _fallback(),
              )
            : CachedNetworkImage(
                imageUrl: url,
                fit: BoxFit.cover,
                // 36lp 圆形头像，按物理像素解码，避免原图全尺寸位图进内存。
                memCacheWidth: (36 * MediaQuery.devicePixelRatioOf(context))
                    .round(),
                errorWidget: (context, imageUrl, error) => Image.asset(
                  'assets/images/mine-header.jpg',
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => _fallback(),
                ),
              ),
      ),
    );
  }

  Widget _fallback() {
    return Container(
      color: const Color(0xFFEAF4FF),
      child: const Icon(
        Icons.person_rounded,
        color: Color(0xFF8C9092),
        size: 22,
      ),
    );
  }
}

/// 右上角「添加设备」圆形按钮（小程序 `home-add-icon.png`，62rpx≈31）。
class _RoundAddButton extends StatelessWidget {
  const _RoundAddButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Image.asset(
        'assets/images/home-add-icon.png',
        width: 31,
        height: 31,
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
///
/// 对齐小程序：「BoltStar」为橙色加粗文字（非图片），与 `欢迎使用` 同一行。
class _GreetingTitle extends StatelessWidget {
  const _GreetingTitle();

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const Key('home-title'),
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('Hi', style: _HomeTextStyles.hi),
        const SizedBox(height: 9),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              AppL10n.of(context).homeGreetingWelcome,
              style: _HomeTextStyles.welcome,
            ),
            const SizedBox(width: 6),
            Image(
              image: const AssetImage('assets/images/logo.png'),
              width: 97,
              height: 20,
              fit: BoxFit.contain,
              errorBuilder: _brandFallback,
            ),
          ],
        ),
      ],
    );
  }

  static Widget _brandFallback(
    BuildContext context,
    Object error,
    StackTrace? stackTrace,
  ) => const Text('BoltStar', style: _HomeTextStyles.brand);
}

/// 设备卡的几何，逐项取自小程序 `home.wxss`（rpx ÷ 2 = dp）：
/// `.device-swiper` 高 372rpx、`.device-carousel` 654×298rpx、圆角 24px。
///
/// ⚠️ **2026-08-28：卡面底图 `home-bg03.png` 换成玻璃层**（需求 18）。
/// 原来整张卡面（白底 + 圆角 + 投影）都烘焙在那张 726×376 的 PNG 里，投影还上下不对称
/// （上 28 / 下 44），所以旧代码得靠 `_kArtW/_kArtH/_kCardAlignY` 一组系数把整幅往上偏着放。
/// 那张图是配**旧的暖白页面背景**画的；2026-08-21 全站背景换成浅蓝墙面后，卡面与墙面
/// 对不上，观感就是「设备卡的背景没了/不对」。
/// 小程序那边同一时期把卡片背景图整条注释掉了（`home.wxml` 的 `.device-carousel-bg`），
/// 改用 `.carousel-glass`：**只有毛玻璃 + 投影 + 24 圆角，不铺底色**（连那层渐变也注释了），
/// 背景换成什么墙面都自动融进去。这里照抄它，随之不再需要那组偏移系数。
const double _kCardW = 654;
const double _kCardH = 298;

/// 轮播视口高（小程序 `.device-swiper` 的 372rpx）：比卡面高，留给投影与上下呼吸。
const double _kViewportH = 372;

/// 卡片圆角（小程序 `.device-carousel` / `.carousel-glass` 的 `border-radius: 24px`，
/// 注意那里写的是 **px 不是 rpx**，所以就是 24）。
const double _kCardRadius = 24;

/// 相邻两张设备卡之间的间距。
///
/// ⚠️ 为什么需要它：轮播是 `viewportFraction: 1.0`（每页 = 视口宽），本来相邻页整张都在
/// 屏幕外；但 [PageView] 这里特意开了 `clipBehavior: Clip.none`（否则卡片投影会在视口
/// 边缘被裁掉），于是上一张/下一张的边缘会**画进两侧各 24 的页边距里**——能看见是对的，
/// 但两张卡就此紧紧贴在一起，中间一条缝都没有。
///
/// 解法是给每一页左右各内缩一半：卡片之间就空出这么宽，相邻那张仍露出
/// `24 − _kCardPeekGap/2` 的边。代价是卡面宽度少了 [_kCardPeekGap]（327 宽上约 3.7%），
/// 换掉「贴在一起」值得。
const double _kCardPeekGap = 12;

/// 卡内「左侧圆环图标」与「右侧设备信息」之间的**保底间距**。
///
/// ⚠️ 这条必须写死、不能再交给 `MainAxisAlignment.spaceAround` 去摊：
/// 小程序那边卡宽是按 rpx 等比的、比例恒定，spaceAround 摊出来的留白也就恒定；
/// App 这边卡宽 = 屏宽 − 固定内缩，**屏越窄留白越少**，360dp 的安卓机上直接摊没了
/// （实测中间只剩约 1.5px，观感就是图标和文字粘在一起）。
const double _kCardIconGap = 16;

/// 已连接设备卡片（小程序 `.device-carousel`）：
/// 玻璃卡面（[_CardGlass]）+ 左侧圆环 `home-device-thumb.png` +
/// 右侧设备信息（名称 / 蓝牙连接状态 / 电量）。
class _DeviceCarousel extends StatefulWidget {
  const _DeviceCarousel({
    required this.devices,
    required this.activeDeviceId,
    required this.onChanged,
    required this.onOpenDevices,
    required this.onConnectDevice,
  });

  final List<DeviceItem> devices;
  final String activeDeviceId;
  final ValueChanged<DeviceItem> onChanged;
  final VoidCallback onOpenDevices;
  final ValueChanged<DeviceItem> onConnectDevice;

  @override
  State<_DeviceCarousel> createState() => _DeviceCarouselState();
}

class _DeviceCarouselState extends State<_DeviceCarousel> {
  late int _index;
  late int _page;
  late final PageController _controller;

  @override
  void initState() {
    super.initState();
    _index = _indexFor(widget.activeDeviceId);
    _page = _initialPage(_index);
    _controller = PageController(initialPage: _page);
  }

  int _initialPage(int index) {
    if (widget.devices.length <= 1) {
      return index;
    }
    return widget.devices.length * 1000 + index;
  }

  int _indexFor(String id) {
    final index = widget.devices.indexWhere((device) => device.id == id);
    return index < 0 ? 0 : index;
  }

  @override
  void didUpdateWidget(covariant _DeviceCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.devices.isEmpty) {
      _index = 0;
      return;
    }
    final next = _indexFor(widget.activeDeviceId);
    final deviceCountChanged =
        oldWidget.devices.length != widget.devices.length;
    if ((next != _index || deviceCountChanged) &&
        next < widget.devices.length) {
      _index = next;
      _page = deviceCountChanged
          ? _initialPage(next)
          : _nearestPage(next, widget.devices.length);
      if (_controller.hasClients) {
        // didUpdateWidget 处于 build/element 更新阶段，而 jumpToPage 会**同步**派发
        // onPageChanged → onChanged(selectDevice) → notifyListeners，等于在构建期给
        // 根部 AnimatedBuilder 这个祖先 markNeedsBuild（debug 直接断言红屏、release
        // 产生不一致帧）。推迟到本帧结束后再跳，语义不变。
        final page = _page;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _controller.hasClients) {
            _controller.jumpToPage(page);
          }
        });
      }
    }
  }

  int _nearestPage(int index, int count) {
    var target = _page - (_page % count) + index;
    if (target - _page > count / 2) {
      target -= count;
    } else if (_page - target > count / 2) {
      target += count;
    }
    return target;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // 视口按比例，不写死高度：宽度取 padding 后的卡面宽（对齐上下文的 24 内缩），
        // 高度取「卡面宽 : 整幅高」= 654:376，正好容下卡面 + 上下投影。
        // 原来是 SizedBox(height: 186) 配一个随宽度缩放的 AspectRatio，两者不同步——
        // 375pt 下只余 0.5px 侥幸不裁，414pt 宽的机器投影已被裁掉约 8.5px。
        AspectRatio(
          aspectRatio: _kCardW / _kViewportH,
          child: PageView.builder(
            // 卡片投影会溢出卡面盒子；PageView 默认的 Clip.hardEdge 会在视口边缘把它裁掉。
            clipBehavior: Clip.none,
            controller: _controller,
            itemCount: widget.devices.length == 1 ? 1 : null,
            onPageChanged: (page) {
              // 卫语句：devices 为空时 `% 0` 直接抛错。当前上游（_buildBound 仅在
              // 有设备时渲染轮播）护住了，但解绑全部设备的边界时序不赌上游。
              if (widget.devices.isEmpty) {
                return;
              }
              _page = page;
              final index = page % widget.devices.length;
              setState(() => _index = index);
              widget.onChanged(widget.devices[index]);
            },
            itemBuilder: (context, page) => Padding(
              // 左右各内缩半条 [_kCardPeekGap]：相邻两张卡之间空出一条缝，
              // 不然 `clipBehavior: Clip.none` 让邻页画进页边距后会与本页贴死。
              padding: const EdgeInsets.symmetric(
                horizontal: _kCardPeekGap / 2,
              ),
              child: Align(
                // 卡面盒子 = 654×298，投影（0 4 16）由玻璃层往外溢出，上下对称留白即可
                //（旧的 28:44 偏移是配那张烘焙投影的 PNG 的，图撤了系数也一并撤）。
                alignment: Alignment.center,
                child: AspectRatio(
                  aspectRatio: _kCardW / _kCardH,
                  child: _ConnectedDeviceCard(
                    device: widget.devices[page % widget.devices.length],
                    onOpenDevices: widget.onOpenDevices,
                    onConnect: () => widget.onConnectDevice(
                      widget.devices[page % widget.devices.length],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        // ⚠️ 20 → 12（2026-08-31 调间距）：指示点是**轮播的一部分**，该贴着卡片。
        // 小程序 `.carousel-dots` 的 `margin-top: 30rpx` 本来就是注释掉的（=0），
        // 靠 swiper 视口比卡面高出来的那截（372−298=74rpx）自然垫开。
        // App 这边给到 20，结果指示点离卡远、离下面的六宫格近，两组内容黏在一起分不清。
        const SizedBox(height: 12),
        _CarouselDots(count: widget.devices.length, activeIndex: _index),
      ],
    );
  }
}

/// 设备卡的卡面（小程序 `.carousel-glass`）：**透明底 + 一层外投影**，没别的。
///
/// ⚠️ 2026-08-28 一次修正：上一版按 CSS 里写着的 `backdrop-filter: blur(10.55px)` 加了
/// [BackdropFilter]，观感仍然不对 —— 产品确认那块**就是透明的**（那条 backdrop-filter
/// 在微信/安卓 webview 上多半根本没生效，所以线上看到的一直是「透明 + 投影」）。
/// 去掉模糊还顺带省了 GPU：模糊要逐帧重算，而它就压在横滑的 [PageView] 里。
///
/// ⚠️ 2026-08-31 二次修正：**「透明底 + BoxShadow」在 Flutter 里画出来是一整张灰卡片**，
/// 不是一圈阴影 —— 成因与解法见 [_CardGlassPainter]。（同轮一度加过 1px 白描边，
/// 产品复看后确认**不要边框**，已撤。）
///
/// 投影按 `box-shadow: 0px 4px 16px rgba(60, 53, 16, 0.12)` 换算：
/// 偏移 (0,4)、模糊 16、色 `#3C3510` @12% = `0x1F3C3510`。
/// 模糊值直接用 CSS 的数值 —— 与本项目其它卡片的换算口径一致
///（Flutter 的 `blurRadius` 与 CSS 的 blur-radius 并非同一物理量，严格换算约是 ×0.87，
///  但全站都按 1:1 转，单独在这里换算反而与别处对不齐）。
class _CardGlass extends StatelessWidget {
  const _CardGlass();

  @override
  Widget build(BuildContext context) {
    return const CustomPaint(painter: _CardGlassPainter());
  }
}

/// 卡面的外阴影，**卡内保持全透明、没有描边**。
///
/// ⚠️ **2026-08-31 修「整个盒子都是灰的」**：上一版是
/// `DecoratedBox(BoxDecoration(borderRadius: …, boxShadow: [ … ]))` 且不给 `color`。
/// 那样写在 CSS 里是对的（`box-shadow` 会被浏览器裁掉盒内那部分，只留外沿一圈），
/// **但 Flutter 不裁**：`BoxShadow` 画的是一整块「按盒形状模糊过的实心圆角矩形」，
/// 垫在盒子底下；盒子自身没有底色，于是那整块模糊直接透出来 —— 观感就是
/// 一整张灰卡片，而不是一圈阴影。
///
/// 所以这里改成自己画：把画布裁成「卡面之外」，再画那块模糊圆角矩形 —— 只剩外沿一圈
/// 真正的投影，卡内一个像素都不涂，浅蓝墙面原样透上来。
///
/// ⚠️ **不要再加描边**（2026-08-31 需求原话「不要边框不要白色的 Border，只要阴影就可以了」）。
/// 同轮曾按「边框带点阴影」加过一圈白 0.9 的 1px 描边，产品复看后确认不要 ——
/// 与小程序 `.carousel-glass` 也一致：那边只有 box-shadow，没有 border。
class _CardGlassPainter extends CustomPainter {
  const _CardGlassPainter();

  /// 小程序 `.carousel-glass` 的 `box-shadow: 0px 4px 16px rgba(60, 53, 16, 0.12)`。
  static const Color _shadowColor = Color(0x1F3C3510);
  static const double _shadowBlur = 16;
  static const Offset _shadowOffset = Offset(0, 4);

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(_kCardRadius),
    );

    // ① 外阴影：先把画布裁成「整块 − 卡面」，模糊矩形就只在卡外沿显形。
    //    裁剪范围按模糊半径外扩，别把该显出来的那圈裁掉。
    final outside = Path.combine(
      PathOperation.difference,
      Path()..addRect((Offset.zero & size).inflate(_shadowBlur * 3)),
      Path()..addRRect(rrect),
    );
    canvas.save();
    canvas.clipPath(outside);
    canvas.drawRRect(
      rrect.shift(_shadowOffset),
      Paint()
        ..color = _shadowColor
        // CSS 的 blur-radius 与高斯 sigma 不是同一物理量，用 Flutter 自己的换算，
        // 与 BoxShadow 内部一致（否则同样的 16 画出来比别处的卡片糊一圈）。
        ..maskFilter = MaskFilter.blur(
          BlurStyle.normal,
          Shadow.convertRadiusToSigma(_shadowBlur),
        ),
    );
    canvas.restore();
  }

  // 无外部输入，画出来永远一样。
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _ConnectedDeviceCard extends StatelessWidget {
  const _ConnectedDeviceCard({
    required this.device,
    required this.onOpenDevices,
    required this.onConnect,
  });

  final DeviceItem device;
  final VoidCallback onOpenDevices;
  final VoidCallback onConnect;

  @override
  Widget build(BuildContext context) {
    // 「进设备列表」的透明手势层压在内容**下方**，卡内「连接蓝牙」按钮(opaque)自己拦截点击。
    // 不再用「整卡 GestureDetector 外层包裹」——那样与按钮的 GestureDetector 嵌套竞争，
    // 某些布局/裁剪下整卡手势会盖过按钮，点「连接蓝牙」反而跳进设备列表（用户反馈的 bug）。
    return Stack(
      clipBehavior: Clip.none,
      fit: StackFit.expand,
      children: [
        // 玻璃卡面（小程序 `.carousel-glass`）：投影 + 毛玻璃 + 24 圆角，**不铺底色**。
        const Positioned.fill(child: _CardGlass()),
        // 整卡点击（非按钮区域）进设备列表：透明手势层，压在内容之下、背景之上。
        // 上方的连接按钮(opaque)会拦截落在自己身上的点击，不会漏到这层。
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onOpenDevices,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          // ⚠️ **弹性布局**（2026-08-31 修「安卓上左右贴到一起」）：
          // 原来是 `spaceAround` + 右列写死 `maxWidth: 190`。这两个数是按 375dp 量的：
          // 卡片内容宽 = 屏宽 − 页内缩 48 − 卡内左右各 18；375dp 上是 291，
          // 减掉圆环 83 与右列 190 还剩 18，spaceAround 摊成中间 9、两端各 4.5，勉强够看。
          // 但 **360dp 的安卓机只剩 276**，83 + 190 = 273 —— 中间只剩 1.5px，就是「贴到一起」。
          //
          // 现在：左侧圆环定宽，中间给一条**写死的 [_kCardIconGap] 间距**（任何屏宽都保底），
          // 右列用 [Expanded] 吃掉剩下的全部宽度。窄屏不再挤（360dp 右列仍有 175），
          // 宽屏也不会因为 190 的上限而在中间空出一大块。
          child: Row(
            children: [
              // 左侧圆环图标（home-icon02.png，166rpx≈83）。
              Image.asset(
                'assets/images/home-device-thumb.png',
                width: 83,
                height: 83,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) {
                  return const SizedBox(
                    width: 78,
                    height: 78,
                    child: _DeviceOrbitMark(),
                  );
                },
              ),
              const SizedBox(width: _kCardIconGap),
              // 右侧设备信息：吃掉剩余全部宽度。
              //
              // 历史（留着免得有人又改回去）：这里曾写死 138，英文 "Connect Bluetooth"
              // 连图标带内边距要 150+，直接把按钮撑爆（按钮是 mainAxisSize.min 的内容宽，
              // 卡在父约束上）；2026-08-28 改成上限 190 治标，2026-08-31 索性改成 Expanded ——
              // 宽度由布局给，不再有任何按某一款屏幕量出来的魔数。
              // 列里的设备名本来就是 maxLines:1 + ellipsis，放宽也不会顶出去。
              Expanded(
                child: SizedBox(
                  height: 110,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      device.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _HomeTextStyles.deviceCardTitle,
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
                          errorBuilder: (context, error, stackTrace) {
                            return Icon(
                              Icons.bluetooth_rounded,
                              color: device.connected
                                  ? const Color(0xFF4A98FF)
                                  : const Color(0xFF777E88),
                              size: 14,
                            );
                          },
                        ),
                        const SizedBox(width: 7),
                        Text(
                          device.connected
                              ? AppL10n.of(context).homeConnected
                              : AppL10n.of(context).homeDisconnected,
                          style: _HomeTextStyles.deviceMeta.copyWith(
                            color: device.connected
                                ? const Color(0xFF287DFF)
                                : null,
                          ),
                        ),
                      ],
                    ),
                    if (device.connected) ...[
                      const SizedBox(height: 11),
                      Row(
                        children: [
                          if (device.hasBatteryReading) ...[
                            Image.asset(
                              _batteryIconAsset(device.batteryLevel),
                              width: 26,
                              fit: BoxFit.contain,
                              errorBuilder: (context, error, stackTrace) {
                                return const Icon(
                                  Icons.battery_2_bar_rounded,
                                  color: Color(0xFFFF6A24),
                                  size: 18,
                                );
                              },
                            ),
                            const SizedBox(width: 7),
                          ],
                          Text(
                            device.batteryLabel,
                            style: _HomeTextStyles.deviceMeta,
                          ),
                        ],
                      ),
                    ] else ...[
                      const SizedBox(height: 22),
                      // 按钮自己也别硬撑：宽度跟文案走，实在放不下就省略号，
                      // 绝不横向溢出（Row 的交叉轴是 start，这里用 Align 收窄到内容宽）。
                      Align(
                        alignment: Alignment.centerLeft,
                        child: _HomeConnectButton(onTap: onConnect),
                      ),
                    ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _HomeConnectButton extends StatelessWidget {
  const _HomeConnectButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 7),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          gradient: const LinearGradient(
            colors: [Color(0xFF2F95FF), Color(0xFF2079FC)],
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF2079FC).withValues(alpha: 0.28),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'assets/images/bluetooth-icon-white.png',
              width: 12,
              height: 12,
              errorBuilder: (context, error, stackTrace) => const Icon(
                Icons.bluetooth_rounded,
                size: 12,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 6),
            // Flexible + ellipsis 是最后一道保险：宽度已经跟着文案走（见上面那层
            // ConstrainedBox 的说明），万一将来某个语种更长，也只是省略号，不会溢出。
            Flexible(
              child: Text(
                AppL10n.of(context).homeConnectBluetooth,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  height: 1,
                ),
              ),
            ),
          ],
        ),
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

/// 设备轮播指示点（小程序 `.carousel-dots`）：每点 34×8rpx(=17×4)，间距 24rpx(=12)，
/// 选中 #ff6922、未选 #d7dce3。点数等于已绑定设备数（至少 1 个）。
class _CarouselDots extends StatelessWidget {
  const _CarouselDots({this.count = 1, this.activeIndex = 0});

  final int count;
  final int activeIndex;

  @override
  Widget build(BuildContext context) {
    final total = count < 1 ? 1 : count;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < total; i++) ...[
          if (i > 0) const SizedBox(width: 12),
          _Dot(
            color: i == activeIndex
                ? const Color(0xFFFF6922)
                : const Color(0xFFD7DCE3),
          ),
        ],
      ],
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 17,
      height: 4,
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
/// 首页六大入口宫格里的一张卡（2026-08-21 同步小程序改版）。
///
/// 小程序对应 `pages/home/home.wxml` 的 `.entry-card` + `home.wxss`：
/// 卡 206×220rpx、圆角 28rpx、半透明白 0.55 压在背景图上；卡内「图标 + 文案组」整体垂直居中，
/// 图标 66rpx、与文案间距 20rpx；文案行左边是标题(28rpx，每项主色)+副标题(18rpx)，右边是箭头徽标。
///
/// 宽度**不写死**：rpx 是按屏宽等比的单位（750rpx 恒等于屏幕宽度），把 206rpx 硬写成
/// 103 逻辑像素会在窄屏溢出（2026-08-05 真机踩过：360dp 机器上两张 159 的卡就超了）。
/// 所以宽度由外层三等分给出，这里只按 206:220 定高。
class _HomeEntryCard extends StatelessWidget {
  const _HomeEntryCard({
    required this.title,
    required this.subtitle,
    required this.color,
    required this.iconAsset,
    required this.arrowAsset,
    required this.titleFontSize,
    required this.fallbackIcon,
    required this.onTap,
  });

  final String title;
  final String subtitle;

  /// 标题字号：由 [_HomeMainView._entryTitleFontSize] 按**六张卡里最长的标题**统一算好传进来。
  /// ⚠️ 不要在这里读 [_HomeTextStyles.entryTitle] 的字号 —— 那是基准值，不是最终值；
  /// 各卡自己决定字号就会缩出六个不同大小。
  final double titleFontSize;

  /// 卡内**留给文案的横向开销**：卡宽减掉它，剩下的才是标题/副标题能用的宽度。
  /// [_HomeMainView._entryTitleFontSize] 按它反推共用字号 ——
  /// **改下面 build 里的 Padding / 箭头 SizedBox，必须同步改这个数**。
  ///
  /// 逐项：左内边距 10 + 右内边距 6 + 箭头槽位 25
  ///       − 箭头视觉右移 5 − 箭头素材四周透明留白 3 = 33
  ///
  /// ⚠️ 后两项是「**布局上占位、视觉上不占位**」的量，2026-08-31 之前漏算了，
  /// 结果算出来的可用宽度比实际窄 8px，共用字号被压小一档 ——
  /// 表现就是 "My Devices" / "My Uploads" 右边明明还空着一条却不肯变大。
  ///   · `Transform.translate(offset: Offset(5, 0))`：Transform **不影响布局**，
  ///     Row 照旧按 25 给箭头留位，箭头却画到了右边 5px 外，那 5px 是空的；
  ///   · 徽标素材 90×90 里白圆盘只占中间约 62，四周是透明阴影留白，
  ///     25 的画布显示出来的圆盘约 17，两侧各约 4 是透明的（保守只认 3）。
  static const double titleHorizontalReserve = 10 + 6 + 25 - 5 - 3;

  /// 每张卡的主色：标题文字色，与箭头徽标同色系（取自素材）。
  final Color color;
  final String iconAsset;
  final String arrowAsset;
  final IconData fallbackIcon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AspectRatio(
        aspectRatio: 206 / 220,
        child: DecoratedBox(
          decoration: BoxDecoration(
            // .entry-card：rgba(255,255,255,.55) + 圆角 28rpx=14 + 与设备卡同一套阴影
            color: Colors.white.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(14),
            boxShadow: const [
              BoxShadow(
                color: Color(0x1A3C3510),
                offset: Offset(0, 4),
                blurRadius: 16,
              ),
            ],
          ),
          child: Padding(
            // 内边距左 20rpx=10 / 右 12rpx=6（右侧是箭头徽标，自带透明留白、视觉上不贴边）
            padding: const EdgeInsets.only(left: 10, right: 6),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 33,
                  height: 33,
                  child: Image.asset(
                    iconAsset,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) =>
                        Icon(fallbackIcon, color: color, size: 30),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: _HomeTextStyles.entryTitle.copyWith(
                              color: color,
                              fontSize: titleFontSize,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            subtitle,
                            // ⚠️ 2026-08-31 需求：小标题**最多两行**，超出才省略号。
                            // 原来写死一行，英文副标题（"Generate images with AI" 这类）
                            // 几乎必被截成半句，等于没说。
                            // 卡高够：206:220 的比例下 360dp 上约 105，
                            // 图标 33 + 10 + 标题 ~16 + 4 + 两行副标题 ~22 ≈ 85，还余 20。
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: _HomeTextStyles.entrySubtitle,
                          ),
                        ],
                      ),
                    ),
                    // 徽标素材 90×90 里白圆盘只占中间约 62，四周是透明阴影留白，
                    // 所以画布 25（=50rpx）显示出来的圆盘约 17，与小程序一致；
                    // 那圈留白压进右内边距（小程序用 margin-right:-10rpx，这里靠 -5 的位移）。
                    Transform.translate(
                      offset: const Offset(5, 0),
                      child: SizedBox(
                        width: 25,
                        height: 25,
                        child: Image.asset(
                          arrowAsset,
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) => Icon(
                            Icons.play_arrow_rounded,
                            color: color,
                            size: 16,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
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
    required this.isCamera,
    required this.artAsset,
    required this.arrowAsset,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final bool isCamera;
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
        height: 64,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFF8F9FB),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Image.asset(
              artAsset,
              width: 49,
              height: 48,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) {
                return Icon(
                  isCamera
                      ? Icons.photo_camera_rounded
                      : Icons.photo_library_rounded,
                  color: isCamera
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
                  const SizedBox(height: 6),
                  Text(subtitle, style: _HomeTextStyles.sheetOptionBody),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Image.asset(
              arrowAsset,
              width: 59,
              height: 59,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) {
                return Icon(
                  Icons.arrow_forward_rounded,
                  color: isCamera
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

/// 蓝牙搜索雷达插画（对照小程序 `.radar-art`）：
/// 搜索中用动图 `search-devices.gif`，已发现 `device_found_art.png`，
/// 未发现 `device_not_found_art.png`；[dimmed] 在弹出扫描帮助时压暗。
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
        : failed
        ? 'assets/images/device_not_found_art.png'
        : 'assets/images/search-devices.gif';
    // 压暗直接用 Image 自带的 opacity（着色时混合，逐帧零额外成本），不要包
    // Opacity——它对每帧都在动的 GIF 会持续 saveLayer 离屏合成。
    return Image.asset(
      asset,
      fit: BoxFit.contain,
      opacity: dimmed ? const AlwaysStoppedAnimation(0.56) : null,
      errorBuilder: (context, error, stackTrace) {
        return const _RadarFallback();
      },
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

/// 「已搜索到设备」列表里的单台设备项，可选中（小程序 `.nearby-device`）。
class _FoundDeviceTile extends StatelessWidget {
  const _FoundDeviceTile({
    required this.device,
    required this.selected,
    required this.iconAsset,
    required this.onTap,
  });

  final DeviceItem device;
  final bool selected;
  final String iconAsset;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 64,
        padding: const EdgeInsets.symmetric(horizontal: 17),
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFFFFF7F2).withValues(alpha: 0.88)
              : Colors.white.withValues(alpha: 0.54),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected
                ? const Color(0xFFFF6421)
                : Colors.white.withValues(alpha: 0.86),
            width: selected ? 2 : 2,
          ),
        ),
        child: Row(
          children: [
            Image.asset(
              iconAsset,
              width: 48,
              height: 48,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) {
                return const Icon(
                  Icons.videocam_outlined,
                  color: Color(0xFFFF6A24),
                  size: 26,
                );
              },
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Text(
                _displayDeviceName(device),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFF2A2D32),
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  height: 1.2,
                ),
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 26,
              height: 26,
              child: selected
                  ? Image.asset(
                      'assets/images/selected-icon.png',
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) {
                        return Container(
                          decoration: const BoxDecoration(
                            color: Color(0xFFFF6421),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.check_rounded,
                            color: Colors.white,
                            size: 18,
                          ),
                        );
                      },
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  String _displayDeviceName(DeviceItem device) {
    // 真实设备名直接展示（后端 productName / 蓝牙广播名），不再做演示别名映射。
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
