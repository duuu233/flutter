# WiFi 版渲染固件管理（FPGA 版本安装）（main）

> 类型：Historical Implementation Record
> 日期：2026-11-13；环境：远程 SSH 服务器；分支：main；修改前：fa7d672
> 依据：产品需求（只有渲染模式 = FPGA16 的设备，设备信息页新增「渲染固件管理」；列出后台启用的 FPGA 版本，点安装进同 OTA 样式的步骤页并带出简介；复用 `POST /api/device/ota`，`type=fpga`、`version` = FPGA 目标版本，其余与固件升级一致）。同小程序同日改动。

## 改动

- 设备信息页（`wifi_device_info_page.dart`）：`state.resolveRenderMode` 为 `fpga16` 时多一行「FPGA版本」（影子 `fpgaVersion`）和「渲染固件管理」入口。
- 新增 `wifi_fpga.dart`：`isFpgaRenderMode`、`WifiFpgaVersion`、`normalizeWifiFpgaVersions`（未启用的去掉、按权重排、简介字段按 `kWifiFpgaIntroFields` 兜底）、`fetchWifiFpgaVersions`。⚠️ 用户端列表接口后端还没提供，路径集中在 `kWifiFpgaListApi`（为空不请求）；`BoltFoxApi.getFpgaVersionList` 为对应调用。
- 新增 `wifi_fpga_page.dart`：当前 FPGA 版本、版本列表（版本号、简介、安装 / 重新安装、当前版本标记）；接口未开放显示「版本列表暂未开放」；非 fpga16 提示不支持。
- `WifiOtaPage` 新增 `fpgaTarget`：传了即安装模式，不比对版本，展示目标版本、当前 FPGA 版本、版本简介；下发 `IotApi.startOta(type: 'fpga', version: 目标版本, url: 固件地址)`；进度、四步、轮询 / WS、本地记录全部沿用，只换文字（渲染固件安装 / 安装完成 / 安装失败 / 立即安装 / 重新安装 …）。
- `WifiOtaRecord` 新增 `otaType`、`intro`（main 时不写入，旧记录按 main）；重进时按记录里的类型选文字。
- `wifi_l10n.dart` 新增渲染固件相关文案（简 / 英 / 日）。

## 验证

- `test/wifi_ota_test.dart` 新增「渲染固件管理」一组：渲染模式判断、版本列表规整、本地记录类型与简介（含旧记录兼容）、接入位置（源码断言用 Python 对实际文件核对过）。
- 本机无 Flutter / Dart，analyze / test / 编译 / 真机都没跑；列表接口待后端，FPGA 安装未联调。

## 补充（同日）：改名「优雅刷新升级」、4047、不显示设备 FPGA 版本

- 「渲染固件管理」改名「优雅刷新升级」（简 / 英 / 日：优雅刷新升级 / Smooth refresh update / スムーズリフレッシュ更新），安装页文案同步。
- 设备不上报 FPGA 版本（`baseVersion` 为 null）：去掉设备信息页「FPGA版本」行、列表页当前版本与「当前版本 / 重新安装」标记、安装页版本卡的「当前版本」行；删掉对应文案。
- `POST /api/device/ota`（`type=fpga`）返回 4047：`isWifiFpgaLimitError` 捕捉，提示 `wifiFpgaLimit`（简 / 繁 / 英 / 日「今日升级次数已达上限」），停在当前页、不存记录。
- `test/wifi_ota_test.dart` 补 4047 判断与「不显示版本号」源码断言；本机无 Flutter，未运行。

## 再补充（同日）：去掉版本列表，改为读最新版本 + 红点提醒

> 产品改口：消息推送要闭环的内容太多，去掉后台推送；APP 去掉优雅刷新版本列表，仅读接口的最新版本，用红点提醒。

