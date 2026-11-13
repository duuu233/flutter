# WiFi 投屏幂等键 Idempotency-Key（main）

> 类型：Historical Implementation Record
> 日期：2026-11-13；环境：远程 SSH 服务器；分支：main；修改前：a5c73fc
> 依据：服务端投屏去重幂等口径（Header `Idempotency-Key`，按 deviceNo + 键去重 10 分钟，失败不缓存；新增错误码 4090）。同小程序同日改动。

## 现状结论（改之前确认）

`IotClient.upload`（`POST /api/device/play`）不做网络重试，只有 GET 静默重试 2 次；唯一再次发送的是结果页「重试未成功的」（用户手动）。

## 规则

- **批量投屏每张图各生成一个新键，绝不整批共用一个**。
- 「重试未成功的」：同一张图、同样的刷屏方式复用原键；刷屏方式变了（原只上传、重试成最后一张要刷屏）换新键。
- 新进入结果页（含「继续投屏」pushReplacement 回来）键全部重新生成。
- 4090 = 同一键首次请求还在处理中：提示「处理中，请稍后重试」，再点重试复用原键。

## 改动

- `wifi_projection.dart`：`WifiProjection.newPlayKey()`（`Random.secure` 生成 UUID v4，不加依赖）；`projectOne` 新增 `idempotencyKey` 透传并记日志。
- `iot_api.dart`：`play` 有键才带 Header `Idempotency-Key`；`iot_client.dart`：`upload` 支持额外请求头，码表登记 4090（简 / 英 / 日，可重试）。
- `wifi_cast_result_page.dart`：`_playKeys`（`序号:refresh` → 键），每张图 `putIfAbsent` 取或生成自己的键。

## 验证

- `test/wifi_projection_progress_test.dart` 新增一组：键的形状 / 唯一 / 长度、4090 解析、结果页按图记键与 Header 带键的源码断言（Python 对源码核对过）。
- 本机无 Flutter / Dart，analyze / test / 编译 / 真机未跑，未联调。
