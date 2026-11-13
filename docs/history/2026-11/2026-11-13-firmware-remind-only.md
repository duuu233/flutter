# 固件升级：去掉强制升级，只保留强提醒 / 弱提示（main）

> 类型：Historical Implementation Record
> 日期：2026-11-13；环境：远程 SSH 服务器；分支：main；修改前：e82059c
> 依据：产品改口（去掉强制升级逻辑，首页、列表页、详情页都不要；只保留强提醒升级与弱提示升级）。同小程序同日改动。取代 [2026-11-13-firmware-force-remind-upgrade](2026-11-13-firmware-force-remind-upgrade.md) 与 [2026-11-13-firmware-gate-type-cache](2026-11-13-firmware-gate-type-cache.md) 中的强制升级部分。

## 升级类型

| `updateType`（后台 `compulsory`） | 红点 | 进入设备详情页 |
|---|---|---|
| 2 强提示升级（强提醒） | 亮，用户主动点 | 弹提示框 |
| 3 弱提示升级 | 亮，用户主动点 | 不弹 |
| 4 不提示升级 / 没给 | 照旧按版本亮 | 不弹 |
| 1 原强制升级 | 亮 | 后台已隐藏该选项，存量数据按强提醒弹 |

## 改动

- `firmware_gate.dart`：`FirmwareGateMode` 只剩 `none` / `remind`；强提醒在进入设备详情页（蓝牙 / WiFi）时判断一次，WiFi 在线、蓝牙已连接且红点亮才弹；取消后本次启动不再弹这台，关闭 / 重启 App 再弹（`FirmwareRemindSession`，内存，按设备计）。立即升级进升级页（蓝牙 `OtaUpgradePage` 自动开始，WiFi `WifiOtaPage`）。
- 去掉：
  - 详情页功能按钮的判断（`_gated` / `_firmwareGate`），投屏连上后直接选图；
  - 我的设备投屏 / WiFi 轮播设置、首页拍照 / 相册投屏的 `guardFirmwareAction`（loading 现查与 `fw_gate_cache` 本地缓存），`wifi_cast_entry` 的 `forceUpgradeCheck` 参数；
  - 升级完成更新缓存（`OtaUpgradePage` / `WifiOtaPage` 的 `markUpgraded`）；
  - 多语言 `otaGateForceMessage`。
- `test/firmware_gate_test.dart` 按新口径重写。

## 验证

本机无 Flutter，未跑 `flutter test` / `flutter analyze`，未真机。
