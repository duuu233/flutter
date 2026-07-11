# App ↔ 小程序 逐页对比 & 同步/优化日志

> 目标：BoltStar Flutter App 与微信小程序 `photo-album`（test 分支，已通过验证，标准答案）在**功能与样式**上 1:1 对齐，
> **与设备(BLE)和后端接口的交互、参数完全一致**。同一套后端 `api.boltfox.cn`、同一款相框硬件。
>
> **维护约定**：每次同步某页 / 做一次优化，都在本文件对应行更新状态与「优化日志」。方便后续查看与继续开发。
>
> **两端已知差异（设计层面，非缺陷）**：
> - 登录：小程序=微信一键登录；App=邮箱密码登录（App 独有）。
> - App 额外功能：邮箱登录/注册、版本升级、语种设置。
> - 允许「App 特有更优实现」：在保证代码质量前提下，若某功能 App 端有更好用的插件 / 实现，
>   且能**提升传给设备与接口的性能/速度**，就用 App 方式实现（并在此登记原因）。

---

## 图例
- ✅ 已对齐并核对（接口/设备交互一致）
- 🟡 已实现但未逐参数核对 / 有已知小差异
- 🔶 App 特有实现（有意不同，已登记原因）
- ⛔ 缺失 / 待实现
- ➖ 不适用（两端差异设计）

---

## 一、页面映射与对齐状态

| 模块 | 小程序页面 | Flutter 页面 | 状态 | 备注 / 待办 |
|---|---|---|---|---|
| 首页 | `pages/home/home.js` | `features/home/presentation/home_page.dart` | ✅ | 设备轮播/连接/投屏入口已核；进入即 `refreshDevices`。tab 重入刷新见 §七G |
| 登录 | `pages/login/login.js`(微信) | `features/account/presentation/auth_page.dart` | ➖🔶 | App=邮箱登录（独有）。待办：缓存输入过的邮箱 |
| 我的 | `pages/mine/mine.js` | `features/mine/presentation/mine_page.dart` | 🟡 | 头像/昵称/入口；待核对 |
| 绑定设备 | `subpackages/device/bind/bind.js` | `features/devices/presentation/bind_device_flow.dart` 等 | ✅ | 搜索白名单(2尺寸)/判重/productId/deviceId 已对齐 |
| 设备调试台 | `subpackages/device/debug/debug.js` | `features/devices/presentation/ble_debug_page.dart` | 🔶 | App 调试工具；去端上调色后保留硬件测试帧 |
| 设备详情 | `subpackages/device/detail/detail.js` | `features/devices/presentation/device_details_page.dart` | ✅ | 重命名/连接(信息回填)/删除/清空已核；投屏自动连接·OTA 入口见 §七B/D |
| 设备列表 | `subpackages/device/list/list.js` | `features/devices/presentation/{devices,my_devices}_page.dart` | ✅ | pageSize100+序列号去重；每项按钮(投屏 vs 轮播)见 §七E |
| OTA 升级 | `subpackages/device/ota/ota.js` | `features/devices/presentation/ota_upgrade_page.dart` | ✅ | DFU 字节协议已核；入口门控/确认弹窗/auto 开始已补齐(`startOtaFlow`) |
| 轮播设置 | `subpackages/device/slideshow/slideshow.js` | `features/devices/presentation/carousel_settings_page.dart` | ✅ | setPlayback(0x10) 模式+间隔已核；间隔取真机值(兜底2h) |
| 投屏预览 | `subpackages/projection/preview/preview.js` | ➖（App 不做预览页） | 🔶 | **既定方针=最小可用链路**：App 端**无预览/无中心裁切/无端上裁剪旋转**。选图→直投；原图交后端接口，后端按设备分辨率转码 .raw 再 BLE 直传。`cast_preview_page.dart`/`cast_image.dart` 已删除（2026-07-12 修正上一会话的越界实现）|
| 投屏结果 | `subpackages/projection/result/result.js` | `features/cast/presentation/casting_progress_page.dart` + `cast/projection_service.dart` | ✅ | 部分成功/空间/归类/失步重同步已对齐；**投屏开始不自动重连**（未连接只提示，连接由用户手动触发）|
| 投屏记录 | `subpackages/projection/records/records.js` | `features/cast/presentation/cast_management_*` | ✅ | 再次投屏链已对齐；列表改为切 tab 分状态回后端拉取。旧 `cast_management_page` 待清理 §六 |
| 图库 | `subpackages/album/list/list.js` | `features/gallery/presentation/gallery_page.dart` | ✅ | list/删除/0x24 已核；单设备图库+跨设备删除拦截+删后对账+删除 loading。重入刷新见 §七G |
| 设置首页 | `subpackages/settings/index/index.js` | `features/settings/presentation/settings_page.dart` | ✅ | 联系方式/隐私/协议/两步删除+退出已核；userOff 失败留页 |
| 个人资料 | `subpackages/settings/profile/profile.js` | `features/account/presentation/profile_page.dart` | 🟡 | 改昵称/头像/改邮箱接口一致；头像提交时机·onShow 重拉见 §七H |
| 修改邮箱 | `subpackages/settings/change-email/change-email.js` | `features/account/presentation/modify_email_page.dart` | ✅ | changeUserEmail 字段一致；验证码统一 sendEmail |
| 绑定邮箱 | `subpackages/settings/bind-email/bind-email.js` | `features/account/presentation/bind_email_incomplete_page.dart` | ✅ | changeUserEmail 一致；验证码统一 sendEmail |
| 忘记密码 | `subpackages/settings/forgot-password/forgot-password.js` | `features/account/presentation/forgot_password.dart` | 🔶 | 小程序为静态占位；App 独有真实重置 `resetPassword`，待后端确认字段 §七A |
| 语言 | `subpackages/settings/language/language.js` | `features/settings/presentation/language_settings_page.dart` | 🔶 | App 独有细节；待核对文案 |
| 用户协议 | `subpackages/settings/agreement/agreement.js` | `features/settings/presentation/user_agreement_page.dart` | 🟡 | 待核对 |
| 隐私政策 | `subpackages/settings/privacy/privacy.js` | `features/settings/presentation/privacy_policy_page.dart` | 🟡 | 待核对 |
| 使用指南 | `subpackages/settings/guide/guide.js` | `features/guide/presentation/guide_page.dart` | 🟡 | 待核对 |
| 版本升级 | `subpackages/settings/update/update.js` | `features/settings/presentation/update_boltstar_page.dart` | 🔶 | App 独有（getLastVersion/安卓下载）；待核对 |
| 注册 | ➖ | `features/account/presentation/register_page.dart` | ➖🔶 | App 独有邮箱注册 |

