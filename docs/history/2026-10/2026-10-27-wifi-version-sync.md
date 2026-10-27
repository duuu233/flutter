# main-wifi：WiFi 版设备功能对齐小程序 main-wifi

> 类型：Historical Implementation Record
> 日期：2026-10-27；环境：远程 SSH 服务器；分支：main-wifi（自 main 399e8c7 新建）
> 对应小程序：`photo-album` main-wifi 分支（截至 f336637，2026-10-26～27 的 WiFi 版 STEP 0～3 与列表样式调整）

## 分支约定

- `main`：线上版本（蓝牙版），保持稳定，与小程序 `main` 对齐。本次核对：小程序 `main` 最新 96cb17b（搜索列表尺寸没配显示「--寸」）已由 App 399e8c7 同步，`main` 无待同步内容。
- `main-wifi`：WiFi 版设备开发分支，与小程序 `main-wifi` 对齐；`main` 上修的问题需及时合入 `main-wifi`。

## 改动

### 基础层（新增）

- `lib/src/device/wifi/broadcast_match.dart`：广播名 ↔ 产品广播 ID 匹配。`*` 模板（后台配置 + 内置 `IJ_*`）整名命中、中间正好 12 位取 deviceNo；`isWifiBroadcastId` 按产品广播 ID 认已绑定的 WiFi 版；`rssiToBars` 信号格（≥-55 四格 / ≥-67 三格 / ≥-78 两格 / 更弱一格 / 未知 0 格）。
- `lib/src/device/wifi/blufi.dart`：乐鑫 BluFi（服务 FFFF，写 FF01 / 通知 FF02）编解帧、分片、会话；设备扫描附近 WiFi（标准 0x11 与本设备自定义文本两种回包）、下发 STA 名称密码、`mqtt_config` / `wifi_set_country_code` JSON 指令（按 ack_msgid 对回执）、连接 WiFi。不做 DH/AES 协商（产品确认先不加密）；密码帧与自定义数据帧不出日志。
- `lib/src/network/iot/`：IoT 服务客户端。`iot_client.dart`（`{code,msg,data}` 解包、错误码表四语种、**401 走登出、503 不登出**、GET 网络静默重试、multipart 上传带进度）、`iot_api.dart`（在线、设备信息、投屏上传、投屏状态、配网 MQTT 参数）、`iot_ws.dart`（WebSocket 推送：按需连接、30 秒心跳、1s→30s 退避重连、重连后补订、回前台立即重连）。地址可用 `--dart-define=IOT_BASE_URL / IOT_WS_URL` 切换。
- `BoltFoxApi.lookupProductByDevice` / `normalizeWifiProduct`：WiFi 设备按 12 位 deviceNo（不带冒号）查产品规格，空壳记录算查不到，不重试、不缓存。
- `PhotoFrameState.bindWifiDevice`：addUserProduct（deviceId 带冒号），已绑定复用；`DeviceItem.isWifi`；IoT 401 接 `_handleSessionExpired`；退出 / 失效 / 注销时关 WebSocket、清云端状态缓存。

### 页面

