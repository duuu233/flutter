# App ↔ 小程序逐页对比与同步日志

> 基准项目：`D:\Work\learn\photo-album`（微信小程序当前工作区）。
>
> 目标：共同拥有的页面、功能、接口参数、BLE 行为、UI 样式和交互反馈以小程序为准；登录、App 安装包升级等平台专属能力保留 App 实现。
>
> 最近一次完整复核：**2026-07-14**。已包含小程序 2026-07-13 的 `b0fd785`、`413be27`、`6db0bd6` 三次更新。

## 图例

- ✅ 已按当前小程序核对并对齐
- 🔶 平台实现不同，但用户能力和结果一致，或属于 App 专属能力
- ➖ 不适用
- ⚠️ 仍需真机或后端确认

## 一、页面与功能模块

| 模块 | 小程序 | Flutter | 状态 | 当前结论 |
| --- | --- | --- | --- | --- |
| 首页 | `pages/home` | `features/home/presentation/home_*` | ✅ | 已绑定/未绑定场景、头像更新、添加设备、多设备循环轮播、断连卡片、卡片进设备列表、投屏入口均已对齐 |
| 登录 | `pages/login` | `features/account/presentation/auth_page.dart` | 🔶 | 小程序微信快捷登录；App 为邮箱密码 + 微信开放平台移动应用登录 |
| 我的 | `pages/mine` | `features/mine/presentation/mine_page.dart` | ✅ | 资料卡、真实计数、图库/设备/投屏记录入口、指南/设置入口以及当前图标资源和底托样式已对齐 |
| 绑定设备 | `subpackages/device/bind` | `features/devices/presentation/bind_device_flow.dart` | ✅ | 权限、扫描白名单、连接、硬件序列号判重、绑定与返回流程一致；连接成功和已绑定复用不再弹多余提示 |
| 设备列表 | `subpackages/device/list` | `features/devices/presentation/{devices,my_devices}_page.dart` | ✅ | 后端列表、序列号去重、选择设备、连接/断开、投屏、重命名均一致 |
| 设备详情 | `subpackages/device/detail` | `features/devices/presentation/device_details_page.dart` | ✅ | 设备信息、连接/断开、投屏、轮播、清空、删除、OTA 入口一致 |
| 设备调试 | `subpackages/device/debug` | `features/devices/presentation/ble_debug_page.dart` | 🔶 | 两端均保留硬件调试能力；App 使用 Flutter BLE 调试实现 |
| 轮播设置 | `subpackages/device/slideshow` | `features/devices/presentation/carousel_settings_page.dart` | ✅ | 设置时断线自动重连、`0x10` 播放模式/间隔、失败回滚一致；成功不弹提示 |
| OTA 升级 | `subpackages/device/ota` | `features/devices/presentation/ota_upgrade_page.dart` | ✅ | 入口连接门控、版本检查、确认弹窗及 DFU 协议一致 |
| 投屏预览 | `subpackages/projection/preview` | `features/cast/presentation/cast_preview_page.dart` | ✅🔶 | 左右预览、裁剪、旋转、还原原图、设备比例中心裁切、JPEG 92% 一致；App 用原生裁剪器，交互更适合原生平台 |
| 投屏过程/结果 | `subpackages/projection/result` | `casting_progress_page.dart` + `projection_service.dart` | ✅ | 后端转六色帧、部分成功、设备空间、记录回写、失败回滚、连接间隔优化、BLE 图传一致 |
| 投屏记录 | `subpackages/projection/records` | `cast_management_figma_page.dart` | ✅ | 成功/失败分页拉取、再次投屏、删除与页面重入刷新一致 |
| 图库 | `subpackages/album/list` | `features/gallery/presentation/gallery_page.dart` | ✅ | 单设备图库、筛选、批量删除、清空状态提示、刷屏 `0x24`、跨设备保护与删后对账一致 |
| 设置首页 | `subpackages/settings/index` | `features/settings/presentation/settings_page.dart` | ✅ | 联系方式、隐私、协议、注销、退出登录入口和失败留页逻辑一致 |
| 个人资料 | `subpackages/settings/profile` | `features/account/presentation/profile_page.dart` | ✅ | 进入刷新资料；头像先本地预览，点击“保存资料”后与昵称一起提交；成功不弹提示 |
| 绑定/修改邮箱 | `subpackages/settings/{bind-email,change-email}` | `features/account/presentation/{bind_email_incomplete_page,modify_email_page}.dart` | ✅ | 验证码与 `changeUserEmail` 参数一致 |
| 语言 | `subpackages/settings/language` | `features/settings/presentation/language_settings_page.dart` | ✅🔶 | 四项 UI、选中态、“已保存”提示和保存后留页一致；App 额外会切换已接入的 zh/en/ja 文案 |
| 操作指南 | `subpackages/settings/guide` | `features/guide/presentation/guide_page.dart` | ✅ | 本地兜底展开态、FAQ 列表/详情、搜索和多项展开一致 |
| 用户协议 | `subpackages/settings/agreement` | `features/settings/presentation/user_agreement_page.dart` | ✅ | 标题、日期、章节和正文已逐段对齐 |
| 隐私政策 | `subpackages/settings/privacy` | `features/settings/presentation/privacy_policy_page.dart` | ✅ | 标题、日期、章节和正文已逐段对齐 |
| App 版本升级 | `subpackages/settings/update` | `features/settings/presentation/update_boltstar_page.dart` | 🔶 | App 使用真实版本检查和安装包下载；平台能力不同 |
| 注册/忘记密码/改密码 | ➖ | `features/account/presentation/*` | 🔶 | App 邮箱账号体系专属 |

