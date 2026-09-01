import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../routes/app_routes.dart';
import '../../../shared/l10n/app_l10n.dart';
import '../../../shared/permission_gate.dart';
import '../../../shared/widgets/app_toast.dart';
import '../../../shared/widgets/app_widgets.dart';
import '../../../shared/widgets/device_picker_sheet.dart';
import '../../../shared/widgets/figma_common.dart';
import '../../../shared/widgets/low_battery_tip.dart';
import '../../../state.dart';
import '../../cast/presentation/cast_preview_page.dart';
import '../../cast/recast_download.dart';
import 'official_gallery_api.dart';

/// 官方图库·图片详情，对照小程序 `photo-album/subpackages/gallery/detail`。
///
/// 版式：大图铺到状态栏（沉浸式，高度**按图片真实比例**算）→ 白卡从图上盖过来
/// （标题 + 收藏 + 简介）→ 贴底「开始投屏」。
///
/// 大图垫在滚动区**下面**、不跟着滚（往上滑只会让白卡盖住更多），所以「一屏放不下的部分」
/// 等于**永远看不到**。2026-09-01 产品要求「下面的文字不要挡住图片、整张图要完整展示、
/// 下面适当减少高度」，为此定死三条（与小程序 `detail.wxss` 的 --hero-max/--detail-card-min 同一套）：
///   ① 白卡顶 = 大图下沿，**不再往上压 3% 屏高**（压上去的那一条正好是图的下沿）；
///   ② 大图高度封顶在「屏高 − 底部文字区」，底部文字区收到 [_kCardMinHeight]（够放标题 + 两行简介
///      + 让开贴底按钮）而不是原来写死的 45% 屏高；
///   ③ 封顶后盒子比例不再等于图片比例，[BoxFit.cover] 会开始裁两边，所以改用 [BoxFit.contain]
///      —— 没被封顶时（绝大多数图）两者逐像素相同。
///
/// ⚠️ 「适用设备尺寸」那一块 2026-08-12 已按产品要求去掉（两端一致）：用户不按分辨率挑图，
/// 它只是把白卡撑高、把大图挤没了。接口仍下发 `productSizeList`，端上不解析。
///
/// 投屏与「我的相册」的再次投屏**同一条链路**：连设备 → 把图下载到本地 → 进 [CastPreviewPage]
/// 构图 →「开始投屏」照常出帧 + BLE 图传 + 建记录。预览页只接受本地路径，所以必须先下载。
class OfficialGalleryDetailPage extends StatefulWidget {
  const OfficialGalleryDetailPage({
    super.key,
    required this.state,
    required this.photoId,
    this.fallbackTitle = '',
    this.fallbackImageUrl = '',
  });

  final PhotoFrameState state;
  final int photoId;

  /// 列表已知的标题/原图：详情接口回来前先拿它顶上，进页面不至于空白一下。
  final String fallbackTitle;
  final String fallbackImageUrl;

  @override
  State<OfficialGalleryDetailPage> createState() =>
      _OfficialGalleryDetailPageState();
}

class _OfficialGalleryDetailPageState extends State<OfficialGalleryDetailPage> {
  OfficialPhotoDetail? _detail;
  bool _loading = true;
  bool _toggling = false;
  bool _projecting = false;

  /// 顶部大图的**真实**高宽比（高/宽）。首屏按 3:4 竖图占位（与列表 [OfficialGalleryApi
  /// .kDefaultRatio] 同源），图解码完按真实宽高校正这一张。
  ///
  /// ⚠️ 只能靠加载完的图去量：后端列表与详情**都不下发图片宽高**
  /// （见 [OfficialGalleryApi] 文件头缺口①）。
  double _heroAspect = 1 / OfficialGalleryApi.kDefaultRatio;

  /// 已经量过的那张图的 URL（详情回来前后 URL 会换一次，换了要重量）。
  String _measuredUrl = '';

