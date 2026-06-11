# API Integration Progress (App / BoltStar)

接口文档：https://api.boltfox.cn/swagger-ui.html#/

后端地址：https://api.boltfox.cn

当前项目：BoltStar Flutter App（iOS / Android）

## 对接规则

- 只对接用户前端模块：基础功能接口、产品接口、用户接口、设备接口。
- 当前为 App，**走邮箱登录/注册体系**，`/Client/User/setWechatAppLogin`（微信小程序一键登录）不接入。
- App 需要版本更新与安卓下载：`/Client/Basic/getLastVersion`、`/Client/Basic/getAndroidDownload` 接入（与小程序相反）。
- `/Client/User/userOffPC`（PC 注销）跳过。
- 公共参数 `device` / `terminal` / `language` / `userToken` 通过 headers 传递；App `terminal`：iOS=1、Android=2（取值以后端约定为准，见 `lib/src/network/api_config.dart`）。
- BoltFox 响应格式为 `retCode/retMsg/retData`，`retCode=200` 表示成功，由 `ApiClient` 统一解析。
- 网络层位置：`lib/src/network/`（`api_config` / `api_session` / `api_exception` / `api_client` / `boltfox_api`）。
- 新增依赖：`http`（见 `pubspec.yaml`）。**首次拉取后需执行 `flutter pub get`。**

## 模块进度

| 模块 | 状态 | 代码位置 | 说明 |
| --- | --- | --- | --- |
| 网络层基础 | 已完成 | `lib/src/network/api_*.dart` | header 注入 + retCode 解析 + 异常/会话 |
| 用户前端-基础功能接口 | 接口层已接入 | `lib/src/network/boltfox_api.dart` | 邮箱验证码、基础数据、版本更新、安卓下载、文件/设备上传 |
| 用户前端-产品接口 | **FAQ 页面联调已接入** | `state.dart` + `features/guide` | 操作指南 FAQ 列表/详情已串通；产品列表待绑定设备流程 |
| 用户前端-用户接口 | **页面联调已接入（账号模块）** | `state.dart` + `features/account` + `features/settings` | 登录/发码/注册/找回/改密/改邮箱/保存资料/退出/注销 已串通真实接口；微信一键登录、PC 注销跳过 |
| 用户前端-设备接口 | **页面联调已接入（设备 + 相册图库 + 投屏记录）** | `state.dart` + `features/devices,album,gallery,cast` | 设备列表/详情/重命名/删除/清空；相册/图库列表+多选删除；投屏记录列表+删除，均已串通真实接口；绑定待 BLE 流程联调 |

> 接入方式：先建立 `lib/src/network` 接口层（本阶段），页面/`PhotoFrameState` 联调时在各 action 方法内部替换为真实接口调用，避免页面直接拼接请求。

## 已接入接口（模块1）

### 基础功能接口

| 方法 | 路径 | `BoltFoxApi` 方法 | Swagger 摘要 |
| --- | --- | --- | --- |
| POST | `/Client/Basic/sendEmail` | `sendEmail()` | 发送邮箱验证码（未登录） |
| POST | `/Client/Basic/sendEmailToken` | `sendEmailToken()` | 发送邮箱验证码（已登录） |
| GET | `/Client/Basic/getBasicData` | `getBasicData()` | 获取基础数据 |
| GET | `/Client/Basic/getLastVersion` | `getLastVersion()` | 获取 App 版本更新状态 |
| GET | `/Client/Basic/getAndroidDownload` | `getAndroidDownload()` | 安卓下载 |
| POST | `/Client/Basic/setFileUpload` | `setFileUpload()` | 基础文件上传（form-data） |
| POST | `/Client/Basic/setUserProductUpload` | `setUserProductUpload()` | 设备上传图片（form-data） |

### 产品接口

| 方法 | 路径 | `BoltFoxApi` 方法 | Swagger 摘要 |
| --- | --- | --- | --- |
| GET | `/Client/Product/getProductList` | `getProductList()` | 产品列表 |
| GET | `/Client/Product/getProductFaqList` | `getProductFaqList()` | 常见问题列表 |
| GET | `/Client/Product/getProductFaqDetail` | `getProductFaqDetail()` | 常见问题详情 |

## 已接入接口（模块2 用户接口）