## 二、全局行为与接口

| 项目 | 状态 | 当前实现 |
| --- | --- | --- |
| 公共请求参数 | ✅ | `terminal/language/device/userToken` 同时进入 header/query；`retCode=200` 解析一致 |
| 密码与验证码 | ✅ | 密码 MD5 小写 32 位；验证码统一 `/Client/Basic/sendEmail` |
| 设备名称 | ✅ | 去首尾空格，不能为空，最多 6 个 Unicode 码点；弹窗标题/提示一致 |
| 设备列表接口 | ✅ | `pageSize=100`，按设备序列号去重；增删改查字段一致 |
| BLE 主协议 | ✅ | 帧头、CRC16-Modbus、CRC32-MPEG2、236 字节分包、ACK、屏型/格式一致 |
| 图传连接间隔 | ✅ | 每批投屏前无条件下发 `0x13`，再回读实际连接间隔，不再因旧值看似相同而跳过 |
| 投屏图片预处理 | ✅🔶 | 编辑产物 JPEG 92%；上传源超过 400KB 时按当前设备长边 2 倍、JPEG 80 兜底压缩；App 在 isolate 中处理避免卡 UI |
| `isCompress` | ✅ | 用户开关已移除，上传接口固定 `isCompress=1`；该参数只影响后端存储图 |
| 投屏链路 | ✅ | 原图/编辑图上传后端转 `.raw/.bin`，App 不做自研六色调色，只把后端帧传给设备 |
| 自动重连 | ✅ | 首页/列表/详情投屏、图库动作、轮播保存按小程序规则连接目标设备；一键清空仍保持小程序的“需先连接”规则 |
| 操作反馈 | ✅ | 居中 Toast；连接/断开、已绑定复用、轮播保存、资料保存、设备删除成功不再弹冗余提示；错误/警告默认显示 3 秒 |
| 页面重入刷新 | ✅ | 首页设备、资料、图库、投屏记录按进入/返回时机刷新真实数据 |

## 三、2026-07-14 同步日志

- **首页与视觉**
  - 设备卡由单张静态展示改为多设备循环 `PageView`，切换时同步全局选中设备。
  - 卡片按当前小程序 `654×298rpx`（327×149）比例、83px 圆环、玻璃阴影和 20px 轮播间距还原。
  - 断连卡隐藏电量，显示灰色断连状态和蓝色“连接蓝牙”按钮；连接成功仅刷新卡片状态。
  - 卡片点击进入设备列表并增加防重复压栈；首页头像可直接选择、即时回显并上传。
  - 问候语改用当前 `logo.png`，不再用旧版纯文字 BoltStar。
- **我的与个人资料**
  - 默认头像统一为 `mine-header.jpg`；常用功能改用 `mine-icon06/07/08.png`。
  - 常用功能图标补齐 56px 圆形底托，内部图标 34px，橙/蓝配色与小程序一致。
  - 资料页头像不再选择后立即上传；改为本地预览，点击“保存资料”后提交昵称与头像；成功不弹提示。
- **设备模块**
  - 设备名统一限制 1–6 个 Unicode 码点，详情/列表弹窗标题、占位文案和错误提示对齐。
  - 手动连接/断开、已有设备复用、删除成功均移除冗余成功 Toast；失败仍提示。
  - 轮播保存增加“保存中”遮罩，断线自动连接，成功只刷新界面。
  - 投屏轮播入口在未连接时阻止进入；进入后连接掉线则保存时自动重连。
  - 一键清空增加“清空中”遮罩；清空/删除失败保留确认页，成功才关闭，清空成功提示统一为“已清空”。
