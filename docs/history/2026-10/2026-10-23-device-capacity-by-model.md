# 设备容量按机型区分（规格书 v1.6）

> 类型：Historical Implementation Record
> 日期：2026-10-23；环境：远程 SSH 服务器；分支：main；修改前：6bb1a96
> 对应小程序：`utils/frame-protocol.js` `capacityOf`、`tests/device-capacity.test.js`
> 依据：`docs/电子相框产品需求规格书1.6.pdf` §5.2、§6.10.5

## 问题

- EC-370（挂牌）：设备详情「最大照片数量」读不出来。
- EB-169（吧唧）：APP 显示得出来，小程序读不出来。

## 原因

规格书 v1.6 §5.2 的各机型最多图片数：EF6-370 95、EF6-589 51、EB-169 25、EC-370（挂牌）11。0x01 应答没有容量字段。

- 原来按屏型表 `FrameProtocol.screenTypes` 给容量，表里只有 0x01/0x02/0x03。EB-169 报 0x04，容量为 0，
  `liveCapacity` 不写入，`DeviceItem.capacity` 回落常量 `FrameProtocolConfig.maxImages`（32）。
  APP 显示的 `n/32` 看着能读出来，实际是常量，不是 25。小程序没有这层兜底，直接显示 `--`。
- EC-370 与 EF6-370 同为 3.7 寸 480×720，屏型同报 0x01，按屏型只会给 95。EC-370 只能按机型（产品 broadcastId）区分。
  若真机报的是表外的码，容量也是 0。

## 改动

- `frame_protocol.dart`：新增 `modelCapacity`、`newScreenCapacity`（0x04→25）与 `capacityOf(model, screenType)`。
  先按机型匹配（大小写不敏感的包含匹配，同设备图口径），认不出再按屏型；都认不出返回 0。
  `parseDeviceInfo` 的 `capacity` 改用它。`screenTypes` 不加 0x04，尺寸以设备列表为准，不影响型号否决和 OTA 面板预检。
- `state.dart`：0x01 回填时 `liveCapacity = capacityOf(device.broadcastId, info.screenType)`。
- `device_details_page.dart`：「最大照片数量」只在 `liveCapacity` 读到时显示 `已用/上限`。读不到时显示 `--`，不再拿常量 32 冒充（对齐小程序 memoryText）。
- `projection_device.dart` `resolveProjectionTransfer` 新增 `broadcastId`：机型认得出就按机型容量定槽位上限，EC-370 不会选到 11 号及以后的槽位。
  `projection_service.castImages` 新增 `deviceBroadcastId`，`casting_progress_page` 传入 `target.broadcastId`。
- 新增 `test/device_capacity_test.dart`。

## 已知限制

- 机型取自设备记录的 `broadcastId`（设备列表下发或按 productId 回查）。取不到时退回屏型：EC-370 若报 0x01 会显示 95。
- 未在真机确认 EC-370 0x01 实际上报的屏型字节。

## 验证

本机无 Flutter/Dart，测试、静态分析均未运行；未编译、未真机。需运行：

```powershell
flutter test --no-pub test/device_capacity_test.dart test/projection_device_test.dart
flutter analyze
```

真机：EC-370、EB-169 连接后设备详情「最大照片数量」分别为 `n/11`、`n/25`；EF6-370/589 仍为 `n/95`、`n/51`。

## 回滚

撤销本提交即可，无数据迁移。
