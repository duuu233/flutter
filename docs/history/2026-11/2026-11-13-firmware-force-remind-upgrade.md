# 固件强制升级 / 强提醒升级判断（main）

> 类型：Historical Implementation Record
> 日期：2026-11-13；环境：远程 SSH 服务器；分支：main；修改前：fdc925b
> 依据：产品口径（WiFi 版在线时判断、蓝牙版已连接时判断；详情页判强制与强提醒，我的设备、首页只判强制）。同小程序同日改动。

## 规则

| 场景 | WiFi 版（在线才判） | 蓝牙版（已连接才判） |
|---|---|---|
| 设备详情页 | 进入后判断一次；点功能按钮再判断（强制 + 强提醒） | 同左 |
| 我的设备 | 「投屏」「轮播设置」（只判强制） | 「投屏」（只判强制） |
| 首页 | 「拍照投屏」「相册投屏」（只判强制） | 同左 |

- 强制升级：弹框「立即升级 / 取消」，可以取消，但这次操作不继续；再次点击或再次进入触发判断的场景会再弹。
- 强提醒升级（只在详情页）：弹框「立即升级 / 取消」，取消后操作照常继续。
- 立即升级进升级页：蓝牙 `OtaUpgradePage(autoStart: true)`，WiFi `WifiOtaPage`；这次操作不再继续。
- 升级方式：`DeviceItem.updateType`（新增），取详情出参 `compulsory`（swagger 字段，与 App 版本接口同名：1 强制 / 2 强提示），缺省再看 `updateType` / `upgradeType` / `forceType`；1 = 强制，其它 = 强提醒。`fetchDeviceFirmwareInfo` 刷新时带回。
- 有没有新版本与详情页「固件升级」行红点同一套判定：WiFi `evaluateWifiOta` 为 available 且本地没有进行中的升级；蓝牙 `evaluateFirmwareUpdate`，读不到版本退回 `hasFirmwareUpdate`。
- 查询失败一律放行。

## 改动

- 新增 `lib/src/features/devices/firmware_gate.dart`：`decideFirmwareGate`、`showFirmwareGateDialog`（返回这次操作是否继续）、`guardFirmwareAction`（我的设备 / 首页现查：WiFi 查状态与详情，蓝牙补读 0x03 再查详情）。
- `device_details_page.dart`：重命名、轮播设置、一键清空先判断；投屏在连上之后、选拍照 / 相册之前判断；`_refreshDetail` 完成后判断一次，进页未连接则在本页连上后判断一次，回到本页不再弹。判定用 `_hasFirmwareUpdate`。
- `wifi_device_detail_page.dart`：投屏、轮播设置、设备信息、消息中心、TF卡、共享设备、一键清空先判断；状态、详情、进行中记录都回来后判断一次（在线才弹）。
- 详情页不判断：连接 / 断开、固件升级行、解除绑定、删除设备。
- `devices_page.dart`：蓝牙投屏连上之后判断；`wifi_cast_entry.dart` 的 `startWifiCast` / `openWifiSlideshow` 加 `forceUpgradeCheck`（我的设备传 true，在离线 / 本地模式拦截之后判断，WiFi 详情不传）。
- `home_page.dart`：`_startCast` 在 WiFi 在线确认 / 蓝牙连上之后判断。
- `app_l10n.dart` 新增 `otaGateForceMessage` / `otaGateRemindMessage` / `otaGateNewVersion`（简 / 英 / 日）。

## 验证

- 新增 `test/firmware_gate_test.dart`：升级方式、判断前提、与红点同一判定、各页接入位置（源码断言用 Python 对实际文件核对过）。
- 本机无 Flutter / Dart，analyze / test / 编译 / 真机都没跑；详情接口升级方式字段未联调。