---

## 二、全局约定对齐（接口/设备/交互层）

| 项 | 状态 | 说明 |
|---|---|---|
| 公共参数 terminal/language/device/userToken | ✅ | header + query 双发（对齐小程序 getClientQuery）。App terminal=iOS1/Android2 |
| 密码 md5(32位小写) | ✅ | login/register/reset/changeEmail 全部 md5 |
| 响应约定 retCode=200/retData | ✅ | 一致 |
| BLE 帧协议 | ✅ | SOF/CMD/CRC16-Modbus/CRC32-MPEG2/0x20帧/236分包/屏型/format 逐字节一致 |
| 投屏后端接口参数 | ✅ | setUserProductUpload/记录接口 字段全一致 |
| 投屏：只走后端 .raw→设备 | ✅ | 已去掉 App 端自研六色量化（uploadRgba/fromRgba/palette）；投屏唯一链路=后端转码。`image_codec` 仅留硬件测试帧(彩条/纯白/crc32) |
| 投屏：无预览/无中心裁切 | ✅ | App 端不做预览页、不做端上 aspectFill 中心裁切、不做裁剪/旋转编辑器；选图直投，后端按设备分辨率转码。（2026-07-12 删 `cast_preview_page`/`cast_image`）|
| 投屏/图库：未连接自动重连 | ✅ | **（2026-07-12 用户改判，撤销「不自动重连」）** 投屏入口(首页/详情/列表)+图库删除/刷屏未连接时**自动扫连**目标设备再操作，对齐小程序 ensureActiveDeviceConnection/ensureConnectedForAction。删除会自动连「照片所属设备」并校验，杜绝跨设备删错槽位 |
| OTA 升级入口门控 | ✅ | `startOtaFlow`：未连接自动扫连 + 二次查版本 loading + 已最新/新版本(稍后·立刻)弹窗 + 确认后 autoStart 自动开始（对齐 goOtaUpgrade）|
| 设备列表项按钮 = 投屏 | ✅ | 列表项操作改「投屏」(auto-connect+拍照/相册)；轮播设置从详情信息列表进入（对齐 list.wxml）|
| 页面重入刷新(onShow) | ✅ | RouteObserver + RouteAware：图库/投屏记录被覆盖页 pop 回来即回后端刷新；个人资料进入 refreshCurrentUser |
| 吐司提示 | ✅ | 全局改为居中 `AppToast`（overlay），已清除所有底部 SnackBar（全仓 0 处 SnackBar）|
| 缓存输入过的邮箱 | ✅ | `EmailHistory`(shared_preferences)：登录页预填最近一个；登录成功 & 注册成功后保存 |
| 连接后回填设备信息(0x01) | ✅ | 对齐 `applyConnectedDevice`：电量/内存(计数·容量)/播放模式/间隔/固件/当前张全回填（原仅电量） |
| 验证码发送接口 | ✅ | 全部走 `/Client/Basic/sendEmail`（auth:false）；小程序从不调 `sendEmailToken`（已删） |
| 密码 md5 / changeUserEmail 字段 | ✅ | login/register/reset/changeEmail 全 md5；changeUserEmail=`userEmail/verifyCode/password/confirmPassword`（均 md5）逐字段一致 |
| 设备增删改查接口 | ✅ | list/detail/rename(editUserProduct)/delete(delUserProduct)/clear(clearUserProductImg) 端点·字段全一致；list `pageSize=100`、按序列号去重 |
| 投屏上传/记录接口 | ✅ | setUserProductUpload(`fileParam`+targetW/H+isCompress)/editUserProductImgRecord(upirId·taskId·state=1)/addUserProductImgRecord(recast) 字段全一致 |
| 投屏记录列表按状态拉取 | ✅ | 切 tab 带 `deviceUploadState`(1/0) 回后端过滤（对齐 records.js），不再本地切片丢行 |
| 图库 list/删除/刷屏(0x24) | ✅ | getUserProductImgList(pageSize100)/delUserProductImg(`idList`)/0x12 掩码/0x24 刷屏 逐字节一致；单设备图库、跨设备删除已拦截；删后回后端对账 |
| 轮播 setPlayback(0x10) | ✅ | PLAY_MODE+INTERVAL；间隔取真机 `intervalSeconds`（兜底 2h，原误用 24h）|
| 注销 userOff 失败处理 | ✅ | 成功才清本地态并跳登录页，失败留页提示（对齐 index.js） |
| 投屏 BLE 0x20/21/22/23/24 | ✅ | 帧头/CRC16-Modbus/CRC32-MPEG2/236 分包/滑窗 ACK/屏型/format 逐字节一致（设备审计确认）|
| OTA DFU(FF10/FF11) | ✅ | 128B 头握手/PRN 窗/END 0xF3 整图校验 op-code 一致（入口门控见 §七判断项）|

