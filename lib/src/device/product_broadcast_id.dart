/// 设备记录 → 所属产品广播名（产品列表 `/Client/Product/getProductList` 的 `broadcastId`）的回查口径。
///
/// 与小程序 `utils/api.js` 的 `withProductBroadcastId` / `withDetailBroadcastId` 同口径，改一端必须同步另一端：
/// 记录自带、且是产品列表里认得的广播名就用它；否则按 `productId` 回查产品列表；都不行返回空串。
/// 设备图（[DeviceThumb]）与最多照片数（`FrameProtocol.capacityOf`）都按这里得到的机型区分。
abstract final class ProductBroadcastId {
  /// [broadcastId] 是否为 [catalog]（productId → 广播名）里某个产品的广播名（去首尾空白、不区分大小写）。
  static bool isKnown(String broadcastId, Map<int, String> catalog) {
    final own = broadcastId.trim().toUpperCase();
    if (own.isEmpty) return false;
    return catalog.values.any((id) => id.trim().toUpperCase() == own);
  }

  /// 记录的机型广播名；认不出返回空串（调用方保留原值，或再按详情接口补）。
  static String resolve({
    required String broadcastId,
    required int productId,
    required Map<int, String> catalog,
  }) {
    if (isKnown(broadcastId, catalog)) return broadcastId.trim();
    if (productId <= 0) return '';
    return (catalog[productId] ?? '').trim();
  }

  /// 搜索结果（绑定前、还没有设备记录）的屏幕尺寸（2026-10-23，与小程序 `api.scanSizeModel` 同口径）：
  /// 蓝牙广播名 [scanName] 包含哪个产品的 broadcastId（去首尾空白、大小写不敏感，同扫描白名单），
  /// 就取该产品后台配置的 sizeModel；多个命中取 broadcastId 最长的（更具体）。
  /// 没命中、没配或 [products] 为空返回空串，调用方不展示。
  static String sizeModelOfScan(
    String scanName,
    List<ProductSizeModel> products,
  ) {
    final name = scanName.toLowerCase();
    ProductSizeModel? best;
    var bestLength = 0;
    for (final product in products) {
      final id = product.broadcastId.trim().toLowerCase();
      if (id.isEmpty || !name.contains(id) || id.length <= bestLength) {
        continue;
      }
      best = product;
      bestLength = id.length;
    }
    return best?.sizeModel.trim() ?? '';
  }
}

/// 产品列表里一个产品的广播名与后台配置的尺寸型号（`/Client/Product/getProductList`，2026-10-23）。
typedef ProductSizeModel = ({String broadcastId, String sizeModel});
