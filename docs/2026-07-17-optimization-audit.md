# 2026-07-17 全维度审查与修复记录

> **📌 文档维护约定**：本文档随代码演进——**每次修复问题 / 改动后，务必回到对应 .md 在文末「操作日志」追加一条**（日期 + 改了什么 + 对应代码符号/文件），防止文档滞后于代码、误导后续把已修的 bug 又改回去。


> 五个维度（架构/状态、BLE、网络、UI 稳定性/性能、可维护性）静态审查产出约 40 项发现，
> 按批次实施完毕。本文档是**修复后的精简版**：已改什么、没改什么、剩什么风险。
> 详细的原始分析（每项的失败场景推演）如需回溯可从 git 历史找本文件的上一版。
>
> ⚠️ 本机无 Flutter 工具链，所有修改均为静态实施、**未编译未运行**。
> 合入前必须在开发机执行：`flutter analyze` → `flutter test` → 按文末回归清单手测。

---

## 一、已修复（2026-07-17，共 34 项，44 文件 +888/-1384 行）

### 稳定性缺陷（S 系列）

| 编号 | 级别 | 问题 → 改法 | 位置 |
|---|---|---|---|
| S1 | **P0** | "一键清空/删除设备"可能落到错误设备：破坏性流程进入时快照 deviceId 全程只认它；`refreshDevices` 选中项落空改**置空**不再静默切首台 | state.dart / delete_device_flow.dart / device_clear_confirm_page.dart |
| S2 | P1 | BLE 连接建立中任一步失败不回收物理连接（设备停止广播、之后搜不到；前台服务/心跳空转耗电）→ 失败路径统一 `disconnect()` 回收；`_linkAlive`/onLinkStateChanged(true) 移到通知订阅成功之后 | device_ble.dart `connect()` |
| S3 | P1 | 远端断开后 `_notifySub`/`_connSub` 泄漏、重连后每条通知被重复解析 N+1 次 → connect 入口先 cancel 旧订阅 + `cancelWhenDisconnected` 兜底 | device_ble.dart |
| S4 | P1 | 4 处 loading 盲 pop（与历史"发验证码偶现闪退"同根因）→ 全部改 `AppLoadingDialog.hide` 精确移除 | home_page / devices_page / device_details / ota_upgrade(startOtaFlow) |
| S5 | P2 | ~16 处 `!mounted` 早退/门控跳过 hide → 全屏 canPop:false 蒙层可能永久滞留锁死 App → 统一 try/finally + hide 去 mounted 门控（hide 本就不依赖 context）；新增 `AppLoadingDialog.hideIfAny()` 并在掉登录态时兜底调用 | app_widgets + 12 个页面 + bolt_star_app |
| S6 | P1 | 上传响应体读取无超时（弱网 body 阶段永久挂起 = loading 无限转圈）→ `Response.fromStream(...).timeout(uploadTimeout)` | api_client.dart |
| S7 | P1 | 非幂等 POST 超时后静默重试（验证码双发/记录重复/重复绑定）→ `postJson` 加 `retryOnTimeout`，sendEmail / addUserProductImgRecord / addUserProduct 关闭；连接失败（未送达）仍重试 | api_client / boltfox_api |
| S8 | P1 | 首页换头像走相机原图（~48MB 位图进 ImageCache + 原图直传）→ 与资料页统一走新建的 `AvatarUpload`（512px/JPEG85 + 兜底压缩 ≤100KB）；两处本地回显 `Image.file` 补 cacheWidth | shared/avatar_upload.dart（新）/ home_page / profile_page / home_widgets |
| S9 | P2 | 首页轮播 `didUpdateWidget`→`jumpToPage` 同步触发构建期 notifyListeners（debug 断言红屏/release 异常帧，唯一真实框架级异常路径）→ 推迟到 postFrameCallback | home_widgets.dart |
| S10 | P2 | 投屏预取 Future 失败无监听 → 弱网失败被写进 last_crash.txt、下次启动误弹"崩溃报告" → `prefetch[idx]!.ignore()`（主循环 await 仍照常拿到错误） | projection_service.dart |
| S11 | P2 | 回前台"连接体检"用 FBP 内存镜像对账（死会话场景下恒 false 空转）→ 改 `FlutterBluePlus.systemDevices([Guid(FF00)])` 问 OS 真实连接表；查询异常保守不动 | ble_controller.dart |
| S12 | P2 | `connect`/`connectBoundDevice` 无重入护栏（并发连接互相踩 `_device`/订阅/广播登记）→ 入口 `if (connecting)` 拒绝第二路，返回新 l10n 提示 | ble_controller.dart |
| S13 | P2 | 登出/换号后在途响应回填旧账号数据（跨账号串屏）→ `_sessionEpoch` 代际：登录/登出/注销/会话过期 +1，refreshAlbum/CastRecords/Devices/_refreshUserInfo 写回前比对、过期丢弃 | state.dart |
| S14 | P2 | 网关 HTML/劫持页（2xx 非 JSON）被吞成 `{}` 伪装成功 → 2xx 且 body 非空但解析失败显性抛 `PARSE_ERROR`；非 2xx 仍按状态码报错 | api_client.dart |
| S15 | P2 | 兜底 `catch (_)` 把编程错误/文件缺失伪装成"网络连接失败"并白白重试 → 按 TimeoutException / ClientException / IOException / 其他 Exception 分类；上传的 FileSystemException 单独报"文件不存在"（新 l10n）；Error 不捕获让全局钩子如实记录 | api_client.dart |
| S16 | P2 | 投屏记录"再次投屏"无并发锁、连接+下载 ~30s 无 loading → `_recasting` 卫语句 + 全程 AppLoadingDialog（try/finally） | cast_management_figma_page.dart |
| S18 | P1 | 硬件调试台 release 对用户可达（可发任意 BLE 指令）→ 入口卡片 `kDebugMode` 门禁渲染为空；路由 release 下兜底为可返回空页（不 return null 防"未知路由"异常） | bind_device_debug_entry / app_routes |
| S19 | P2 | `connectDevice` 跨 await 写孤儿 DeviceItem（"toast 说成功、卡片显示未连接"）→ await 返回后按 id 重查列表再写标记，找不到走 reconcile | state.dart |
| S20a | P3 | 轮播 `page % devices.length` 空列表 `%0` 潜在崩溃 → onPageChanged 加 isEmpty 卫语句 | home_widgets.dart |
| S20b | P3 | 重命名对话框 controller：详情页从不 dispose（泄漏）、列表页退场动画期过早 dispose（断言）→ 统一延迟 kThemeAnimationDuration 释放 | device_details / my_devices |
| S20c | P3 | 网关 HTTP 406 被 `isAuthError` 数值推断误判成登录失效踢回登录页 → ApiException 加显式 `authError` 标志，非 2xx 分支传 false | api_exception / api_client |
| S20d | P3 | `ApiSession.restore()` 不排落盘队列，理论可被 setToken 时序覆盖 → 首行 `await _persistQueue` | api_session.dart |
| S20e | P3 | 两路并发图传互相打脏 `_lastImgAck` → `_imgUploadBusy` 门闩，第二路明确报"已有图传进行中"（busy kind） | device_ble.dart |
| S20f | P3 | 读电量与 25s 保活心跳撞 0x04 时用户看到"指令正在等待应答"内部措辞 → readBattery 对 commandPending 类错误延迟 2.2s 重试一次 | device_ble.dart |
| S20g | P3 | 断链时图传报错慢 ~1s（等 600ms ACK 超时 + 4×80ms 写重试）→ `_failAllPending` 同时 completeError 唤醒 `_imgAckWaiter` | device_ble.dart |
| S20h | P3 | `selectedDevice` 注释说"找不到会抛异常"与实现（占位设备）脱节 → 修注释；DeviceItem 加 `isPlaceholder` 标记供破坏性操作拦截 | state.dart |
| S20i | P3 | 热重启后原生前台服务/GATT 残留（通知栏常驻、设备被占线搜不到）→ main() 启动时 best-effort 停一次保活服务（冷启动无害空调用） | main.dart |

