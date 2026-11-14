# 设备列表直接用接口的 productId / broadcastId（main）

> 类型：Historical Implementation Record
> 日期：2026-11-14；环境：远程 SSH 服务器；分支：main
> 依据：后端 `/Client/UserProduct/getUserProductList` 每条记录已补 `productId`（同详情接口）与 `broadcastId`（同产品列表 `getProductList` 里该产品的值，如 `EF6-370`、`EC-370`、`IJ_*`）。同小程序同日改动。

## 原来

列表不带这两个字段：`refreshDevices` 与产品列表并行请求，最多等产品列表 3 秒按 productId 回查 broadcastId；仍认不出的再给每台调一次 `getUserProductDetail`（最多再等 3 秒，会话内缓存），首页 / 我的设备 loading 跟着变长。

## 现在

- `refreshDevices` 只调列表接口，`_deviceFromJson` 直接读 `productId` / `broadcastId`；设备图、蓝牙版最多照片数、投屏取产品配置都用记录自带的字段；
- 删除 `_fillBroadcastIds`、`_detailBroadcastId`、`_detailBroadcastIds`，以及 `ProductBroadcastId.resolve` / `isKnown`；
- 产品列表仍会话内缓存，只供投屏取 renderMode / screenType（`_productField`）与绑定页搜索列表尺寸（`loadProductSizeModels`）；
- 详情接口不带 broadcastId，`fetchDeviceFirmwareInfo` 合并时本来就不覆盖它，不变；
- WiFi版 / 蓝牙版仍只按 `versionType`。
- `test/product_broadcast_id_test.dart`：删去 `resolve` 用例（逻辑已删），改为锁列表字段直出与 `refreshDevices` 不再调详情 / 等产品列表；搜索列表尺寸用例保留。

## 验证

本机无 Flutter，未运行测试、未 analyze、未真机。