---

## 三、优化 / 同步日志（倒序，最新在上）

> 格式：`日期 — 模块 — 做了什么 — 触及文件 — 状态`

- 2026-07-12 — **§七 判断项按用户确认全部实现（含撤销「投屏不自动重连」）** — 用户拍板：全 App 按小程序自动重连 / OTA 补齐整套入口 / 列表项改「投屏」/ 零散 UX 全做：
  1. **自动重连（撤销既定方针）**：投屏开始（首页 `_startCast` / 详情 `_startCast` / 列表项「投屏」）未连接→蒙层 loading 自动扫连再投；图库删除/刷屏未连接→自动连「照片所属设备」再操作（`ensureConnectedForAction`）。删除路径改为按「照片所属设备」自动连并校验，替代原「跨设备拦截只提示」。
  2. **详情/列表投屏**：加「拍照 / 相册」选择面板（原详情仅相册），相册上限 5。
  3. **设备列表按钮**：每项「轮播设置」→「投屏」（`onCarouselSettings`→`onCast`，auto-connect + 选图 + 投屏页），轮播设置仍从详情信息列表进入。
  4. **OTA 入口**：`startOtaFlow` 补齐小程序 goOtaUpgrade——未连接自动扫连 + loading 二次拉版本(`fetchDeviceFirmwareInfo`) + 「已最新/新版本(稍后·立刻更新)」弹窗 + 确认后进 OTA 页 `autoStart` 自动开始。
  5. **删设备前「先断开」确认**：已连接时删除前先弹「需断开」确认（对齐 detail.js）。
  6. **页面重入刷新**：`appRouteObserver`(RouteObserver) 注册到 MaterialApp；图库/投屏记录实现 `RouteAware.didPopNext`，被覆盖页 pop 回来即回后端刷新（对齐 onShow）。
  7. **个人资料**：进入回后端 `refreshCurrentUser`（对齐 profile onShow）。头像仍选完即传（端点/字段与保存时提交一致，仅时机不同——因无编译器环境保守保留，已登记）。
  8. **图库底栏**：加「取消」按钮清空选择；刷屏按钮常驻，多选时点它提示「刷新屏幕只能选中一张图片」（对齐 list.wxml）。
  — `home_page.dart` `device_details_page.dart` `devices_page.dart` `my_devices_page.dart` `ota_upgrade_page.dart` `app_routes.dart` `bolt_star_app.dart` `gallery_page.dart` `cast_management_figma_page.dart` `profile_page.dart` `state.dart` — ✅