### 结构与可维护性（M 系列）

| 编号 | 内容 | 位置 |
|---|---|---|
| M2 | **错误分类枚举化**（服务层 i18n 的硬前置）：`FrameBleException` 加 `kind`（busy/commandPending/storageFull/disconnected/timeout/aborted/unsupported/unknown），BLE 层与 projection_service 全部抛出点标注；`ProjectionResult` 加 `failureKind` 穿透；投屏失败页优先按 kind 归类、**中文子串匹配保留为兜底**（老抛出点/非 BLE 错误仍走原逻辑，行为不回退） | device_ble / projection_service / casting_progress_page |
| M3 | **死代码删除 ~900 行**（每项均 grep 验证 0 引用）：state.dart 内整套演示期假投屏链路（castDraft/recast*/create*Draft/DraftPhoto/GuideArticle/buildGuideArticles/setOffline/isOffline/10 个死 getter，-491 行）；home_page 离线弹层死路径与冗余监听；3 个死文件（shared.dart 桶/prompt_text/background/scaffolds）；app_widgets 8 个旧首页死类（-264 行）；死路由 `/devices`。**castDraft 数据污染地雷已排除** | state / home_page / shared / app_routes |
| M8 | 路由表内嵌的 100 行删除设备流程搬到独立 `delete_device_flow.dart`（与 startOtaFlow 同模式）；busy 标志从"每次路由实例化一份"改为文件级单份；顺手统一 loading 收口 | app_routes / delete_device_flow.dart（新） |
| M10 | 补 `serial_match` 单测（曾出 EF6-370→EF6-589 真实串台事故的模块）：归一化/等长即否/前后缀锚定/中段重叠即否/<8 位即否/型号一票否决，全分支覆盖 | test/serial_match_test.dart（新） |
| M13 | baseUrl 改 `String.fromEnvironment('API_BASE_URL', defaultValue: 生产)`——不传 define 产物不变，`--dart-define` 即可切环境 | api_config.dart |

