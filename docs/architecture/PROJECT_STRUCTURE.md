# BoltStar 当前架构

> 文档类型：Architecture  
> 状态：Active  
> 最后核验：2026-07-28  
> 事实来源：当前源码、CodeGraph、`pubspec.yaml`

## 1. 系统概览

BoltStar 采用 feature-first 的 Flutter 结构，同时保留少量跨业务的应用层、状态层、网络层和
BLE 设备层。产品主链路为：

```text
main.dart
  → BoltStarApp
    → PhotoFrameState + BleController
      → AppShell
        ├── HomePage
        └── MinePage
```

主导航只有“首页 / 我的”两个 Tab。各页面使用共享的 `PhotoFrameState`，不会自行创建业务状态
实例。复杂能力通过网络层、BLE 控制层、投屏服务和共享组件下沉。

## 2. 当前源码结构

```text
lib/
├── main.dart
└── src/
    ├── app/
    │   ├── bolt_star_app.dart
    │   └── app_theme.dart
    ├── device/
    │   ├── ble/
    │   │   ├── ble_ab_benchmark.dart      # ⚠️ 临时对照实验，定版后删除
    │   │   ├── ble_direct_connect_cache.dart
    │   │   ├── ble_tuning.dart
    │   │   ├── device_ble.dart
    │   │   ├── frame_protocol.dart
    │   │   ├── image_codec.dart
    │   │   └── ota_ble.dart
    │   ├── battery_cache.dart
    │   ├── ble_connection_lease.dart
    │   ├── ble_controller.dart
    │   ├── device_identity_registry.dart
    │   ├── device_interaction_trace.dart
    │   ├── frame_device_protocol.dart
    │   └── serial_match.dart
    ├── features/
    │   ├── account/
    │   ├── ai/
    │   ├── cast/
    │   ├── devices/
    │   ├── gallery/
    │   ├── guide/
    │   ├── home/
    │   ├── mine/
    │   ├── settings/
    │   └── shell/
    ├── network/
    │   ├── api_client.dart
    │   ├── api_config.dart
    │   ├── api_exception.dart
    │   ├── api_rows.dart
    │   ├── api_session.dart
    │   ├── boltfox_api.dart
    │   ├── boltstar_ai_api.dart
    │   ├── crypto_util.dart
    │   └── dithering_api.dart
    ├── routes/
    │   └── app_routes.dart
    ├── shared/
    │   ├── l10n/
    │   ├── widgets/
    │   ├── ai_service_consent.dart
    │   ├── avatar_upload.dart
    │   ├── image_cache_cleanup.dart
    │   ├── permission_gate.dart
    │   └── temp_cache_sweeper.dart
    ├── app.dart
    ├── native_device_api.dart
    └── state.dart
```

不存在独立的 `features/album` 或 `features/demo` 模块。相册/图库能力位于 `gallery`，演示与
工程诊断入口分别落在具体 feature 内。AI 模块已经存在，但正式用户入口由功能开关控制。

## 3. 业务模块

| 模块 | 职责 |
| --- | --- |
| `shell` | “首页 / 我的”双 Tab 壳层与 Android 返回行为 |
| `home` | 首页、设备卡、拍照/相册投屏入口、绑定入口 |
| `mine` | 个人中心与图库、设备、投屏记录、指南、设置入口 |
| `account` | 邮箱/微信登录、注册、找回/修改密码、资料、邮箱变更 |
| `devices` | 扫描绑定、设备列表/详情、轮播、清空、解绑、OTA、BLE 调试与性能自检 |
| `cast` | 选图、预览编辑、后端转帧、BLE 图传、结果页和投屏记录 |
| `gallery` | 用户图库、设备筛选、批量删除、刷屏与再次投屏 |
| `guide` | FAQ/操作指南的全量分页、语种刷新和 HTML 子集展示 |
| `settings` | 语言、用户/隐私/AI 服务协议、版本检查、退出与注销 |
| `ai` | 星宝会话、按用户授权、图文对话、图片压缩/增强和四语种错误映射 |

## 4. 跨模块架构

### 应用与状态

- `main.dart` 先全局启用 Android 系统 Photo Picker，再初始化缓存、BLE 调优和插件日志级别，
  最后启动 `BoltStarApp`。
- `BoltStarApp` 持有 `PhotoFrameState`、生命周期观察、路由和崩溃现场提示。
- `PhotoFrameState` 是页面共享的业务状态门面，负责账号、设备、图库、投屏记录和网络动作。
- 生命周期通过 `BleConnectionLease` 区分前台、切出和息屏，管理 BLE 宽限与回收。

### 路由

- 稳定页面入口在 `AppRoutes.onGenerateRoute` 中维护。
- 带参数的业务流和需要局部编排的页面允许直接使用 `AppPageRoute`。
- 路由表只做页面分发；连接、权限、删除、清空和 OTA 等业务判断留在状态层或流程函数。
- `bleDebug` 只在 debug 构建开放；`blePerf` 为正式包内可达的隐藏诊断页。

### 网络