- 2026-07-12 — 逐页对比·**四模块审计完成并逐条修复** — 对账号/设置、设备、首页/投屏、图库四大模块与小程序逐接口·逐 BLE·逐流程对比，据结果修复：
  1. **设备连接信息回填(高)**：连接后仅同步电量→改为回填真机 0x01 全字段（内存/播放模式/间隔/固件/当前张），对齐 `applyConnectedDevice`。新增 `DeviceItem.liveImageCount/liveCapacity`（真机容量最多 95 槽，超 int 掩码 32 位范围，直接采用真机上报计数/容量）+ `_applyConnectedInfo`/`_playbackModeFromWire`。修复详情页内存恒显 0、播放模式/固件默认、以及↓。
  2. **轮播间隔(中)**：`setPlayback` 原用 24h 默认覆盖设备现有间隔→改为连接时同步真机 `intervalSeconds`，兜底默认 24h→**2h**（对齐小程序 intervalHours 默认）。
  3. **验证码接口(高)**：绑定/换邮箱/改密的验证码原走 `sendEmailToken`→统一 `/Client/Basic/sendEmail`（小程序从不调 sendEmailToken）；删死代码 `sendEmailToken`/`changePassword`。
  4. **图库跨设备删除(高·BLE 正确性)**：移除「全部相框」筛选、默认单设备（优先已连接）；删除路径新增「所选照片必须属于当前连接设备」校验，杜绝按连接设备掩码解析删错槽位(0x12)。
  5. **注销失败处理(中)**：`userOff` 抛错原仍本地登出→改为**成功才**清本地态并跳登录页，失败提示留页（对齐 index.js）。
  6. **投屏记录分状态拉取(中)**：原一次取 100 条本地切片（>100 丢行）→切 tab 时带 `deviceUploadState`(1成功/0失败) 回后端拉取。
  7. **删除后回后端对账(中)**：删相册照片成功后 `refreshAlbum()`（对齐 loadPhotos），不再只本地软隐藏。
  8. **首页进入刷新(中)**：`initState` post-frame `refreshDevices()`，修复登录后直落首页误显「未绑定」。
  9. **设备列表**：`pageSize` 50→**100**；按序列号去重（对齐 dedupeDevices）。
  10. **投屏批量上限**：`pickMultiImage(limit:5)`（对齐 media.chooseFromAlbum count:5）。
  11. **删除 loading**：设备删除(最长~180s)期间蒙层「删除中」（对齐 wx.showLoading mask）。
  12. **轮播标签**：「已关闭」→「未启用」并含 manual 条件（对齐 getPlaybackLabel）。
  — `state.dart` `boltfox_api.dart` `frame_device_protocol.dart` `gallery_page.dart` `cast_management_figma_page.dart` `settings_page.dart` `home_page.dart` `casting_progress_page.dart` `device_details_page.dart` `bind_email_incomplete_page.dart` `modify_email_page.dart` `modify_password.dart` — ✅（判断项/大改见 §七）
