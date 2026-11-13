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
