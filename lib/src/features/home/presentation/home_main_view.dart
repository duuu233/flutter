part of 'home_page.dart';

/// 首页主视图（未进入绑定流程时显示，即 `_bindMode == none`）。
///
/// 内部按 [activeDevice] 是否为空再分两种场景：
/// - [activeDevice] != null → 「首页-已绑定设备」：头像、问候语、已连接设备卡、
///   设备轮播指示点。
/// - [activeDevice] == null → 「首页-未绑定设备」：空设备插画 +「绑定设备」按钮。
///
/// 两种场景顶部共用居中「首页」标题栏，底部共用「选择投屏方式」卡片区与底部 Tab 栏
/// （见 [_castSection]）。整体用 `SingleChildScrollView + ConstrainedBox + IntrinsicHeight`
/// 包裹：屏幕够高时用 `Spacer` 撑开布局，屏幕过矮时可滚动，避免溢出。
///
/// 横向留白对齐小程序：文字内容区 48rpx(=24)，设备卡 / 投屏卡区 24rpx(=12)，
/// 因此不再使用统一外层 padding，而是按区块分别设置。
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

  /// 当前已连接设备；为空表示未绑定场景。
  final DeviceItem? activeDevice;

  /// 未绑定场景点击「绑定设备」。
  final VoidCallback onBindDevice;

  /// 已绑定场景点击右上角「+」添加设备。
  final VoidCallback onAddDevice;

  /// 点击「选择投屏方式」标题，弹出投屏方式选择层。
  final VoidCallback onShowCastSheet;
  final VoidCallback onCamera;
  final VoidCallback onAlbum;

  /// 点击底部「我的」Tab。
  final VoidCallback onOpenMine;

  bool get _bound => activeDevice != null;

  /// 文字内容区横向留白（48rpx）。
  static const _textInset = EdgeInsets.symmetric(horizontal: 24);

  /// 卡片区横向留白（24rpx）。
  static const _cardInset = EdgeInsets.symmetric(horizontal: 12);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const _HomeNavBar(title: '首页'),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: IntrinsicHeight(
                    child: _bound
                        ? _buildBound(context)
                        : _buildUnbound(context),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  /// 「首页-已绑定设备」布局。
  Widget _buildBound(BuildContext context) {
    // 设备轮播指示点：点数=已连接设备数，高亮当前设备。
    final connected = state.devices
        .where((device) => device.connected)
        .toList();
    final activeIndex = connected.indexWhere((d) => d.id == activeDevice!.id);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 5),
        Padding(
          padding: _textInset,
          child: SizedBox(
            height: 36,
            child: Row(
              children: [
                const _Avatar(),
                const Spacer(),
                _RoundAddButton(onTap: onAddDevice),
              ],
            ),
          ),
        ),
        const SizedBox(height: 35),
        const Padding(padding: _textInset, child: _GreetingTitle()),
        const SizedBox(height: 23),
        // 设备卡：702×420rpx，横向 24rpx 留白，保持 351:210 比例。
        Padding(
          padding: _cardInset,
          child: AspectRatio(
            aspectRatio: 351 / 210,
            child: _ConnectedDeviceCard(device: activeDevice!),
          ),
        ),
        const SizedBox(height: 18),
        Center(
          child: _CarouselDots(
            count: connected.length,
            activeIndex: activeIndex < 0 ? 0 : activeIndex,
          ),
        ),
        const Spacer(),
        ..._castSection(),
        const Spacer(),
        Padding(
          padding: _textInset,
          child: _HomeTabBar(onOpenMine: onOpenMine),
        ),
        const SizedBox(height: 13),
      ],
    );
  }

  /// 「首页-未绑定设备」布局。
  Widget _buildUnbound(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Spacer(flex: 4),
        const Center(
          child: SizedBox(width: 240, height: 189, child: _UnboundDeviceArt()),
        ),
        const SizedBox(height: 12),
        const SizedBox(
          width: double.infinity,
          child: Text(
            '请先绑定相框设备后再投屏照片',
            textAlign: TextAlign.center,
            style: _HomeTextStyles.mutedBody,
          ),
        ),
        const SizedBox(height: 24),
        Center(
          child: SizedBox(
            width: 200,
            height: 44,
            child: _GradientButton(
              label: '绑定设备',
              height: 44,
              fontSize: 15,
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
        ),
        const Spacer(flex: 6),
        ..._castSection(),
        const Spacer(),
        Padding(
          padding: _textInset,
          child: _HomeTabBar(onOpenMine: onOpenMine),
        ),
        const SizedBox(height: 13),
      ],
    );
  }

  /// 两种场景共用的底部「选择投屏方式」标题 + 拍照/相册两张入口卡。
  List<Widget> _castSection() {
    return [
      Padding(
        padding: _textInset,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onShowCastSheet,
          child: const Text('选择投屏方式', style: _HomeTextStyles.sectionTitle),
        ),
      ),
      const SizedBox(height: 8),
      Padding(
        padding: _cardInset,
        child: Row(
          children: [
            Expanded(
              child: _CastEntryCard(
                title: '拍照',
                subtitle: '拍摄照片并投屏',
                artAsset: 'assets/images/camera_material.png',
                arrowAsset: 'assets/images/home-camera-card-right-icon.png',
                backgroundAsset: 'assets/images/home-camera-card-bg.png',
                fallbackColor: const Color(0xFFFFF8F4),
                onTap: onCamera,
              ),
            ),
            // 不额外留间距：两张底图各自带约 12rpx 透明阴影边距，并排即形成
            // 与小程序一致的视觉间隙（小程序 .projection-grid 卡片溢出收缩后亦无显式间距）。
            Expanded(
              child: _CastEntryCard(
                title: '相册',
                subtitle: '选择照片并投屏',
                artAsset: 'assets/images/album_material.png',
                arrowAsset: 'assets/images/home-album-card-right-icon.png',
                backgroundAsset: 'assets/images/home-album-card-bg.png',
                fallbackColor: const Color(0xFFEAF4FF),
                onTap: onAlbum,
              ),
            ),
          ],
        ),
      ),
    ];
  }
}
