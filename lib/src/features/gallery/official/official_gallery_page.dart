import 'package:flutter/material.dart';

import '../../../routes/app_routes.dart';
import '../../../shared/l10n/app_l10n.dart';
import '../../../shared/widgets/app_toast.dart';
import '../../../shared/widgets/app_widgets.dart';
import '../../../shared/widgets/figma_common.dart';
import '../../../state.dart';
import 'official_gallery_api.dart';
import 'official_gallery_detail_page.dart';
import 'official_gallery_favorites_page.dart';
import 'official_gallery_waterfall.dart';

/// 官方图库，对照微信小程序 `photo-album/subpackages/gallery/list`
/// （2026-08-12 App 侧补齐该模块；小程序 2026-08-06 上线、同日切真实后端）。
///
/// 结构：分类横滑条（首项是端上补的「全部」）+ 右端固定的「收藏」入口 → 两列瀑布流 → 上拉续页。
///
/// ⚠️ 「收藏」入口**不在横滑区里**：写进去就会跟着分类一起被滑走。样式也刻意与分类胶囊分家
/// （竖分隔线 + 红心 + 橙字），否则挤在一行里像是「最后一个分类」——小程序首版正是栽在这。
class OfficialGalleryPage extends StatefulWidget {
  const OfficialGalleryPage({super.key, required this.state});

  final PhotoFrameState state;

  @override
  State<OfficialGalleryPage> createState() => _OfficialGalleryPageState();
}

class _OfficialGalleryPageState extends State<OfficialGalleryPage> {
  final ScrollController _scroll = ScrollController();

  List<OfficialCategory> _categories = const [];
  int _activeCategoryId = 0;
  List<OfficialPhoto> _photos = const [];
  Set<int> _favoriteIds = <int>{};

  bool _loading = true;
  bool _loadFailed = false;
  bool _loadingMore = false;
  bool _hasMore = false;
  int _pageIndex = 1;

