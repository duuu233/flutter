import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'official_gallery_api.dart';

/// 官方图库 / 我的收藏共用的两列瀑布流（对齐小程序 `shared.wxss` 的 `.waterfall`）。
///
/// 两件事必须按这个来，改坏了不会报错、只有肉眼能看出来：
///
/// ① **分列按累计高度、不按奇偶下标**：图片高宽比不一，奇偶分列会让某一列明显长出一截。
/// ② **高度先定下来再渲染**：卡片高度由 [OfficialPhoto.heightFor] 预先算好，
///    图片加载完**不重排**、只在拿到真实宽高时校正**自己那一张**（[onRatioResolved]）。
///    后端列表项目前不给图片比例（见 official_gallery_api.dart 文件头缺口①），
///    所以首屏是默认 3:4，加载完各归其位；**绝不能在校正后重新分列** ——
///    那会把用户正在看的卡片整块挪走。
class OfficialWaterfall extends StatelessWidget {
  const OfficialWaterfall({
    super.key,
    required this.photos,
    required this.onTapPhoto,
    required this.onToggleFavorite,
    this.onRatioResolved,
  });

  final List<OfficialPhoto> photos;
  final ValueChanged<OfficialPhoto> onTapPhoto;
  final ValueChanged<OfficialPhoto> onToggleFavorite;

  /// 图片加载完回吐真实比例（宽/高），页面据此只更新这一张的高度。
  final void Function(OfficialPhoto photo, double ratio)? onRatioResolved;

  /// 页面左右留白 24 + 两列间距 10（对齐小程序 48rpx / 20rpx）
  static const double _gap = 10;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columnWidth = (constraints.maxWidth - _gap) / 2;
        final columns = <List<OfficialPhoto>>[[], []];
        final heights = <double>[0, 0];
        for (final photo in photos) {
          final target = heights[0] <= heights[1] ? 0 : 1;
          columns[target].add(photo);
          // 卡片高 = 图高 + 标题行（估值，与小程序 splitColumns 的 0.22 同口径）
          heights[target] += photo.heightFor(columnWidth) + columnWidth * 0.22;
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < columns.length; i++) ...[
              if (i > 0) const SizedBox(width: _gap),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final photo in columns[i])
                      Padding(
                        padding: const EdgeInsets.only(bottom: _gap),
                        child: _PhotoCard(
                          // 按图片 id 绑 State：切分类/刷新后同一位置换了张图时，
                          // 「已量过比例」的标记要跟着图走，不能留给下一张
                          key: ValueKey<int>(photo.id),
                          photo: photo,
                          height: photo.heightFor(columnWidth),
                          onTap: () => onTapPhoto(photo),
                          onToggleFavorite: () => onToggleFavorite(photo),
                          onRatioResolved: onRatioResolved == null
                              ? null
                              : (ratio) => onRatioResolved!(photo, ratio),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _PhotoCard extends StatefulWidget {
  const _PhotoCard({
    super.key,
    required this.photo,
    required this.height,
    required this.onTap,
    required this.onToggleFavorite,
    this.onRatioResolved,
  });

  final OfficialPhoto photo;
  final double height;
  final VoidCallback onTap;
  final VoidCallback onToggleFavorite;
  final ValueChanged<double>? onRatioResolved;

  @override
  State<_PhotoCard> createState() => _PhotoCardState();
}

class _PhotoCardState extends State<_PhotoCard> {
  /// 这张已经量过（或正在量）了。没有它，每次 build 都会再挂一个监听 ——
  /// 列表滚动时 build 得很频繁，白白攒一堆一次性监听。
  bool _measuring = false;

  OfficialPhoto get photo => widget.photo;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.86),
          borderRadius: BorderRadius.circular(10),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF7D94B5).withValues(alpha: 0.10),
              blurRadius: 17,
              offset: const Offset(0, 7),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: widget.height,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CachedNetworkImage(
                    imageUrl: photo.thumbUrl,
                    fit: BoxFit.cover,
                    // 拿真实宽高回吐比例：后端列表项不给，只能靠加载完这一下校正
                    imageBuilder: (context, provider) {
                      _resolveRatio(provider);
                      return Image(image: provider, fit: BoxFit.cover);
                    },
                    placeholder: (context, url) =>
                        Container(color: const Color(0xFFE2E6EC)),
                    errorWidget: (context, url, error) => Container(
                      color: const Color(0xFFE2E6EC),
                      alignment: Alignment.center,
                      child: const Icon(
                        Icons.image_not_supported_outlined,
                        color: Color(0xFF9AA0A8),
                        size: 22,
                      ),
                    ),
                  ),
                  // 右上角红心：实心=已收藏、描边=未收藏。半透明白圆底是这里画的，
                  // 图里只有心（与小程序 `.photo-fav` 同一口径）。
                  Positioned(
                    top: 8,
                    right: 8,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      // 独立手势：点角标只切收藏，不该冒泡进详情页
                      onTap: widget.onToggleFavorite,
                      child: Container(
                        width: 30,
                        height: 30,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.62),
                          shape: BoxShape.circle,
                        ),
                        child: Image.asset(
                          photo.favorited
                              ? 'assets/images/heart-solid.png'
                              : 'assets/images/heart-outline.png',
                          width: 18,
                          height: 18,
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) => Icon(
                            photo.favorited
                                ? Icons.favorite
                                : Icons.favorite_border,
                            size: 18,
                            color: photo.favorited
                                ? const Color(0xFFFE7B2D)
                                : const Color(0xFF9AA0A8),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
              child: Text(
                photo.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFF2A2D32),
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  height: 1.3,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 从已解码的图上量真实宽高回吐给页面（后端列表项不给比例，见 official_gallery_api 缺口①）。
  ///
  /// ⚠️ 两个坑，都会炸：
  /// ① **回调必须延到当前帧之后**。这里是在 `imageBuilder`（build 期间）挂的监听，
  ///    图若已在缓存里，监听会**同步**触发 —— 直接回调就是「build 期间 setState」，
  ///    Flutter 会当场抛 `setState() called during build`。
  /// ② **量过就别再量**（[_measuring]）：列表滚动时 build 很频繁，
  ///    每次都挂一个一次性监听纯属浪费。
  void _resolveRatio(ImageProvider provider) {
    final callback = widget.onRatioResolved;
    if (callback == null || photo.ratio > 0 || _measuring) {
      return;
    }
    _measuring = true;
    final stream = provider.resolve(const ImageConfiguration());
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (image, synchronousCall) {
        stream.removeListener(listener);
        final w = image.image.width.toDouble();
        final h = image.image.height.toDouble();
        if (w <= 0 || h <= 0) {
          return;
        }
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            callback(w / h);
          }
        });
      },
      onError: (error, stackTrace) => stream.removeListener(listener),
    );
    stream.addListener(listener);
  }
}
