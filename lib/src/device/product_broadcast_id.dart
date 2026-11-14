/// 产品列表（`/Client/Product/getProductList`）按广播名取产品配置的口径。
///
/// 已绑定设备的机型直接用设备列表接口下发的 `broadcastId`（2026-11-14 起，同小程序 `api.getDevices`），
/// 原「按 productId 回查 / 详情接口补」的 `resolve` / `isKnown` 已删除。
abstract final class ProductBroadcastId {
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
