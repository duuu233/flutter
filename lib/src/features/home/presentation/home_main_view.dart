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
    required this.devices,
    required this.onBindDevice,
    required this.onAddDevice,
    required this.pendingAvatarPath,
    required this.onChangeAvatar,
    required this.onDeviceChanged,
    required this.onOpenDevices,
    required this.onConnectDevice,
    required this.onShowCastSheet,
    required this.onCamera,
    required this.onAlbum,
    required this.onOpenMine,
  });

  final PhotoFrameState state;

  /// 当前已连接设备；为空表示未绑定场景。
  final DeviceItem? activeDevice;
  final List<DeviceItem> devices;

  /// 未绑定场景点击「绑定设备」。
  final VoidCallback onBindDevice;

  /// 已绑定场景点击右上角「+」添加设备。
  final VoidCallback onAddDevice;

  /// 首页头像支持即时更换；选择中先显示本地临时图。
  final String? pendingAvatarPath;
  final VoidCallback onChangeAvatar;

  /// 首页设备轮播切换、点卡片进设备列表、未连接时点卡内按钮连接。
  final ValueChanged<DeviceItem> onDeviceChanged;
  final VoidCallback onOpenDevices;
  final ValueChanged<DeviceItem> onConnectDevice;

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
  static const _cardInset = EdgeInsets.symmetric(horizontal: 24);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _HomeNavBar(title: AppL10n.of(context).tabHome),
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
                _Avatar(
                  avatarUrl: state.currentUser.avatarUrl,
                  localPath: pendingAvatarPath,
                  onTap: onChangeAvatar,
                ),
                const Spacer(),
                _RoundAddButton(onTap: onAddDevice),
              ],
            ),
          ),
        ),
        const SizedBox(height: 35),
        const Padding(padding: _textInset, child: _GreetingTitle()),
        const SizedBox(height: 20),
        // 当前小程序：swiper 372rpx 高，内部卡片 654×298rpx，横向 48rpx 留白。
        Padding(
          padding: _cardInset,
          child: _DeviceCarousel(
            devices: devices,
            activeDeviceId: activeDevice!.id,
            onChanged: onDeviceChanged,
            onOpenDevices: onOpenDevices,
            onConnectDevice: onConnectDevice,
          ),
        ),
        const Spacer(),
        ..._castSection(context),
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
        const SizedBox(height: 95),
        const Center(
          child: SizedBox(width: 240, height: 189, child: _UnboundDeviceArt()),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: Text(
            AppL10n.of(context).homeUnboundHint,
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
              label: AppL10n.of(context).homeBindDevice,
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
        // const Spacer(flex: 6),
        const SizedBox(height: 68),
        ..._castSection(context),
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
  List<Widget> _castSection(BuildContext context) {
    return [
      Padding(
        padding: _textInset,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onShowCastSheet,
          child: Text(
            AppL10n.of(context).homeCastSheetTitle,
            style: _HomeTextStyles.sectionTitle,
          ),
        ),
      ),
      const SizedBox(height: 8),
      Padding(
        padding: _cardInset,
        // 两张卡**等分剩余宽度**，不再写死 159×155。
        //
        // 小程序 `.projection-card` 是 318×310rpx —— 而 rpx 是**按屏宽等比**的单位
        // （750rpx 恒等于屏幕宽度），并不是固定像素。「1rpx = 0.5px」这个换算只在
        // 375pt 宽的机型（iPhone 6/7/8）上成立。把 318rpx 硬写成 159 逻辑像素后：
        //   360dp 宽的机器 → 可用宽度 360-48=312 < 两张卡 159×2=318 → **溢出 6px**。
        // 这就是真机上宽度溢出的原因（iPhone 8 上刚好不溢出，所以不是每台都能复现）。
        //
        // 用 Expanded 等分 + 卡内 AspectRatio 保持 318:310 的原始宽高比，
        // 任何屏宽下都既不溢出、比例也与设计稿一致。中缝 18rpx≈9。
        child: Row(
          children: [
            Expanded(
              child: _CastEntryCard(
                title: AppL10n.of(context).homeCastCameraTitle,
                subtitle: AppL10n.of(context).homeCastCameraCardSubtitle,
                artAsset: 'assets/images/camera_material.png',
                arrowAsset: 'assets/images/home-icon05.png',
                backgroundAsset: 'assets/images/home-camera-card-bg.png',
                fallbackColor: const Color(0xFFFFF8F4),
                onTap: onCamera,
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: _CastEntryCard(
                title: AppL10n.of(context).homeCastAlbumTitle,
                subtitle: AppL10n.of(context).homeCastAlbumCardSubtitle,
                artAsset: 'assets/images/album_material.png',
                arrowAsset: 'assets/images/home-icon06.png',
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