- **投屏模块**
  - 确认当前小程序仍有完整预览、裁剪、旋转、原图还原和中心裁切流程，修正文档中“无预览/选图直投”的过时结论。
  - 移除“是否压缩”状态、路由参数和开关；API 固定 `isCompress=1`。
  - 编辑导出 JPEG 92%；新增超过 400KB 后按设备长边 2 倍、质量 80 的上传前兜底压缩。
  - 保留 App 原生裁剪器 + isolate 图片处理，实现不同但结果、比例和导出质量与小程序一致。
- **设置与文案**
  - 语言保存提示改为“已保存”，保存后不自动返回。
  - 操作指南本地兜底默认展开首项和末项；后端列表默认展开第一项。
  - 用户协议、隐私政策正文按小程序当前文件逐段替换。
  - 错误/警告 Toast 默认时长调整为 3 秒。
- **质量治理**
  - 清理无效 BLE 通知字段和 OTA 代码风格告警。
  - `dart analyze lib test`：**No issues found**。
  - `flutter test --no-pub --reporter expanded`：**7 项测试全部通过**。

## 四、平台差异与剩余确认项

1. ⚠️ **真机 BLE 回归**：静态分析和单元/组件测试无法替代两种屏型真机。发布前仍应分别验证绑定、连接、单张/五张投屏、轮播、清空、删除和 OTA。
2. ✅（2026-07-16 已确认并修复）**App 忘记密码/注册接口字段**：经 swagger `/v2/api-docs` + 线上实测确认，`userRegister` / `resetPassword` / `chkUserEmailNotExist` 的字段为 `userEmail / verifyCode / password / confirmPassword`（原来发 `email/emailCode` 且缺 `confirmPassword`，后端收不到邮箱，注册/重置从未成功过）。已按 swagger 修正，详见「五」。
3. 🔶 **繁体中文资源**：页面选项与小程序一致；Flutter 状态层尚无独立 `zh-Hant` 文案包，目前复用简体中文。小程序当前也只保存视觉选中态、未实际切换全局文案。
4. 🔶 **原生裁剪器**：小程序使用 canvas 裁剪框，App 使用 `image_cropper`。宽高比、旋转、还原、中心裁切和 JPEG 输出一致，不复制小程序受沙箱限制的具体实现。
5. 低优先级：`photo_preview_adjust_image_page.dart`、`photo_preview_saved_page.dart`、旧 `cast_management_page.dart` 等仅供 `/figma/...` 演示路由或历史调试使用，不在真实用户链路中，可在后续单独做死代码收敛。

## 五、2026-07-16 同步日志

- **图库空态对齐小程序**
  - 空态改为小程序 `.album-empty` 同款：`album-bg01.png` 插图（350×342rpx→175×171）+ 标题 + 描述，顶部对齐（250rpx→125）。
  - **移除「重新投屏」按钮**（小程序 wxml 无按钮，`.empty-action` 样式已废弃）；`galCastAgain` 文案键随之删除。
- **登录页键盘交互**（App 特有页，小程序无对应）
  - 点击「登录」/微信登录先 `unfocus` 收起键盘，再做校验/弹协议提示。
  - 移除密码框键盘「完成」触发登录的绑定：未勾选协议时按「完成」不再重复弹协议提示，只收起键盘。
- **验证码发送（注册/忘记密码/修改密码/修改邮箱/绑定邮箱 共 5 页）**
  - 倒计时 30s → **60s**（⚠️ 与小程序差异：小程序为 30s，本次按产品要求改 60s）。
  - 点击发送**立即**弹蒙层 loading（`AppLoadingDialog`，「发送中…」），后端响应前无法再次点击；响应后关闭并 toast 结果（小程序无此防护，属 App 增强——后端 `sendEmail` 同步发信、响应可达数秒，此前可连发多封）。
  - 5 页补齐 `_sendingCode` 在途防重入标记（原来仅注册/忘记密码有）。
  - 卡顿排查结论：客户端无任何延时/前置耗时（keep-alive 连接、点击即发请求），数秒无响应来自后端 `sendEmail` 同步发信的耗时，非 App 代码问题。
- **接口字段修正（swagger `/v2/api-docs` 为权威，线上实测验证）**
  - `userRegister`：`email/emailCode` → `userEmail/verifyCode`，补发 `confirmPassword`（=password 的 md5）；DTO 无 `nickName`，移除该参数。原载荷后端恒报 “Please enter the correct email address”，**注册从未成功过**。
  - `resetPassword`：同上修正（`ResetPasswordApiIn`）。
  - `chkUserEmailNotExist`：`email` → `userEmail`（`SetUserEmailApiIn`）；实测该接口需登录态。