  /// 极端比例钳制（对齐小程序 `heroPad` 的 `[40, 240]`）：太扁的图会让白卡几乎顶到
  /// 导航栏。⚠️ 2026-09-01 起「能不能看全图」由 [_kCardMinHeight] 那条封顶负责，
  /// 这两个钳位只剩「别把盒子算成离谱值」的兜底作用。
  static const double _kMinHeroAspect = 0.4;
  static const double _kMaxHeroAspect = 2.4;

  /// 底部文字区（白卡）最少要留多高：内边距 16 + 标题/收藏行 36 + 简介 11 + 两行 45 +
  /// 让开贴底「开始投屏」的 98 ≈ 206，取整 210；底部安全区另加。
  /// 与小程序 `--detail-card-min: 420rpx` 同一笔账（420rpx 在 375pt 屏上正是 210）。
  ///
  /// ⚠️ 它同时是大图的高度上限（屏高 − 它）。调小 = 图更大、文字区更挤；
  /// 调大 = 矮屏上更多图会被缩进框里（两侧留底色）。
  static const double _kCardMinHeight = 210;

  PhotoFrameState get state => widget.state;

  String get _title => _detail?.title ?? widget.fallbackTitle;
  String get _imageUrl =>
      (_detail?.url.isNotEmpty ?? false) ? _detail!.url : widget.fallbackImageUrl;
  bool get _favorited => _detail?.favorited ?? false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final detail = await OfficialGalleryApi.fetchDetail(widget.photoId);
      if (!mounted) {
        return;
      }
      if (detail == null) {
        AppToast.warn(context, AppL10n.of(context).galleryPhotoGone);
        Navigator.of(context).maybePop();
        return;
      }
      setState(() {
        _detail = detail;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() => _loading = false);
      AppToast.warn(context, AppL10n.of(context).galleryLoadFailed);
    }
  }

  /// 量出大图真实比例（后端不下发宽高，只能从解码后的图上取）。
  ///
  /// ⚠️ 与瀑布流那处同样的两个坑：图若已在缓存里，监听会**同步**触发，直接 setState
  /// 就是「build 期间 setState」；同一张量过一次就够，别在每次 build 里再挂监听。
  void _measureHero(String url) {
    if (url.isEmpty || url == _measuredUrl) {
      return;
    }
    _measuredUrl = url;
    final stream = CachedNetworkImageProvider(
      url,
    ).resolve(const ImageConfiguration());
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (image, synchronousCall) {
        stream.removeListener(listener);
        final w = image.image.width.toDouble();
        final h = image.image.height.toDouble();
        if (w <= 0 || h <= 0) {
          return;
        }
        final aspect = (h / w).clamp(_kMinHeroAspect, _kMaxHeroAspect);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && aspect != _heroAspect) {
            setState(() => _heroAspect = aspect);
          }
        });
      },
      onError: (error, stackTrace) => stream.removeListener(listener),
    );
    stream.addListener(listener);
  }

  Future<void> _toggleFavorite() async {
    final detail = _detail;
    if (detail == null || _toggling) {
      return;
    }
    _toggling = true;
    final l10n = AppL10n.of(context);
    try {
      final favorited = await OfficialGalleryApi.toggleFavorite(
        detail.id,
        detail.favorited,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _detail = OfficialPhotoDetail(
          id: detail.id,
          title: detail.title,
          desc: detail.desc,
          url: detail.url,
          favorited: favorited,
        );
      });
      AppToast.show(
        context,
        favorited ? l10n.galleryFavorited : l10n.galleryUnfavorited,
      );
    } catch (_) {
      if (mounted) {
        AppToast.warn(context, l10n.galleryFavoriteFailed);
      }
    } finally {
      _toggling = false;
    }
  }

  /// 「开始投屏」。已连接就直接用当前设备；未连接则先让用户选一台已绑定设备再连。
  Future<void> _startProjection() async {
    if (_projecting || _imageUrl.isEmpty) {
      return;
    }
    final l10n = AppL10n.of(context);
    final devices = state.devices;
    if (devices.isEmpty) {
      AppToast.show(context, l10n.galleryNoBoundDevice);
      return;
    }

    // 已连接的那台优先；都没连就弹选择框（与小程序 devicePicker 同一口径）。
    // ⚠️ 不用 firstOrNull：那是 package:collection 的扩展，本项目没引这个包。
    DeviceItem? target;
    for (final device in devices) {
      if (device.connected) {
        target = device;
        break;
      }
    }
    // ⚠️ 只有一台时也照样弹（2026-08-13）：投屏不可撤销，「只有一台就替他选」同样是端上
    // 替用户做了选择——用户按下「连接并投屏」之前，谁都不该开始往设备写图。
    target ??= await showDevicePickerSheet(context, devices: devices);
    if (target == null || !mounted) {
      return;
    }
    // 拷进 final 局部：下面既要读它、又要在闭包里用，避免依赖可变局部的类型提升
    final DeviceItem device = target;

    _projecting = true;
    setState(() {});
    try {
      // 权限门禁必须在 AppLoadingDialog **之前**（授权框与设备操作不同屏，见 PermissionGate 文档）
      if (!await PermissionGate.ensureBleReady(context) || !mounted) {
        return;
      }
      if (!device.connected) {
        AppLoadingDialog.show(context, l10n.castConnectingDevice);
        final ActionFeedback feedback;
        try {
          feedback = await state.connectDevice(device.id);
        } finally {
          // 不做 mounted 门控：页面在 await 期间被卸载时也要收掉蒙层
          AppLoadingDialog.hide(context);
        }
        if (!mounted) {
          return;
        }
        if (!feedback.success) {
          AppToast.warn(context, feedback.message);
          return;
        }
      }

      // 「连接并投屏」是主动操作：本来就连着 / 刚扫连上都提醒一次电量
      // （2026-08-27 补齐 08-21 遗留入口）。放在下载蒙层之前，不与蒙层抢屏。
      await showLowBatteryTipIfNeeded(context, state, device.id);
      if (!mounted) {
        return;
      }

      // 预览页只接受本地路径，远程图必须先下下来
      String? path;
      AppLoadingDialog.show(context, l10n.galRecastPreparing);
      try {
        path = await RecastDownload.toTempFile(_imageUrl);
      } finally {
        AppLoadingDialog.hide(context);
      }
      if (!mounted) {
        return;
      }
      final localPath = path;
      if (localPath == null) {
        AppToast.warn(context, l10n.castRecordImageDownloadFailed);
        return;
      }
      await Navigator.of(context).push(
        AppPageRoute<void>(
          builder: (_) => CastPreviewPage(
            state: state,
            // 重新按 id 取一次：连接过程中列表会被刷新，用最新那份的连接态/分辨率
            device: state.deviceById(device.id),
            imagePaths: [localPath],
          ),
        ),
      );
    } finally {
      _projecting = false;
      if (mounted) {
        setState(() {});
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final size = MediaQuery.of(context).size;
    final bottomInset = MediaQuery.of(context).padding.bottom;
    _measureHero(_imageUrl);
    // 大图**不裁**（2026-08-13，两端一致）：原来是「宽满屏 + 写死 58% 屏高 + cover」，
    // 两个比例对不上时 cover 会放大填满再把多出来的裁掉——横图裁上下、竖图裁左右，
    // 正是反馈里的「图片被压缩了」。现在盒子比例＝图片比例，一个像素都裁不掉。
    //
    // 2026-09-01 再封一次顶：大图不跟着滚，越过「屏高 − 底部文字区」的部分永远看不到，
    // 与其让长图的下半截落在屏幕外，不如把整张图缩进框里（配 BoxFit.contain）。
    // math.max 兜一手：窗口比底部文字区还矮时（桌面端把窗口拖到很小）差值会是负数，
    // 负高度会让 Positioned 直接断言崩掉。
    final maxHeroHeight = math.max(
      0.0,
      size.height - (_kCardMinHeight + bottomInset),
    );
    final heroHeight = math.min(size.width * _heroAspect, maxHeroHeight);
    // 白卡起点必须与大图**同源**：写死就会在图矮时露出一条底色、图高时提前盖住图。
    // 2026-09-01 起白卡顶 = 大图下沿（原来还往上压 3% 屏高，压住的正是图片下沿，
    // 产品要的「下面的文字不要挡住图片」说的就是这一条）。
    final spacerHeight = heroHeight;
    // 白卡一路铺到屏幕底部。⚠️ 别写死成「45% 屏高」——横图（图矮、留白也矮）时白卡下沿
    // 会停在屏幕中段，底下露出一条页面底色，贴底按钮浮在那条底色上。
    final cardMinHeight = size.height - spacerHeight;

    return Scaffold(
      backgroundColor: const Color(0xFFF8F5EF),
      body: Stack(
        children: [
          // 大图垫在最底层，滚动区透明、白卡滑上来时正好盖住它
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: heroHeight,
            // 底色兜在外层：封顶时 contain 会在两侧留出空档，露出的是这层灰
            //（与小程序 `.detail-hero { background: #dfe3e9 }` 同色），不是页面的米色。
            child: ColoredBox(
              color: const Color(0xFFDFE3E9),
              child: _imageUrl.isEmpty
                  ? const SizedBox.expand()
                  : CachedNetworkImage(
                      imageUrl: _imageUrl,
                      // ⚠️ 不能用 cover：盒子被 maxHeroHeight 压矮后比例不再等于图片比例，
                      // cover 会放大填满再裁掉两边。contain 在没被压矮时与 cover 逐像素相同。
                      fit: BoxFit.contain,
                      placeholder: (context, url) => const SizedBox.expand(),
                      errorWidget: (context, url, error) => const SizedBox.expand(),
                    ),
            ),
          ),
          SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(height: spacerHeight),
                Container(
                  constraints: BoxConstraints(minHeight: cardMinHeight),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                  ),
                  padding: EdgeInsets.fromLTRB(
                    24,
                    16,
                    24,
                    // 让开贴底的「开始投屏」：按钮是浮在上面的，不留出这段高度，
                    // 简介长一点就会从按钮底下穿过去
                    98 + MediaQuery.of(context).padding.bottom,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Text(
                              _title,
                              style: const TextStyle(
                                color: Color(0xFF2A2D32),
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                                height: 1.25,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          _FavoriteButton(
                            favorited: _favorited,
                            label: _favorited
                                ? l10n.galleryCancelFavorite
                                : l10n.galleryFavorite,
                            onTap: _loading ? null : _toggleFavorite,
                          ),
                        ],
                      ),
                      if ((_detail?.desc ?? '').isNotEmpty) ...[
                        const SizedBox(height: 11),
                        Text(
                          _detail!.desc,
                          style: const TextStyle(
                            color: Color(0xFF8B8F96),
                            fontSize: 14,
                            height: 1.6,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          // 顶栏压在大图上（沉浸式：只留返回键，标题白字会被浅色天空糊掉，索性不放标题）
          Positioned(
            top: MediaQuery.of(context).padding.top,
            left: 0,
            right: 0,
            child: const FigmaTopBar(title: '', showBack: true),
          ),
          Positioned(
            left: 24,
            right: 24,
            bottom: 20 + MediaQuery.of(context).padding.bottom,
            child: FigmaPrimaryButton(
              label: l10n.galleryStartCast,
              loading: _projecting,
              onPressed: _projecting ? null : _startProjection,
            ),
          ),
        ],
      ),
    );
  }
}

class _FavoriteButton extends StatelessWidget {
  const _FavoriteButton({
    required this.favorited,
    required this.label,
    required this.onTap,
  });

  final bool favorited;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 13),
        decoration: BoxDecoration(
          border: Border.all(
            color: favorited
                ? const Color(0xFFFF6A1E).withValues(alpha: 0.5)
                : const Color(0xFFA0A6AE).withValues(alpha: 0.5),
          ),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              favorited
                  ? 'assets/images/heart-solid.png'
                  : 'assets/images/heart-outline.png',
              width: 16,
              height: 16,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) => Icon(
                favorited ? Icons.favorite : Icons.favorite_border,
                size: 16,
                color: favorited
                    ? const Color(0xFFFE7B2D)
                    : const Color(0xFF9AA0A8),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: favorited
                    ? const Color(0xFFF2621F)
                    : const Color(0xFF2A2D32),
                fontSize: 14,
                height: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
