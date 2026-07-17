# 2026-07-17 项目全维度优化分析（只读审查，未改任何代码）

> **审查对象**：当前工作区全量代码（85 个 Dart 文件 / 约 31,358 行）+ Android 原生 BLE 服务。
> **审查方式**：五个维度并行深度静态阅读——底层架构与状态管理、BLE 层与设备通信、网络层与会话、UI 崩溃与渲染/内存性能、可维护性与一致性。本机无 Flutter 工具链，所有结论来自静态分析与交叉验证；**任何修复动手前，建议在开发机先跑 `flutter analyze` + `flutter test` 建立基线**。
> **总原则**：所有建议均按"谨慎改动原有功能"设计——优先给出**不改变行为语义**的渐进式改法，每项标注回归面。本文档只记录，不改代码；由你逐项挑选后再实施。

---

## 目录

1. [总体评价](#一总体评价)
2. [优先级速查总表](#二优先级速查总表)
3. [稳定性与缺陷类发现（S 系列）](#三稳定性与缺陷类发现s-系列)
4. [结构与可维护性类发现（M 系列）](#四结构与可维护性类发现m-系列)
5. [性能与体验类发现（P 系列）](#五性能与体验类发现p-系列)
6. [建议执行批次](#六建议执行批次)
7. [明确建议保持现状、不要动的部分](#七明确建议保持现状不要动的部分)

## 修复进度

| 日期 | 编号 | 状态 | 实施摘要 |
|---|---|---|---|
| 2026-07-17 | S1 | ✅ 已修复 | ① `state.dart` refreshDevices：选中项落空改**置空**不切首台；② `app_routes.dart` onDeleteDevice：流程开头快照 `deviceId`，断开/删除全用快照（快照为空直接返回）；③ `device_clear_confirm_page.dart`：`_deviceId` 进页快照，清空用快照。轮播设置入口的连接检查（app_routes.dart onCarouselSettings）为非破坏性、有意保留实时读；路由传参化留待长期项。 |
| 2026-07-17 | S8 | ✅ 已修复 | 新增 `lib/src/shared/avatar_upload.dart`（`AvatarUpload.maxBytes/maxEdge/ensureUnderLimit`，自 profile 页原样迁移）；首页 `_changeAvatar` 补 `pickImage(512/512/q85)` + 兜底压缩 ≤100KB；profile 页改用共享实现（行为不变）；首页 36lp / 资料页 32lp 两处本地回显 `Image.file` 补 `cacheWidth`。 |
| 2026-07-17 | S9 | ✅ 已修复 | `home_widgets.dart` `_DeviceCarousel.didUpdateWidget` 的 `jumpToPage` 包进 `addPostFrameCallback`（mounted + hasClients 守卫），构建期不再可能触发 notifyListeners。 |
| 2026-07-17 | S10 | ✅ 已修复 | `projection_service.dart` `startPrefetch` 赋值后 `prefetch[idx]!.ignore()`（主循环 await 仍照常拿到错误）；复投路径 `frameFuture` 创建后无异步间隙即被 await，确认无需改动。 |

> 以上均为静态修改，本机无 SDK 未编译；**需在开发机跑 `flutter analyze` + `flutter test`**，手测回归点：删除设备/一键清空全流程、多设备时首页轮播切换与刷新、首页与资料页换头像、弱网连投多张（含中途断网）后重启看是否误弹崩溃报告。

**优先级定义**：
- **P0**：存在数据破坏或严重误操作的现实窗口，应尽快修。
- **P1**：已知崩溃同源 / 确定性资源泄漏 / 用户可复现的功能性缺陷 / 发布质量问题，改动小、收益确定。
- **P2**：低概率但后果重的缺陷、结构性技术债、防恶化投资，可按批次排期。
- **P3**：加固、余量优化、清理项，随日常迭代顺手做。

---

## 一、总体评价

### 各维度健康度

| 维度 | 健康度 | 一句话结论 |
|---|---|---|
| 架构/状态管理 | ★★★☆☆ | "根部精心优化、腹部超载"：根组件重建收窄、监听配对、路由 arguments 零滥用都做得干净；但 3188 行 `PhotoFrameState` 以 12 类职责 + 46 处全局广播成为全部复杂度汇聚点，并衍生出本次唯一的 P0。 |
| BLE 层 | ★★★★☆ | 设计成熟度明显高于同类项目：协议层纯函数、全链路超时有界、写全部 await、租约/心跳/前台服务生命周期闭环清晰。两个 P1 都集中在**非 happy-path 的资源回收**（连接失败不回收、重连订阅泄漏）。 |
| 网络层 | ★★★★☆ | 纪律性强：超时/重试/日志脱敏/字段名溯源/安全解析大面积做对。残留两个 P1：上传响应体的无界等待、非幂等 POST 的超时重试（验证码双发可复现）。会话模型简单自洽，无刷新竞态。 |
| UI 稳定性/性能 | ★★★★☆ | 卫生水平高于平均：列表全惰性构建、CachedNetworkImage 全量 memCacheWidth、Timer/Controller 无一泄漏、四分支加载态成体系。风险集中在 loading 弹窗的 4 处盲 pop 残留和首页两个尖点（换头像原图位图、轮播构建期 notify）——都落在曾发生崩溃的首页。 |
| 可维护性 | ★★★☆☆ | "注释文档一流、结构卫生二流"：协议注释、事故复盘、依赖选型说明属顶部水平，TODO 债务几乎为零；但 537 处硬编码颜色、三套样式表、约 800 行死代码、双 i18n 体系在持续累积改版成本。 |

### 与"首页崩溃排查"的关系（重点）

本次发现三项与已知"华为系疑 Impeller 崩溃"直接相关，建议在下一轮崩溃归因**之前**先消除这些干扰项，否则崩溃日志信噪比会持续被污染：

1. **S8**：首页换头像走相机原图（可达 48MB 位图瞬间进 ImageCache）——大位图 + 华为 Vulkan 驱动正是该类崩溃的常见组合；
2. **S10**：投屏预取 Future 失败无监听 → 普通弱网失败被写入 `last_crash.txt` 并在下次启动弹"崩溃报告"，把正常失败伪装成崩溃；
3. **S9**：首页轮播 `didUpdateWidget` 里 `jumpToPage` 可触发构建期 `notifyListeners`——排查中发现的**唯一真实框架级异常路径**。

---

## 二、优先级速查总表

| 编号 | 优先级 | 问题 | 主要位置 | 改动量 |
|---|---|---|---|---|
| S1 ✅已修 | **P0** | 详情/清空页依赖全局 `selectedDeviceId`，并发刷新可静默切换选中设备 → "一键清空"可能落到**错误设备** | state.dart:2088；app_routes.dart:162-275 | 小 |
| S2 | P1 | BLE `connect()` 失败路径不回收物理连接 → 僵尸会话、设备搜不到、前台服务/心跳空转耗电 | device_ble.dart:220-283 | 小 |
| S3 | P1 | 远端断开后 `_notifySub`/`_connSub` 泄漏，重连后每条通知被重复处理 N+1 次 | device_ble.dart:229-235, 277-278 | 小 |
| S4 | P1 | 4 处残留"loading 盲 pop"（与历史闪退同根因） | home_page.dart:455 等 4 处 | 极小 |
| S5 | P2 | 约 9 处 `!mounted` 早退跳过 hide → 全屏模态 loading 永久滞留锁死 App | home_page/gallery/cast_preview 等 | 小 |
| S6 | P1 | 上传响应体读取无超时，弱网可永久挂起（loading 无限转圈） | api_client.dart:215-218 | 极小 |
| S7 | P1 | 非幂等 POST 超时后静默重试 → 验证码双发、投屏记录重复 | api_client.dart:153-182 | 小 |
| S8 ✅已修 | P1 | 首页换头像用原图：~48MB 位图进内存 + 原图直传（与 profile 页行为不一致） | home_page.dart:320；home_widgets.dart:355 | 小 |
| S9 ✅已修 | P2 | 首页轮播 `didUpdateWidget`→`jumpToPage` 同步触发构建期 notify | home_widgets.dart:515-534, 561-565 | 小 |
| S10 ✅已修 | P2 | 投屏预取 Future 无错误监听 → 弱网失败污染崩溃日志与启动弹窗 | projection_service.dart:192-207 | 极小 |
| S11 | P2 | `reconcileConnections` 用 FBP 内存镜像对账，查不出它想查的死会话 | ble_controller.dart:487-504 | 小 |
| S12 | P2 | `connect`/`connectBoundDevice` 无重入护栏，并发连接互相踩状态 | ble_controller.dart:364-401 | 极小 |
| S13 | P2 | 登出/换号后在途响应回填旧账号数据（跨账号串屏窗口） | state.dart:1581-1601, 2564 | 小 |
| S14 | P2 | 畸形 2xx（网关 HTML 页）被吞成 `{}` 按成功返回 | api_client.dart:233-243 | 极小 |
| S15 | P2 | `catch (_)` 把编程错误/文件不存在伪装成"网络连接失败"并白白重试 | api_client.dart:173-180, 225-227 | 小 |
| S16 | P2 | 投屏记录"再次投屏"无并发锁、20s 下载期无 loading | cast_management_figma_page.dart:104-157 | 小 |
| S17 | P2 | 前台服务无 wakelock，Doze 下 25s 心跳停发 → "息屏 30 分钟"定版在激进 ROM 上达不到 | BleConnectionService.kt | 中（需真机验证） |
| S18 | P1 | 硬件调试台在 **release 包对最终用户可达**（可发任意 BLE 指令） | bind_device_debug_entry.dart；app_routes.dart:105 | 极小 |
| S19 | P2 | `connectDevice` 跨 await 写孤儿 DeviceItem（与 refreshDevices 竞态） | state.dart:692-731, 2085-2087 | 极小 |
| S20 | P3 | 加固杂项 ×9（轮播 %0、controller dispose、406 误判、restore 串行化、图传互斥、心跳互斥、断链慢 1s、占位设备标记、热重启残留清扫） | 见详述 | 各极小 |
| M1 | P1 | `state.dart` 3188 行上帝对象：渐进拆分（纯函数/模型外移 + mixin 分域） | state.dart 全文 | 大（零行为） |
| M2 | P1 | 错误分类靠**中文子串匹配**，是服务层 i18n 收尾的硬前置；另有 ~90 条漏网用户可见中文 | casting_progress_page.dart:189-211 等 | 中 |
| M3 | P2 | 死代码清理：state 内 ~400 行演示链路（castDraft 有数据污染风险）+ 3 死文件 + 8 死类 + 死路由，共 ~800 行 | 见详述 | 中（纯删除） |
| M4 | P2 | shared/widgets 三件套职责失效：8 个死类 + home_figma_common 与 home_widgets 分叉平行实现 | shared/widgets/ | 中 |
| M5 | P2 | 确认对话框 12 处手搓 + `_DialogButton` 三处复制分叉 | 12 个文件 | 中 |
| M6 | P2 | 537 处硬编码 Color、品牌橙 10 个变体、Theme 与实际视觉脱节 | 45 个文件 | 大（渐进） |
| M7 | P2 | 双 i18n 体系并存（AppL10n vs state.tr 内联三语 ~270 条） | state.dart / app_l10n.dart | 大（冻结+渐迁） |
| M8 | P2 | 路由表内嵌 100 行删除设备业务流程 | app_routes.dart:162-266 | 小（纯搬运） |
| M9 | P2 | lint 仅入门级配置，`unawaited_futures` 等未开 | analysis_options.yaml | 小（分批） |
| M10 | P1/P2 | 补单测：serial_match（P1，曾出真实串台事故）→ frame_protocol / image_codec / crypto_util（P2） | test/ | 小 |
| M11 | P3 | 三处反向/越层依赖（device→network/state、页面直摸 httpClient） | ble_controller.dart:7,9 等 | 小 |
| M12 | P3 | `frame_device_protocol.dart` 陈旧协议副本：离线态容量兜底错值 32（真机 95/51） | frame_device_protocol.dart；state.dart:154 | 小 |
| M13 | P2 | baseUrl 编译期硬编码，无环境切换（一行 `String.fromEnvironment` 可解） | api_config.dart:11 | 极小 |
| PF1 | P2 | 全局 state 每次 notify 重建整个可见 Tab 子树（首页全页 rebuild） | bolt_star_app.dart:275-293 | 中（逐页） |
| PF2 | P2 | 三种状态订阅模式并存；命名路由页（图库/记录）不订阅 state → BLE 断链后显示陈旧连接态 | gallery_page.dart 等 | 小（逐页） |
| PF3 | P3 | 性能余量杂项 ×7（CRC sublist 拷贝、压缩传参、FilterQuality.high、Opacity+GIF、IntrinsicHeight、磁盘缓存上限、读宽高全图解码） | 见详述 | 各极小 |
| PF4 | P3 | 体验杂项 ×5（OTA 握手 15s 无反馈、didPopNext 白闪、guide 空态、settings 图标无兜底、断开无 loading） | 见详述 | 各极小 |

---

## 三、稳定性与缺陷类发现（S 系列）

### S1 【P0】✅已修复（2026-07-17，见「修复进度」）"一键清空"可能落到错误设备：全局 `selectedDeviceId` 隐式传参 + 后台刷新静默改选

- **位置**：`lib/src/routes/app_routes.dart:162-275`（figmaDeviceDetails / figmaDeviceClearConfirm / figmaCarouselSettings 路由均**零参数**，页面内部读 `state.selectedDevice`）；`lib/src/state.dart:2088-2091`（`refreshDevices` 中：选中 id 不在新列表时 `_selectedDeviceId = _devices.first.id` **静默切换成第一台**）。
- **问题**："当前操作哪台设备"完全依赖全局 `_selectedDeviceId`。而 `refreshDevices` 可能在详情页打开期间被任何页面并发触发（`gallery_page.dart:41` 就在并发调用）；一旦后端返回里没有当前选中设备（另一端解绑、接口抖动返回不全），选中项被静默切成第一台——用户停留的详情页、即将执行的"一键清空"（`clearDeviceMemory` 按 `selectedDevice.id` 执行）就指向了**另一台设备**。
- **为什么要改**：清空是物理删除固件上全部照片，这是真实的**数据破坏**误操作窗口；多页并发 `refreshDevices` 是常态路径，不是理论场景。
- **建议改法（渐进，三步可独立停）**：
  1. 破坏性流程页面（清空/删除）在 `initState` 记下 `_deviceId = state.selectedDeviceId` 本地快照，后续动作全用快照而非实时读 `selectedDevice`；
  2. 给 `refreshDevices` 的"选中项落空自动切首台"加保护：改为置空，让 `_findDevice` 的占位设备兜底渲染，不静默换台；
  3. 长期：`pushNamed(figmaDeviceDetails, arguments: deviceId)` + 路由层解参（大版本再做）。
- **改后变化**：详情页生命周期内操作对象恒定；并发刷新不可能把破坏性操作重定向到别的设备。
- **回归面**：仅设备详情/清空/删除流程；步骤 1、2 各 <10 行。

### S2 【P1】BLE `connect()` 失败路径不回收物理连接 →"连不上也搜不到"+ 前台服务空转耗电

- **位置**：`lib/src/device/ble/device_ble.dart:220-283`（配合 `ble_controller.dart:391-395`）。
- **问题**：`connect()` 在 `await device.connect(...)` 成功后**立即**置 `_linkAlive = true` 并触发 `onLinkStateChanged(true)`，早于服务发现与特征校验。此后任何一步抛错（`discoverServices` 失败、FF00 主服务缺失、FF01/FF02 缺失、`setNotifyValue` 失败）都不会回收连接；上层 `BleController.connect` 的 catch 只 `return error.toString()`，不调用 `disconnect()`。最危险的场景：`_writeChar` 已赋值后 `setNotifyValue` 抛错，此时 `connected` getter 返回 **true**，但没有通知订阅——之后每条指令白等 6s 超时，UI 却显示已连接。
- **为什么要改**：① GATT 物理链路保持连接 → 设备停止广播，之后**扫描永远搜不到**这台设备，用户只能杀 App/重启设备；② `onLinkStateChanged(true)` 已触发 → 保活心跳 Timer + Android 前台服务启动，且部分失败场景下租约不排定时器，**前台服务与心跳永不停止**，持续耗电。触发条件不苛刻：弱信号下发现服务失败、CCCD 写失败在国产 ROM 上并不罕见。
- **建议改法**：把 `device.connect` 之后的整段包进 try/catch，任何一步失败先 `await disconnect()` 再 rethrow；同时把 `_linkAlive = true / onLinkStateChanged(true)` 挪到通知订阅成功之后。成功路径语义不变。
- **改后变化**：连接失败即物理断开、设备恢复广播可再次扫到；不可能出现"connected=true 但没有通知订阅"的死会话；前台服务/心跳不再空转。
- **回归面**：仅连接建立失败路径；成功路径不动。

### S3 【P1】远端断开后订阅泄漏：重连同一设备后每条通知被重复处理

- **位置**：`lib/src/device/ble/device_ble.dart:229-235、277-278`；`ble_controller.dart:85-107`。
- **问题**：设备侧断开（重启/超距/租约外被系统断）时只置 `_linkAlive=false`、`_failAllPending`，**不取消** `_notifySub`/`_connSub`；下一次 `connect()` 直接覆盖两个订阅变量。flutter_blue_plus 的 `onValueReceived` 是全局流，不随断开自动取消。每经历一次"远端断开→重连"就泄漏两个 StreamSubscription；重连同一台设备后，每条通知被 N+1 个监听器各解析一次，图传 ACK 与应答帧成倍重复处理，CPU 开销随重连次数线性增长。
- **为什么要改**：泄漏是**累积性**的，且发生在最核心的收包路径；与租约策略（到期断开→用户再连）叠加后必然发生。长时间挂后台反复断连重连的用户，图传会越来越慢。
- **建议改法**：`connect()` 开头先 `await _notifySub?.cancel(); await _connSub?.cancel();`；订阅后追加 `device.cancelWhenDisconnected(sub)` 兜底。
- **改后变化**：任意次重连后每条通知只被处理一次，订阅数恒定；无行为语义变化。
- **回归面**：连接建立入口，2-4 行。

### S4 【P1】4 处残留"loading 盲 pop"——与已修复的历史闪退同根因

- **位置**：
  - `home_page.dart:455`（连接设备）
  - `device_details_page.dart:169`
  - `devices_page.dart:174`
  - `ota_upgrade_page.dart:45、57`（`startOtaFlow` 两处）
- **问题**：`AppLoadingDialog.show(...)` 后用 `Navigator.of(context, rootNavigator: true).pop()` 关 loading，而不是 `AppLoadingDialog.hide(context)`。`show()` 在已有 loading 时**静默忽略**（app_widgets.dart:364-366），一旦两条链路并发，第二个 `show` 没弹框，配对的盲 `pop` 弹掉的就是真正的 loading 或**底下的业务页**——这正是 app_widgets.dart:358-361 注释里记录的"修改密码发验证码偶现闪退"的同一根因。`hide()` 已做成精确 `removeRoute`，这 4 处是漏改残留。
- **建议改法**：机械替换为 `AppLoadingDialog.hide(context)`，一行 × 4 处。
- **改后变化**：并发/竞态下不可能误弹业务页；该类偶现闪退路径归零。
- **回归面**：4 个调用点，行为等价替换。

### S5 【P2】约 9 处 `!mounted` 早退跳过 hide → 全屏模态 loading 永久滞留、App 锁死

- **位置**（同一模式 `show → await → if (!mounted) return → hide`）：`home_page.dart:452-454`、`gallery_page.dart:269-273、295-299`、`device_details_page.dart:146-151`、`cast_preview_page.dart:290-293、384-387`、`carousel_settings_page.dart:61-64`、`bind_device_flow.dart:208-210、241-243、266-268`、`device_clear_confirm_page.dart:76-79`。
- **问题**：页面在 await 期间被卸载（典型链路：接口 401/406 → `_handleSessionExpired` → `popUntil`；或 Tab 切换直接换 child 卸载页面），`hide` 永不执行。loading 在 root navigator 上、`PopScope(canPop:false)`、barrier 不可点——一旦滞留，**整个 App 被蒙层锁死只能杀进程**；且 `_route` 残留会让后续所有 `show()` 静默失效。
- **建议改法**：
  1. `AppLoadingDialog.hide()` 实际不依赖传入 context（内部走 `route.navigator`），把调用点统一改成 `try { await ... } finally { AppLoadingDialog.hide(context); }`，**不要**用 `mounted` 门控 hide（`settings_page.dart:233-240` 已是正确范本，照抄即可）；
  2. 给 `AppLoadingDialog` 增加无 context 的 `hideIfAny()`，在 `_handleSessionExpired` 全局导航前先调它。
- **改后变化**：任何异常/卸载路径下 loading 都能收尾，App 级"假死蒙层"不可能出现。
- **回归面**：9 个调用点的收尾逻辑；与 S4 同批做，模式统一。

### S6 【P1】上传响应体读取无超时：弱网下"图片处理中"可无限转圈

- **位置**：`lib/src/network/api_client.dart:215-218`。
- **问题**：`.timeout(uploadTimeout)` 只覆盖 `send()`（请求体发完 + 响应头到达）；之后 `http.Response.fromStream(streamed)` 读响应体**没有任何超时**。移动网络"连接不断但停止收发"（NAT 超时、基站切换、静默断链）时该 Future 永远 pending。这是全项目**唯一残留的无界等待点**，且正好在配 loading 弹窗的高频路径（投屏上传、换头像）上——与之前已修过的"下载无超时永久挂起"同类，上传侧漏掉了。
- **建议改法**：`await http.Response.fromStream(streamed).timeout(ApiConfig.uploadTimeout)`，一行。
- **改后变化**：body 阶段 stall 也会在 20s 内抛 TimeoutException → 走现有"网络超时"提示分支。
- **回归面**：仅上传路径超时行为。

### S7 【P1】非幂等 POST 超时后静默重试：验证码双发（用户可复现）

- **位置**：`lib/src/network/api_client.dart:153-182`（`_sendWithRetry`）。
- **问题**：注释写"业务/服务器错误不重试（避免重复副作用）"，但**网络超时会重试所有方法包括 POST**。超时 ≠ 请求未送达。受影响接口：`sendEmail`（重试连发 2-3 封验证码，若后端"新码作废旧码"，用户输入先到的那封会报错）、`addUserProductImgRecord`（投屏记录重复）、`addUserProduct`（是否重复绑定取决于后端去重）。上传路径已明确不重试（团队意识到了该风险），普通 POST 漏了同样的判断。
- **建议改法**：给 `postJson` 加 `bool retryOnTimeout = true` 参数保持默认行为不变，逐个把 `sendEmail` / `addUserProductImgRecord` / `addUserProduct` 改为 `false`（TimeoutException 直接抛；`SocketException` 连接失败仍可重试——连接没建立不可能有副作用）。
- **改后变化**：弱网下不再重复发验证码/重复记录；连接不上时的重试体验不变。
- **回归面**：3 个接口的超时重试行为。

### S8 【P1】✅已修复（2026-07-17，见「修复进度」）首页换头像走原图：~48MB 位图瞬间进内存 + 原图直传后端

- **位置**：`home_page.dart:320`（`pickImage` 未给 `maxWidth/maxHeight/imageQuality`）；`home_widgets.dart:355-360`（`Image.file` 渲染 36lp 圆头像**无 `cacheWidth`**，按原始像素解码）。
- **问题**：相机原图常见 4000×3000，解码后 ≈ 48MB 位图瞬间进 ImageCache——华为等设备上最典型的 OOM/GC 卡顿来源，与已知"华为系崩溃"画像吻合（大位图 + Vulkan 驱动）；且 `updateAvatar` 直接把原图（4~12MB）上传，弱网十几秒无进度。**同功能的 `profile_page.dart:167-168` 已做了 `maxWidth: 512` + `_compressAvatar ≤100KB`**，两个入口行为不一致。
- **建议改法**：① `pickImage` 补 `maxWidth: 512, maxHeight: 512, imageQuality: 85`（与 profile 页对齐）；② `Image.file` 补 `cacheWidth: (36 * dpr).round()`；③ 把 profile 页的 `_compressAvatar` 提到共享层，两入口统一。
- **改后变化**：换头像内存峰值从 ~48MB 降到 <1MB；上传体积从数 MB 降到 ≤100KB；两入口行为一致。
- **回归面**：仅首页换头像入口；profile 页逻辑已验证过（2026-07-16 修复轮）。

### S9 【P2】✅已修复（2026-07-17，见「修复进度」）首页轮播 `didUpdateWidget` → `jumpToPage` 可触发构建期 `notifyListeners`

- **位置**：`home_widgets.dart:515-534`（`didUpdateWidget` → `_controller.jumpToPage`）、`561-565`（`onPageChanged` → `selectDevice` → `notifyListeners`）。
- **问题**：`didUpdateWidget` 处于 build/element 更新阶段；`jumpToPage` **同步**派发 ScrollNotification → `onPageChanged` → `selectDevice` → `notifyListeners()`，而根部 `AnimatedBuilder(animation: _state)` 是正在构建子树的祖先——debug 下抛 `markNeedsBuild() called during build`，release 下产生不一致帧。触发条件真实存在（`selectedDeviceId` 为空而推导出已连接设备时，`selectDevice` 不会被短路）。这是排查中发现的**唯一真实框架级异常路径**，且在曾发生崩溃的首页。
- **建议改法**：`didUpdateWidget` 里的 `jumpToPage` 包进 `WidgetsBinding.instance.addPostFrameCallback`；或把 `onPageChanged` 里的 `widget.onChanged` 推迟到帧末。
- **改后变化**：设备列表刷新/连接完成瞬间首页不再可能出现构建期异常帧。
- **回归面**：轮播翻页与设备选中联动，需手测轮播切换。

### S10 【P2】✅已修复（2026-07-17，见「修复进度」）投屏预取 Future 无错误监听：弱网失败被写入崩溃日志、下次启动弹"崩溃报告"

- **位置**：`projection_service.dart:192-207`（`prefetch[idx] = trace.measure(...)`）；`main.dart:48-60`。
- **问题**：预取流水线把 Future 存进数组，主循环要等上一张 BLE 图传完（数十秒）才 `await`；Dart 对"完成出错且暂无监听器"的 Future 会先上报未处理异步错误 → `PlatformDispatcher.onError` 把它写入 CrashLogger 的 `last_crash.txt` 并消耗错误预算。一次普通弱网下载失败会在**下次启动弹"上次崩溃报告"对话框**，直接污染正在进行的首页崩溃排查的信噪比。
- **建议改法**：赋值后立刻 `prefetch[idx]!.ignore();`（`ignore()` 只挂丢弃监听器，后续 `await` 同一 Future 依然拿到该错误，主循环判失败的语义**完全不变**）。
- **改后变化**：预取失败仍按原流程整单判失败；不再污染崩溃日志与启动弹窗。
- **回归面**：一行 × 1 处（`recastRecord` 的 `frameFuture` 同理检查）。

### S11 【P2】`reconcileConnections` 用 FBP 内存镜像对账，查不出它想查的死会话

- **位置**：`ble_controller.dart:487-504`。
- **问题**：回前台"连接体检"用 `FlutterBluePlus.connectedDevices`（FBP **自己内部状态**的已连接列表）——它恰恰由"可能没补发的断开事件"驱动更新。注释里要治理的场景（系统后台挂起蓝牙、事件丢失）下，FBP 镜像与 `_client.connected` 会一起谎报 true，体检变成恒 false 的空转，既有防护形同虚设。
- **建议改法**：改用 `FlutterBluePlus.systemDevices(...)`（问 OS 的真实已连接表），或做一次主动探活（发 0x04、2s 短超时，失败即 `disconnect()`）。保持"异常时保守不动"的现有语义。
- **改后变化**：假连接在回前台时被如实清理；正常连接零额外开销（或一条轻量 0x04）。

### S12 【P2】`connect`/`connectBoundDevice` 无重入护栏

- **位置**：`ble_controller.dart:364-401、426-480`。
- **问题**：`connecting` 只被置位、从不在入口检查（对比 `scan()` 有护栏）。列表快速双击、或自动重连与手动连接并发时，两次 `_client.connect()` 交错：`_device/_connSub/_notifySub/_writeChar` 被后者中途覆盖（叠加 S3 泄漏），`broadcastDeviceId/deviceName` 可能与实际连上的设备错位——正是序列号交叉认领体系最怕的输入。
- **建议改法**：`connect()` 入口 `if (connecting) return ...;`（或复用 in-flight Future）；`connectBoundDevice` 同样短路。
- **改后变化**：并发触发时第二次调用立即返回，单连接模型真正成立。

### S13 【P2】登出/换号后在途响应回填旧账号数据

- **位置**：`state.dart:1581-1601`（`refreshAlbum` 无条件写 `_albumPhotos`）、`2564-2592`（logout 清列表）、`3142+`。
- **问题**：登出前发出的在途请求（headers 里带旧 token，请求发起时已固化）返回时无条件写回列表并置 loaded 标记。快速切换账号时，B 账号首屏可能闪现 A 账号的相册/记录（窗口 ≤10s）。
- **建议改法**：state 加 `int _sessionEpoch`，logout/会话失效/登录成功时 `++`；各 `refresh*` 方法开头捕获 epoch，await 回来后 `if (epoch != _sessionEpoch) return`。改动集中在 5-6 个 refresh 方法，纯防御。
- **改后变化**：登出/换号后过期响应被丢弃，杜绝跨账号数据串屏。

### S14 【P2】畸形 2xx 响应被吞成 `{}` 并按"成功"返回

- **位置**：`api_client.dart:233-243、271-282`。
- **问题**：网关/CDN 返回 HTTP 200 + HTML 错误页（运营商劫持、维护页）时，JSON 解析失败 → `body = {}` → 无 `retCode` 键 → **按成功返回空 map**。下游各自碎成不同症状（"服务器未返回转换结果"、列表悄悄变空），排障无法区分"后端真返回空"和"响应根本不是 JSON"。
- **建议改法**：解析失败且 `bodyBytes` 非空时抛 `ApiException('PARSE_ERROR', ...)`；空 body 保持现状返回 `{}`。
- **改后变化**：劫持/维护页立即显性报错，而不是伪成功后在业务层变成奇怪现象。

### S15 【P2】`catch (_)` 把编程错误/文件缺失伪装成"网络连接失败"并重试

- **位置**：`api_client.dart:173-180、225-227`。
- **问题**：兜底 `catch (_)` 会捕获 `jsonEncode` 的编程错误并重试 2 次后报"网络连接失败"；upload 路径 `MultipartFile.fromPath` 对不存在的本地文件抛 `FileSystemException` 也被报成网络错——用户按提示检查网络永远修不好。
- **建议改法**：catch 里区分 `SocketException`/`ClientException`/`HandshakeException`（真网络错误，重试）与其他（rethrow 或独立 code，不重试）；upload 把 `FileSystemException` 单独包成"文件不存在/已被清理"文案。
- **改后变化**：错误归因准确；编程错误不再被重试延迟和错误文案掩盖。

### S16 【P2】投屏记录"再次投屏"无并发锁、长耗时无 loading

- **位置**：`cast_management_figma_page.dart:104-157`。
- **问题**：① 无 `_busy` 标记——连点两次会并发两次 `connectDevice` + 顺序 push 两个预览页；② `connectDevice`（可达 10s+）+ `_downloadToTemp`（超时 20s）期间只有一条 2 秒即逝的 toast，无阻断 loading，用户必然重复点。同类操作（详情页/列表页连接）都有 `AppLoadingDialog`，唯此处漏。
- **建议改法**：加 `bool _recasting` 卫语句 + 全程 `AppLoadingDialog.show` / try-finally `hide`（沿用 S5 模式）。
- **改后变化**：无双开预览页；20 秒下载期有明确等待反馈。

### S17 【P2】Doze 下 25s 心跳停发："息屏 30 分钟"产品定版在激进 ROM 上实际达不到

- **位置**：`android/.../BleConnectionService.kt`（全文无 wakelock）；`ble_controller.dart:117-128`。
- **问题**：保活实体是 Dart `Timer.periodic(25s)` 发 0x04。前台服务只提升进程优先级，**不保证 CPU 不挂起**：息屏进入 Doze/厂商深度省电后 Timer 不触发，固件侧 1~2 分钟无流量即主动断链——表现为"息屏几分钟后回来发现已断开"。断开后能正确清理（不泄漏、不崩溃），纯粹是租约达成率与产品定版的冲突。
- **建议改法（先验证再动）**：真机测出息屏实际存活时长；若确认达不到，在 `onStartCommand` 持 `PARTIAL_WAKE_LOCK`（`onDestroy` 释放，与连接同生命周期，最长 30 分钟有界）；或接受现状记入 App vs 小程序差异台账。
- **改后变化**：息屏期心跳按时发出，30 分钟租约真实兑现；代价是连接期间有界的额外耗电。

### S18 【P1】硬件调试台在 release 包对最终用户可达

- **位置**：`bind_device_debug_entry.dart`（`BindDebugEntryCard` 常驻显示在绑定流程三态顶部）→ `app_routes.dart:105`（无条件注册）→ `ble_debug_page.dart`（723 行，可对设备逐条发任意 BLE 指令、看原始字节）。
- **问题**：两文件及路由注册处均无 `kDebugMode` 门禁；终端用户在绑定页一眼可见"硬件联调调试台"，可发含删除图片类的指令；且整页硬编码中文不随语言切换——发布质量与支持成本问题。
- **建议改法**：入口卡片包 `if (kDebugMode)`（或隐藏手势开关）；路由在 release 下重定向。~5 行。
- **改后变化**：release 包不暴露调试面；debug 联调流程不变。

### S19 【P2】`connectDevice` 跨 await 写孤儿 DeviceItem

- **位置**：`state.dart:692-731`（await 之后继续写 `device.connected`）；`state.dart:2085-2087`（`refreshDevices` 整体替换列表对象）。
- **问题**：`connectDevice` 在 await 期间若 `refreshDevices` 并发完成，列表已被新对象整体替换，连接成功的标记写进孤儿对象——表现为"点了连接、toast 说成功、卡片却显示未连接"的难复现 UI 抖动（靠 `reconcileConnectionFlags` 自愈，但存在窗口）。
- **建议改法**：await 返回后**按 id 重查**列表再写标记，找不到则只调 `reconcileConnectionFlags`。~4 行。
- **改后变化**：并发刷新不再产生孤儿写入。

### S20 【P3】加固杂项（各 <10 行，随批次顺手做）

| # | 位置 | 问题 | 改法 |
|---|---|---|---|
| a | home_widgets.dart:563,571,574 | 轮播 `page % devices.length` 空列表时 `% 0` 抛错（现被上游护住） | itemBuilder/onPageChanged 加 isEmpty 卫语句 |
| b | device_details_page.dart:99 | `_renameDevice` 的 TextEditingController 从不 dispose（微量累积泄漏）；my_devices_page.dart:142-166 / prompt_text.dart:28 则是在退场动画期**过早** dispose | 统一为对话框自管 controller 或延迟 dispose |
| c | api_client.dart:254 | 网关返回 HTTP 406（与鉴权无关）会被 `isAuthError` 误判为登录失效踢回登录页 | 业务 retCode 401/406 与 HTTP 401 算 auth，HTTP 406 走普通错误 |
| d | api_session.dart:56-64 | `restore()` 不排 `_persistQueue`，理论上可被 setToken 时序覆盖 | 首行 `await _persistQueue;` |
| e | device_ble.dart:86-89 | `uploadImage` 无互斥，两路图传互相打脏 `_lastImgAck`（仅调试台可触发，设备端 CRC 兜底） | 加 `_uploading` 门闩，第二路明确报错 |
| f | device_ble.dart:595-597 | 心跳 0x04 在飞（≤2s）时用户读电量撞"指令 0x4 正在等待应答"报错 | readBattery 捕获后短延迟重试一次 |
| g | device_ble.dart:299-307 | 断链时 `_failAllPending` 不唤醒 `_imgAckWaiter`，图传报错慢 ~1s（有界，非挂死） | 断开分支补 completeError |
| h | state.dart:452-454, 2710-2738 | 注释说 `selectedDevice` 找不到会抛异常，实现已改为返回**占位设备**且可流入真实请求 | 改注释 + 加 `isPlaceholder` 标记供破坏性操作拦截（与 S1 互补） |
| i | 热重启残留 | 热重启后原生 GATT/前台服务残留，新单例 `connected==false` 不清理 → 设备被占线搜不到（仅影响开发调试） | 启动时 best-effort 停一次保活服务 + debug 下断开清扫 |

---

## 四、结构与可维护性类发现（M 系列）

### M1 【P1】`state.dart`：3188 行上帝对象的渐进拆分

- **位置**：`lib/src/state.dart:339-3188`（`PhotoFrameState`，单个 ChangeNotifier）。
- **现状**：承担 **12 类职责**——领域模型定义（16-334 行，10 个类 + 5 个枚举）、登录/会话、用户资料、设备管理（网络）、设备管理（BLE，含 `deleteAlbumPhotos` 142 行内嵌 BLE 指令编排）、图库、投屏记录、FAQ、版本检查、i18n 兜底（数百条内联三语文案）、JSON 映射、UI 首屏状态。46 处 `notifyListeners()` 全部是"整个 App 状态变了"粒度；46 处 `required this.state` 逐层传参。
- **为什么要改**：① 任何域变更都全局广播，监听者无法按需订阅（PF1 的根源）；② 改一处需理解全局，回归面不可控；③ 无法按域单测（构造即拖入 BleController 单例副作用）；④ 占全库 10% 行数，是所有维护成本的放大器。
- **建议改法（三阶段，任何一步都可独立停在安全点，前两阶段零行为变化）**：
  - **第一阶段（零风险，纯搬运）**：把无 this 依赖的**纯函数**搬出——JSON 映射（`_deviceFromJson`/`_albumPhotoFromJson`/`_castRecordFromJson`/`_faqFromJson`/`_readToken`/`_asInt`/`_parseDate`/`_versionGreater` 等）移入 `lib/src/network/api_mappers.dart`；10 个领域模型 + 5 个枚举移入 `lib/src/models/`；state.dart 用 `export` 保持旧 import 路径不破。**约减 900 行**。
  - **第二阶段（低风险）**：按域拆成 **mixin**（`on ChangeNotifier`）：`_AuthStateMixin`、`_DeviceStateMixin`、`_AlbumStateMixin`、`_CastRecordStateMixin`、`_FaqStateMixin`。对外 API、单实例、通知语义**完全不变**，只是物理分文件；跨域调用（logout 清全部列表、删设备清三个域）天然保留。
  - **第三阶段（暂不建议）**：真正拆成多个 Notifier + 聚合门面——跨域耦合点多，强拆会引入通知时序问题，违背"谨慎改动原有功能"，留待将来单独评审。
- **改后变化**：单文件从 3188 行降到每域 300-600 行；编译产物与运行行为完全一致；后续按域改动的回归面收窄。
- **回归面**：理论为零（纯搬运 + export 兼容），但涉及面广，需开发机 `flutter analyze` + 全量测试兜底，建议单独一个 PR、不夹带任何逻辑修改。

### M2 【P1】错误分类靠中文子串匹配——服务层 i18n 收尾的硬前置

- **位置**：`casting_progress_page.dart:189-211`——`raw.contains('繁忙')`、`raw.contains('空间')||raw.contains('已满')`、`raw.contains('断')||raw.contains('未连接')`、`raw.contains('超时')`、`raw.contains('中止')`，匹配对象是 `device_ble.dart` / `projection_service.dart` / `ota_ble.dart` 抛出的中文异常文案。
- **为什么要改**：错误**语义**被编码在**展示字符串**里。已排期的待办正是"翻译 projection_service 等服务层"——一旦翻译，这里的失败原因分类**静默**全部落入兜底分支，投屏失败页会给出错误的原因和建议；`raw.contains('断')` 单字匹配还极易误伤。**不做这项，服务层翻译就不能安全启动**（若现在启动翻译，本项升 P0）。
- **配套发现（漏网中文盘点）**：已知清单（projection_service + 法务长文）**之外**，还有 5 个文件约 **90 条用户可见中文**未入 i18n，全被子串匹配"锁住"：`wechat_authorization_client.dart`（16 条，如"请先安装微信…"）、`device_ble.dart`（19 条 FrameBleException）、`ota_ble.dart`（69 条，错误码表 + 异常消息，经 OTA 页冒泡给用户）、`frame_protocol.dart`（17 条）、`frame_device_protocol.dart`（26 条，部分为 UI 标签）。另：`test/widget_test.dart` 断言硬编码 `'登 录'` 等，默认语言一变即碎（P3 顺手修）。
- **建议改法**：给 `FrameBleException` 加 `kind` 枚举（busy / storageFull / disconnected / timeout / aborted / unsupported），抛出点标注 kind，页面按 kind 分类、message 仅展示；**然后**才翻译服务层与上述 5 个文件。
- **改后变化**：错误分类与文案解耦、可单测；服务层 i18n 解除封印。

### M3 【P2】死代码清理：约 800 行，其中 castDraft 一族有数据污染风险

- **清单**：
  - **state.dart 内约 400 行演示期链路**：`castDraft`（1394-1575，整套**模拟投屏**——假扣电量、本地伪造 AlbumPhoto/CastRecord；真实投屏早已走 `ServerImageProjectionService`。它 API 完整、注释像真的，未来有人误接线会把**假记录混进后端真数据**，是清理项里唯一的"地雷"）、`recastAlbumPhoto/recastRecord`（注释自认无调用方）、`createCameraDraft/createAlbumDraft/draftFromAlbumPhoto`（内含"门口剪影"等 demo 假数据）、`buildGuideArticles`、`setOffline`（全库无调用方 → `isOffline` 永 false → home_page.dart:147-189 整套离线弹层监听是死路径）、`successRate` 等 0 引用 getter、`DraftPhoto`/`GuideArticle` 模型。
  - **3 个死文件**（0 引用，shared.dart barrel 还在导出）：`shared/widgets/background.dart`、`shared/widgets/scaffolds.dart`、`shared/dialogs/prompt_text.dart`。
  - **8 个死类**：app_widgets.dart 12 个类中的 AppPanel、SectionHeader、ActionCard、HeroMetric、StatTag、StatusPill、DeviceIllustration、EmptyState（仅 PageLoading/PageLoadError/AppLoadingDialog 存活）。
  - **1 个死路由**：`AppRoutes.devices`('/devices') 0 处导航引用，与 figmaMyDevices 双注册同一页面。
- **为什么要改**：castDraft 是数据污染地雷；死代码使 state.dart 约 13% 是噪音，加重 M1 的理解成本；死类让 shared 层失去可信度（新人会往错误文件加组件）。
- **建议改法**：纯删除 PR（不夹带任何活代码修改）；若担心一次删太多，先删 castDraft 一族（风险源），其余分批；删前开发机跑 `flutter analyze` 确认无引用。
- **改后变化**：全库 -2.5%~3% 行数；不可能再有假投屏数据；行为零变化（全是死路径）。

### M4 【P2】shared/widgets 三件套职责失效与组件分叉

- **位置**：`app_widgets.dart`（8/12 死类，见 M3）、`figma_common.dart`（1174 行，真公共层，健康）、`home_figma_common.dart`（704 行，仅 2 个文件引用、只用到 6 个类）。
- **问题**：`home_figma_common` 的 FigmaHomeBackground / FigmaSoftBackgroundPainter / FigmaHomeAssetImage / FigmaBluetoothRadar 在 `home_widgets.dart` 里存在**私有平行实现**（`_HomeBackground`/`_SoftBackgroundPainter`/`_AssetImage`/`_BluetoothRadar`），复制后已分叉（如雷达一个用图片素材、一个用 CustomPaint）。改一个视觉元素要在 2~3 处找实现，分叉持续扩大。
- **建议改法**：① 随 M3 删死类；② 把 bind_device_found/scan_help 用到的 6 个类收敛后，评估 home_figma_common 整体并入 figma_common 或删分叉副本；③ shared/widgets/ 加 README 注释声明各文件职责。
- **改后变化**：shared 层从 3+1 文件收敛到 2 个，~500 行消失，"现行款"唯一。

### M5 【P2】确认对话框 12 处手搓 + 对话框按钮三处复制分叉

- **位置**：`grep AlertDialog(` 命中 12 文件 15 处；`_DialogButton` ×3（gallery_page.dart:820、settings_page.dart:513、device_details_page.dart:876，参数已分叉）；另有 `_PhotoToolButton` ×2、`_DeviceActionButton` ×2、主按钮 4 套、文字样式表 3 套。
- **为什么要改**：文案样式、barrierDismissible、返回值语义各页微妙不同；i18n/无障碍要逐处过；改全局视觉必然漏改。
- **建议改法**：抽 `showAppConfirmDialog({title, message, confirmLabel, danger})` + 共享 `AppDialogButton`；**新页面强制走它，旧页面顺手迁**（不做一次性大扫除）。样式表 3 合 1 可与 M6 一起做。
- **改后变化**：新增确认框从 ~40 行降到 1 行调用；对话框按钮单一来源。

### M6 【P2】537 处硬编码 Color：品牌橙 10 个变体，Theme 与实际视觉脱节

- **证据**：45 个文件 537 处 `Color(0xFF...)`；品牌橙至少 10 种写法（0xFFEB5F1B ×32、0xFFFF6A24 ×31、0xFFFF6A20 ×14、0xFFFF6421 ×9、0xFFFF5F1F ×9、0xFFFF7D36 ×7、0xFFFF621F ×7、0xFFFF5B1F ×5、0xFFFF641F ×3、0xFFFF9140 ×3）；正文深灰双胞胎 0xFF2A2B2B(37) vs 0xFF2A2D32(35)；`app_theme.dart:4` 的 primary 还是旧设计的深青 0xFF234E52，页面基本不消费 Theme。
- **为什么要改**："对齐设计稿"变成了"锁死设计稿"：换主色/做深色模式成本约等于重写；相邻页面橙色已肉眼可见不一致。
- **建议改法（渐进，不做全库大扫除）**：建 `shared/design_tokens.dart`（AppColors.brandOrange、textPrimary、textSecondary… 约 15 个 token 可覆盖 80% 用量）；**只在新代码和三张样式表里替换**；顺手把 app_theme 的 colorScheme 改成真实品牌色。
- **改后变化**：新代码不再产生新变体；橙色经样式表收敛后剩 2~3 个正当变体（主/深/浅）。

### M7 【P2】双 i18n 体系并存

- **位置**：`shared/l10n/app_l10n.dart`（~426 条 getter，294 处调用，页面层已全量迁移）vs `state.dart:457` 的 `tr(zh:,en:,ja:)`（state 内 91 处调用、~270 条文案，zhHant 靠机器简繁转换，与 AppL10n 人工文案质量不一致）。
- **建议改法**：定规矩"**新文案一律 app_l10n**"；`tr()` 存量冻结不动；待 M1 第二阶段拆 mixin 时把各域 ActionFeedback 改为注入 AppL10n（届时一并处理 M2 的服务层翻译）。
- **改后变化**：文案单一来源；state.dart 再瘦身 ~500 行。

### M8 【P2】路由表内嵌 100 行删除设备业务流程

- **位置**：`app_routes.dart:162-266`（figmaDeviceDetails 分支内嵌完整删除交互编排——二次确认、断开、loading、删除、pop，含闭包可变状态 `deleteFlowBusy`）。
- **为什么要改**：路由表成为第二个业务层（文件头注释承诺只做分发）；与 `startOtaFlow`（已正确抽为独立函数）风格割裂；路由文件 import 了 AppToast/业务模型，依赖方向倒挂。
- **建议改法**：把 `onDeleteDevice` 闭包**原样搬进** `device_details_page.dart`（或独立 `delete_device_flow.dart`），路由分支退化为 `DeviceDetailsPage(state: state)`。纯搬运零改动。
- **改后变化**：app_routes.dart 回到纯分发（~200 行）；删除流程可与页面一起评审/测试。

### M9 【P2】lint 仅入门级配置

- **位置**：`analysis_options.yaml`——裸 `include: flutter_lints`，0 条自定义规则。
- **建议改法（按噪音从低到高分批开，每批修干净再开下一批）**：第一批 `unawaited_futures`（本项目 BLE/网络异步重灾区最需要）、`always_declare_return_types`、`prefer_single_quotes`；第二批 `directives_ordering`、`avoid_redundant_argument_values`。
- **改后变化**：异步遗漏类 bug 编译期可见。

### M10 【P1/P2】补单测（纯逻辑模块，无需 mock BLE）

- **现状**：test/ 共 6 文件 462 行，对 31k 行占比约 1.5%。
- **收益排序**：
  1. **serial_match.dart【P1】**——纯函数、规则微妙（前后缀锚定、等长即否、<8 位即否），**历史上真出过 "EF6-370 串到 EF6-589" 串台事故**（文件头注释有完整复盘），~30 行测试锁住全部分支，收益最大成本最小；
  2. `ble/frame_protocol.dart`【P2】——帧组包/解析/CRC 零测试（注意：现有测试测的是另一个文件 frame_device_protocol）；
  3. `image_codec.dart`【P2】——packNibbles 高低位顺序、奇数像素取整、CRC32；
  4. `crypto_util.dart`【P2】——一条用例锁"32 位小写 md5 与小程序互通"契约；
  5. casting_progress 错误分类——待 M2 枚举化后配套补。

### M11 【P3】三处反向/越层依赖

- ① `ble_controller.dart:7,9`：device 层 import network 层（拉广播白名单）+ import state.dart（取 AppLanguage），形成弱环；② `api_client.dart:255` 直接 `ApiSession.instance.clear()`，token 清除分散两处靠注释维系时序；③ `cast_management_figma_page.dart:5,163` 表现层直摸 `ApiClient.instance.httpClient` 下载图片，绕开统一错误/鉴权处理。
- **改法**：`AppLanguage` 枚举移到 `shared/l10n/`（配合 M1 第一阶段）；广播白名单改注入（同现有 languageResolver 模式）；ApiClient 暴露 `downloadBytes(url)`。均为搬运/包装。

### M12 【P3】`frame_device_protocol.dart` 是参数错误的陈旧协议副本

- **位置**：`frame_device_protocol.dart:36-44`（`maxImages=32`，真机 95/51；屏幕尺寸 416×240/600×448，真机 480×720/680×960；`_pseudoCrc32` 占位实现）；`state.dart:154` 仍用它兜底容量。
- **问题**：`cast_preview_page.dart:129` 已专门写注释警告别用它的宽高，但离线态容量展示仍会失真（显示 32 而真实 95）；与权威 `ble/frame_protocol.dart` 文件名近到必然点错。
- **改法**：`capacity` 兜底改为按 `screenType` 查 `FrameProtocol.screenTypes[].capacity`；中期把仅存活的常量挪到独立小文件，删除错误的尺寸/容量/伪 CRC。

### M13 【P2】baseUrl 编译期硬编码，无环境切换

- **位置**：`api_config.dart:11`。
- **建议改法**：`static const String baseUrl = String.fromEnvironment('API_BASE_URL', defaultValue: 'https://api.boltfox.cn');`——不传 define 时产物与现在**逐字节等价**；需要时 `--dart-define=API_BASE_URL=...` 即可切测试/预发环境，不用改源码重打包。
- **改后变化**：默认构建完全不变，获得环境切换能力。一行改动，收益/成本比最高。

---

## 五、性能与体验类发现（P 系列）

### PF1 【P2】全局 state 每次 notify 重建整个可见 Tab 子树

- **位置**：`bolt_star_app.dart:275-293`（`home: AnimatedBuilder(animation: _state, ...)` 包住 AppShell）。
- **问题**：任何字段变化（BLE 电量回读、`reconcileConnectionFlags`、相册刷新、FAQ 回填…）都让 HomePage 整树 rebuild：全屏背景图、`IntrinsicHeight` 双遍布局、轮播、投屏卡全部重走 build+layout。单次毫秒级，但 BLE 连接期间状态高频变化时是持续掉帧源，且随页面复杂化线性恶化。根部已有的减负（theme 缓存、语言作用域收窄、reconcile 仅变化才 notify）说明作者有意识，剩下的是首页粒度。
- **建议改法（渐进，一页一步）**：① 短期：给 AnimatedBuilder 加 `child:` 缓存静态子树；`_castSection` 等无关区块用 `RepaintBoundary` 隔离；② 中期：把 HomePage 里真正依赖 state 的区块（设备卡、头像）各自包 `ListenableBuilder(listenable: state)`，外层 AnimatedBuilder 移除；③ 长线（配合 M1 第三阶段评审）：字段级 `ValueListenable`（devices/user/album 各一个）。
- **改后变化**：BLE 心跳/电量刷新期间首页 rebuild 范围从全页缩到设备卡一行，轮播动画不再受全局 notify 干扰。

### PF2 【P2】三种状态订阅模式并存；图库/记录页显示陈旧连接态

- **位置**：①AnimatedBuilder 订阅：devices_page.dart:41、device_details_page.dart:76；②addListener：home_page.dart:147;③**完全不订阅、手动 setState**：gallery_page.dart:23-85、cast_management_figma_page.dart:30-93。
- **问题**：命名路由 push 出的页面不在 `home:` 的 AnimatedBuilder 之下。图库/记录页打开期间若 BLE 断链（`reconcileConnectionFlags` → notify），页面上读自 `state.devices[..].connected` 的展示**不会刷新**——用户在"看似已连接"的图库页发起删除/刷屏，进入自动重连分支多等一轮扫描超时。三种模式并存也意味着每个新页面都要重新决策一次。
- **建议改法**：不引状态管理库；为依赖 state 的**局部**补 `ListenableBuilder(listenable: widget.state)`（如 gallery 顶部设备筛选条），数据加载时序（didPopNext 重拉）不动。一页一 PR。
- **改后变化**：BLE 断链等外部事件在打开中的页面即时反映；订阅模式收敛为一种。

### PF3 【P3】性能余量杂项

| # | 位置 | 问题 | 改法与预期 |
|---|---|---|---|
| a | frame_protocol.dart:531 | 每帧 `frame.sublist()` 拷贝 ~250B 算 CRC：一张图 ~1340 帧 ≈ 340KB 纯垃圾分配，在唯一性能敏感路径上 | 改 `Uint8List.sublistView`（零拷贝视图），字节输出不变，图传期 GC 停顿减少 |
| b | projection_service.dart:758-766 | 压缩前主 isolate `readAsBytes` 整张原图（8~15MB）再拷贝进 compute isolate → 瞬时 2× 内存 | 给 compute 传**文件路径**，isolate 内读；低端机连投大图内存峰值明显下降 |
| c | home_widgets.dart:616,625 | 设备卡背景 `FilterQuality.high`（三次立方采样），轮播滑动每帧重采样 | 删参数或降 medium，视觉无差异、滑动帧时间下降 |
| d | home_widgets.dart:1215 | `Opacity(0.56)` 压暗**动图 GIF** → 持续 saveLayer 离屏合成 | 改 ColorFiltered 或叠半透明黑层 |
| e | home_main_view/mine/auth 三处 | 页面级 `IntrinsicHeight` 双遍布局，叠加 PF1 双倍成本 | 现状可接受；做 PF1 时顺手改 `Column(spaceBetween)` |
| f | 全部 CachedNetworkImage | 均未设 `maxWidthDiskCache`，磁盘存服务端原图 | gallery 瓦片补 ~800，磁盘与二次解码成本同降 |
| g | cast_preview_page.dart:246-256, 502-506 | `_readImageSize` 全图解码只为读宽高（8~16MB 瞬时）；预览 `Image.file` 无 cacheWidth | 改 `ui.ImageDescriptor` 读头信息；补屏宽 cacheWidth |

### PF4 【P3】体验杂项

| # | 位置 | 问题 | 改法 |
|---|---|---|---|
| a | ota_ble.dart:609-651 | `_doStart` 兜底穷举 3 特征 ×2 objType，最坏 ~15s 停在"握手中"无变化，易误判卡死 | 每换一个目标补发一条 onProgress（"握手中 2/6"），纯提示 |
| b | cast_management_figma_page.dart:70-73 | `didPopNext` 走整页 loading，从预览页返回列表闪白 | 返回场景走 `_silentReload()` |
| c | guide_page.dart | 搜索无结果时玻璃卡内空白 | 加"无匹配结果"文案 |
| d | settings_page.dart:340-345, 383-388 | 仅有的两处 `Image.asset` 无 errorBuilder（其余 40+ 处都有兜底） | 补 errorBuilder |
| e | device_details_page.dart:143-154 | "断开"方向无 loading、无锁（BLE 层幂等，仅体验） | 加锁 + loading |

---

## 六、建议执行批次

> 每批做完是一个可独立回归、可独立发版的安全点。批内条目多为 <20 行的机械修改，建议一批一个 PR。

### 批次一：高危小修（P0 + P1 缺陷，预计总改动 <200 行）
1. **S1** 设备 id 快照防护（先做，数据破坏风险）✅已修（2026-07-17）
2. **S4 + S5** loading 盲 pop ×4 替换 + 9 处改 try/finally（同一模式，一起修一起测）
3. **S6** 上传 body 超时（1 行）
4. **S7** 三个非幂等 POST 关超时重试
5. **S2 + S3 + S12** BLE 连接失败回收 + 重连订阅取消 + 重入护栏（同文件同主题，一起修）
6. **S8** 首页换头像对齐 profile 页压缩（含 cacheWidth）✅已修（2026-07-17）
7. **S18** 调试台 release 门禁（~5 行）

**回归点**：连接/断开/重连、投屏全流程、换头像、注册发验证码、绑定流程。

### 批次二：排障信噪（配合首页崩溃排查，在下一轮崩溃归因前完成）
1. **S10** 预取 Future `.ignore()`（1 行）✅已修（2026-07-17）
2. **S9** 轮播 jumpToPage 移出构建期 ✅已修（2026-07-17）
3. **S11** reconcileConnections 改 systemDevices/主动探活

**回归点**：首页轮播切换、投屏弱网失败路径、回前台连接体检。

### 批次三：i18n 收尾前置（在翻译 projection_service 之前必须先做）
1. **M2** FrameBleException 加 kind 枚举、失败页按 kind 分类
2. 然后才翻译：projection_service + device_ble + ota_ble + frame_protocol + wechat_authorization_client（~90 条 + 已知清单）

### 批次四：结构瘦身（纯删除/纯搬运，零行为变化，每步单独 PR）
1. **M3** 死代码删除（先删 castDraft 一族）
2. **M1 第一阶段** 模型/纯函数外移（-900 行）
3. **M1 第二阶段** mixin 分域
4. **M8** 路由表业务下沉
5. **M4** shared/widgets 收敛

### 批次五：网络层加固（P2 缺陷）
1. **S13** sessionEpoch 防串号
2. **S14** PARSE_ERROR 显性化
3. **S15** 错误归因区分
4. **M13** baseUrl dart-define（1 行）
5. **S20c/d** 406 误判 + restore 串行化

### 批次六：性能防恶化 + 体验（随版本迭代）
1. **PF1** 首页 rebuild 收窄（一页一步）
2. **PF2** 图库/记录页局部订阅
3. **S16** 再次投屏加锁加 loading
4. **PF3/PF4/S20** 杂项顺手清
5. **S17** Doze 心跳（先真机测数据再决定）

### 长线（大版本再动）
- **M6** design tokens（新代码先行）、**M7** i18n 归一、**M9** lint 分批加强、**M10** 补单测（serial_match 可提前到批次一附带）、**M11/M12** 依赖方向与陈旧协议副本、路由 figma 前缀与文件命名（devices_page vs my_devices_page、app.dart shim）重命名。

---

## 七、明确建议保持现状、不要动的部分

审查同时确认了以下部分**质量高于平均水平，改动它们只有风险没有收益**，列出来防止"顺手优化"误伤：

1. **BLE 协议层核心**：全链路超时有界（每条请求/固件下载/帧下载/START/DATA ACK/END）、写全部 await 无 fire-and-forget、MTU 协商失败有降级、滑动窗口 AIMD、查表 CRC、每 256 帧让出事件循环——不要动。
2. **租约/心跳/前台服务生命周期**：`_keepAliveTimer` 与链路严格同生命周期、"心跳不刷新租约"已正确落实、`ble_connection_lease.dart` 墙钟 deadline + 回前台补判实现干净——除 S17 的 Doze 达成率外不要动。
3. **网络层纪律**：getJson/postJson 全局超时、日志 kDebugMode 门禁 + 递归脱敏（连 query 里的 userToken 都做了 `_redactUri`）、`extractApiRows` 脏数据容忍、全库无 `as Map` 强转、字段名 swagger 溯源注释——不要动。
4. **会话模型**：无 token 刷新（后端固定租约 + 401 重登）意味着**不存在**并发刷新竞态；`_handleSessionExpired` 有门闩只处理一次；token 落盘串行队列 + 冷启动 `Future.wait` 时序正确——不要动。
5. **UI 卫生已达标部分**：列表全部惰性构建（GridView/ListView.builder）、6 处 CachedNetworkImage 全量 memCacheWidth 且按 lp×dpr 计算、账户 5 页倒计时 Timer 与全部 Controller 无一泄漏、RouteAware 均 unsubscribe、投屏/OTA 页 `_aborted` + PopScope 闭环、loading/失败重试/空态/列表四分支链、全局收键盘、防重复点击覆盖（仅 S16 一处漏）——不要动。
6. **微信授权客户端**：并发去重、state 防 CSRF（Random.secure）、2 分钟超时、finally 里 cancel、错误码枚举化——整体质量高，不要动。
7. **注释与文档**：serial_match 的事故复盘注释、image_codec 的架构决策注释、pubspec 每个依赖的选型理由、docs/ 6 份文档——是项目的资产，拆分搬运时务必**连注释一起搬**。
8. **布局方案**：PROJECT_STRUCTURE.md 已复核结案"维持现状、不推广 Flex"（2026-06-05），本次不推翻该结论。

---

## 附：本次审查未覆盖 / 需开发机验证的事项

- 本机无 Flutter/JDK/Android SDK（既定约束），未运行 `flutter analyze` / `flutter test` / 真机验证；所有 file:line 以当前工作区为准。
- S17（Doze 心跳达成率）需真机息屏实测数据才能定改法。
- iOS 侧原生工程未深入审查（当前发布重心在 Android）。
- 修复实施时，逐项以本文档编号为锚点，每项独立验证后再合入。