  /// 收藏切换在途锁：连点会对同一张图切两次，最后一次的结果还可能先回来。
  bool _toggling = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _loadCategories();
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
    // 提前 200 拉下一页：瀑布流卡片高，贴到底再拉会让用户看见一段空白
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  Future<void> _loadCategories() async {
    setState(() {
      _loading = true;
      _loadFailed = false;
    });
    try {
      final categories = await OfficialGalleryApi.fetchCategories();
      if (!mounted) {
        return;
      }
      setState(() {
        _categories = categories;
        // 首项是「全部」（id=0）
        _activeCategoryId = categories.isEmpty ? 0 : categories.first.id;
      });
      await _loadPhotos(_activeCategoryId);
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _loadFailed = true;
      });
    }
  }

  /// 拉某个分类的第一页。收藏态与图片并行取（见 official_gallery_api.dart 缺口②）。
  ///
  /// [silent]＝背景刷新：**不清屏、不显示整页加载中**，数据回来才替换。
  /// 从详情页/收藏页返回时的收藏态对账走这条——把用户正看着的一屏清成「加载中…」
  /// 再长回来，比不刷新还难受。失败也只是保持现状，不弹错误页。
  ///
  /// 非 silent（切分类、首屏、下拉重试）则**先清空再拉**：留着上一分类的图 + 一行
  /// 「加载中…」，等于用户点了 A 却还在看 B。
  Future<void> _loadPhotos(int categoryId, {bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _loadFailed = false;
        _photos = const [];
        _hasMore = false;
        _pageIndex = 1;
      });
    }
    try {
      final results = await Future.wait([
        OfficialGalleryApi.fetchPhotos(categoryId: categoryId, pageIndex: 1),
        OfficialGalleryApi.fetchFavoriteIds(),
      ]);
      if (!mounted || _activeCategoryId != categoryId) {
        return; // 切分类期间又切走了，回来的数据不再覆盖当前分类
      }
      final page = results[0] as OfficialPhotoPage;
      final favoriteIds = results[1] as Set<int>;
      setState(() {
        _favoriteIds = favoriteIds;
        _photos = _markFavorites(page.photos, favoriteIds);
        _pageIndex = page.pageIndex;
        _hasMore = page.hasMore;
        _loading = false;
        _loadingMore = false;
      });
    } catch (_) {
      if (!mounted || _activeCategoryId != categoryId) {
        return;
      }
      if (silent) {
        return; // 背景刷新失败不动现状：屏上那批仍是上一次拉到的真数据
      }
      setState(() {
        _photos = const [];
        _hasMore = false;
        _loading = false;
        _loadFailed = true;
      });
    }
  }

  /// 上拉续页：**往列表尾部追加**。瀑布流的分列在 [OfficialWaterfall] 里按累计高度算，
  /// 追加不会动已经在屏上的卡片顺序。
  Future<void> _loadMore() async {
    if (_loading || _loadingMore || !_hasMore) {
      return;
    }
    final categoryId = _activeCategoryId;
    setState(() => _loadingMore = true);
    try {
      final page = await OfficialGalleryApi.fetchPhotos(
        categoryId: categoryId,
        pageIndex: _pageIndex + 1,
      );
      if (!mounted || _activeCategoryId != categoryId) {
        return;
      }
      setState(() {
        _photos = [..._photos, ..._markFavorites(page.photos, _favoriteIds)];
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

  List<OfficialPhoto> _markFavorites(
    List<OfficialPhoto> photos,
    Set<int> favoriteIds,
  ) {
    if (favoriteIds.isEmpty) {
      return photos;
    }
    return photos
        .map((photo) => photo.copyWith(favorited: favoriteIds.contains(photo.id)))
        .toList();
  }

  void _onSelectCategory(int categoryId) {
    if (categoryId == _activeCategoryId) {
      return;
    }
    setState(() => _activeCategoryId = categoryId);
    _loadPhotos(categoryId);
  }

  /// 图片加载完拿到的真实比例：只改这一张的 ratio（进而改它的高度），**不重新排序**。
  void _onRatioResolved(OfficialPhoto photo, double ratio) {
    if (!mounted || ratio <= 0) {
      return;
    }
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

  /// 卡片右上角红心：就地切收藏态。
  ///
  /// 与「我的收藏」页的差别只有一处、但很关键：收藏页取消后那张图要消失、必须重拉；
  /// **本页不能重拉** —— 收藏与否图都还在列表上，重拉会让瀑布流按新数据重排，
  /// 把用户正在看的卡片挪走。所以这里只改那一张。
  ///
  /// 先请求成功再改 UI（不做乐观更新）：失败时红心闪一下又弹回去，比慢 200ms 更难受。
  Future<void> _toggleFavorite(OfficialPhoto photo) async {
    if (_toggling) {
      return;
    }
    _toggling = true;
    final l10n = AppL10n.of(context);
    try {
      final favorited = await OfficialGalleryApi.toggleFavorite(
        photo.id,
        photo.favorited,
      );
      if (!mounted) {
        return;
      }
      final index = _photos.indexWhere((item) => item.id == photo.id);
      if (index >= 0) {
        setState(() {
          final next = [..._photos];
          next[index] = next[index].copyWith(favorited: favorited);
          _photos = next;
          // 本地收藏集合跟着走：续页/重进本页时新拉的那批要按最新状态标记
          if (favorited) {
            _favoriteIds = {..._favoriteIds, photo.id};
          } else {
            _favoriteIds = {..._favoriteIds}..remove(photo.id);
          }
        });
      }
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

  Future<void> _openDetail(OfficialPhoto photo) async {
    await Navigator.of(context).push(
      AppPageRoute<void>(
        builder: (_) => OfficialGalleryDetailPage(
          state: widget.state,
          photoId: photo.id,
          // 详情页自己会拉一次，这里先把列表已知的东西传过去，进页面不至于空白一下
          fallbackTitle: photo.title,
          fallbackImageUrl: photo.url,
        ),
      ),
    );
    if (!mounted) {
      return;
    }
    // 详情页里可能改过收藏态，回来按当前分类重拉第一页对账（静默：不清屏）
    _loadPhotos(_activeCategoryId, silent: true);
  }

  Future<void> _openFavorites() async {
    await Navigator.of(context).push(
      AppPageRoute<void>(
        builder: (_) => OfficialGalleryFavoritesPage(state: widget.state),
      ),
    );
    if (mounted) {
      _loadPhotos(_activeCategoryId, silent: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    return FigmaScreen(
      title: l10n.galleryOfficialTitle,
      scrollable: false,
      bodyPadding: EdgeInsets.zero,
      background: Image.asset('assets/images/bg02.jpg', fit: BoxFit.cover),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_categories.isNotEmpty) _buildCategoryBar(l10n),
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
      return PageLoadError(onRetry: _loadCategories);
    }
    if (_photos.isEmpty) {
      return _EmptyHint(text: l10n.galleryEmptyCategory);
    }
    return RefreshIndicator(
      // 下拉刷新自带转圈，再清屏一次是两个加载态叠着闪
      onRefresh: () => _loadPhotos(_activeCategoryId, silent: true),
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
              onToggleFavorite: _toggleFavorite,
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

  /// 分类条：左边横滑分类，右端固定「收藏」。
  Widget _buildCategoryBar(AppL10n l10n) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 12, 16, 15),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.only(left: 24, right: 6),
              child: Row(
                children: [
                  for (final category in _categories) ...[
                    _CategoryChip(
                      label: category.isAll ? l10n.galleryAllCategory : category.name,
                      active: category.id == _activeCategoryId,
                      onTap: () => _onSelectCategory(category.id),
                    ),
                    const SizedBox(width: 10),
                  ],
                ],
              ),
            ),
          ),
          _FavoritesEntry(label: l10n.galleryFavorites, onTap: _openFavorites),
        ],
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: 15),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          // ⚠️ 选中/未选中都**不带阴影**（2026-08-12 产品要求）：这一条紧挨着顶栏，
          // 投影会让它显得浮，两态也不像在同一个平面上。
          gradient: active
              ? const LinearGradient(colors: [Color(0xFFFF8338), Color(0xFFF2621F)])
              : null,
          color: active ? null : Colors.white.withValues(alpha: 0.72),
          border: Border.all(
            color: active ? Colors.transparent : Colors.white.withValues(alpha: 0.9),
          ),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? Colors.white : const Color(0xFF6B7078),
            fontSize: 13,
            fontWeight: FontWeight.w500,
            height: 1,
          ),
        ),
      ),
    );
  }
}

/// 固定在分类条右端的「收藏」入口。**刻意不做成胶囊**：它是跳转入口、不是第 N 个分类，
/// 形状/底色/颜色三处都与分类不同，扫一眼就分得开（对齐小程序 `.category-fav`）。
class _FavoritesEntry extends StatelessWidget {
  const _FavoritesEntry({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 22,
        padding: const EdgeInsets.only(left: 12),
        decoration: const BoxDecoration(
          border: Border(
            left: BorderSide(color: Color(0x3D78808A), width: 1),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'assets/images/heart-solid.png',
              width: 16,
              height: 16,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) => const Icon(
                Icons.favorite,
                size: 16,
                color: Color(0xFFFE7B2D),
              ),
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: const TextStyle(
                color: Color(0xFFF2621F),
                fontSize: 13,
                fontWeight: FontWeight.w600,
                height: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Text(
          text,
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
}
