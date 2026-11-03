# main-wifi：同步小程序 10-29 之后的 WiFi 版改动（固件升级等）

> 类型：Historical Implementation Record
> 日期：2026-11-03；环境：远程 SSH 服务器；分支：main-wifi（起点 4a8ac89，先合入 origin/main 68dc1b4 构建号）
> 对应小程序：`photo-album` main-wifi d3e14ed、c1cac77、c8d8bb9、fc63897、e7a9d36、e47e3bf（上一轮见 [2026-10-29 补齐剩余差异](../2026-10/2026-10-29-wifi-full-alignment.md)）

## 改动

### 固件升级（OTA，对应 c1cac77，前端对接文档 20261031）

- `IotApi.startOta`（`POST /api/device/ota`：deviceNo / url / type=main / version → msgid）、`IotApi.getOtaStatus`（`GET /api/device/ota/status`）。
- `features/wifi/wifi_ota.dart`（纯逻辑，同小程序 `utils/wifi-ota.js`）：四步 SENT / DOWNLOADING / FLASHING / VERIFYING，FAILED / TIMEOUT 在最后到达的一步打叉，未知值停在已到达的一步；VERIFYING 是步骤页终点但不是终态；版本比较（x.y.z，当前读不到或旧格式 → 无法判断，目标非 x.y.z 退回「不相同即有新版本」，包地址须 http(s)）；`isWifiOtaBusyError`（4045，或 4000 且服务端文案为空 / 含「升级、进行中」）；本地记录 `ota_inflight:{deviceNo}`（SharedPreferences，`type: 'ota'`，一台一条，终态或 4044 清掉，查询失败保留）。
- `WifiOtaPage`：与配网状态页同一版式（`WifiStepIcon` 由配网页私有组件改为公共）；进页先核对本地进行中记录（进行中接着展示、VERIFYING 显示「升级完成 · 等待设备重启」），否则按设备详情接口的 newVersionNo / downloadPath 对比 IoT `firmwareVersion` 显示发现新版本 / 已是最新 / 无法判断 / 升级包信息不完整；立即升级先按设备状态拦（离线、休眠、关机、本地模式），确认后下发，成功即存 msgid，3 秒轮询 + WS `ota.result` 加速 + 重连补查，进后台停轮询；4000 / 4045 切到「设备正在升级」。
- WiFi 设备详情：「消息中心」后新增「固件升级」行，右侧当前固件版本（读不到 `--`），有新版本红点，本机有进行中的升级显示「升级中」；进页拉设备详情（目标版本 / 升级包）并核对本地记录，收到 `ota.result` 或从升级页回来刷新。
- 消息中心：新增 `OTA_SUCCESS`「固件升级成功」/ `OTA_FAILED`「固件升级失败」，详情一行显示 `旧版本 → 新版本`（或目标版本），reason=timeout 显示「升级超时」。

### 轮播开启中标记（c8d8bb9）

- `WifiSlideshowStore`：按设备记 `GET /api/device/strategy` 的 `running`，查不到保持上次、不弹错，各台带序号防旧结果覆盖。
- `WifiActionBar` 新增 `slideshowOn`：「轮播设置」图标右上角绿点 + 「轮播中」小标签。我的设备随每次拉列表（含从轮播设置页返回）重查；WiFi 详情进页查一次，`openWifiSlideshow` 改为返回 Future，从轮播设置页回来重查。

### 详情页设备ID、屏幕尺寸行（fc63897、e7a9d36）

- 功能栏「设备信息」后新增「设备ID」（没有显示 `--`）、「屏幕尺寸」（sizeModel 没配整行不展示）两行，只展示不可点；顶部卡片去掉设备ID与屏幕尺寸两行。

### 我的上传按设备 ID 查（e47e3bf）

- `refreshCastRecords` 新增可选 `deviceId`；图库页（我的上传）选了具体设备时带该设备的完整 6 字节 ID（`canonicalDeviceSerial(serialNumber)`），未选 / 找不到 / 不完整不带，仍按用户查。其它调用方不变。后端口径：传了 deviceId 按设备查、不再按用户。

### 分享成员加入时间（d3e14ed）

- `WifiShareMember.joinedAt` 只取接口 `joinTime`（原为 createTime 优先），空显示「--」。

### 无需改动

- a8ce496 删除设备确认文案补「成员同时失去设备」：App 已有。6468f04 分享列表「复制测试参数」：小程序自定义编译用的开发工具，不移植。

## 测试

- 新增 `test/wifi_ota_test.dart`：步骤展示、VERIFYING 非终态、失败打叉位置、未知值、版本比较、固件版本取值、busy 错误判断、本地记录存取 / 核对 / 4044 清除、分享 joinTime。
- 本机没有 Flutter 工具链，**未 analyze、未跑测试、未编译、未真机**；请本地 `flutter analyze` + `flutter test`，并在 Android / iOS 各编一次。OTA 需真机配合服务端联调。
