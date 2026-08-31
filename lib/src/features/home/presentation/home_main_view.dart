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
    required this.onOpenUploads,
    required this.onOpenAi,
    required this.onOpenGallery,
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
  /// ⚠️ 2026-08-21 起首页不再显示这个标题（小程序同步去掉），弹层本身仍在——
  /// 投屏结果页等处仍会用到，回调保留不删。
  final VoidCallback onShowCastSheet;
  final VoidCallback onCamera;
  final VoidCallback onAlbum;

  /// 六宫格里另外四项（2026-08-21 同步小程序：底栏两格，其余入口收进首页）。
  final VoidCallback onOpenUploads;
  final VoidCallback onOpenAi;
  final VoidCallback onOpenGallery;

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
          child: _HomeTabBar(onOpenMine: onOpenMine),
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
        // ⚠️ **模块间距要保底，不能全交给 [Spacer]**（2026-08-31 修「六宫格贴着指示点」）。
        //
        // 原来这里是 `Spacer()` … 六宫格 … `Spacer()`，两个等权 —— 富余高度对半分。
        // 问题是这一屏在**安卓常见的 360×760 上本来就几乎没有富余**：
        // 内容约 594，可用高度约 623（还要再扣手势条），对半分下来上下各只剩十来 px，
        // 六宫格于是紧贴着轮播指示点。小程序那边这一段是**固定的**
        //（`.bound-home .entry-grid { margin-top: 40rpx }`），压根不参与分配。
        //
        // 现在：两处各给一个保底值（[_kDotsToGridGap] / [_kGridToTabGap]），
        // 富余高度再按 2:1 优先补给上面那段 —— 屏幕越高，两组内容分得越开，
        // 而不是把空档平摊到六宫格下面那块本来就不缺的地方。
        // 矮屏上保底值可能让内容略高于视口，交给外层的 SingleChildScrollView 滚一点点，
        // 这比「挤在一起」好（那层滚动本来就是为这种情况准备的）。
        const SizedBox(height: _kDotsToGridGap),
        const Spacer(flex: 2),
        ..._castSection(context),
        const SizedBox(height: _kGridToTabGap),
        // 还有富余就落在最后（Tab 栏已在滚动区外，这里只是内容与它之间的呼吸）。
        const Spacer(flex: 1),
      ],
    );
  }

  /// 轮播指示点 → 六宫格的**保底**间距。
  ///
  /// 参照小程序 `.bound-home .entry-grid` 的 `margin-top: 40rpx`（=20）再放宽一档：
  /// App 这边指示点上方还有 12 的间隔，两组内容之间需要更明确的断层才分得开。
  /// 嫌松/嫌紧改这一个数即可。
  static const double _kDotsToGridGap = 28;

  /// 六宫格 → 底部 Tab 栏的**保底**间距：别让卡片贴着 Tab 栏。
  static const double _kGridToTabGap = 16;

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

  /// 六宫格三列之间的中缝（小程序 18rpx）。
  static const double _entryGridGap = 9;

  /// 六张宫格卡标题的**共用字号**：按六条标题里最长的那条算，保证
  /// **六张一样大、且一条都不被截成「...」**。
  ///
  /// ⚠️ 2026-08-31 需求：英文版好几张卡的标题显示成「Camera Ca...」。
  /// 成因是标题写死 [_HomeTextStyles.entryTitle] 的字号 + `TextOverflow.ellipsis`，
  /// 而三列等分的卡宽在 360~375dp 上只给标题留 57~62 —— 英文词比中文长得多，必然截断。
  ///
  /// 两种改法里选了「算共用字号」而不是「每张卡各自 FittedBox 缩放」：后者六张卡会缩出
  /// 六个不同大小（长标题缩得多、短的不缩），正是 AI 工具栏那条反馈过的毛病。
  ///
  /// ⚠️ **不用 [LayoutBuilder] 量宽度**：首页内容外面套着
  /// `SingleChildScrollView + ConstrainedBox + IntrinsicHeight`（见 [_CollapsibleGap]），
  /// LayoutBuilder 量不出固有高度，放进去会在布局期直接抛错。
  /// 好在这里的卡宽是**确定可算**的：屏宽 − 左右各 24 的页内缩 − 两条 9 的中缝，再三等分。
  ///
  /// 中/繁/日词短、放得下 → 比例为 1，字号仍是基准值，与改动前逐像素相同；只有英文会真的缩。
  double _entryTitleFontSize(BuildContext context, List<String> titles) {
    final base = _HomeTextStyles.entryTitle.fontSize ?? 13;
    final media = MediaQuery.of(context);
    // 横向安全区在竖屏恒为 0，带上只是为了异形屏/横屏时不算错。
    final rowWidth =
        media.size.width - media.padding.horizontal - _cardInset.horizontal;
    final cardWidth = (rowWidth - _entryGridGap * 2) / 3;
    // 卡内留给标题的宽度 = 卡宽 − 左内边距 10 − 右内边距 6 − 右侧箭头徽标 25
    //（三个数与 [_HomeEntryCard] 的 Padding / SizedBox 一一对应，那边改了这里要跟着改）。
    final available = cardWidth - 10 - 6 - 25;
    if (available <= 0) {
      return base;
    }

    var scale = 1.0;
    final direction = Directionality.of(context);
    for (final title in titles) {
      final painter = TextPainter(
        text: TextSpan(
          text: title,
          style: _HomeTextStyles.entryTitle.copyWith(fontSize: base),
        ),
        maxLines: 1,
        textDirection: direction,
      )..layout();
      if (painter.width > 0) {
        final fit = available / painter.width;
        if (fit < scale) {
          scale = fit;
        }
      }
    }
    return base * (scale > 1 ? 1 : scale);
  }

  /// 两种场景共用的底部六宫格入口（2026-08-21 同步小程序改版）。
  ///
  /// 原来这里是「选择投屏方式」小标题 + 拍照/相册两张卡；改版后：
  /// - 小标题**去掉**（六项里已有四项与投屏无关，这句话把入口说窄了）；
  /// - 底栏的「AI助手」「官方图库」两格取消，连同「我的上传」「我的设备」一起收进 3×2 宫格。
  ///
  /// ⚠️ `kAiEntryEnabled` / `kGalleryEntryEnabled` 两个灰度开关**保留**（小程序侧已删）：
  /// App 是要过审、发版才能改的，关掉开关这一路退路不能丢。关掉时对应的卡整张不渲染，
  /// 宫格自然回落成 5 项（3 + 2），不留空位。
  List<Widget> _castSection(BuildContext context) {
    final l10n = AppL10n.of(context);
    // 六张卡的标题**共用一个字号**，按最长的那条算（见 [_entryTitleFontSize]）。
    // 必须在建卡之前先算：每张卡都要拿到同一个值。
    final titleFontSize = _entryTitleFontSize(context, <String>[
      l10n.homeEntryCameraTitle,
      l10n.homeEntryAlbumTitle,
      l10n.homeEntryUploadsTitle,
      if (kAiEntryEnabled) l10n.homeEntryAiTitle,
      if (kGalleryEntryEnabled) l10n.tabGallery,
      l10n.devMyDevicesTitle,
    ]);
    final entries = <_HomeEntryCard>[
      _HomeEntryCard(
        title: l10n.homeEntryCameraTitle,
        subtitle: l10n.homeCastCameraCardSubtitle,
        color: const Color(0xFFEE6242),
        iconAsset: 'assets/images/home-icon01.png',
        arrowAsset: 'assets/images/home-icon11.png',
        titleFontSize: titleFontSize,
        fallbackIcon: Icons.photo_camera_outlined,
        onTap: onCamera,
      ),
      _HomeEntryCard(
        title: l10n.homeEntryAlbumTitle,
        subtitle: l10n.homeCastAlbumCardSubtitle,
        color: const Color(0xFF3E92E8),
        iconAsset: 'assets/images/home-icon02.png',
        arrowAsset: 'assets/images/home-icon12.png',
        titleFontSize: titleFontSize,
        fallbackIcon: Icons.photo_library_outlined,
        onTap: onAlbum,
      ),
      _HomeEntryCard(
        title: l10n.homeEntryUploadsTitle,
        subtitle: l10n.homeEntryUploadsSubtitle,
        color: const Color(0xFF7B5FE8),
        iconAsset: 'assets/images/home-icon03.png',
        arrowAsset: 'assets/images/home-icon13.png',
        titleFontSize: titleFontSize,
        fallbackIcon: Icons.folder_open_outlined,
        onTap: onOpenUploads,
      ),
      if (kAiEntryEnabled)
        _HomeEntryCard(
          title: l10n.homeEntryAiTitle,
          subtitle: l10n.homeEntryAiSubtitle,
          color: const Color(0xFF11AE7B),
          iconAsset: 'assets/images/home-icon04.png',
          arrowAsset: 'assets/images/home-icon14.png',
          titleFontSize: titleFontSize,
        fallbackIcon: Icons.auto_awesome_outlined,
          onTap: onOpenAi,
        ),
      if (kGalleryEntryEnabled)
        _HomeEntryCard(
          title: l10n.tabGallery,
          subtitle: l10n.homeEntryGallerySubtitle,
          color: const Color(0xFFF0982B),
          iconAsset: 'assets/images/home-icon05.png',
          arrowAsset: 'assets/images/home-icon15.png',
          titleFontSize: titleFontSize,
        fallbackIcon: Icons.collections_outlined,
          onTap: onOpenGallery,
        ),
      _HomeEntryCard(
        title: l10n.devMyDevicesTitle,
        subtitle: l10n.homeEntryDevicesSubtitle,
        color: const Color(0xFF05A6B1),
        iconAsset: 'assets/images/home-icon06.png',
        arrowAsset: 'assets/images/home-icon16.png',
        titleFontSize: titleFontSize,
        fallbackIcon: Icons.devices_other_outlined,
        onTap: onOpenDevices,
      ),
    ];

    // 三列等分 + 9(=18rpx) 中缝、行距 12(=24rpx)。卡宽不写死的理由见 _HomeEntryCard：
    // rpx 是按屏宽等比的单位，写死逻辑像素会在窄屏溢出。
    const gap = _entryGridGap;
    final rows = <Widget>[];
    for (var i = 0; i < entries.length; i += 3) {
      final row = entries.skip(i).take(3).toList();
      rows.add(
        Row(
          children: [
            for (var j = 0; j < 3; j++) ...[
              if (j > 0) const SizedBox(width: gap),
              // 不足三项时用空占位补齐，剩下那一两张卡才不会被拉宽
              Expanded(child: j < row.length ? row[j] : const SizedBox.shrink()),
            ],
          ],
        ),
      );
      if (i + 3 < entries.length) {
        rows.add(const SizedBox(height: 12));
      }
    }

    return [
      Padding(
        padding: _cardInset,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: rows),
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