- 最新版本只读设备详情新增出参：`DeviceItem.fpgaVersionNo / fpgaDownloadPath / fpgaUpgradeTips`（`newVersionNoFpga / downloadPathFpga / upgradeTipsFpga`），`fetchDeviceFirmwareInfo` 刷新时带回。删除 `wifi_fpga_page.dart`、`kWifiFpgaListApi` 与 `BoltFoxApi.getFpgaVersionList`。
- 设备信息页「优雅刷新升级」直接进 `WifiOtaPage(fpga: true)`（参数由 `fpgaTarget` 改为 `fpga`），显示最新版本与版本说明；后台没有版本时显示「暂无可用的优雅刷新版本」。
- 红点（`wifi_fpga.dart`：`wifiFpgaHasNew` / `WifiFpgaSeenStore`）：本地缓存看过的版本号 `fpga_seen:{deviceNo}`，fpga16、有版本且地址有效、缓存为空或最新更高 → WiFi 详情「设备信息」与设备信息页入口亮红点；进优雅刷新升级页即记下，返回后重算消失。重装 / 换手机会再提醒。
- 4047 多语种提示与不显示设备 FPGA 版本保持；版本行标签统一「最新版本」；删掉不再使用的列表文案，新增「暂无可用」两条。
- `test/wifi_ota_test.dart` 该组重写（版本比较、红点与缓存、记录类型、4047、接入位置），`test/firmware_gate_test.dart` 设备信息入口断言挪到新写法；本机无 Flutter，未运行。

## 补充（2026-11-14）：入口不再晚 1 秒出现、文字与上面一致

- 原因：设备列表不下发 productId，设备信息页解析渲染模式要按设备号查一次产品（约 1 秒），查到才显示入口；信息行加载中时入口也被隐藏。
- 改法：`PhotoFrameState.resolveRenderMode` 解析到的值按设备记一份（会话内，`cachedRenderMode`）。设备详情页进页时已经解析过一次，设备信息页据此进页就显示入口，并先按现有数据算红点；入口不随信息行加载态隐藏。进页仍重新解析一次校正：不是 fpga16 时隐藏。
- 入口文字改为与上面信息行标签同样式（`0xFF5E6470`、14、常规字重）。`test/wifi_ota_test.dart` 补断言。
- 本机无 Flutter，未运行测试、未真机。

## 补充（2026-11-14）：不做红点

- 产品要求优雅刷新不做红点：去掉 WiFi 详情「设备信息」行与设备信息页「优雅刷新升级」入口的红点，以及进安装页记下看过版本号的本地缓存（`WifiFpgaSeenStore`、`wifiFpgaHasNew`、`isWifiFpgaNewer` 删除）。
- WiFi 详情页进页仍先解析一次渲染模式（原来顺带在算红点时做），设备信息页入口照样进页即显示。
- `test/wifi_ota_test.dart` 原红点用例撤掉，改为断言不再显示、不再记录。本机无 Flutter，未运行测试。

## 补充（2026-11-14）：安装页不显示顶部图标

`WifiOtaPage` 优雅刷新模式（`_fpga`）不显示标题上方的图标，普通固件升级照旧；`test/wifi_ota_test.dart` 补断言。本机无 Flutter，未运行。

## 补充（2026-11-14）：设备信息行取值不再被截断（安卓）

- 原因：信息行是「标签 + Spacer + Flexible(取值)」，Spacer 与 Flexible 各分一半剩余宽度，取值最多只能用一半。安卓字体略宽，「最后上线 / 最后心跳」的时间被截成「...」；iOS 字体窄，刚好放得下。
- 改法：标签后留 12 的间距，取值（含信号格）放进 Expanded 右对齐，吃满剩余宽度；仍是单行、真放不下才省略。`test/wifi_ota_test.dart` 补断言。本机无 Flutter，未运行、未真机。

## 补充（2026-11-14）：暂无可用版本时内容居中

优雅刷新模式 `_phase == latest` 且不显示版本卡（即「暂无可用的优雅刷新版本」）时，`FigmaScreen(fillViewport: true)`，标题上下各放一个 Spacer，内容在页面里上下居中。其它状态与普通固件升级不变。本机无 Flutter，未运行。