| 方法 | 路径 | `BoltFoxApi` 方法 | 关键字段 / 说明 |
| --- | --- | --- | --- |
| POST | `/Client/User/userLogin` | `userLogin()` | `email`、`password`；返回登录 token，需 `ApiSession.setToken` |
| POST | `/Client/User/userRegister` | `userRegister()` | `email`、`password`、`emailCode`、`nickName?` |
| POST | `/Client/User/resetPassword` | `resetPassword()` | `email`、`password`、`emailCode`（sendType:2） |
| POST | `/Client/User/chkUserEmailNotExist` | `chkUserEmailNotExist()` | 注册前置校验，邮箱已存在返回异常码 |
| POST | `/Client/User/changePassword` | `changePassword()` | `oldPassword`、`newPassword` |
| POST | `/Client/User/changeUserEmail` | `changeUserEmail()` | `email`、`emailCode`（sendType:3） |
| GET | `/Client/User/getUserInfo` | `getUserInfo()` | userToken 走 header |
| POST | `/Client/User/changeNickName` | `changeNickName()` | 1-10 字 |
| POST | `/Client/User/changeAvatar` | `changeAvatar()` | 头像地址（可先 `setFileUpload`） |
| POST | `/Client/User/loginOut` | `loginOut()` | 成功后 `ApiSession.clear()` |
| POST | `/Client/User/userOff` | `userOff()` | 成功后 `ApiSession.clear()` |

### 用户接口-小程序跳过项（App 不接入）

| 方法 | 路径 | 跳过原因 |
| --- | --- | --- |
| POST | `/Client/User/setWechatAppLogin` | 微信小程序一键登录，App 走邮箱登录 |
| POST | `/Client/User/userOffPC` | PC 版注销 |

## 已接入接口（模块3 设备接口 / UserProduct）

| 方法 | 路径 | `BoltFoxApi` 方法 | 关键字段 / 说明 |
| --- | --- | --- | --- |
| POST | `/Client/UserProduct/addUserProduct` | `addUserProduct()` | `productId`、`productName`、`productSerialNo` |
| GET | `/Client/UserProduct/getUserProductList` | `getUserProductList()` | 分页：pageIndex/pageSize/keyword/startDate/endDate |
| GET | `/Client/UserProduct/getUserProductDetail` | `getUserProductDetail()` | `userProductId`、`productVersionNo?` |
| POST | `/Client/UserProduct/editUserProduct` | `editUserProduct()` | `userProductId`、`productName` |
| POST | `/Client/UserProduct/delUserProduct` | `delUserProduct()` | `id`=userProductId |
| POST | `/Client/UserProduct/clearUserProductImg` | `clearUserProductImg()` | `id`=userProductId（格式化） |
| GET | `/Client/UserProduct/getUserProductImgList` | `getUserProductImgList()` | 分页 + userProductId（我的图库） |
| POST | `/Client/UserProduct/delUserProductImg` | `delUserProductImg()` | `ids`=[uProductImgId]，支持多选 |
| GET | `/Client/UserProduct/getUserProductImgRecordList` | `getUserProductImgRecordList()` | 投屏记录列表 |
| POST | `/Client/UserProduct/delUserProductImgRecord` | `delUserProductImgRecord()` | `id`=upirId |

## 全部接口层已对接 ✅

用户前端 4 个模块（基础公共 / 产品 / 用户 / 设备）接口层已全部接入 `lib/src/network/boltfox_api.dart`。

## 页面联调进度（模块A：用户/账号）✅

`PhotoFrameState` 新增/改造为 `Future` 形态的 action 方法，内部调用 `BoltFoxApi`，
页面只负责 `await` 并展示 `ActionFeedback.message`；登录态由 `ApiSession` 统一持有。

| 页面 | 文件 | 触发动作 → `PhotoFrameState` 方法 → 接口 |
| --- | --- | --- |
| 登录 | `account/auth_page.dart` | 登录 → `loginWithPassword` → `userLogin`，成功写 `ApiSession.setToken` 并 `getUserInfo` |
| 注册 | `account/register_page.dart` | 获取验证码 → `sendEmailCode(sendType:1)` → `sendEmail`；注册 → `registerWithEmail` → `userRegister` |
| 忘记密码 | `account/forgot_password.dart` | 获取验证码 → `sendEmailCode(sendType:2)` → `sendEmail`；确认 → `resetPasswordByEmail` → `resetPassword` |
| 修改密码 | `account/modify_password.dart` | 获取验证码 → `sendEmailCode(sendType:2, loggedIn:true)` → `sendEmailToken`；确认 → `resetPasswordByEmail` → `resetPassword` |
| 修改邮箱 | `account/modify_email_page.dart` | 获取验证码（发到新邮箱）→ `sendEmailCode(sendType:3, loggedIn:true)` → `sendEmailToken`；确认 → `changeBoundEmail` → `changeUserEmail` |
| 个人信息 | `account/profile_page.dart` | 保存资料 → `updateProfile` → `changeNickName`（昵称 1-10 字校验） |
| 设置 | `settings/settings_page.dart` | 退出登录 → `logout` → `loginOut` + `ApiSession.clear`；用户注销 → `deleteAccount` → `userOff` + `ApiSession.clear` |
| 语种设置 | `settings/language_settings_page.dart` | 切换语言 → `switchLanguage` 内同步 `ApiSession.setLanguage`（更新 `language` header） |