### 性能与体验（PF 系列）

| 编号 | 内容 | 位置 |
|---|---|---|
| PF2 | 图库/投屏记录页补全局 state 订阅（原来完全不订阅，BLE 断链后显示陈旧连接态）；订阅模式与其余页面收敛 | gallery_page / cast_management_figma_page |
| PF3a | 图传热路径每帧 `sublist` 拷贝算 CRC（每张 ~340KB 垃圾分配）→ `Uint8List.sublistView` 零拷贝 | frame_protocol.dart |
| PF3b | 上传压缩改为把**文件路径**传进 compute isolate 内读取（原来主 isolate 读 8~15MB 原图再跨 isolate 拷贝，瞬时 2× 内存） | projection_service.dart |
| PF3c | 设备卡背景去掉 `FilterQuality.high`（轮播滑动每帧三次立方采样，视觉无差异） | home_widgets.dart |
| PF3d | 雷达 GIF 压暗从 `Opacity` 包裹（动图每帧 saveLayer）改为 `Image.opacity` 着色混合 | home_widgets.dart |
| PF3f | 图库瓦片补 `maxWidthDiskCache: 800`（磁盘不再存原图） | gallery_page.dart |
| PF3g | 裁剪确认读宽高改 `ImageDescriptor`（只读头信息，省 8~16MB 全图解码）；预览 `Image.file` 补屏宽 cacheWidth | cast_preview_page.dart |
| PF4a | OTA 握手兜底穷举（最坏 ~15s）每换组合报一次"握手中（尝试 N/M）" | ota_ble.dart |
| PF4b | 投屏记录页 `didPopNext` 改静默重拉，返回时列表不再整页白闪 | cast_management_figma_page.dart |
| PF4c | 操作指南搜索无结果补空态文案（原来玻璃卡空白） | guide_page + l10n |
| PF4d | settings 仅有的两处无兜底 `Image.asset` 补 errorBuilder | settings_page.dart |
| PF4e | 详情页连接/断开加 `_togglingConnection` 重入锁 | device_details_page.dart |

