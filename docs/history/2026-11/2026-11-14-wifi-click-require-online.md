# WiFi 版点击入口要在线（main）

> 类型：Historical Implementation Record
> 日期：2026-11-14；环境：远程 SSH 服务器；分支：main；修改前：d5c352a
> 依据：产品要求 WiFi 版投屏、轮播、固件升级、优雅刷新升级、TF卡切换点击时都要判断是否在线，不在线不能进；一键清空、删除设备、解绑设备不判断；蓝牙版不动。同小程序同日改动。

## 规则（`wifi_status.dart` 的 `requireWifiOnline`）

- [WifiStatusStore] 已知离线 / 休眠 / 关机 / 本地模式：直接提示，不进。
- 已知在线：直接进。`fresh: true` 时仍现查一次。
- 查询中 / 状态未知 / `fresh`：现查一次 `IotApi.getDeviceOnline`（loading「检查设备」），只有在线才进。查不到提示「设备不在线」。
- `useKnown: false` 时不看已有状态，一律现查（首页、结果页没有对应的状态缓存）。

## 接入位置

- `startWifiCast`（我的设备 / WiFi 详情投屏）、`openWifiSlideshow`（轮播设置，原「离线也能看」撤掉）：按已知状态，未知现查。
- WiFi 详情 `_openOta`（固件升级）、设备信息 `_openFpga`（优雅刷新升级）：现查。
- 首页拍照 / 相册（WiFi 版）：原 `ensureWifiDeviceOnline`「查不到放行」改为 `requireWifiOnline(fresh, useKnown: false)`，查不到也拦。
- WiFi 投屏结果页「继续投屏」：现查。
- TF卡切换（`WifiTfPage`）原本就开启前现查、只放行在线，未改。
- 一键清空、解除绑定、删除设备不判断。AI / 官方图库选设备投屏仍走 `ensureWifiDeviceOnline`，预览页「开始投屏」本就严格判断，未改。
- 新增 `test/wifi_click_online_test.dart`。

## 验证

本机无 Flutter，未运行测试、未真机。