- 2026-07-12 — 投屏 — **撤销上一会话的越界实现**，回到既定「最小可用链路」：① 删除 `cast_preview_page.dart` + `cast_image.dart`（预览页 + `castCenterCrop` 中心裁切）；② 首页/设备详情投屏入口改为「选图→直接 `CastingProgressPage` 真实投屏」，不再进预览裁切；③ 首页 `_startCast` 未连接时**不再自动重连**（原 `connectDevice` 静默重连），改为提示弹层「设备连接失败/请先连接设备后再投屏/重新连接」，「重新连接」按钮=用户**手动**触发的 `_reconnectActiveDevice`（非自动）。依据：2026-07-10 用户确认「不做端上裁剪/旋转编辑器，最小可用链路」+ 本次用户明确「投屏没有预览/中心裁切、开始不自动重连」 — `home_page.dart` `device_details_page.dart`（删 `cast_preview_page.dart` `cast_image.dart`）— ✅
- 2026-07-12 — 逐页对比 — 4 模块并行审计（账号 / 设置 / 设备 / 图库·投屏记录）对比后端接口参数·BLE·流程，据结果逐条修复回填 —（审计运行中）
- 2026-07-12 — 注册 — 注册成功后也缓存邮箱（补齐待办5）：`register_page._register` 成功时 `EmailHistory.add`，与登录页统一，登录页可自动填充 — `register_page.dart` — ✅
- 2026-07-12 — 逐页对比 — 启动首页 / 我的·设置·账号 / 设备(详情·列表·轮播·OTA) / 图库·投屏记录 四模块并行审计（对比后端接口参数·BLE交互·关键流程），据结果逐条修复 — （审计进行中）
- 2026-07-12 — 投屏 — 预览+设备比率中心裁切：新增 `cast_image.castCenterCrop`(dart:ui aspectFill)+`cast_preview_page`；首页/设备详情投屏入口改为「选图→预览裁切→真实投屏」 — `cast_image.dart` `cast_preview_page.dart` `home_page.dart` `device_details_page.dart` — ✅
- 2026-07-12 — 投屏 — 去端上调色（见下）后，首页投屏未连接自动重连 —（见上一条重连）
- 2026-07-12 — 全局 — 吐司居中：新增 `AppToast`(居中 overlay) 并从 figma_common re-export；转换 gallery/modify_email。剩余机械清扫见待办 4 — `app_toast.dart` `figma_common.dart` `gallery_page.dart` `modify_email_page.dart` — 🟡
- 2026-07-11 — 登录 — 缓存输入过的邮箱：新增 `EmailHistory`(shared_preferences)，登录成功后记住邮箱、进入登录页自动填充最近一个 — `email_history.dart` `auth_page.dart` `pubspec.yaml` — ✅（注册页保存待补）
- 2026-07-11 — 首页/投屏 — 投屏开始自动重连：`_startCast` 未连接时不再直接报错，改为 `state.connectDevice`（复用/重扫重连，对齐小程序 ensureActiveDeviceConnection），连上再投 — `home_page.dart` — ✅
- 2026-07-11 — 投屏 — 去掉 App 端自研调色：删 `BleController.uploadRgba` + `image_codec` 的 `fromRgba`/palette/抖动 + 调试台端上量化按钮/调参；投屏统一后端 .raw→设备。保留 crc32/彩条/纯白测试帧 —
  `image_codec.dart` `ble_controller.dart` `ble_debug_page.dart` `projection_service.dart` — ✅
- 2026-07-11 — 投屏编排 — 部分成功判成功页 / 去整单空间预检逐张放满 / 尺寸=0 归类 / 通知失步重同步 —
  `projection_service.dart` `device_ble.dart` — ✅
