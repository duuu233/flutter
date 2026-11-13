# 固件升级判断：按后台升级类型、强提醒每次启动一次、列表页 / 首页本地缓存（main）

> 类型：Historical Implementation Record
> 日期：2026-11-13；环境：远程 SSH 服务器；分支：main；修改前：07610af
> 依据：产品复核（弱提示升级被误弹；强提醒只在进入设备页时提醒一次；列表页 / 首页强制升级判断加 loading 并缓存）。同小程序同日改动。在 [2026-11-13-firmware-force-remind-upgrade](2026-11-13-firmware-force-remind-upgrade.md) 的基础上调整。

## 改动

- **升级类型**：`firmwareGateModeOf` 按后台 `compulsory`（归一为 `updateType`）判断：
  - 1 = 强制、2 = 强提醒，这两种弹框；
  - 3 弱提示、4 不提示及其它都不弹，照改动前只亮「固件升级」红点。
  - 红点不分类型。
  - 原来把「不是 1」都当强提醒，弱提示也会弹，而且取消后照常继续，所以投屏取消后还会弹出选择拍照 / 相册。
- **强提醒**：
  - 只在进入详情页时弹（`checkFirmwareGateOnEnter`）。
  - 每台设备每次启动 App 只弹一次（`FirmwareGateCache.takeRemind`）。
  - 详情页按钮、列表页、首页都不弹。
- **强制升级**：
  - 详情页：进入时弹；按钮的 `_firmwareGate` 只判强制（`forceOnly`），取消后每次点都再弹、操作不继续。
  - 列表页 / 首页（`guardFirmwareAction`）：
    - 本次启动第一次点某台设备时，显示 `AppLoadingDialog` 现查一次。
    - 结果存进 SharedPreferences `fw_gate_cache`；之后按缓存判断，不再请求接口。
    - 列表里已知不在线的 WiFi 设备不判断；首页已确认在线时传 `online: true`。
- **缓存更新**：
  - 详情页进入时的判定写进缓存。
  - 升级完成后，`FirmwareGateCache.markUpgraded` 把缓存改成无需升级：
    - 蓝牙：`OtaUpgradePage` 升级成功时；
    - WiFi：`WifiOtaPage` 主固件走到设备重启确认时（优雅刷新不涉及）。
  - 每次启动第一次点击仍会现查一次，避免后台新发的版本一直沿用旧缓存。
- 不新增依赖（`shared_preferences` 原本就有）。
- `test/firmware_gate_test.dart` 更新：升级类型、缓存与强提醒一次、接入位置。

## 验证

本机无 Flutter / Dart，analyze、test、编译和真机都没跑。改动文件的括号配平与改动前一致；测试文件新增的差值都来自字符串和正则，已逐行核对。`git diff --check` 通过。
