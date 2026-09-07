import 'package:flutter/material.dart';

import '../../../routes/app_routes.dart';
import '../../../shared/l10n/app_l10n.dart';
import '../../../shared/widgets/app_toast.dart';
import '../../../shared/widgets/app_widgets.dart';
import '../../../shared/widgets/figma_common.dart';
import '../../../state.dart';
import 'official_gallery_api.dart';
import 'official_gallery_detail_page.dart';
import 'official_gallery_waterfall.dart';

/// 我的收藏（官方图库的收藏列表），对照小程序 `photo-album/subpackages/gallery/favorites`。
///
/// 与图库列表共用同一套瀑布流与角标；差别只有一个、但很关键：
/// **这里取消收藏后那张图要消失，所以必须重拉**；图库列表页则只能原地改状态
/// （重拉会把用户正看的卡片挪走）。
class OfficialGalleryFavoritesPage extends StatefulWidget {
  const OfficialGalleryFavoritesPage({super.key, required this.state});

  final PhotoFrameState state;

  @override
  State<OfficialGalleryFavoritesPage> createState() =>
      _OfficialGalleryFavoritesPageState();
}

class _OfficialGalleryFavoritesPageState
    extends State<OfficialGalleryFavoritesPage> {
  final ScrollController _scroll = ScrollController();

  List<OfficialPhoto> _photos = const [];
  bool _loading = true;
  bool _loadFailed = false;
  bool _loadingMore = false;
  bool _hasMore = false;
  int _pageIndex = 1;
  int _total = 0;
  bool _toggling = false;

  /// 端上量准的真实比例（图片 id → 宽/高），由 [_onRatioResolved] 记下。
  ///
  /// ⚠️ 本页尤其需要：**每次进页面都整页重拉**（取消收藏后那张要消失），从详情页返回也走这一遭。
  /// 重拉换回来的 photo 的 ratio 又是 0，而 `_PhotoCard` 的 State 按 id 复用、量过就不再量，
  /// 比例要是丢了，宽 > 高的横图就永远停在 3:4 的竖盒子里被 `BoxFit.cover` 放大裁切 ——
  /// 肉眼就是「返回之后图被拉长了」（2026-09-04 报障，与官方图库列表页、小程序两端同源同修）。
  final Map<int, double> _ratios = <int, double>{};

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _load();
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) {
      return;
    }
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadFailed = false;
    });
    try {
      final page = await OfficialGalleryApi.fetchFavorites(pageIndex: 1);
      if (!mounted) {
        return;
      }
      setState(() {
        _photos = _withKnownRatios(page.photos);
        _pageIndex = page.pageIndex;
        _hasMore = page.hasMore;
        _total = page.total;
        _loading = false;
        _loadingMore = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _photos = const [];
        _hasMore = false;
        _loading = false;
        _loadFailed = true;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loading || _loadingMore || !_hasMore) {
      return;
    }
    setState(() => _loadingMore = true);
    try {
      final page = await OfficialGalleryApi.fetchFavorites(
        pageIndex: _pageIndex + 1,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _photos = [..._photos, ..._withKnownRatios(page.photos)];
        _pageIndex = page.pageIndex;
        _hasMore = page.hasMore;
        _loadingMore = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() => _loadingMore = false);
      }
    }
  }

  /// 把已经量准的比例贴回新拉到的这批（后端不给比例，重拉回来的 ratio 恒为 0）。
  /// 没量过的保持 0，交给 3:4 占位 + 解码后校正那条老路。
  List<OfficialPhoto> _withKnownRatios(List<OfficialPhoto> photos) {
    if (_ratios.isEmpty) {
      return photos;
    }
    return photos.map((photo) {
      if (photo.ratio > 0) {
        return photo;
      }
      final known = _ratios[photo.id];
      return known == null ? photo : photo.copyWith(ratio: known);
    }).toList();
  }

  /// 图片加载完拿到的真实比例：只改这一张，同时记进 [_ratios] 供之后每次重拉复用。
  void _onRatioResolved(OfficialPhoto photo, double ratio) {
    if (!mounted || ratio <= 0) {
      return;
    }
    _ratios[photo.id] = ratio;
    final index = _photos.indexWhere((item) => item.id == photo.id);
    if (index < 0 || _photos[index].ratio > 0) {
      return;
    }
    setState(() {
      final next = [..._photos];
      next[index] = next[index].copyWith(ratio: ratio);
      _photos = next;
    });
  }

  /// 本页每一张按定义都是已收藏，点角标就是取消 → 那张图要消失 → 重拉整页。
  Future<void> _cancelFavorite(OfficialPhoto photo) async {
    if (_toggling) {
      return;
    }
    _toggling = true;
    final l10n = AppL10n.of(context);
    try {
      await OfficialGalleryApi.toggleFavorite(photo.id, true);
      if (!mounted) {
        return;
      }
      AppToast.show(context, l10n.galleryUnfavorited);
      await _load();
    } catch (_) {
      if (mounted) {
        AppToast.warn(context, l10n.galleryFavoriteFailed);
      }
    } finally {
      _toggling = false;
    }
  }

  Future<void> _openDetail(OfficialPhoto photo) async {
    await Navigator.of(context).push(
      AppPageRoute<void>(
        builder: (_) => OfficialGalleryDetailPage(
          state: widget.state,
          photoId: photo.id,
          fallbackTitle: photo.title,
          fallbackImageUrl: photo.url,
        ),
      ),
    );
    if (mounted) {
      // 详情页里可能取消了收藏，回来这张就该没了
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    return FigmaScreen(
      title: l10n.galleryFavoritesTitle,
      scrollable: false,
      bodyPadding: EdgeInsets.zero,
      background: Image.asset('assets/images/bg02.jpg', fit: BoxFit.cover),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!_loading && _photos.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2, bottom: 14),
              child: Text(
                l10n.galleryFavoriteCount(_total),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFF8B8F96),
                  fontSize: 14,
                  height: 1,
                ),
              ),
            ),
          Expanded(child: _buildBody(l10n)),
        ],
      ),
    );
  }

  Widget _buildBody(AppL10n l10n) {
    if (_loading) {
      return const PageLoading();
    }
    if (_loadFailed && _photos.isEmpty) {
      return PageLoadError(onRetry: _load);
    }
    if (_photos.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text(
            l10n.galleryFavoritesEmpty,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF9AA0A8),
              fontSize: 13,
              height: 1.5,
            ),
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: SingleChildScrollView(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            OfficialWaterfall(
              photos: _photos,
              onTapPhoto: _openDetail,
              onToggleFavorite: _cancelFavorite,
              onRatioResolved: _onRatioResolved,
            ),
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                _loadingMore
                    ? l10n.galleryLoading
                    : (_hasMore ? l10n.galleryPullMore : l10n.galleryNoMore),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFF9AA0A8),
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
