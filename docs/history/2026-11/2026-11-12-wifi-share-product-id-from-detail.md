# WiFi 分享产品 ID 改取设备详情（main）

> 类型：Historical Implementation Record
> 日期：2026-11-12；环境：远程 SSH 服务器；分支：main；修改前：40b49c0
> 依据：测试包联调日志「分享按钮置灰：设备没有产品ID（productId=0）」，同一页 `getUserProductDetail` 返回 `productId: 20`。

## 原因

- 分享页 `_canShare` 与分享链接里的 `p` 取的是本地设备缓存 `_device.productId`。缓存由设备列表接口 `getUserProductList`（`ClientUserProductApiOut`）映射，该接口不下发 `productId`，所以缓存一直是 0，所有者也永远置灰。
- 分享页进页面时已经调了 `getUserProductDetail`，但只拿来判断所有者，没用它的 `productId`。小程序 `wifi-share` 走 `getDeviceDetail`，产品 ID 取自详情，所以不受影响。

## 改动

- `wifi_share_page.dart`：`_load()` 读详情时把 `productId`、`deviceId`（`canonicalDeviceSerial` 规范化）存下来。新增 `_productId` / `_serial`：优先用详情里的值，没下发再回落本地缓存。置灰判断、置灰原因、成员列表查询、`WifiShareLink.h5Url` 的 `deviceId` / `productId` 都改用这两个值。
- `test/wifi_share_link_test.dart`：新增源码断言，覆盖取详情、优先级和链接参数。

## 验证

本机无 Flutter / Dart，analyze / test / 真机均未跑；新增与原有分享页断言已用 python 对源码核对，`git diff --check` 通过。
