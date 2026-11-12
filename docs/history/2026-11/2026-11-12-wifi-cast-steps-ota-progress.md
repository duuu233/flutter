# WiFi 投屏进度页加步骤、去掉投屏日志面板；WiFi 固件升级页加进度条（main）

> 类型：Historical Implementation Record
> 日期：2026-11-12；环境：远程 SSH 服务器；分支：main；修改前：287ac4f
> 依据：产品需求（投屏进度页按进度文案加四步，样式与交互同配网步骤；去掉投屏页下方的黑底投屏日志）；服务端 OTA 进度口径（`GET /api/device/ota/status` 与 WS `ota.result` 新增 `progress`）。同小程序同日改动。

## 改动

### WiFi 投屏结果页（`wifi_cast_result_page.dart`）

- 进度条卡片下方新增步骤卡，四步对应进度文案：准备投屏（取产品屏幕方向 / 渲染模式）→ 图片上传中（`UPLOADING`）→ 图片处理中（`PROCESSING`）→ 已发送，屏幕即将刷新（接口返回 `SENT` / `UPLOADED` 即打勾，写相册记录不另占一步）。文案复用 `wifiCastPrepare` / `wifiCastStage`。
- 样式与交互同配网状态页：复用 `WifiStepIcon`，每行 48 高、行间细分隔线；失败在当时那一步打叉（上传失败第 2 步、处理 / 下发失败第 3 步、投屏信息失效第 1 步），逐张记 `failStep`。多张时步骤跟着正在投的那一张走；结束后全部成功四步全勾，有失败按最后一张失败的那一步打叉。
- 去掉页面下方的黑底投屏日志面板（`_buildLogPanel`、复制、`_logs` / `_logScroll`），`wifi_l10n.dart` 删掉只给它用的 4 条文案（`wifiCastLogTitle` / `wifiCopyLog` / `wifiLogEmpty` / `wifiLogCopied`）。页面日志改 `debugPrint('[WiFi投屏] …')`，`projectOne` 不再传 `onLog`（它本身就 debugPrint），联调日志浮窗照样能看到；每张图文件大小仍只在非正式包读取。

### WiFi 固件升级页（`wifi_ota_page.dart` / `wifi_ota.dart`）

- 步骤卡上方新增进度条卡：左边当前那一步的步骤文案（`wifiOtaSteps[otaActiveStep(view)]`），右边百分比；失败转红。
- `progress`（0~100，可选）：设备私有进度回执 182 / 184 / 186 / 188 换算为 20 / 40 / 60 / 80，WS 每条回执推一次；VERIFYING 后为 100；固件不上报为 null。
- 显示值只增不减、每 200ms 匀速走 1%（`kWifiOtaProgressTick`），服务端进度只抬上限（`otaProgressCap`）：没收到停 19；收到 20 / 40 / 60 / 80 走到 39 / 59 / 79 / 98；DOWNLOADING 一直没进度值（不上报）或进入 FLASHING 走到 98；VERIFYING / SUCCESS 为 100；FAILED / TIMEOUT 停住。只认收到过的最大进度，偶发 null 不放开到 98；WS 只带 `progress` 时沿用最近一次状态。
- `WifiOtaRecord` 新增 `progress`（收到过的最大进度），`WifiOtaStore.update` / `refresh` 写入，重进页面从那里接着走。

## 验证

- `test/wifi_ota_test.dart` 新增「进度条」一组：`parseOtaProgress`、`otaProgressCap` 各档上限、`otaActiveStep`、本地记录保存最大进度且 null 不覆盖。
- 本机无 Flutter / Dart，analyze / test / 编译 / 真机都没跑；OTA 进度未联调。
