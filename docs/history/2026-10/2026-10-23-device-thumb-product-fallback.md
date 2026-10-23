# 设备图：记录里认不出机型时按 productId 回查产品列表

> 类型：Historical Implementation Record
> 日期：2026-10-23；环境：远程 SSH 服务器；分支：main；修改前：adc4dcb
> 对应小程序：`utils/api.js withProductBroadcastId`（同日同口径调整）

## 背景

反馈：挂件（EC-370）的新设备图只有搜索页正确，首页设备卡、我的设备、设备详情都是默认图。

- 搜索页按本次蓝牙广播名判断机型（`DeviceThumb.ofScanName`），所以正确。
- 已绑定设备按记录的 `broadcastId` 判断，取不到时只有 `shapeType == 1` 能兜成圆屏图（EB-169），EC-370 没有兜底，落默认图。
- 小程序在记录缺 `broadcastId` 时会按 `productId` 回查产品列表，APP 同步 10-22 改动时漏了这一步。

## 改动

- `PhotoFrameState.refreshDevices`：与设备列表并行拉产品列表（`/Client/Product/getProductList`），映射后调用 `_fillBroadcastIds`：
  - 记录自带、且是产品列表里某个产品的 `broadcastId`（不区分大小写）就不动；
  - 缺失或认不出时按 `productId` 回查覆盖；
  - 产品列表成功才缓存（整次会话复用），失败静默、不挡设备列表；最多多等 3 秒，超时先按已有信息出图。
- 绑定时 `_resolveProductId` 拉到的产品列表顺手刷新该缓存。

## 未覆盖（需核对后台数据）

- 设备当初绑定到错误的产品（10-22 加权前 EC-370 可能与 EF6-370 平分、广播名缺失时落到列表第一个）：记录的 `productId`、尺寸、形状都属于别的产品，设备图也跟着错，回查无法纠正。需在后台核对这台设备所属产品，错的删除后重新绑定。

## 验证

本机无 Flutter/Dart，测试、静态分析均未运行；未编译、未真机。`PhotoFrameState` 的网络层没有测试注入点，本次未加用例。需运行：

```powershell
flutter test --no-pub test/device_thumb_test.dart
flutter analyze
```

真机核对：EC-370 在首页、我的设备、设备详情显示矩形图；EB-169 显示圆屏图；EF6 老机型仍是原图。

## 回滚

撤销本提交即可，无数据迁移。
