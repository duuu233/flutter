# APP 连不上 EC-370：屏型否决对齐小程序

> 类型：Historical Implementation Record
> 日期：2026-10-23；环境：远程 SSH 服务器；分支：main；修改前：6eb28a9
> 对应小程序：`utils/active-device.js` `deviceInfoMatches` / `sameScreen`

## 背景

挂件 EC-370：小程序能连，APP 一直连不上；EB-169 也不稳定。

APP 比小程序多一道屏型一票否决，且比较的值口径不同：

- `sameScreenCode(a, b)`：两侧非 0 且不同就否决。
- 连上后 `_verifyBoundDeviceIdentity` 先拿记录的 `screenCode` 比 `sessionScreenCode`，后者优先取 0x01 应答里的**原始**屏型字节（不在旧表里也不归 0）。
- 记录码不为 0 的情况：宽高是旧尺寸（480×720 / 680×960，含被绑到 EF6 产品的记录），或后台没下发宽高（回落 5.89 寸的码）。
- 新机型 0x01 报的屏型不是旧码时即被判「不是这台」→ 断开、把该 remoteId 排除、删直连缓存 → 下一轮没有候选，报「未搜索到该电子纸设备」。这一分支不打日志。
- 扫描匹配（`matchScannedDevice`）、会话认领（`sessionMatchesSerial`，投屏/详情/删图判已连接）、绑定判重用的是同一个函数。

小程序：连上后只比完整 6 字节 ID；`sameScreen` 只在记录是旧尺寸、且对方屏型在旧表里有尺寸时才否决。

## 改动

- `serial_match.dart` `sameScreenCode`：只在两侧都是有确定尺寸的旧屏型（0x01 3.7寸 / 0x02 5.89寸）且不同时否决；0、7.3寸占位 0x03、新机型屏型码一律放行。扫描匹配、会话认领、绑定判重随之对齐。
- `ble_controller.dart` `_verifyBoundDeviceIdentity`：去掉屏型判断，只认 0x01 完整 6 字节 ID；去掉不再使用的 `screenCode` 参数。
- `test/serial_match_test.dart`：原断言 `sameScreenCode(0x03, 0x02)` 为 false 改为放行（7.3寸无尺寸，小程序不拿它否决，用例内已注明），新增新机型屏型码放行用例；0x01 对 0x02 仍否决。

## 未改

- `DeviceItem.screenCode` 在后台没下发宽高时仍回落 5.89 寸的码（OTA 面板预检也依赖它），小程序此时不否决。若 EC-370 记录无宽高且广播报 0x01，扫描阶段仍会被挡；后台下发宽高即不受影响。
- 兜底候选 `matchScannedDeviceFallback` 仍要求两侧屏型已知且相等（只在窗口走满后用）。
- 连上约 2 秒后切 Android LOW_POWER 并下发 0x13、25 秒心跳（小程序都没有），Android 只收传统广播：可能影响稳定性，未改，需日志确认。

## 验证

本机无 Flutter/Dart，测试、静态分析均未运行；未编译、未真机。需运行：

```powershell
flutter test --no-pub test/serial_match_test.dart
flutter analyze
```

真机：EC-370 首页/设备详情连接、投屏、断开后重连；EB-169 同样走一遍；EF6-370 / EF6-589 老机型连接不受影响。仍连不上时取「投屏性能自检」页日志与 EC-370 设备列表的 width/height/productId。

## 回滚

撤销本提交即可，无数据迁移。
