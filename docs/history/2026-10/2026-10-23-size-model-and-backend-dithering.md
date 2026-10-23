# 设备详情屏幕尺寸读 sizeModel、抖动出帧迁到我方后端

> 类型：Historical Implementation Record
> 日期：2026-10-23；环境：远程 SSH 服务器；分支：main；修改前：e162214
> 对应小程序：`utils/dithering.js`、`subpackages/device/detail/*`（同日同口径）

## 需求

1. 后台产品新增/编辑/详情新增「尺寸型号」`sizeModel`（如“3.6寸”），设备列表、详情接口同样下发。App 直接展示，不再按屏型或宽高推算；没配就不展示。
2. 投屏出帧原来调第三方 seekink 抖动接口返回 .bin，现迁到我方后端 `POST /Client/Basic/imageDitheringBinDownload`（图片上传且抖动，form-data，返回 .bin）。参数一样，headers 带我们自己用户的 userToken，第三方 token 不再需要。

## 改动

- `DeviceItem` 新增 `sizeModel`（`_deviceFromJson` 读 `sizeModel` 去首尾空白）；`fetchDeviceFirmwareInfo` 详情带了该键时覆盖（含空串）。
- 设备详情页：删除 `_resolutionText`（0x01 实读宽高 → 后端宽高 → `--`），「屏幕尺寸」行改为展示 `device.sizeModel`，为空时整行连同分隔线不渲染。
- `ApiClient.postMultipartForBytes`：form-data 上传、响应为二进制；公共 header 与 `/Client/` query（含 userToken）同 `upload`；回 JSON/文本或非 2xx 时走 `_parse` 抛 `ApiException`（401/406 清会话），2xx 却无文件抛 `EMPTY_FILE`；二进制响应只打一行摘要日志，不把整帧当文本打印。
- `DitheringApi`：地址改为后端路径，经 `postMultipartForBytes` 发送；删掉 token 缓存/预热/401 强制重登；字段 `color=BWRYGB`、`imageDitheringModes=2`、`type`（沿用原取值：480×720 传 1，其余 0）、`file` 不变；网络失败（超时/ClientException/IOException）退避重试共 3 次，`ApiException` 不重试。
- 删除 `BoltFoxApi.getXTYUserToken`、投屏预览页 `DitheringApi.prefetchAuthToken()`、BLE 调试台「第三方 Token」卡片（及其 Clipboard/BoltFoxApi 引用）；`projection_service.dart` 等注释里的 seekink 改为抖动接口。
- 新增 `test/dithering_api_test.dart`：路径/userToken（header+query）/multipart 字段、二进制原样返回、业务报错不重试、401 清会话、网络失败重试 3 次。

## 未改 / 待确认

- 搜索/绑定流程里的屏幕文案仍来自蓝牙广播屏型（`BleController.screenLabelOf`）：绑定前没有设备记录，要改成 `sizeModel` 需按广播名匹配产品列表，待确认。
- Swagger 把 `type` 描述为“屏幕类型(1=顺时针90° 2=逆时针90°)”，与原第三方用法字面不同；按“参数一样”沿用原取值，需联调确认 3.7 寸设备传 1 不会被旋转。
- 后端成功响应的 `Content-Type` 未实测，判定沿用原逻辑。

## 验证

- 本机无 Flutter/Dart，`flutter analyze`、`flutter test`（含新增用例）均未运行；未真机。
- `git diff --check` 通过。

## 同日追加（用户确认后）

- 绑定页搜索列表：副标题的尺寸改为按广播名（platformName + advName）匹配产品列表 `broadcastId`（去首尾空白、大小写不敏感的包含匹配，多个命中取最长），显示该产品的 `sizeModel`；匹配不到、没配或产品列表没拉到都不显示，不再用 `BleController.screenLabelOf`。产品列表与扫描并行拉（`PhotoFrameState.loadProductSizeModels`，与设备图回查共用一次请求与会话缓存，失败静默），回来后重建列表。绑定时传给 `bindDevice` 的 `screen` 仍是广播屏型（只用于匹配打分），未改。`test/product_broadcast_id_test.dart` 新增 3 个用例。
- `type`：用户确认数值与原来一致不改（0=5.8寸大设备、1=3.7寸小设备，出帧策略非旋转角），后端按此对齐；注释与文档改为该口径。
- 验证：本机仍无 Flutter，analyze/test 未运行，未真机。