### 附带（非审查项，用户另行指定）

- **changePassword 接口对接**（2026-07-17）：已登录"修改密码"从复用 `resetPassword` 切换到 swagger 专用的 `/Client/User/changePassword`（verifyCode/password/confirmPassword，userToken 定位账号）；邮箱行改只读；未绑邮箱有引导文案；`docs/接口清单.md` 同步更正。

---

## 二、未修复（原因与建议时机）

| 编号 | 内容 | 为什么这次不动 | 建议时机 |
|---|---|---|---|
| **S17** | Doze 下 25s 心跳停发，"息屏 30 分钟"租约在激进 ROM 上可能达不到 | **需真机数据才能定改法**（wakelock 有耗电代价，不能盲加）。已在 BleConnectionService.kt 头注留 TODO 与两个候选方案 | 真机实测息屏存活时长后：达不到 → onStartCommand 持 PARTIAL_WAKE_LOCK；可接受 → 记差异台账 |
| **批次三·翻译** | projection_service / device_ble / ota_ble / frame_protocol / wechat_authorization_client 约 90 条用户可见中文 + 法务长文 | 内容量大（~90 条 × 3 语言）应作为独立内容型任务；**M2 枚举化已完成，翻译已解除封印**（翻了也不会破坏失败页归类） | 单独一轮专做，翻完跑失败页归类回归 |
| **M1 一/二阶段** | state.dart 拆分（模型/纯函数外移 + mixin 分域） | 零行为的 900+ 行大搬运，与本轮 30+ 项修复混在一个 diff 里会让回归归因困难——正是"改 A 坏 B"的温床；且本机无 analyze 兜底。M3 已先把 state.dart 从 3188 减到 ~2700 行 | 本轮在开发机验证通过**之后**，作为独立 PR 做（先第一阶段纯搬运，再第二阶段 mixin） |
| **M4** | home_figma_common 与 home_widgets 的分叉组件合并 | 同上，纯搬运/合并类，避免与行为修复混批 | 随 M1 一起的结构专场 |
| **M5/M6/M7** | 确认弹窗封装、design tokens 收敛 537 处颜色、双 i18n 归一 | 长线项：新代码先行、旧代码渐迁，不适合一次性大扫除 | 定规矩后随日常迭代 |
| **M9** | lint 加强（unawaited_futures 等） | 开一批规则会产生一批需要修的告警，须在能跑 analyze 的环境里边开边修 | 开发机上分批开、修干净再开下一批 |
| **M11/M12** | device 层反向依赖、frame_device_protocol 陈旧参数收敛 | P3 结构债，且 M12 的容量兜底（离线态显示 32 而非 95）连接后会被真值覆盖 | 随 M1 结构专场 |
| **PF1** | 首页全页 rebuild 收窄（局部 ListenableBuilder / 字段级监听） | 改重建粒度需在真机上盯帧验证，静态改风险大于收益；且 M3 删掉死监听后首页只剩根部一条重建路径，现状可控 | 有真机盯帧条件时逐区块做 |

---

## 三、风险点（合入前必读）

### 必须先跑的验证
1. **`flutter analyze`**：本轮 44 个文件全部为静态修改，未经编译器检查。重点关注：state.dart（删了 491 行 + 多处插入）、device_ble.dart（connect 重构 + 图传互斥）、api_client.dart（异常分类重写）。
2. **`flutter test`**：既有 6 个测试文件 + 新增 serial_match_test。注意 `test/widget_test.dart` 断言硬编码中文（审查已知问题，未动）。

