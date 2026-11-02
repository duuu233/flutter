# 抖动出帧基地址改由 download-endpoint 下发；我的设备连接后平滑回顶

> 类型：Historical Implementation Record
> 日期：2026-11-02；环境：远程 SSH 服务器；分支：main；修改前：399e8c7
> 对应小程序：`utils/dithering.js`、`subpackages/device/list/list.js`（同日同口径）

## 需求

1. 抖动出帧的基地址不再固定：先调 `https://iot.boltfox.cn/api/device/download-endpoint`，返回结构与 IoT 接口一致（`{ code: 0, msg, data }`），`data` 为基地址，如 `https://api.boltfox.cn/` 或其它反代域名；最终请求 基地址 + `Client/Basic/imageDitheringBinDownload`，参数不变。
2. 「我的设备」蓝牙设备连接后，连上的设备排到第一张，列表当前位置要平滑滚回顶部。

## 改动

- `DitheringApi.resolveBaseUrl`：`GET download-endpoint`（Header `userToken`，5 秒超时，走 `ApiClient.instance.httpClient`），`code=0` 且 `data` 是 http(s) 地址时去掉末尾 `/` 作为基地址，内存缓存 10 分钟；网络失败、`code≠0`、`data` 不是地址时回落 `ApiConfig.baseUrl`，不缓存，下次重新取。`requestFrameBin` 先取基地址再上传，form 字段、公共参数、报错与重试均不变。
- `ApiClient.postMultipartForBytes` 新增可选 `baseUrl`，`_uri` 支持覆盖默认基地址；`/Client/` 公共 query 仍按路径判定照常拼，其它调用不受影响。
- `MyDevicesPage`：`ListView` 挂 `ScrollController`；`promotedDeviceId` 由空变为某台（连接设备切换、那台已排到第一张并开始播上移动效）时，下一帧 `animateTo(0, 300ms, easeOutCubic)`，已在顶部不动。
- 小程序后台域名限制不适用于 APP；APP 需能访问 `iot.boltfox.cn` 与下发的基地址域名。

## 验证

- `test/dithering_api_test.dart`：原有断言改为基地址取自 download-endpoint，新增缓存、反代域名带路径、失败回落且不缓存三组用例。滚回顶部未加 widget 测试。
- 本机无 Flutter/Dart，`flutter analyze`、`flutter test` 未运行；未真机、未联调。
- `git diff --check` 通过。
