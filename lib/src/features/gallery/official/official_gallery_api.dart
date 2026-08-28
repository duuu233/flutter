import '../../../network/boltfox_api.dart';

/// 官方图库（`/Client/Product/*`）的数据层 —— 对齐小程序 `utils/gallery-api.js`，
/// 字段口径、兜底策略、判停规则一律与那边保持一致，两端出问题时才好对账。
///
/// 页面拿到的是 [OfficialPhoto] / [OfficialPhotoDetail] / [OfficialCategory]，
/// 不直接碰后端字段名。
///
/// ⚠️⚠️ **后端两处缺口，端上只能兜着**（补齐后端上兜底即可删）：
///
///   ① 列表项**没有图片宽高/比例**（`ClientProductImgApiOut` 只有 img/imgThumb/productImgId/title）。
///      瀑布流要在渲染前把高度占住，否则图陆续到达时会把下方卡片一路顶走、用户正看的那张跳掉。
///      所以 [OfficialPhoto.ratio] 为 0＝未知，页面先按 [kDefaultRatio] 占位，
///      图片加载完再按真实宽高校正**那一张**（只改高度，不重新分列）。
///      请后端在列表项补 width/height 或 ratio —— 端上两种写法都认（见 [OfficialPhoto.fromJson]）。
///
///   ② 列表项**没有收藏态**（只有详情有 `isAlreadyCollected`）。图库列表右上角的红心要按
///      收藏态显示实心/描边，所以另拉一页收藏列表在端上标记（[fetchFavoriteIds]），
///      拉不到就一律按未收藏渲染（不影响点击，点了以详情/收藏列表为准）。
///      请后端给 `ClientProductImgApiOut` 补 `isAlreadyCollected`。
class OfficialGalleryApi {
  const OfficialGalleryApi._();

  /// 列表分页大小。瀑布流两列，20 条≈10 行，一屏多一点，滚到底再续。
  static const int pageSize = 20;

  /// 列表项拿不到真实比例时的占位比例（宽/高）。取 0.75（3:4 竖图）——
  /// 图库以竖图为主，用它兜底时首屏的错落感最接近真实数据。
  static const double kDefaultRatio = 0.75;

  /// 「收藏态兜底扫描」一次拉多少条（见文件头缺口②）。收藏一般不会太多，一页够用；
  /// 真超了也只是第 200 条之后的图在列表里显示成未收藏，点进详情仍是对的。
  static const int _favoriteScanSize = 200;

  static int _toInt(Object? value) {
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse('${value ?? ''}'.trim()) ?? 0;
  }

  static double _toDouble(Object? value) {
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse('${value ?? ''}'.trim()) ?? 0;
  }

  static String _toText(Object? value) => '${value ?? ''}'.trim();

  /// `BasePageOutput` 取列表：与 `api_rows.dart` / 小程序 pageRows 同口径。
  static List<Map<String, dynamic>> _rows(Object? data) {
    final Object? list = data is Map ? data['pageData'] : data;
    if (list is! List) {
      return const [];
    }
    return list.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
  }

  /// 分页判停：优先用后端的 `pageCount`，缺失时退回「不满一页即最后一页」。
  /// 不能只看条数 —— 后端可能无视 pageSize 按自己的默认值分页（购买记录页踩过同一个坑）。
  static bool _hasMore(Object? data, int pageIndex, int size, int rowCount) {
    final int pageCount = data is Map ? _toInt(data['pageCount']) : 0;
    return pageCount > 0 ? pageIndex < pageCount : rowCount >= size;
  }

  /// 分类导航。首项是**端上补的「全部」**（categoryId = 0）。
  static Future<List<OfficialCategory>> fetchCategories() async {
    final data = await BoltFoxApi.getImgCategory();
    final list = <OfficialCategory>[const OfficialCategory.all()];
    if (data is List) {
      for (final item in data.whereType<Map>()) {
        final id = _toInt(item['categoryId']);
        final name = _toText(item['categoryName']);
        if (id > 0 && name.isNotEmpty) {
          list.add(OfficialCategory(id: id, name: name));
        }
      }
    }
    return list;
  }

  /// 公共图库列表。[categoryId] 传 0＝全部（后端该参数可选，不传即全部）。
  static Future<OfficialPhotoPage> fetchPhotos({
    int categoryId = 0,
    int pageIndex = 1,
  }) async {
    final data = await BoltFoxApi.getProductImgList(
      pageIndex: pageIndex,
      pageSize: pageSize,
      categoryId: categoryId > 0 ? categoryId : null,
    );
    final rows = _rows(data);
    return OfficialPhotoPage(
      photos: rows.map(OfficialPhoto.fromJson).toList(),
      pageIndex: pageIndex,
      hasMore: _hasMore(data, pageIndex, pageSize, rows.length),
      total: data is Map ? _toInt(data['recordCount']) : rows.length,
    );
  }

  /// 用户收藏列表。项与图库列表同结构，只是这里的每一张按定义都是已收藏。
  static Future<OfficialPhotoPage> fetchFavorites({int pageIndex = 1}) async {
    final data = await BoltFoxApi.getProductImgCollectionList(
      pageIndex: pageIndex,
      pageSize: pageSize,
    );
    final rows = _rows(data);
    return OfficialPhotoPage(
      photos: rows
          .map((item) => OfficialPhoto.fromJson(item).copyWith(favorited: true))
          .toList(),
      pageIndex: pageIndex,
      hasMore: _hasMore(data, pageIndex, pageSize, rows.length),
      total: data is Map ? _toInt(data['recordCount']) : rows.length,
    );
  }