- **后端 retMsg 客户端兜底翻译（提示语语种问题的根因）**
  - 实测确认：后端**忽略** `language` 参数，`retMsg` 以英文为主（个别中文如「请重新登录！」），导致简中环境弹英文提示。
  - `ApiClient._parse` 统一走 `AppL10n.localizeServerMessage`：已知 retMsg 按当前语言（zh/zh-Hant/en/ja）重译，未知文案原样透传；映射表见 `app_l10n.dart _serverMessages`（实测收集 6 条 + 同族猜测 6 条）。
  - 后续实测遇到新的英文 retMsg，直接往 `_serverMessages` 表加条目即可。
- **登录态持久化（修「切出 App 后进程被杀，回来要重新登录」）**
  - 根因：`ApiSession` 原为纯内存 token，Android 后台进程被系统回收（国产 ROM 切出后 1 分钟内就可能杀）→ 冷启动即掉登录。小程序一直是 `wx.getStorageSync('token')` 持久化，App 才是偏差方，本次对齐。
  - `ApiSession.setToken/clear` 同步落盘 shared_preferences（串行队列防乱序）；冷启动 `restore()` 读回。
  - 启动闪屏改为「时长到 **且** 登录态恢复完成」才切页（`bolt_star_app.dart`），避免先闪登录页再跳首页。
  - 恢复出的 token 若已在服务端失效：`_refreshUserInfo` 收到 401/406 走 `_handleSessionExpired` 清态回登录页（先乐观进门，失效再请出去）。
  - 登出/注销/鉴权失效均经 `ApiSession.clear()`，持久化 token 随之清除，无残留。
- **BLE 空闲保活心跳（修「前台 1~2 分钟不操作就断连」，落实 docs/场景.png 策略）**
  - 根因：相框固件对空闲链路有设备侧断链超时（实测 1~2 分钟无流量即断），App 租约层的「前台 10 分钟」策略此前无流量支撑，形同虚设。
  - 连接存活期间每 25s 发一条最轻的读电量 0x04 喂活链路（`keepAlivePing`）；图传/OTA 期间跳过（本就有流量，且不能往停等协议插帧）；有指令在飞时跳过。
  - 心跳**不刷新**空闲租约（`request(countsAsActivity: false)`）：前台空闲满 10 分钟/后台宽限满 3 分钟照常按策略断开，心跳只负责「策略说保持时真的保持得住」。
  - ⚠️ 与小程序差异（App 特有增强）：小程序无心跳——微信主进程常驻、其连接生命周期与 App 不同；App 按「原生最优解」原则自持心跳。附带收益：投屏中途固件假死时心跳超时可更早暴露死链。
- **连接/进程存活时长按产品要求定版（2026-07-16 口头需求，覆盖 docs/场景.png 的参考值）**
  - 产品要求：① 前台蓝牙无活动 10 分钟断开；② 切出 App 后连接保持 15 分钟、只息屏不切出保持 30 分钟，到期断开（断开即允许进程被回收，重启不丢登录态所以无感）。
  - ⚠️ 与场景.png 差异：图中「后台宽限 2~5 分钟」被产品新要求取代为 15/30 分钟，图仅作场景清单参考。
  - 租约层 `BleLeasePhase{foreground/background/screenOff}`：前台空闲 10 分钟、切出 15 分钟、息屏 30 分钟（`ble_connection_lease.dart`）。「切出」vs「息屏」在进入 paused 那一刻由原生 `PowerManager.isInteractive` 判定（`isScreenInteractive` 通道方法）。
  - **Android 前台服务 `BleConnectionService`**（connectedDevice 类型）与连接同生命周期：连接建立启动（必在前台，避开 12+ 后台启服限制）、断开即停。这是「切出后进程活满 15/30 分钟」的唯一正规手段；国产 ROM 极端白名单策略仍可能提前杀，属系统行为。
  - 通知常驻文案 `bleKeepAliveNotification`（zh/en/ja），通道 IMPORTANCE_LOW 静默。Manifest 新增 FOREGROUND_SERVICE / FOREGROUND_SERVICE_CONNECTED_DEVICE / POST_NOTIFICATIONS（不运行时索要，未授权仅通知不可见、服务照跑）。
  - iOS 无对应机制：通道方法静默跳过，退后台由系统挂起，回前台走 reconcile 体检，属平台差异。