- 扫描：`FrameBleClient.scan` / `BleController.scan` 加 `includeWifi`，只有搜索设备页收录 WiFi 版；其余扫描入口（连接前扫描、自动重连、调试台白名单）一律不收，带 `*` 的广播 ID 不参与包含匹配。内置兜底名单加 `IJ_*`。
- 搜索设备页：两类设备同列表；第二行改为「通信类型标签包住尺寸（如 WiFi版·5.89寸 / 蓝牙版·--寸）→ 电量（蓝牙版）→ 信号 + 信号格」，信号格上提 1.5px（对应小程序同日「信号格往上移」）；WiFi 行设备ID 显示 deviceNo 加冒号，规格查询中显示小圆圈、查不到为「未知设备」（警示色）；选中 WiFi 版时底部为「立即配网」：查询中提示稍候、未知设备弹「未知设备，请联系客服开通」（非正式包带原因）、查到的先停扫 → BluFi 连上 → 进 WiFi 列表。
- 新页 `features/wifi/presentation/`：
  - `wifi_list_page.dart` 选择 WiFi：设备扫描、只留 2.4G、同名取强、边收边显示、重新搜索、手动输入；离开本页断开蓝牙。
  - `wifi_config_page.dart` 账号密码：名称带入、切换图标回列表、密码默认密文 + 小眼睛；名称密码内存交接，不进路由。
  - `wifi_provision_page.dart` 配网状态：四步（手机网络 → 取 MQTT 参数 + BluFi 下发 WiFi / mqtt_config / 国家码 + 连接 WiFi → 绑定 → 轮询上云 60 秒），失败按钮上下排（重新配网整行在上、取消橙色文字在下），成功「立即体验」选中该设备回首页。
  - `wifi_device_detail_page.dart` WiFi 设备详情：设备信息行（电量 / WiFi 信号 / 名称 / 固件 / TF / 国家码 / 最后上线 / 最后心跳）、订阅 `device.status` 自动重查、「投屏」「刷新状态」。`AppRoutes.figmaDeviceDetails` 对 WiFi 版分流到这里。
  - `wifi_cast_result_page.dart` WiFi 投屏结果：逐张上传进度 → 处理中 → 已下发 → 刷屏 → 终态（WS `play.result` 为主、3 秒状态查询兜底、TIMEOUT 再等 3 秒、90 秒未知、4044 过期），「重试未成功的」「完成」。不写投屏记录（相册归属待产品）。
- 我的设备：按 WiFi版 / 蓝牙版分组（WiFi 在前，有设备才出该组标题）；WiFi 卡显示云端在线 / 离线 / 状态未知、信号格、电量，按钮「投屏」「刷新状态」（没有连接 / 断开）；点卡进 WiFi 详情。
- 首页：WiFi 卡显示云端状态与电量、无「连接蓝牙」；拍照 / 相册对 WiFi 版只确认在线（明确离线拦，查不到放行）。
- 投屏预览：WiFi 版导出后 `pushReplacement` 到 WiFi 投屏结果页（type 与抖动出帧同口径）。
- 官方图库详情：选中 WiFi 版不连蓝牙、不弹低电量，确认在线后进预览；设备选择弹层 WiFi 版挂「WiFi版」角标。
- 文案：`features/wifi/wifi_l10n.dart`（`AppL10n` 扩展，简中与小程序逐字一致，英 / 日新译，繁中自动转换）。
- 状态缓存：`features/wifi/wifi_status.dart` `WifiStatusStore`（首页 / 我的设备 / 详情共用，沿用上次结果避免闪「查询中」，各台带序号防旧请求覆盖）。

### 测试

- 新增 `test/wifi_protocol_test.dart`：广播匹配、信号格、BluFi 编帧 / 分片 / 列表与 JSON 解析 / 密码帧不出 hex、IoT 错误码（401 / 503 / 5xx / 429）、规格归一、云端状态字段，用例取自小程序同名测试。

## 未做 / 差异

- 小程序调试台的「IoT 联调」卡未移植（App 调试台不加）。
- AI 对话、我的相册「再次投屏」、投屏管理入口未接 WiFi 版（与小程序现状一致：选 WiFi 版仍走蓝牙会失败）。
- 配网全程不保持屏幕常亮（App 未引入 wakelock 依赖；小程序有 `setKeepScreenOn`）。
- 第 1 步「手机网络」用解析 IoT 域名判断（App 无网络类型 API 依赖），超时按放行处理。
- 头图、WiFi / 蓝牙 / 小眼睛图标用 Material 图标代替小程序 svg，不新增图片资源。
- 新增简中文案里若有繁中转换表缺的字，繁中会残留简体，待按 2026-09-14 的方法复核。

## 验证

- 本机无 Flutter SDK：`flutter analyze`、`flutter test` 未运行；未编译、未真机、未与 IoT 联调。
- 用 Dart SDK 3.12.2 对全部改动 / 新增文件跑 `dart format --output=none` 解析通过（只证明语法，不含类型检查）。
- 文案 key 引用逐个核对存在；`git diff --check` 通过。
