# 设备机型：列表记录认不出时按详情接口补（修复 EC-370 设备图与最多照片数）

> 类型：Historical Implementation Record
> 日期：2026-10-23；环境：远程 SSH 服务器；分支：main；修改前：72c365a
> 对应小程序：`utils/api.js withDetailBroadcastId`（同日同口径）

## 背景

反馈：EC-370 在首页设备卡、我的设备、设备详情的设备图都不对（应为 `home-device-rectangle-thumb.png`），设备详情的最多照片数量也读不出；小程序同一台设备详情页的图和容量都对，只有首页与我的设备不对。

- 两端设备图（`DeviceThumb.ofRecord`）与容量（`FrameProtocol.capacityOf`）都按记录的机型广播名区分。
- APP 首页、我的设备、详情页用的都是设备列表接口（`getUserProductList`）映射出的同一个 `DeviceItem`；小程序详情页另调详情接口（`getUserProductDetail`），按它回查产品列表就认出了 EC-370。
- 产品列表（`/Client/Product/getProductList`）本身带标识：EC-370 为 `productId 17 / broadcastId EC-370`。认不出说明列表接口这条记录里没有能对上产品列表的 `productId` / `broadcastId`。原 `_fillBroadcastIds` 在列表里没有任何 `productId > 0` 时直接返回，EC-370 落默认图；容量按屏型也给不出时详情显示 `--`。
- 列表接口这条记录的原始返回未拿到，以上由两端表现与代码推断。

## 改动

- 新增 `lib/src/device/product_broadcast_id.dart`：`ProductBroadcastId.resolve`，记录自带且是产品列表认得的广播名就用它，否则按 `productId` 回查，都不行返回空串（与小程序 `withProductBroadcastId` 同口径）。
- `PhotoFrameState._fillBroadcastIds`：
  - 去掉“列表里没有 productId 就返回”的提前退出；
  - 仍认不出的记录按 `userProductId` 调 `getUserProductDetail`，用详情的 `broadcastId` / `productId` 按同一口径回查；详情正常返回的结果（认不出记空串）整次会话复用，请求失败不缓存、不提示；最多再等 3 秒，超时先按已有信息出图；
  - 机型补上后，已从真机读过 0x01（`liveImageCount` 非空）的设备按机型重算 `liveCapacity`（EC-370 → 11），不必重连。

## 测试

新增 `test/product_broadcast_id_test.dart`：自带认得不被覆盖、按 productId 回查且去空白、认不出为空串、补到 EC-370 后设备图为矩形图且容量 11。`PhotoFrameState` 网络层仍无测试注入点，详情补查本身未加用例。

## 未覆盖

- 列表接口这条记录若带着一个**产品列表里认得、但不是它自己**的广播名（如 EF6-370），按“自带认得不覆盖”的口径不会调详情，仍会错。需要列表接口的原始返回确认。

## 验证

本机无 Flutter/Dart，测试、静态分析均未运行；未编译、未真机。需运行：

```powershell
flutter test --no-pub test/product_broadcast_id_test.dart test/device_thumb_test.dart test/device_capacity_test.dart
flutter analyze
```

真机核对：EC-370 在首页、我的设备、设备详情显示矩形图，连接后详情最多照片数为 `n/11`；EB-169 圆屏图、`n/25`；EF6 老机型不变。

## 回滚

撤销本提交即可，无数据迁移。