## 六、2026-07-17 同步日志（六项反馈）

- **设备详情「投屏 / 连接」操作栏样式同步小程序**（`device_details_page.dart`）
  - 原为「橙色渐变大按钮 + 白底橙描边按钮」，与小程序不符。现对齐 `detail.wxss .device-actions glass-panel`：一条玻璃面板（高 42 / 圆角 14 / 白 0.4 底 + 白 0.86 描边 + 柔和投影）内两个等宽图文按钮，中间 1×19 竖分割线（#dadddf）。
  - 配色/字号同小程序：文字 14/w500；投屏恒橙 #eb5f1b（图标 20）；连接蓝 #2079fc / 断开橙 #eb5f1b（图标 16）。文案由「连接蓝牙/断开连接」改为与小程序一致的短词「连接/断开」（devConnectShort/devDisconnectShort）。
- **「我的设备」暂无设备空态对齐小程序**（`my_devices_page.dart`）
  - 面板改为**全宽**玻璃卡（原 Align 收缩包裹，卡片只有文字宽）。
  - 空态插图复刻小程序 CSS 画法 `.frame-logo`（app.wxss）：橙色描边「相框 + U 形底座」CustomPaint 绘制，非图片资源（原来误用 device-list-icon04.png）。文案/间距/CTA 尺寸沿用（已与 list.wxss 一致）。
- **注册页 UI 重做（App 原生设计，非小程序复刻）**（`register_page.dart` 重写 + 新增 `auth_widgets.dart`）
  - 与登录页共用同一套视觉组件（从 auth_page.dart 抽出）：AuthBackground(bg01)、BoltStarWordmark(LOGO)、AuthPillTextField 胶囊输入框、AuthPrimaryButton 渐变主按钮、AuthAgreementRow 协议确认行、AuthTextStyles。改组件 = 登录注册一起变。
  - 新版结构：返回钮 → LOGO + 「创建账户」大标题 + 副标题（accRegisterSubtitle）→ 邮箱/验证码/密码/确认密码四个胶囊行 → 渐变「注 册」→「已有账户？去登录」→ 底部协议确认行。
  - **注册新增协议确认**：未勾选点注册 toast 提示（同登录页 accAgreementRequired）。
  - 校验时机与登录页统一：点「注册」时统一判定、错误就地显示在对应行下方、重新输入即清除；键盘「完成」不触发校验。验证码按钮从表单卡样式改为胶囊行尾部橙字（倒计时置灰），发送在途蒙层 loading 逻辑保留。
  - ⚠️ 与小程序差异：小程序无邮箱注册页，本页为 App 原生设计（按登录页风格），修改/忘记密码页保持原表单卡风格不共用。
- **loading 补充**（`settings_page.dart`）
  - 退出登录、用户注销确认后增加蒙层 loading（接口在途阻断重复点击）；注册按钮/各验证码按钮此前已有 loading，本轮核对无缺口。
- **照片权限前置授权（产品要求：必须先授权再进相册）**（新增 `shared/permission_gate.dart`）
  - `PermissionGate.ensurePhotoAccess`：进相册前先走系统授权框（原生通道 requestPhotoPermission，Android 13+ 系统选择器本不要求权限也照样先授权）；拒绝弹「去设置」引导框（openAppSettings）；设置中手动关闭后再次使用会重新弹系统框（每次按真实状态请求，同拍照行为）。
  - 覆盖入口：投屏相册（CastPhotoPicker.pickFromAlbum 内统一门禁，首页底部照片/投屏方式弹层/设备列表/设备详情/继续投屏全走它）、首页头像、个人信息头像。拍照走 image_picker 自带 CAMERA 授权（产品确认 OK），不改。
  - iOS/通道缺失平台不拦截（catch 后放行，交给系统选择器自身权限机制）。
- **位置（蓝牙）权限时序：先授权框、后设备操作，二者不同屏**
  - 绑定流程页（`bind_device_flow.dart`）新增 `_Stage.permission` 初始安静占位态（只有导航栏+背景）：系统授权框先单独出现，权限/蓝牙开关全就绪才切入「正在搜索」雷达动画并开扫；拒绝弹「去设置」引导（原有 guide 保留）。
  - 连接类操作（首页自动连、设备列表连接/投屏自动连、详情连接/投屏自动连）统一在弹「连接中」loading **之前**先过 `PermissionGate.ensureBleReady`（蓝牙权限 + 蓝牙开关，Android 11- 含定位）；拒绝/未开蓝牙分别弹「去设置/去打开蓝牙」引导框（permBleConnectMessage/permBtOffConnectMessage）。