- `ApiClient` 负责 BoltFox 请求头、会话参数、响应解析、上传和统一异常。
- `BoltFoxApi` 封装账号、产品、设备、图库、投屏记录和版本接口。
- `DitheringApi` 负责 seekink 图片抖动/六色帧服务及 token 缓存、401 刷新。
- `BoltStarAiApi` 是独立第三方 AI 服务，不复用 BoltFox 的响应壳和公共参数。
- `AiServiceConsent` 以协议版本和 BoltFox 用户 ID 隔离本地同意状态；AI 发送前统一检查，
  退出、注销成功和登录态失效时由 `PhotoFrameState` 清理。

当前接口契约见 `API_INTEGRATION.md`。

### BLE

```text
UI / PhotoFrameState
  → BleController
    → FrameBleClient
      → FrameProtocol / FrameDeviceProtocol
        → flutter_blue_plus / 原生能力
```

- `BleController` 统一权限、扫描、连接、身份确认、设备信息、图传、OTA、保活与租约。
- `FrameBleClient` 管理 GATT、MTU、连接间隔、指令、ACK、分包和重试。
- `DeviceBatteryCache` 以完整设备 ID 缓存 15 秒电量并合并并发 `0x04` 读取。
- `DeviceIdentityRegistry` 以后端记录主键落盘完整 6 字节 ID，供列表接口漏发 `deviceId` 时
  兜底补齐；只作补齐链最后一档，不反向覆盖后端最新值，删除设备与退出登录时清理。
- 广播短 ID 只用于筛选候选；后端记录、绑定入库与活动会话认领必须使用完整
  6 字节 ID，建连后再次读取 0x01 做最终验身。
- 同一时刻只维护一个目标设备会话，连接切换必须先清理旧连接状态。

长期规则见 `BLE_CONNECTION_AND_IDENTITY.md`。

### 投屏与图片

- `CastPhotoPicker` 使用系统相机/相册并在入口控制源图尺寸。Android 的投屏、AI 和头像相册
  入口统一由 `main()` 配置为系统 Photo Picker，只获取用户选中图片的访问权，不经过
  `PermissionGate`，也不声明媒体整库读取权限。
- `CastPreviewPage` 使用常驻编辑层支持平移、缩放、旋转、横竖取景框和多图切换。
- 编辑结果由 Canvas 按设备物理分辨率烘焙；横向内容按 270° 规则写入竖向设备画布。
- `CastImageEditor` 负责未编辑图片的中心裁切缩放及 RGBA → JPEG 92% 编码。
- `ProjectionService` 并行处理记录上传、服务端六色帧和 BLE 图传。

原生 `image_cropper` 不再参与当前投屏预览链路。

### 资源生命周期

- Flutter 图片缓存上限在 `main.dart` 配置。
- 系统内存压力由 `BoltStarApp.didHaveMemoryPressure` 主动清理图片缓存。
- 临时投屏文件在冷启动由 `TempCacheSweeper` 回收。
- 退出、注销和会话失效统一清理内存及磁盘图片缓存。

长期规则见 `RESOURCE_LIFECYCLE.md`。

## 5. 共享约定

- 新业务页面优先放入 `features/<domain>/presentation/`；领域服务放在对应 feature 根目录。
- 跨业务组件放 `shared/widgets`，跨业务工具放 `shared`。
- 用户可见文案必须进入 `AppL10n`；工程调试页可明确标注为不接 i18n。
- 设备名称不是物理身份；设备身份以协议返回的完整 ID 为准。
- 电量只以 `0x04` 为页面数据源；0% 合法、未知显示 `--`、失败保留旧值。
- 网络 DTO/接口变化更新 API 文档，BLE 语义变化更新对应 Decision 文档。
- 当前符号位置、调用链和影响范围以 CodeGraph 为准，不在 Markdown 复制完整源码索引。

## 6. 测试

当前 `test/` 包含：

- `ai_service_consent_test.dart`
- `api_rows_test.dart`
- `api_session_test.dart`
- `auth_page_test.dart`
- `ble_connection_lease_test.dart`
- `ble_direct_connect_cache_test.dart`
- `ble_signal_level_test.dart`
- `boltstar_ai_api_test.dart`
- `device_battery_cache_test.dart`
- `device_identity_registry_test.dart`
- `frame_device_protocol_test.dart`
- `language_settings_test.dart`
- `serial_match_test.dart`
- `simple_html_text_test.dart`
- `wechat_login_test.dart`
- `widget_test.dart`

常规验证：

```bash
dart analyze lib test
flutter test
```

BLE 图传、连接间隔、OTA、相机/相册和平台登录仍需要真机验证。

## 7. 当前边界

- 产品发布目标是 Android/iOS；其他 Flutter 平台目录仅为生成的工程壳。
- AI 正式入口当前关闭；语音输入仍是占位，下载只落应用缓存目录。
- BLE 性能自检参数会影响正常投屏，测试后必须恢复默认。
- 临时件：`android/app/src/main/kotlin/com/boltfox/boltstar/BleNativeProbe.kt`、
  `lib/src/device/ble/ble_ab_benchmark.dart` 和性能自检页顶部的「连接对照实验」卡片
  只服务于安卓原生 vs `flutter_blue_plus` 的 A/B 实验，不属于生产连接路径；
  拆除清单见 `../history/2026-07/2026-07-30-安卓原生连接AB对比.md`。
- 历史架构、Figma 还原和改造过程已归档到
  `../history/2026-07/PROJECT_STRUCTURE_LEGACY.md`。
