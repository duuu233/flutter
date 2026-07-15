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

/// 底部导航栏（首页主视图底部，「首页 / 我的」两个 Tab）。
///
/// 对齐小程序 `custom-tabbar`：白色半透明胶囊（圆角全圆 + 柔和投影），
/// 图标用 `tabbar-*.png`，首页态高亮 #ff6421、未选态 #777d86。
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
                errorBuilder: (context, error, stackTrace) => _fallback(),
              )
            : url.isEmpty
            ? Image.asset(
                'assets/images/mine-header.jpg',
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => _fallback(),
              )
            : Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => Image.asset(
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
<<<<<<< HEAD
        const Text('Hi', style: _HomeTextStyles.hi),
        const SizedBox(height: 9),
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: AppL10n.of(context).homeGreetingWelcome,
                style: _HomeTextStyles.welcome,
              ),
              const TextSpan(text: 'BoltStar', style: _HomeTextStyles.brand),
            ],
          ),
=======
        Text('Hi', style: _HomeTextStyles.hi),
        SizedBox(height: 9),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('欢迎使用', style: _HomeTextStyles.welcome),
            SizedBox(width: 6),
            Image(
              image: AssetImage('assets/images/logo.png'),
              width: 97,
              height: 20,
              fit: BoxFit.contain,
              errorBuilder: _brandFallback,
            ),
          ],
>>>>>>> 890cc97b41cb000834f5f79708465e466fd86adf
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