实现要点：
- 登录 token 解析见 `state.dart` 的 `_readToken`（兼容 `userToken/token/accessToken` 等命名，retData 为纯字符串也可）。
- 接口异常统一经 `_apiFailure` 透传后端 `retMsg`；网络异常回落本地多语言文案。
- 路由 `app_routes.dart` 已把 `state` 透传给注册/找回/改密/改邮箱页（原先是无状态 mock 页）。
- 验证码按钮统一加 30s 倒计时，仅在发送成功后启动。

### 待后端确认 / 已知差异

- **修改密码页**收集「邮箱+验证码+新密码」，对应 `resetPassword`（sendType:2），而非仅 old/new 的 `changePassword`；如后端「修改密码」要求旧密码请改用 `changePassword`。
- **修改邮箱页**含「密码/确认密码」输入框，但 `changeUserEmail` 仅需 email+emailCode，密码字段当前未提交，待确认后端是否需要密码校验。
- 绑定邮箱流程页（`bind_email_incomplete_page` / `bind_email_complete_page`）仍为 mock，未接 `changeUserEmail`，待联调（仅在用户邮箱未绑定时触达）。
- 账户资料另有 `profile_bound_email_page` / `profile_unbound_email_page` 两个并列 Figma mock 页，主资料页为 `profile_page.dart`（已联调）。
- 头像上传（`setFileUpload` + `changeAvatar`）未接：`UserProfile` 当前用 `avatarColor` 占位，无头像 URL 字段，待引入图片选择后再接。

## 页面联调进度（模块B：设备）✅

`PhotoFrameState` 设备 action 改造 / 新增为 `Future` 形态，内部调用 `BoltFoxApi`；
设备列表页改为以 `state` 为单一数据源，通过 `AnimatedBuilder` 监听状态变化自动刷新。

| 页面 | 文件 | 触发动作 → `PhotoFrameState` 方法 → 接口 |
| --- | --- | --- |
| 我的设备列表 | `devices/devices_page.dart`（包装 `my_devices_page.dart`）| 打开拉取 → `refreshDevices` → `getUserProductList`；重命名 → `renameDevice` → `editUserProduct` |
| 设备详情 | `devices/device_details_page.dart` | 渲染 `state.selectedDevice`（名称/连接/电量/SN/内存/固件）；打开前 `selectDevice(id)` |
| 一键清空 | `devices/device_clear_confirm_page.dart` | 确认 → `clearDeviceMemory` → `clearUserProductImg`（+ 本地 IMG_MASK / 相册同步）|
| 删除设备 | `devices/device_delete_confirm_page.dart` | 确认 → `deleteDevice` → `delUserProduct`（+ 本地设备/相册/记录清理）→ 退回列表 |
| 绑定设备 | （待 BLE 流程联调）| `bindDevice` → `addUserProduct` + `refreshDevices`（方法就绪，绑定 UI 流程未接）|

实现要点：
- 路由 `figmaMyDevices` 由原先的无状态 mock 列表切换为 `DevicesPage(state)`；详情 / 清空 / 删除确认页均透传 `state`，删除/清空确认页 `onConfirm` 内部走真实接口。
- `refreshDevices` 把 `getUserProductList` 行映射为 `DeviceItem`（`_deviceFromJson`，兼容 `userProductId/productName/productSerialNo/productVersionNo` 等字段）；蓝牙字段（电量/IMG_MASK/连接态）给默认值，连接后由 BLE 更新。
- `MyDevicesPage` 改为展示型组件（数据源 = `widget.devices`，编辑经回调到 `state`），不再各自维护本地副本。

### 设备模块已知差异 / 依赖

