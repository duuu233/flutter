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
/// 全部页面统一用同一张背景 `bg01.png`（对应小程序全屏 `.mock-bg__image`）。
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

/// `home-bg03.png` 的几何（rpx，量自 PNG alpha 通道，非目测）：
/// 画布 726×376，其中**卡面实体** 654×304，四周是烘焙进图的投影——
/// 左 36 / 右 36 / 上 28 / 下 44。注意投影**偏下、上下不对称**，
/// 所以整幅在卡面盒子里不能居中，得按 28:44 的比例往上偏。
///
/// 旧的 bg01(卡面) + bg02(投影) 两层叠加已被这一张替代：bg03 自带投影和
/// 40rpx 圆角，因此既不需要 ClipRRect，也不需要第二层图。
const double _kCardW = 654;
const double _kCardH = 304;
const double _kArtW = 726;
const double _kArtH = 376;

/// 卡面在整幅中的垂直对齐系数：上下投影 28:44 → Alignment.y ≈ -0.222。
/// 轮播视口内「卡面 vs 视口」和卡片内「整幅 vs 卡面盒」两处都用它，
/// 因为两者是同一个 28:44 比例的两种表述。
const double _kCardAlignY = (28 - 44) / (28 + 44);

/// 已连接设备卡片（小程序 `.device-carousel`）：
/// 卡片底图 `home-bg03.png`（726×376rpx，含投影）+ 左侧圆环 `home-icon02.png` +
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
          aspectRatio: _kCardW / _kArtH,
          child: PageView.builder(
            // 背景图的左右投影会超出卡面盒子；PageView 默认的
            // Clip.hardEdge 会在视口边缘把这部分裁掉。
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
            itemBuilder: (context, page) => Align(
              // 卡面盒子 = 卡面实体（654×304），投影由卡片内部往外溢出。
              // 在视口里按 28:44 偏上放，给下方更厚的投影留出空间。
              alignment: const Alignment(0, _kCardAlignY),
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
        const SizedBox(height: 20),
        _CarouselDots(count: widget.devices.length, activeIndex: _index),
      ],
    );
  }
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
        // 整幅底图（含投影）按比例往卡面盒子外溢出：横向各 (726-654)/2、
        // 纵向按 28:44 分配。用 Fractionally 而非写死的 -18px，是为了在任何
        // 屏宽下溢出量都随卡片一起缩放——固定 px 在宽屏上会和图对不上。
        // 盒子比例已等于图的比例，BoxFit.fill 此处等价于 cover/contain。
        // 不用 FilterQuality.high（三次立方采样）：底图本就接近显示尺寸，
        // 视觉无差异，但轮播滑动时每帧重采样的 GPU 成本显著更高。
        Positioned.fill(
          child: FractionallySizedBox(
            widthFactor: _kArtW / _kCardW,
            heightFactor: _kArtH / _kCardH,
            alignment: const Alignment(0, _kCardAlignY),
            child: Image.asset('assets/images/home-bg03.png', fit: BoxFit.fill),
          ),
        ),
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
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
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
              // 右侧设备信息。
              SizedBox(
                width: 138,
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
                      _HomeConnectButton(onTap: onConnect),
                    ],
                  ],
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
            Text(
              AppL10n.of(context).homeConnectBluetooth,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w500,
                height: 1,
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
    required this.fallbackIcon,
    required this.onTap,
  });

  final String title;
  final String subtitle;

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
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            subtitle,
                            maxLines: 1,
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