/// 已连接设备卡片（小程序 `.device-carousel`）：
/// 卡片底图 `home-bg01.png`（702×420rpx）+ 左侧圆环 `home-icon02.png` +
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
        _controller.jumpToPage(_page);
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
<<<<<<< HEAD
    // 对齐小程序 .device-carousel：圆角 24 + 阴影 0/4/16 rgba(60,53,16,.12) + 毛玻璃 blur(10.55)。
    return DecoratedBox(
      decoration: const BoxDecoration(
        borderRadius: BorderRadius.all(Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Color.fromRGBO(60, 53, 16, 0.12),
            offset: Offset(0, 4),
            blurRadius: 16,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10.55, sigmaY: 10.55),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // 卡片背景图铺满（home-bg01.png 自带圆角与玻璃质感）。
              Image.asset(
                'assets/images/home-bg01.png',
                fit: BoxFit.fill,
                errorBuilder: (context, error, stackTrace) {
                  return DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.85),
                      ),
                    ),
                  );
                },
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    // 左侧圆环图标（home-icon02.png，286rpx≈143）。
                    Image.asset(
                      'assets/images/home-icon02.png',
                      width: 143,
                      height: 143,
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) {
                        return const SizedBox(
                          width: 136,
                          height: 136,
                          child: _DeviceOrbitMark(),
                        );
                      },
                    ),
                    // 右侧设备信息。
                    Column(
                      mainAxisSize: MainAxisSize.min,
=======
    return Column(
      children: [
        SizedBox(
          height: 186,
          child: PageView.builder(
            controller: _controller,
            itemCount: widget.devices.length == 1 ? 1 : null,
            onPageChanged: (page) {
              _page = page;
              final index = page % widget.devices.length;
              setState(() => _index = index);
              widget.onChanged(widget.devices[index]);
            },
            itemBuilder: (context, page) => Center(
              child: AspectRatio(
                aspectRatio: 327 / 149,
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
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onOpenDevices,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          boxShadow: const [
            BoxShadow(
              color: Color(0x1F3C3510),
              blurRadius: 16,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 当前小程序同一张 OSS 卡片底图；加载期间/离线时回退本地资源。
            ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: Image.network(
                'https://oss.boltfox.cn/prodFile/202607072104114724571.png',
                fit: BoxFit.fill,
                loadingBuilder: (context, child, progress) =>
                    progress == null ? child : _cardBackgroundFallback(),
                errorBuilder: (context, error, stackTrace) =>
                    _cardBackgroundFallback(),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  // 左侧圆环图标（home-icon02.png，166rpx≈83）。
                  Image.asset(
                    'assets/images/home-icon02.png',
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
>>>>>>> 890cc97b41cb000834f5f79708465e466fd86adf
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
<<<<<<< HEAD
                              'assets/images/bluetooth-icon.png',
=======
                              device.connected
                                  ? 'assets/images/bluetooth-icon.png'
                                  : 'assets/images/bluetooth-icon-not.png',
>>>>>>> 890cc97b41cb000834f5f79708465e466fd86adf
                              width: 11,
                              height: 14,
                              fit: BoxFit.contain,
                              errorBuilder: (context, error, stackTrace) {
<<<<<<< HEAD
                                return const Icon(
                                  Icons.bluetooth_rounded,
                                  color: Color(0xFF4A98FF),
=======
                                return Icon(
                                  Icons.bluetooth_rounded,
                                  color: device.connected
                                      ? const Color(0xFF4A98FF)
                                      : const Color(0xFF777E88),
>>>>>>> 890cc97b41cb000834f5f79708465e466fd86adf
                                  size: 14,
                                );
                              },
                            ),
                            const SizedBox(width: 7),
                            Text(
<<<<<<< HEAD
                              device.connected
                                  ? AppL10n.of(context).homeConnected
                                  : AppL10n.of(context).homeDisconnected,
                              style: _HomeTextStyles.deviceMeta,
                            ),
                          ],
                        ),
                        const SizedBox(height: 11),
                        Row(
                          children: [
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
                            Text(
                              '${device.batteryLevel}%',
                              style: _HomeTextStyles.deviceMeta,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
=======
                              device.connected ? '已连接' : '未连接',
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
                              Text(
                                '${device.batteryLevel}%',
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
>>>>>>> 890cc97b41cb000834f5f79708465e466fd86adf
              ),
            ),
          ],
        ),
      ),
<<<<<<< HEAD
=======
    );
  }

  Widget _cardBackgroundFallback() {
    return Image.asset(
      'assets/images/home-bg01.png',
      fit: BoxFit.fill,
      errorBuilder: (context, error, stackTrace) => DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withValues(alpha: 0.85)),
        ),
      ),
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
            const Text(
              '连接蓝牙',
              style: TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w500,
                height: 1,
              ),
            ),
          ],
        ),
      ),
>>>>>>> 890cc97b41cb000834f5f79708465e466fd86adf
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
      child: AspectRatio(
        // 小程序 `.projection-card` 是 318×310rpx。宽度由外层 Expanded 等分屏宽给出
        // （rpx 本就是按屏宽等比的单位，写死 159 会在窄屏溢出，见 home_main_view 的说明），
        // 这里只负责按设计稿的原始宽高比 318:310 定高。
        // 阴影不来自图片透明边距，由下方 boxShadow 在卡外绘制，不计入布局尺寸。
        aspectRatio: 318 / 310,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 卡面层：圆角渐变底图 + 1px 白描边 + 0.64 半透明 + 柔和投影。
            // 对照前端 CSS：border-radius:20; border:1px solid #FFF; opacity:0.64;
            //              background:radial-gradient(...)（暖白/浅蓝已烘焙进底图）;
            //              box-shadow:0 3px 12px rgba(44,63,97,0.04)。
            // 投影放在最外层（全强度），卡面（描边+底图）整体 0.64，避免阴影一并被淡到不可见。
            DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                boxShadow: const [
                  BoxShadow(
                    color: Color.fromRGBO(44, 63, 97, 0.04),
                    offset: Offset(0, 3),
                    blurRadius: 12,
                  ),
                ],
              ),
              child: Opacity(
                opacity: 0.64,
                child: Container(
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white, width: 1),
                  ),
                  child: Image.asset(
                    backgroundAsset,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      // 兜底：底图缺失时用纯色近似卡面（暖白/浅蓝）。
                      return ColoredBox(color: fallbackColor);
                    },
                  ),
                ),
              ),
            ),
            // 内容层：左上素材图 + 底部「名称/描述 + 箭头」行，对照小程序 .projection-card
            // 的 flex 纵向流（.media-art 在上、.projection-copy 在下），按小程序数值换算留白。
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // `.media-art`：96rpx = 48；margin 28rpx 0 8rpx 34rpx。
                Padding(
                  padding: const EdgeInsets.only(top: 14, left: 17, bottom: 4),
                  child: SizedBox(
                    width: 48,
                    height: 48,
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
                          size: 44,
                        );
                      },
                    ),
                  ),
                ),
                // `.projection-copy` 左内边距 34rpx = 17；右侧为完整的 132rpx = 66 图标画布。
                Padding(
                  padding: const EdgeInsets.only(left: 17),
                  child: Row(
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
                              style: _HomeTextStyles.cardTitle,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: _HomeTextStyles.cardSubtitle,
                            ),
                          ],
                        ),
                      ),
                      Transform.translate(
                        // 对齐小程序 `translateY(4rpx)`，抵消图标内置阴影的透明留白。
                        offset: const Offset(0, 2),
                        child: SizedBox(
                          width: 66,
                          height: 66,
                          child: Image.asset(
                            arrowAsset,
                            fit: BoxFit.contain,
                            errorBuilder: (context, error, stackTrace) {
                              return Icon(
                                Icons.arrow_forward_rounded,
                                color: title == '拍照'
                                    ? const Color(0xFFFF6A24)
                                    : const Color(0xFF287BFF),
                                size: 30,
                              );
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
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
    return Opacity(
      opacity: dimmed ? 0.56 : 1,
      child: Image.asset(
        asset,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) {
          return const _RadarFallback();
        },
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