### 行为变化的回归点（按风险从高到低）
1. **BLE 连接/断开/重连全流程**（S2/S3/S12/S11/S19 都动了这条链）：绑定新设备、详情页连接/断开、投屏自动重连、连接失败后设备还能被再次搜到、回前台体检、快速连点连接按钮。**这是本轮改动最集中、最需要真机验证的一条链。**
2. **投屏全流程**（M2/S10/S16/PF3a/PF3b/PF3g/S20e/S20g）：多张连投、弱网中断看失败页归类是否正确（设备忙/存满/断连/超时/中止五类）、投屏中断链报错应 ~1s 内浮出、再次投屏连点只进一次。
3. **loading 收口**（S4/S5）：把上一版的"偶现闪退/假死"场景过一遍——发验证码、连接中切 Tab、删除设备全流程、会话过期时正在 loading。预期：任何路径蒙层都能收掉、绝不误弹业务页。
4. **删除/清空设备**（S1/M8）：流程行为应与改前完全一致（二次确认、断开、删除、出栈）；重点验证多设备场景下操作对象恒定。
5. **验证码**（S7）：弱网下发验证码只发一封；连接不上（飞行模式）时仍有自动重试。
6. **登出/换号**（S13/S5）：A 登出→B 快速登录，B 首屏不应闪现 A 的数据；登出瞬间有在途 loading 也能收掉。
7. **换头像**（S8）：首页与资料页两个入口行为一致、上传体积 ≤100KB、圆头像清晰度无肉眼退化。
8. **M3 删除面**：理论零行为（全部 grep 验证 0 引用），但请留意首页（删了离线死路径与冗余监听）与操作指南页正常。
9. **release 包专项**（S18）：绑定页不再出现"硬件联调调试台"横幅；debug 包一切照旧。

### 已知的有意行为微调（不是 bug，验收时别误判）
- 投屏失败页对"结束校验失败(0x22)：设备忙"现在正确归入**设备忙**话术桶（原子串匹配匹配不到"繁忙"二字，落兜底原样透出）——归类更准，属预期改善。
- `refreshDevices` 后端返回不含当前选中设备时，选中项**置空**而非切到第一台：首页展示不受影响（自带"选中→已连接→第一台"推导），但详情页若恰在此刻打开会显示占位数据（此前是悄悄显示另一台设备的数据——那正是 S1 要消灭的）。
- HTTP 406（非业务 406）不再踢登录；2xx 非 JSON 响应从"伪成功空数据"变为显性报"服务器异常"。
- 图库/投屏记录页现在会随全局状态变化即时重建（PF2）——列表滚动位置在 notify 时保持不变属预期（builder 惰性构建）。

### 环境切换（M13）
`flutter build apk --dart-define=API_BASE_URL=https://测试环境` 可切后端；不传时与原硬编码逐字节一致。

---

## 四、维持现状（审查确认质量高于平均、勿"顺手优化"）

- BLE 协议核心：全链路超时有界、写全 await、MTU 降级、滑动窗口 AIMD、查表 CRC。
- 租约/心跳/前台服务生命周期闭环（S17 的 Doze 达成率除外，见未修复）。
- 网络层纪律：公共参数双通道、日志 kDebugMode 门禁 + 递归脱敏（含 query 里的 userToken）、`extractApiRows` 脏数据容忍、字段名 swagger 溯源。
- 会话模型：无 token 刷新（后端固定租约 + 401 重登），不存在并发刷新竞态；落盘串行队列。
- 微信授权客户端：并发去重、state 防 CSRF、2 分钟超时、错误码枚举化。
- 布局方案：维持"FigmaScreen + 固定尺寸"现状（2026-06-05 已复核结案，不推广 Flex）。

---

## 五、遗留待办速查