- **跨模块顺序依赖**：`refreshDevices` 成功时会用后端设备（新 id）替换本地列表；当前相册/图库/投屏记录仍引用种子设备 id（如 `dev-aurora`）。真后端返回设备后，需同步把**相册/投屏模块**也改为后端驱动，否则按种子 `deviceId` 反查设备可能不匹配。开发阶段无 token 时 `refreshDevices` 会失败并保留种子列表，故当前不受影响。
- **空列表未处理**：首页 `selectedDevice` 假定至少有一个设备；`refreshDevices` 仅在后端返回非空时替换，删到 0 台时的空状态 UI 待补。
- **轮播设置 / 连接断开**为蓝牙端能力（接口清单标 ➖），未接后端；`carousel_settings_page` 仍为本地状态。
- 设备详情未单独调用 `getUserProductDetail`（直接用列表项渲染），如需 OTA/更多字段可后续接入。

## 页面联调进度（模块C：相册图库 + 投屏记录）✅

| 页面 | 文件 | 触发动作 → `PhotoFrameState` 方法 → 接口 |
| --- | --- | --- |
| 我的相册 | `album/album_page.dart` | 打开拉取 → `refreshAlbum` → `getUserProductImgList`；删除 → `deleteAlbumPhotos` → `delUserProductImg` |
| 我的图库 | `gallery/gallery_page.dart` | 同上（共用 `_albumPhotos`）；多选删除二次确认后走 `delUserProductImg` |
| 投屏管理 | `cast/cast_management_figma_page.dart` | 打开拉取 → `refreshCastRecords` → `getUserProductImgRecordList`；删除 → `deleteCastRecord` → `delUserProductImgRecord` |

实现要点：
- 三个列表页 `initState` 后台拉取（`refreshDevices` + 对应列表刷新），失败保留本地数据；删除走真实接口成功后再同步本地。
- 新增 `AlbumPhoto.imageUrl` / `CastRecord.imageUrl`（可空），`PhotoArtwork` / 图库格子 / 投屏缩略图存在地址时用 `Image.network` 展示真实图，加载失败回退占位色块。
- `_albumPhotoFromJson` / `_castRecordFromJson` 兼容常见字段（`uProductImgId/upirId/userProductId/img/createTime` 等）；时间用 `_parseDate`（ISO 或时间戳）解析，色块按序号取 `_palette`。
- `deviceName` 改为容错查找：后端相册/记录的 `deviceId` 不在设备列表时回退展示 id，不再抛异常（消除模块B提到的跨模块反查崩溃风险）。
- 列表刷新前一并 `refreshDevices`，保证设备名能解析（设备、相册、记录三者后端数据一致）。

### 相册 / 投屏记录已知差异（待后端确认）

- **投屏成功/失败字段**：`_castStatusFromJson` 目前按 `uploadState/state/status/deviceUploadState/isSuccess` 猜测，失败取值集合 `{0,false,fail,failed,error,-1}`，其余视为成功——**字段名与取值需后端确认**。
- 列表字段映射（图片地址 `img`、标题 `imgName`、时间 `createTime` 等）按常见命名兜底，真后端联调时按实际返回调整 `_albumPhotoFromJson` / `_castRecordFromJson`。
- 相册照片的 BLE 字段（imageIndex/IMG_MASK/尺寸/字节）后端不下发，给默认 0；删除时仅对带 IMG_MASK 的种子照片同步设备掩码，后端照片直接软删除。
- 投屏（`recastRecord/recastAlbumPhoto/castDraft`）仍为本地 BLE 模拟（接口清单标 ➖），未接后端。

## 页面联调进度（模块D：操作指南 FAQ）✅

| 页面 | 文件 | 触发动作 → `PhotoFrameState` 方法 → 接口 |
| --- | --- | --- |
| 操作指南 | `guide/guide_page.dart` | 打开拉取 → `refreshFaq` → `getProductFaqList`；展开无答案时 → `loadFaqDetail` → `getProductFaqDetail` |

实现要点：
- 新增 `FaqArticle` 模型与 `_faqArticles`（内置 5 条兜底文案，原先硬编码在 guide 页，现移入 state）。
- 列表 `initState` 拉取，失败保留内置文案；展开项 `answer` 为空时懒加载详情回填。
- 展开态改为按 `faq.id` 跟踪（之前按下标，列表动态后下标会错位）。
- `_faqFromJson` 兼容 `faqId/title/content` 等常见字段。

### 后续待办

