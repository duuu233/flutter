# WiFi版 / 蓝牙版只按 versionType 判断（main）

> 类型：Historical Implementation Record
> 日期：2026-11-14；环境：远程 SSH 服务器；分支：main
> 依据：用户反馈首页 / 我的设备把 WiFi 版先显示成蓝牙版、过一会才变；接口口径：设备列表 `getUserProductList`、详情 `getUserProductDetail` 出参 `versionType`（1 = 蓝牙版，2 = wifi版），用户确认只按它判断。同小程序同日改动。

## 原因

- `DeviceItem.isWifi` 按所属产品的广播 ID（`IJ_*` 模板 / `IJ_` 前缀）认；
- 设备列表实际返回不带 `productId` / `broadcastId`，要等产品列表（最多 3 秒）和详情接口补上才认得出；没等到就按蓝牙版显示，之后才变对。

## 改法

- `DeviceItem` 新增 `versionType`（未下发为 0），`_deviceFromJson` 读 `versionType`；详情带了这个键就覆盖；
- `isWifi` 改为 `versionType == 2`，不再看广播 ID。首页设备卡、我的设备 Tab、设备选择弹层、投屏、图库、AI、固件提醒、WiFi 状态订阅等都走 `isWifi`，一起生效；
- 设备图 / 机型容量仍按 `broadcastId`（不变）；绑定页搜索结果仍按扫描到的广播名判断（不变）；
- `state.dart` 去掉不再使用的 `broadcast_match.dart` 引用；
- 新增 `test/device_version_type_test.dart`，`firmware_gate_test.dart` 的 WiFi 设备补 `versionType: 2`。

## 验证

本机无 Flutter，未运行测试、未 analyze、未真机。