- 2026-07-11 — 绑定设备 — 搜索白名单(EF6-370/589 两尺寸)/判重/productId 打分/deviceId 字段/序列号优先级 —
  `boltfox_api.dart` `ble_controller.dart` `device_ble.dart` `bind_device_*` `state.dart` — ✅
- 2026-07-11 — 网络层 — 公共参数补进 query string（修复 App 绑定/已登录接口鉴权，根因） — `api_client.dart` — ✅
- 2026-07-11 — 绑定设备 — 搜索中改用 `assets/images/search-devices.gif` — `bind_device_searching.dart` — ✅

---

## 四、待办队列（按优先级）

1. ✅ 去掉 App 端自研调色（uploadRgba/fromRgba/palette），投屏统一后端 .raw→设备。（已完成）
2. ↩️ 投屏预览 + 设备比率中心裁切 —— **已撤销**（2026-07-12）。既定方针=最小可用链路：App 端不做预览/中心裁切/裁剪旋转编辑器。已删 `cast_preview_page.dart`/`cast_image.dart`，选图直投，后端按设备分辨率转码。
3. ↩️ 投屏开始自动重连 —— **已撤销**（2026-07-12）。投屏开始不自动重连：未连接只提示，连接由用户手动触发（`_reconnectActiveDevice`）。
4. ✅ 吐司居中展示（全局）——**已完成**：新增 `AppToast`（居中 overlay）+ figma re-export，全仓 22 处吐司改用它，已无 SnackBar。
   <details><summary>历史清单（已全部完成）</summary>
   - ✅ 已建 `shared/widgets/app_toast.dart`（`AppToast.show(context, msg)` 居中 overlay），并从 `figma_common.dart` re-export（import 它的页面免加 import）。
   - ✅ 已转换：`gallery_page`、`modify_email_page`。
   - ⏳ 剩余统一改法：把各页吐司体 `ScaffoldMessenger.of(context)..hideCurrentSnackBar()..showSnackBar(SnackBar(content: Text(x)))` → `AppToast.show(context, x)`。
     - 封装方法(改体即可)：`auth_page`/`home_page`/`bind_device_flow`/`ble_debug_page`/`cast_management_page`（这 5 个**未** import figma_common，需 `import '.../shared/widgets/app_toast.dart'`）；`bind_email_incomplete_page`/`modify_password`/`forgot_password`/`carousel_settings_page`/`register_page`/`cast_management_figma_page`（figma re-export，直接改体）。
     - 内联 showSnackBar(逐处替换)：`profile_page`(4)、`settings_page`(4)、`device_clear_confirm_page`、`device_delete_confirm_page`、`device_details_page`、`devices_page`、`casting_progress_page`、`language_settings_page`、`update_boltstar_page`。
   </details>
5. ✅ 缓存用户输入过的邮箱（登录页预填最近一个 + 登录/注册成功后保存）。（已完成）
6. ✅ 逐页对比实现：四模块（账号·设置 / 设备 / 首页·投屏 / 图库）并行审计**已完成**，确认为真实差异的 12 项已逐条修复（见 §三 顶部条目）。**wire 级（后端端点·字段 + BLE 帧字节）已确认全对齐**；剩余为流程/UX 判断项，见 §七（需你确认后再动，部分与「不自动重连」既定方针相关）。

---

## 五、App 特有实现登记（🔶）

> 在此登记「有意与小程序不同、用 App 更优方式」的点，含原因与性能收益。