- **执行 `flutter pub get`**（`http` 已在 `pubspec.yaml`，但 `pubspec.lock` 仍标记为 transitive，需 pub get 落为 direct），再 `flutter analyze` 校验本轮改动（本机无 Flutter SDK，未能本地编译）。
- 真机/真后端联调全链路：账号、设备、相册图库、投屏记录、操作指南。**重点确认投屏记录成功/失败字段、各列表字段名、FAQ 字段名**。
- **绑定设备 UI 流程**（`bind_device_*` 蓝牙扫描页）接 `bindDevice`：需配合 `getProductList` 取 `productId` 与 BLE 扫描到的 `productSerialNo`。属蓝牙能力，需 BLE 流程配合。
- **App 版本更新**（`getLastVersion` / `getAndroidDownload`）：`update_boltstar_page` 目前为本地 mock（下载动画），且设置页入口被注释隐藏。接版本检查可加 `state.checkAppUpdate()`；安卓下载/安装需引入 `url_launcher`（或安装插件）才能真正落地，暂未接。
- **头像上传**（`setFileUpload` + `changeAvatar`）：需先引入图片选择（image_picker），`UserProfile` 再补头像 URL 字段，暂未接。
- 跟后端确认 `terminal` 取值（iOS=1/Android=2）与是否需要持久化 token（重启免登录，可在 `ApiSession.setToken/clear` 接 `shared_preferences`）。
- 空状态：设备删到 0 台、相册/记录为空的 UI 已有空态组件；首页 `selectedDevice` 仍假定至少一台设备，真后端零设备场景需补首页空态。
- `state.dart` 种子态 `_isLoggedIn = true` 为演示用，无真实 token；真机需先走登录拿 token，已登录态接口才不会 401。

## 页面联调进度（模块E：BLE 扫描 / 绑定）🟡 真机待验

BLE 协议栈（`device/ble/*` + `native_device_api`）此前已完整实现（扫描/连接/MTU/图传/六色量化），
本轮新增**跨页面持久会话**并把绑定流程接上真实蓝牙。

| 文件 | 职责 |
| --- | --- |
| `device/ble_controller.dart` | **新增** BLE 会话单例 `BleController`：持有唯一 `FrameBleClient`，让「已连接设备」跨页面存活；封装权限/扫描/连接/读信息/图传(`uploadRgba`)，调用序列严格对齐已验证的 `ble_debug_page` |
| `devices/bind_device_flow.dart` | **新增** 绑定流程编排页：权限 → `BleController.scan` → 发现/未发现 → `BleController.connect` → `state.bindDevice`(addUserProduct) → 退回列表 |
| `bind_device_found.dart` | 新增 `onBindIndex`（按下标回传选中项，编排页据此映射回真实 `ScanResult`） |
| 路由 `figmaBindDeviceSearching` | 由静态 mock 页改为 `BindDeviceFlowPage(state)`（设备页「添加设备」入口） |

> ⚠️ 本机无 Flutter SDK 且无真机，BLE 部分**无法编译/真机验证**；BLE 调用序列照搬仓库内已验证的 `ble_debug_page`，但仍需真机联调。

### BLE 绑定已知差异 / 待确认

- **后端 productId**：`addUserProduct` 需要 `productId`（后端产品类型）。BLE 设备只能给到机型/SN，缺少「BLE 设备 → 后端产品」匹配规则；当前用 `screenType` 占位，**待后端确认匹配方式**（应配合 `getProductList`）。`productSerialNo` 用设备信息里的 `deviceId`（硬件 id），`productName` 用蓝牙广播名。
- **设备模型不统一**：实时 BLE 模型是 96 槽位 + 12 字节 IMG_MASK（`FrameDeviceInfo`），演示 state 是 32 位 mask（`DeviceItem`）。本轮**未合并**两套模型——绑定后设备列表仍走后端 `refreshDevices`，BLE 会话单独存活在 `BleController` 供投屏复用；列表里的「已连接」标记暂不反映真实 BLE 连接态。
- 绑定后端失败（如 productId 不对/离线）时，蓝牙仍已连接、可投屏，流程照常退回列表并提示错误。

## 剩余未接清单

| 功能 | 接口 | 状态 / 阻塞 |
| --- | --- | --- |
| **投屏图传（cast 流程）** | `setUserProductUpload`（+ BLE 图传） | `BleController.uploadRgba` 已就绪（选图→解码→六色量化→图传），**待接 cast UI**：首页拍照/相册 → `photo_preview_adjust` → `casting_progress` → `cast_success/failed`，并把上传成功写回后端相册/投屏记录 |
| App 版本更新 | `getLastVersion` / `getAndroidDownload` | 入口被注释隐藏；APK 下载安装需 `url_launcher`/安装插件 |
| 头像上传 | `setFileUpload` + `changeAvatar` | 需 `image_picker` 选图；模型需补头像 URL 字段 |
| 基础数据 | `getBasicData` | 字典/配置，按需取用，暂无对应 UI |