- [ ] 开发机 `flutter analyze` + `flutter test` + 上述回归清单
- [ ] S17：真机测息屏心跳存活时长 → 决定 wakelock
- [ ] 服务层 i18n 翻译（~90 条 + 法务长文，M2 已解除封印）
- [ ] M1 state.dart 拆分（本轮验证通过后单独做）
- [ ] M4/M5/M6/M7/M9/M11/M12/PF1（长线，见"未修复"表）

---

## 操作日志

- 2026-07（本轮文档核对）：本审查文档的"已修/未修"标记经复核与代码一致；S17(Doze 心跳)/服务层完整 i18n/M1(state 拆分) 三项确属仍未做，其余标记为已修的均已落地。另本轮修复了 BleConnectionService start/stop 竞态("屡次停止运行"进程崩溃)与更新页 _check() 的失败兜底。

- 2026-07-17（六项用户反馈修复，App + 小程序同步）：
  1. **「扫描不到怎么办」弹窗去掉底部按钮**：Flutter 删 `bind_device_scan_help.dart` 底部 `FigmaHomePrimaryButton`(重新扫描) 及已无人传入的 `onRetry` 字段（3 处实例化都不传，按钮本就是禁用态）；小程序同步删 `subpackages/device/bind/bind.wxml`(弹窗内 `bindtap="scan"` 那条) 与 `pages/home/home.wxml`(弹窗内 `bindtap="rescanDevices"` 那条)。注意：搜索页/未发现页底部的「重新扫描」是另一个按钮，保留。
  2. **绑定流程提示精简**：删 `bind_device_flow.dart` 已绑定分支的 `_toast(bindAlreadyBoundConnected)`(该设备已绑定/已为你连接)，改为静默返回列表；保留全部失败提示与新绑定成功的 `bindSuccess`(绑定成功)。`bindAlreadyBoundConnected` 键退化为死键（保留定义）。
  3. **字体加粗（以小程序 bind.wxss 为准，.scan-title/.primary-action=700）**：`bind_device_searching.dart`/`bind_device_not_found.dart` 页标题 `pageHeading.copyWith(w700)`；`FigmaHomePrimaryButton` 新增可选 `fontWeight`(默认 w500 不影响别处)，`bind_device_found.dart`「立即绑定」传 w700。
  4. **toast 跟随语种**：排查确认生产面 `AppToast.show/warn` 无硬编码中文实参；唯一残留是开发者调试页 `ble_debug_page.dart`(非用户可见，有意不译)。核心漏点即第 5 项的 BLE 原始异常，一并修复。
  5. **蓝牙连接报错不再裸奔原始异常**：`FrameBleErrorKind` 加 `connectFailed`；`device_ble.dart _connectWithRetry` 失败异常打该 kind（原始 `FlutterBluePlusException | connect | android-code:133 | ANDROID_SPECIFIC_ERROR` 仅进日志）；`ble_controller.dart connect()` catch 改为 `debugPrint` 记原始错误 + 返回本地化 `bleConnectFailed`（新 l10n：连接失败，请靠近设备后重试 / EN / JA）；`bind_device_flow.dart:215` 改 `_toast(error)` 去掉双重「设备连接失败：」前缀。此修复级联到设备列表/首页/详情的连接失败路径（均经 `state.connectDevice` 透传该文案），提示同时变友好且跟随语种。`bindConnectFailed` 模板退化为死键。
  6. **图库/投屏管理列表取 imgThumb（对齐小程序 list.wxml/records.wxml 的 `item.imgThumb`）**：`AlbumPhoto`/`CastRecord` 新增 `thumbUrl` 字段（映射 `imgThumb ?? img`，对齐小程序 api.js `normalizePhoto`/`normalizeProjectionRecord`）；`gallery_page.dart`/`cast_management_figma_page.dart` 列表缩略图改绑 `thumbUrl`。**`imageUrl` 保留为原图**——投屏管理「再次投屏」仍用它下载原图重裁剪(`recastImgUrl: record.imageUrl`)，不能改指缩略图否则再投拿到低清图。