- **吐司 = 居中 overlay（`shared/widgets/app_toast.dart`）**：小程序用 `wx.showToast`（系统居中吐司）。App 不用底部 `SnackBar`，自建居中 `AppToast`（overlay + 自动淡出），从 `figma_common.dart` re-export。原因：与小程序「屏幕中部提示」观感一致，且不占用 `Scaffold` 底部、避免与底部导航/按钮遮挡。全仓 0 处 SnackBar。
- **投屏图片选择 = `image_picker` 原生插件**：小程序用 `wx.chooseMedia`。App 用 `image_picker` 直接拿到**本地可上传文件路径**（避免 `content://` 无法直传），拍照/多选相册统一。原因：原生相册/相机选择更快、返回路径即可 multipart 上传后端转码。
- **邮箱历史缓存 = `shared_preferences`（`EmailHistory`）**：小程序登录是微信一键登录、无需记邮箱；App 独有邮箱登录，故本地缓存输入过的邮箱，登录页预填最近一个、登录/注册成功后保存。App 独有能力。
- **版本升级 = `url_launcher` + `package_info_plus`**：App 独有（小程序无安装包升级概念）。`getLastVersion` 比对本地版本，安卓走 `getAndroidDownload` 兜底下载链接。
- **BLE 通知失步重同步**：坏字节丢头重同步 + `RX_BUFFER_MAX` 上限（`device_ble.dart`），防止解析卡死导致全指令超时。见 memory `photo-album-sync-plan`。

## 六、待清理（低优先，非阻断）

> App 内的 figma 展示/演示遗留页，仅 `/figma/...` 路由可达，不在真实用户流程中；与「无预览/无中心裁切」方针相悖的演示编辑器尤应清理。

- `features/cast/presentation/photo_preview_adjust_image_page.dart`（**端上调整图片编辑器**，与既定方针相悖）、`photo_preview_saved_page.dart`、`cast_success_page.dart`、`cast_failed_page.dart` —— 均仅由 `routes/app_routes.dart` 的 `/figma/...` 展示路由引用，实流程未用。建议连同对应路由常量一并删除（需编译验证后再动）。
- `state.dart` 里 `castDraft`/`createCameraDraft`/`createAlbumDraft`/`recastAlbumPhoto`/`_draftLibrary`/`DraftPhoto` 等**投屏模拟**遗留方法：外部调用为 0，可删（其 `palette` 仅是占位缩略图底色，非图像调色）。
- `features/cast/presentation/cast_management_page.dart`（**旧版投屏管理**，其 `recastRecord` 走 `castDraft` 模拟、不碰设备/后端）：仅 `/cast-management` 死路由引用，真流程走 `CastManagementFigmaPage`。建议删该页 + 死路由（家庭审计 home#3）。

## 七、审计判断项（用户 2026-07-12 已拍板，除 A 外均已实现）

> 四模块审计发现的非 wire 级流程/UX 项；用户选择「全按小程序对齐」，实现见 §三 顶部条目。

- ✅ **B/C. 自动重连**：用户选「全部按小程序自动重连」。投屏入口(首页/详情/列表)+图库删除/刷屏未连接均自动扫连目标设备再操作（撤销「投屏不自动重连」既定方针）。
- ✅ **B 附带. 投屏拍照/相册面板**：详情/列表投屏加拍照+相册选择面板，相册上限 5。
- ✅ **D. OTA 入口门控**：`startOtaFlow` 补齐（未连接自动扫连 + 二次查版本 loading + 稍后/立刻弹窗 + autoStart 自动开始）。
- ✅ **E. 设备列表按钮**：改「投屏」（轮播设置移到详情信息列表）。
- ✅ **F. 删设备前「先断开」确认**：已连接时删除前弹「需断开」确认。
- ✅ **G. 页面重入刷新**：RouteObserver + RouteAware（图库/投屏记录 didPopNext 回后端刷新）；个人资料进入 refreshCurrentUser。
- ✅ **H②. 个人资料 onShow 重拉**：已加。 ⚠️ **H① 头像保存时提交**：暂保留「选完即传」（端点/字段与保存提交完全一致，仅时机不同；无编译器环境下保守不改，避免 Image.file 预览 + pending 态引入回归）。
- ✅ **I. 图库零散 UX**：加「取消」按钮；刷屏常驻，多选点它提示「刷新屏幕只能选中一张图片」。（总数语义/清空文案属更细的文案项，未逐字改）
- ⚠️ **A. 忘记密码/改密 `resetPassword` 接口**：小程序忘记密码是**静态占位页**（无标准答案）；App 独有邮箱登录必须真实重置。当前走 `POST /Client/User/resetPassword`、字段 `email`（其余接口用 `userEmail`）。**仍需后端确认路径/字段名**，保持现状（删了会断 App 功能）。← **唯一待你/后端确认项**。
