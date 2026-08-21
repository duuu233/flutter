part of 'home_page.dart';

/// 首页主视图（未进入绑定流程时显示，即 `_bindMode == none`）。
///
/// 内部按 [activeDevice] 是否为空再分两种场景：
/// - [activeDevice] != null → 「首页-已绑定设备」：头像、问候语、已连接设备卡、
///   设备轮播指示点。
/// - [activeDevice] == null → 「首页-未绑定设备」：空设备插画 +「绑定设备」按钮。
///
/// 两种场景顶部共用居中「首页」标题栏，底部共用「选择投屏方式」卡片区与底部 Tab 栏
/// （见 [_castSection]）。
///
/// 竖向结构（2026-08-05 调整，对齐小程序 `pages/home`）：
/// ```text
/// 标题栏                         ← 固定
/// Expanded(滚动区)               ← 只有中间内容进来
///   SingleChildScrollView + ConstrainedBox(minHeight: 视口) + IntrinsicHeight
/// 底部 Tab 栏                    ← 固定，永远在视口内
/// ```
/// 底部 Tab 栏**留在滚动区外**：小程序侧它是 `position: fixed` 的 `custom-tabbar`，
/// 本来就不跟着内容滚。之前它排在滚动内容的末尾，窗口一矮就被顶到视口以外，
/// 用户得先滚一段才能点到「我的」——正是 2026-08-05 反馈的「首页样式错乱、还自己出滚动条」。
///
/// 短窗口下的降级顺序：**先压可压缩间距（[_CollapsibleGap]），压完仍装不下才滚动**。
/// `IntrinsicHeight` 量到的是「间距压没之后的高度」，所以只要压一压能装下就不会出现滚动。
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
        // 底部 Tab 栏固定在滚动区外（同小程序的 fixed `custom-tabbar`）：
        // 无论内容多高，「我的」入口都在视口里，不会被内容顶出去。
        Padding(
          padding: _textInset,
          child: _HomeTabBar(state: state, onOpenMine: onOpenMine),
        ),
        const SizedBox(height: 13),
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
        // 末尾的 Spacer 吃掉剩余高度：Tab 栏已移到滚动区外，这里留白的观感与之前一致。
        const Spacer(),
      ],
    );
  }

  /// 「首页-未绑定设备」布局。
  ///
  /// 本页是全 App 最高的一屏（插画 189 + 提示 + 按钮 + 投屏卡片区），在 360×760 一类
  /// 常见 Android 机型上，按设计稿的固定间距排下来会比可用高度多出几十 dp。
  /// 顶部 95 与按钮下方 68 这两处纯留白因此改用 [_CollapsibleGap]：装得下时就是设计值
  /// （逐像素一致），装不下时按 95:68 的比例一起收缩，收缩到 0 仍装不下才交给滚动。
  Widget _buildUnbound(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Flexible(flex: 95, child: _CollapsibleGap(95)),
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
        const Flexible(flex: 68, child: _CollapsibleGap(68)),
        ..._castSection(context),
        // 末尾的 Spacer 吃掉剩余高度：Tab 栏已移到滚动区外，这里留白的观感与之前一致。
        const Spacer(),
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
                isCamera: true,
                artAsset: 'assets/images/camera_material.png',
                arrowAsset: 'assets/images/home-icon05.png',
                backgroundAsset: 'assets/images/home-camera-card-bg.png',
                onTap: onCamera,
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: _CastEntryCard(
                title: AppL10n.of(context).homeCastAlbumTitle,
                subtitle: AppL10n.of(context).homeCastAlbumCardSubtitle,
                isCamera: false,
                artAsset: 'assets/images/album_material.png',
                arrowAsset: 'assets/images/home-icon06.png',
                backgroundAsset: 'assets/images/home-album-card-bg.png',
                onTap: onAlbum,
              ),
            ),
          ],
        ),
      ),
    ];
  }
}

/// 可压缩留白：**够高时占满设计值（逐像素一致），不够高时按 flex 份额收缩**。
///
/// 必须放进 [Flexible]（`fit` 用默认的 loose），flex 取设计高度，多处间距之间
/// 就按设计比例分摊收缩量：
/// ```dart
/// const Flexible(flex: 95, child: _CollapsibleGap(95)),
/// ```
///
/// 与 `Flexible(child: SizedBox(height: 95))` 的唯一区别是**固有高度恒为 0**，
/// 而这正是本类存在的理由：首页内容外面套着
/// `SingleChildScrollView + ConstrainedBox(minHeight: 视口) + IntrinsicHeight`，
/// [IntrinsicHeight] 会把内容按**最大固有高度**定高——
/// 用 SizedBox 时固有高度里含着这 95/68 的留白，于是内容只要比视口高一点点，
/// 整页就直接进入滚动：`Spacer` 全部归零、元素挤成一坨、底部 Tab 栏被顶出视口
/// （2026-08-05 反馈的「首页样式错乱 + 自己出现滚动条」，未绑定态在 360×760
/// 一类机型上稳定复现）。
///
/// 固有高度记 0 之后，[IntrinsicHeight] 量到的是「留白压没之后仍需要的高度」：
/// - 视口 ≥ 该高度 → 内容高度 = 视口高，剩余空间按 flex 分配，
///   本类拿到的份额若 ≥ 设计值就取设计值（大屏与改动前完全一致），
///   否则按比例收缩（短窗口先让留白，不滚动）；
/// - 视口 < 该高度 → 留白压到 0 仍装不下，这时才真的滚动（横屏/分屏/超小窗口的兜底）。
class _CollapsibleGap extends LeafRenderObjectWidget {
  const _CollapsibleGap(this.height);

  /// 设计稿留白高度，也是本留白能占到的上限。
  final double height;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderCollapsibleGap(height);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderCollapsibleGap renderObject,
  ) {
    renderObject.designHeight = height;
  }
}

class _RenderCollapsibleGap extends RenderBox {
  _RenderCollapsibleGap(this._designHeight);

  double _designHeight;

  set designHeight(double value) {
    if (value == _designHeight) {
      return;
    }
    _designHeight = value;
    markNeedsLayout();
  }

  // 固有尺寸恒为 0：见类注释——外层 IntrinsicHeight 据此量出「压缩后的最小高度」。
  @override
  double computeMinIntrinsicWidth(double height) => 0;

  @override
  double computeMaxIntrinsicWidth(double height) => 0;

  @override
  double computeMinIntrinsicHeight(double width) => 0;

  @override
  double computeMaxIntrinsicHeight(double width) => 0;

  @override
  Size computeDryLayout(BoxConstraints constraints) => _sizeFor(constraints);

  @override
  void performLayout() {
    size = _sizeFor(constraints);
  }

  /// Flexible(loose) 给下来的 maxHeight 就是本项分到的份额：取「份额与设计值的较小者」。
  Size _sizeFor(BoxConstraints constraints) =>
      constraints.constrain(Size(0, _designHeight));
}
