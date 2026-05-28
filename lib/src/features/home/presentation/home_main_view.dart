part of 'home_page.dart';

/// 首页主视图（未进入绑定流程时显示，即 `_bindMode == none`）。
///
/// 内部按 [activeDevice] 是否为空再分两种场景：
/// - [activeDevice] != null → 「首页-已绑定设备」：头像、问候语、已连接设备卡、
///   设备轮播指示点。
/// - [activeDevice] == null → 「首页-未绑定设备」：空设备插画 +「绑定设备」按钮。
///
/// 两种场景底部共用「选择投屏方式」卡片区与底部 Tab 栏（见 [_castSection]）。
/// 整体用 `SingleChildScrollView + ConstrainedBox + IntrinsicHeight` 包裹：屏幕够高
/// 时用 `Spacer` 撑开布局，屏幕过矮时可滚动，避免溢出。所有交互通过回调上抛。
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

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: IntrinsicHeight(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: _bound ? _buildBound(context) : _buildUnbound(context),
              ),
            ),
          ),
        );
      },
    );
  }

  /// 「首页-已绑定设备」布局。
  Widget _buildBound(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        SizedBox(
          height: 34,
          child: Row(
            children: [
              const _Avatar(),
              const Spacer(),
              SizedBox(
                width: 30,
                height: 30,
                child: _RoundAddButton(onTap: onAddDevice),
              ),
            ],
          ),
        ),
        const SizedBox(height: 52),
        const _GreetingTitle(),
        const SizedBox(height: 25),
        SizedBox(
          width: double.infinity,
          height: 186,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: _ConnectedDeviceCard(device: activeDevice!),
              ),
              const Positioned(
                right: -130,
                top: 25,
                width: 154,
                height: 134,
                child: _SideCardHint(),
              ),
            ],
          ),
        ),
        const SizedBox(height: 31),
        const Center(child: _CarouselDots()),
        const Spacer(),
        ..._castSection(),
        const Spacer(),
        _HomeTabBar(onOpenMine: onOpenMine),
        const SizedBox(height: 12),
      ],
    );
  }

  /// 「首页-未绑定设备」布局。
  Widget _buildUnbound(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Spacer(flex: 3),
        const Center(
          child: SizedBox(width: 185, height: 116, child: _UnboundDeviceArt()),
        ),
        const SizedBox(height: 29),
        const SizedBox(
          width: double.infinity,
          child: Text(
            '请先绑定相框设备后再投屏照片',
            textAlign: TextAlign.center,
            style: _HomeTextStyles.mutedBody,
          ),
        ),
        const SizedBox(height: 8),
        Center(
          child: SizedBox(
            width: 200,
            height: 44,
            child: _GradientButton(
              label: '绑定设备',
              height: 44,
              fontSize: 16,
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
        const Spacer(flex: 4),
        ..._castSection(),
        const Spacer(),
        _HomeTabBar(onOpenMine: onOpenMine),
        const SizedBox(height: 12),
      ],
    );
  }

  /// 两种场景共用的底部「选择投屏方式」标题 + 拍照/相册两张入口卡。
  List<Widget> _castSection() {
    return [
      GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onShowCastSheet,
        child: const Text('选择投屏方式', style: _HomeTextStyles.sectionTitle),
      ),
      const SizedBox(height: 14),
      Row(
        children: [
          Expanded(
            child: _CastEntryCard(
              title: '拍照',
              subtitle: '拍摄照片并投屏',
              artAsset: 'assets/images/camera_material.png',
              arrowAsset: 'assets/images/Group 194521.png',
              backgroundAsset: 'assets/images/Rectangle 10457.png',
              fallbackColor: const Color(0xFFFFF8F4),
              onTap: onCamera,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: _CastEntryCard(
              title: '相册',
              subtitle: '选择照片并投屏',
              artAsset: 'assets/images/Group 194924.png',
              arrowAsset: 'assets/images/Group 194522.png',
              backgroundAsset: 'assets/images/Rectangle 10403.png',
              fallbackColor: const Color(0xFFEAF4FF),
              onTap: onAlbum,
            ),
          ),
        ],
      ),
    ];
  }
}