  /// 收藏态兜底：拉一页收藏列表，返回其中的图片 id（见文件头缺口②）。
  /// **静默失败返回空集**：未登录、接口异常都只是让列表里的心显示成描边，
  /// 不该打断图库浏览，更不该弹一条红字。
  static Future<Set<int>> fetchFavoriteIds() async {
    try {
      final data = await BoltFoxApi.getProductImgCollectionList(
        pageIndex: 1,
        pageSize: _favoriteScanSize,
      );
      return _rows(data)
          .map((item) => _toInt(item['productImgId']))
          .where((id) => id > 0)
          .toSet();
    } catch (_) {
      return <int>{};
    }
  }

  /// 图片详情（id 传 productImgId）。
  static Future<OfficialPhotoDetail?> fetchDetail(int productImgId) async {
    if (productImgId <= 0) {
      return null;
    }
    final data = await BoltFoxApi.getProductImgDetail(productImgId);
    if (data is! Map) {
      return null;
    }
    final json = data.cast<String, dynamic>();
    if (_toInt(json['productImgId']) <= 0) {
      return null;
    }
    return OfficialPhotoDetail.fromJson(json);
  }

  /// 收藏 / 取消收藏（同一个接口来回切），返回**切换后**的收藏态。
  ///
  /// ⚠️ 新状态由端上**取反当前态**推出，不看接口返回值：出参是 `BaseOutput<boolean>`，
  /// 而这个布尔到底是「操作是否成功」还是「切换后的收藏态」文档没写。两种语义下取反都是对的
  /// （真失败会抛异常，到不了这里）。后端明确后再决定要不要改用它。
  static Future<bool> toggleFavorite(int productImgId, bool favorited) async {
    await BoltFoxApi.setImgCollected(productImgId);
    return !favorited;
  }
}

/// 分类。`id = 0` 是端上补的「全部」（后端没有这一项，列表接口不传 categoryId 即全部）。
class OfficialCategory {
  const OfficialCategory({required this.id, required this.name});

  /// 「全部」：名字由页面按语种给（[name] 留空，页面 fallback 到 l10n）。
  const OfficialCategory.all() : id = 0, name = '';

  final int id;
  final String name;

  bool get isAll => id == 0;
}

/// 列表项。
class OfficialPhoto {
  const OfficialPhoto({
    required this.id,
    required this.title,
    required this.url,
    required this.thumbUrl,
    this.ratio = 0,
    this.favorited = false,
  });

  factory OfficialPhoto.fromJson(Map<String, dynamic> json) {
    final img = OfficialGalleryApi._toText(json['img']);
    final thumb = OfficialGalleryApi._toText(json['imgThumb']);
    // 后端哪天补了比例，这里认 ratio 或 width/height 两种写法，页面不用改
    double ratio = OfficialGalleryApi._toDouble(json['ratio']);
    if (ratio <= 0) {
      final w = OfficialGalleryApi._toDouble(json['width']);
      final h = OfficialGalleryApi._toDouble(json['height']);
      ratio = (w > 0 && h > 0) ? w / h : 0;
    }
    return OfficialPhoto(
      id: OfficialGalleryApi._toInt(json['productImgId']),
      title: OfficialGalleryApi._toText(json['title']),
      url: img,
      // 列表用缩略图，没给就回落原图（别让列表空着）
      thumbUrl: thumb.isNotEmpty ? thumb : img,
      ratio: ratio,
    );
  }

  final int id;
  final String title;

  /// 原图（详情 / 投屏用）
  final String url;

  /// 缩略图（列表用）
  final String thumbUrl;

  /// 宽/高。**0 = 未知**（后端列表项不给，见文件头缺口①），页面按默认比例占位后再校正。
  final double ratio;

  final bool favorited;

  OfficialPhoto copyWith({double? ratio, bool? favorited}) {
    return OfficialPhoto(
      id: id,
      title: title,
      url: url,
      thumbUrl: thumbUrl,
      ratio: ratio ?? this.ratio,
      favorited: favorited ?? this.favorited,
    );
  }

  /// 按列宽算这一张的渲染高度。ratio 未知时用默认比例兜底。
  double heightFor(double columnWidth) {
    final r = ratio > 0 ? ratio : OfficialGalleryApi.kDefaultRatio;
    return columnWidth / r;
  }
}

/// 一页列表。
class OfficialPhotoPage {
  const OfficialPhotoPage({
    required this.photos,
    required this.pageIndex,
    required this.hasMore,
    required this.total,
  });

  final List<OfficialPhoto> photos;
  final int pageIndex;
  final bool hasMore;
  final int total;
}

/// 详情。⚠️ 简介字段后端叫 `content`（不是 desc）；收藏态是 `isAlreadyCollected` 的 **0/1**。
class OfficialPhotoDetail {
  const OfficialPhotoDetail({
    required this.id,
    required this.title,
    required this.desc,
    required this.url,
    required this.favorited,
  });

  factory OfficialPhotoDetail.fromJson(Map<String, dynamic> json) {
    return OfficialPhotoDetail(
      id: OfficialGalleryApi._toInt(json['productImgId']),
      title: OfficialGalleryApi._toText(json['title']),
      desc: OfficialGalleryApi._toText(json['content']),
      url: OfficialGalleryApi._toText(json['img']),
      favorited: OfficialGalleryApi._toInt(json['isAlreadyCollected']) == 1,
    );
  }

  final int id;
  final String title;
  final String desc;
  final String url;
  final bool favorited;

  // `productSizeList` / `productSizes`（适用设备尺寸）后端仍下发，但两端都已按产品要求
  // 从详情页去掉（2026-08-12），所以这里不解析 —— 要恢复时照小程序 normalizeDetail 补即可。
}
