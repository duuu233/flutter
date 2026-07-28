# App ↔ 小程序逐页对比与同步日志 — 2026-07 历史台账

> 文档类型：Historical Cross-client Ledger  
> 状态：Historical  
> 归档日期：2026-07-28  
> 本文混合了当时的当前矩阵与逐日同步日志，其中部分中间状态已被后续条目覆盖。
> 当前跨端结论只维护在 `../../integration/APP_VS_MINIPROGRAM.md`。

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
| 投屏预览 | `subpackages/projection/preview` | `features/cast/presentation/cast_preview_page.dart` | ✅⚠️ | **2026-07-25 整页重写，已与小程序 07-22~07-25 的模型对齐**：常驻编辑层（单指长按 1s 拖拽 / 双指缩放+旋转 / 右上角转90°）、竖向·横向取景框、左右滑动切图（切前先烘焙进预览缓存，无缝过场）、点「开始投屏」才按框内所见烘焙。**导出铁律**：两方向恒导出竖向设备物理分辨率，横向整幅转 270° 进竖向画布。原生裁剪器（image_cropper）与预览态旋转烘焙随之下线。⚠️本机无 Flutter SDK，未编译/未真机 |
| 投屏过程/结果 | `subpackages/projection/result` | `casting_progress_page.dart` + `projection_service.dart` | ✅ | 后端转六色帧、部分成功、设备空间、记录回写、失败回滚、连接间隔优化、BLE 图传一致 |
| AI 对话（星宝） | `subpackages/ai/{chat,sessions}` | `features/ai/presentation/ai_{chat,sessions}_page.dart` | ✅⚠️ | 2026-07-25 移植，**2026-07-27 已追平小程序 07-25 二次 ~ 07-27 全部改动**：接口对齐 v1.0.4（`new_session` 废弃 / `clearHistory` 删除 / 20013 会话上限引导）、**建会话收敛到「首次发送」唯一时机**、会话列表「原路径返回」+ 删会话点对点通知、「清空全部」整功能下线（改长按逐条删）、`msg_count` 恒 0 的前端补数兜底、**AI 回复图文合并进一个气泡**、上传前压到 ~100KB、图片按 `img_orientation` 预占高宽、打字机 16ms 递归 Timer + 贴底不再用动画、首屏「先渲染→贴底→再显形」、AI 气泡去头像铺满屏宽、＋工具栏点外面收起。入口仍与小程序一样**整体屏蔽**（`kAiEntryEnabled=false`），屏蔽期走调试台底部暗门（口令同小程序）。⚠️ **语音输入仍是占位**（微信「同声传译」是小程序独有，App 需另加录音+STT 依赖）、「下载」仍只落应用缓存目录。差异与细节见文末 07-27 日志 |
| 投屏记录 | `subpackages/projection/records` | `cast_management_figma_page.dart` | ✅ | 成功/失败分页拉取、再次投屏、删除与页面重入刷新一致 |
| 图库 | `subpackages/album/list` | `features/gallery/presentation/gallery_page.dart` | ✅ | 单设备图库、筛选、批量删除、清空状态提示、刷屏 `0x24`、跨设备保护与删后对账一致 |
| 设置首页 | `subpackages/settings/index` | `features/settings/presentation/settings_page.dart` | ✅ | 联系方式、隐私、协议、注销、退出登录入口和失败留页逻辑一致 |
| 个人资料 | `subpackages/settings/profile` | `features/account/presentation/profile_page.dart` | ✅ | 进入刷新资料；头像先本地预览，点击“保存资料”后与昵称一起提交；成功不弹提示 |
| 绑定/修改邮箱 | `subpackages/settings/{bind-email,change-email}` | `features/account/presentation/{bind_email_incomplete_page,modify_email_page}.dart` | ✅ | 验证码与 `changeUserEmail` 参数一致 |
| 语言 | `subpackages/settings/language` | `features/settings/presentation/language_settings_page.dart` | ✅🔶 | 四项 UI、选中态、“已保存”提示和保存后留页一致；App 额外会切换已接入的 zh/en/ja 文案 |
| 操作指南 | `subpackages/settings/guide` | `features/guide/presentation/guide_page.dart` | ✅ | FAQ 列表/详情、多项展开一致；两端均**默认全部收起**、翻页**全量**读取、随语种重新拉取。差异：答案富文本小程序用原生 `rich-text`，App 用自研 `SimpleHtmlText`（零依赖 HTML 子集渲染）；滚动小程序用 `scroll-view`，App 用 `SingleChildScrollView`（2026-07-19） |
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
| 投屏图片预处理 | ✅🔶 | 编辑产物 JPEG 92%；**上传源先经 `coverCropToSize` 恒缩到设备分辨率（480×720 / 680×960）**，后端转码零缩放不变形；`_prepareUploadSource` 的「>400KB 按设备长边 2 倍、JPEG 80」仅为极端兜底（几乎不触发）；App 在 isolate 中处理避免卡 UI |
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
  - 编辑导出 JPEG 92%；上传源先 `coverCropToSize` 恒缩到设备分辨率（480×720 / 680×960），
    「>400KB 按设备长边 2 倍、质量 80」仅为极端兜底。
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

---

## 操作日志

- 2026-07（本轮）：投屏预览/预处理改为 `coverCropToSize` 恒缩到设备分辨率(480×720/680×960)，非仅"设备比例中心裁切"；400KB 长边2倍仅为极端兜底。
- 2026-07-18：接入设备槽位索引 imgIndex（对齐小程序同日改动）。投屏成功上报物理槽位，图库删除/刷屏改为「优先真实索引、无索引才回退推算」，根治「删错图/指定刷新的图不对」的槽位推断错位。当前规则见 `../../architecture/IMAGE_SLOT_INDEX.md`；问题 A（幽灵记录）仍待后端唯一性规则。
- 2026-07-18（三项反馈）：
  - **更新 BoltStar 去掉下载进度环**（`update_boltstar_page.dart`、`app_routes.dart`、`app_l10n.dart`）。原 `downloading` 态是一个 6 秒**假**动画（`AnimationController` 空跑，与真实下载无关），会让用户误以为 App 在自己下载。现改为三态 `checking / upToDate / updateAvailable`：进页真实检查版本，有更新才显示「立即更新」，点击直接用 `launchUrl(externalApplication)` 交给应用商店/浏览器并停留本页。同时删除 `_DownloadProgressRing`/`_RingPainter`、演示路由 `figmaUpdateBoltStarProgress` 和 `setUpdating`/`setDownloading` 文案。
  - **顺带补回 scheme 白名单**：`downloadUrl` 来自后端，旧的 `{https, market, itms-apps}` 白名单只留在 `settings_page.dart` 那条**已停用**的弹窗式旧路径里，现行页面是裸 `Uri.tryParse` + 任意 scheme 直拉。已在 `_startUpdate` 补回白名单与 `PlatformException` 兜底（无商店 ROM 上 `market://` 会抛 ActivityNotFoundException）。
  - **图库「设备已被清空」提示改用小程序 `.confirm-dialog` 样式**（`gallery_page.dart`）。原为系统 `AlertDialog`，与项目其它弹窗割裂。把同文件的 `_DeleteDialog` 泛化为 `_GalleryConfirmDialog(title/message/showCancel)`，删除确认与本提示共用同一张白卡（radius 14 + 橙色图标盒 + 19/700 标题 + 12 说明 + 胶囊按钮）；`showCancel: false` 时渲染通栏「确认」，对应小程序 `wx.showModal({showCancel:false})`。仍保持 `barrierDismissible: false`——点遮罩不算确认，不复位清空标记。
  - **投屏记录缩略图去掉多余图层**（`cast_management_figma_page.dart`）。原本无条件在图片**上方**叠一个居中 24px 白色来源图标（`Stack` 里排在 `CachedNetworkImage` 之后），底色又是按列表下标轮转的彩色渐变，`BoxFit.contain` 的留白露出渐变 → 观感就是「默认图和真实图片重叠」。现对齐小程序 `.thumb`：纯 `#D9E8F7` 底 + 单张 aspectFit 图片，来源图标降级为 `_ThumbFallbackIcon`，**只在无缩略图/加载中/加载失败时**出现。（`CastRecord.color` 与 `_paletteColor` 已无读取方，属可选清理，未动。）
- 2026-07-18（强制升级 + 登录/注册错误位）：
  - **强制升级门禁**（`state.dart`、新增 `shared/widgets/force_update_dialog.dart`、`bolt_star_app.dart`、`app_l10n.dart`）。字段已按 swagger `AppVersionConApiOutput` 核对：`compulsory` integer，1=强制 2=强提示 3=弱提示 4=不提示。`AppVersionInfo` 新增 `compulsory` 与 `isCompulsory`（**必须 `isUpdate=1` 同时成立**——后端把版本配成强制类型但当前已是最新时，不该把用户锁在弹窗里）。
  - 触发点在 `bolt_star_app.dart` 的登录态跳变处，**不是**登录页：登录成功后 `AuthPage` 立刻被根节点换成主壳层，在登录页弹窗会随页面一起卸载。`_maybeCheckForceUpdate()` 在「未登录→已登录」跳变和闪屏结束两处触发（冷启动恢复 token 时跳变发生在闪屏期间），每个登录会话只查一次，登出复位。
  - 弹窗关不掉：`barrierDismissible:false` + `PopScope(canPop:false)`，只有一个通栏「立即更新」，点了去应用商店但**弹窗不关**（用户没真升级就回来仍被挡住）。三条兜底防止误锁死用户：版本检查失败静默放行、`downloadPath` 为空不弹（否则按钮打不开商店而弹窗又关不掉＝彻底卡死）、闪屏期间不弹。scheme 白名单同 `update_boltstar_page.dart`。
  - 非强制升级（2/3/4）**不弹任何提示**，按产品要求由用户自己去「设置 → 更新BoltStar」手动更新。
  - **登录/注册页错误提示不再顶动页面**（`auth_widgets.dart` 新增 `AuthErrorSlot`，`auth_page.dart` 2 处 / `register_page.dart` 4 处替换）。原来是 `if (error) Padding(...)` + 其后 `SizedBox(height:16)`，错误一出现就把下方所有内容顶下去。现在改为「输入框之间的间距**恒定预留**一行错误高度」：`AuthErrorSlot(text: cond ? msg : null, gap: …)` 无论有无错误都占住 `top 8 + minHeight 16 + gap`。用 `minHeight` 而非固定高度——中文文案全部单行、零位移；EN/JA 个别长文案（`accPasswordRuleError`、`accPasswordMismatchReconfirm`）会换到第二行并轻微下移，宁可位移也不裁切文案。两页都在 `SingleChildScrollView + IntrinsicHeight + Spacer` 内，多出的高度由 Spacer 吸收、不够则滚动。
- 2026-07-19（十二项反馈，详见同目录 `2026-07-19-bugfix-round.md`）。与小程序的关系分三类：
  - **两端同步改**：投屏记录失败空态去掉「投屏失败时会保留原因，方便排查。」小字（App `cast_management_figma_page.dart` 条件渲染 + l10n key `castEmptyFailedDesc` 删除；小程序 `subpackages/projection/records/records.wxml` 用 `wx:if` 整块不渲染——都不要改成「文案置空」，那会留下一个带间距的空节点）。
  - **新增有意差异 —— App 先行**：
    - **设备刷屏中投屏改为「等它刷完」**。小程序 `result.js` 是把首张预取放在读设备信息之前（用设备记录里缓存的 width/height），因此设备忙时后端仍会落一条失败记录；App 没照抄这条（缓存尺寸与实读不一致就会白传一张，见 memory 里「上传与 BLE 连接并行」的风险条），改为 `_readTransferInfoAwaitingIdle` 遇忙重试最长 12s。效果更好：刷屏这几秒等过去投屏就正常继续，压根不产生失败记录。
    - **等满超时仍忙时弹系统消息框**「设备繁忙中，请稍后再试」。小程序当前**没有**在投屏结果页弹这个框（它只换失败页的说明文字，`classifyFailureMessage`），这是 App 按用户要求先行的一条。
    - **BLE 连接保活持 `PARTIAL_WAKE_LOCK`**（`BleConnectionService.kt`）。小程序跑在微信里没有这层能力，是 App 特有；它是「切出 15 分钟 / 息屏 30 分钟」租约能真正走到到期点的前提（不持锁时 Doze 下定时器停摆，租约永远不到期、进程也就一直不可回收）。
    - **注册/登录页校验提示由模态确认框改为居中黑色吐司**，与小程序 toast 组件（黑色半透明底 + 白字）观感一致；App 此前用的是「标题 + 知道了」确认框，属两端不一致，本轮对齐。
    - **「扫描不到怎么办？」改为真正的底部上拉弹层**（`showModalBottomSheet`），此前是全屏页自绘蒙层假装弹层，与小程序交互不一致，本轮对齐。
  - **无需同步 —— 结论是「小程序更弱，App 保持现状」**：头像上传压缩。App 有 ≤100KB / 长边 ≤512px 的客户端压缩；小程序头像走微信 `chooseAvatar` 拿到的现成小图，`setFileUpload` 不带任何压缩参数，即**小程序侧没有客户端压缩**。不要为了「对齐」把 App 这层去掉。
- 2026-07-20（搜索设备列表图标/设备ID 两端同步；图库张数经核对 App 无需改）：
  - **搜索设备列表图标统一成首页那张 home-icon02**（`shared/widgets/home_figma_common.dart` 的 `FigmaBindDeviceCard`）。首页/设备列表/设备详情已在 2026-07-19 统一，**搜索设备列表是漏掉的最后一处**。原实现比小程序那边更偏：不是资源图，而是 Material 的 `Icons.videocam_outlined` 字形，还按列表下标 `_deviceAccent(i)` 染成橙/绿/蓝 —— 同一列表里几台设备图标颜色各不相同，与首页毫无关系。现改为 `Image.asset('assets/images/home-icon02.png', 48×48)` + `errorBuilder`，并**删掉底色容器**（该图四角 alpha=0 自带圆角，加底色会在四角露色晕，与 `my_devices_page.dart:404-420`、`device_details_page.dart:317-332` 换图时的处理一致）。随之删除已成死参的 `iconColor` / `iconBackground` 与 `bind_device_found.dart` 的 `_deviceAccent()`。
  - **搜索设备列表新增「设备ID」行**（`bind_device_found.dart` 的 `BindDeviceEntry` 加 `deviceId` 字段、`bind_device_flow.dart` 新增 `_displayDeviceCode()`、`FigmaBindDeviceCard` 加 `deviceId` 参数渲染第三行）。默认设备名=产品广播名，同型号必然重名，绑定前这是唯一能区分两台的标识。取值规则与小程序 `bind.js` 的 `displayDeviceCode()` **完全一致**（广播 Device_ID → `normalizeSerial` 去分隔符大写 → 8 位十六进制；解析失败退回 remoteId 取末 8 位），保证两端展示同一个值。复用已有 l10n `devDeviceId`（`app_l10n.dart:879`），无需新增文案。
    - ⚠️ **`BindDeviceEntry.id` 与 `deviceId` 不是一回事**，别混：`id` 是平台给的 MAC/UUID，只作单选键、从不展示；`deviceId` 才是给用户看的那个。
    - ⚠️ **卡片高度 64 → 82 是必须的配套改动**：第三行使内容高度约 54px，而 64 减去上下各 8 的 padding 只剩 48px，不改会稳定触发 `RenderFlex overflowed` 黄条。
    - 为什么单独一行而不是拼进 subtitle：英文副标题（`"5.89in · Battery 88% · Signal Excellent"`）本就已被 ellipsis 截断，拼进去等于直接被截没，达不到目的。
  - **图库「共 N 张」：核对结论是 App 无需改动**。小程序原来把它绑成了全部设备合计且切设备不变（本轮已修）；App 的 `gallery_page.dart:361` 一直绑的是按设备过滤后的 `_photos`（`:127`），切设备经 `setState` 自动重算，且同一个列表同时驱动 `itemCount`，标签与网格不可能对不上 —— **App 本来就是小程序修完之后的形态**。
    - ⚠️ 不要拿 `UserProfile.imgCount`（`state.dart:81`）去「优化」这里：那是账号级总数，用上去正好复刻小程序刚修掉的 bug。
    - ⏳ **两端共有的遗留问题（本轮均未改）**：`refreshAlbum` 只拉一页 `pageSize:100` 且无滚动加载，这 100 条是所有设备**共享**预算，账号总照片超 100 时单设备计数会静默偏小（3 台各 60 张 → 只加载 100 条 → 某台可能显示「共 20 张」）。App 侧已有正确范式可抄：`refreshFaq`（`state.dart:2789-2842`）按信封的 `pageCount`/`recordCount` 翻页，而 `refreshAlbum` 把这两个字段丢掉了。修的话给 `refreshAlbum` 加翻页循环、保持全量拉取+客户端过滤，爆炸半径最小。
  - **本轮未验证**：本机无 Flutter SDK，`dart analyze` / 真机均未跑，仅人工核对了符号签名（`BleController.advertisingOf` 为 static、`FrameAdvertising.deviceId` 存在、`devDeviceId` l10n key 存在、`FigmaBindDeviceCard` 全项目仅一处调用、删除的参数无悬空引用）。
- 2026-07-24（seekink 抖动 token 401 自愈加 `isNewLogin` + 预览页预热；对齐小程序同日改动）：
  - **`getXTYUserToken` 新增入参 `isNewLogin`**（`BoltFoxApi.getXTYUserToken({int isNewLogin=0})` 走 query，`_uri` 对 int `0` 会保留成 `isNewLogin=0`）。语义：`0`=复用后端已有会话（默认，首取/预热）；`1`=强制重新登录取新 token。用途：抖动接口 `imageDitheringBinDownload` 回 **401**（`{"msg":"…认证失败，无法访问系统资源","code":401}`，token 过期）时，`DitheringApi.requestFrameBin` 先清会话缓存、带 `isNewLogin=1` 重取一次 token 再重发出帧请求——否则后端可能把刚过期的**同一会话**原样返回、重试仍 401 死循环。
    - 落点：`DitheringApi.ensureAuthToken({bool forceNewLogin=false})`（强制刷新时不复用可能属旧会话的在途请求，另起一发确保 `isNewLogin=1` 生效）+ `requestFrameBin` 的 `run` 循环用 `forceNewLogin` 变量，在 `authFailed && !authRetried` 分支置真后 continue；刷新只做一次（`authRetried`），不消耗网络退避重试次数。与小程序 `utils/dithering.js`/`utils/api.js` 一一对应。
  - **`CastPreviewPage.initState` 补上 `DitheringApi.prefetchAuthToken()` 预热**（对齐小程序 `preview.js` onLoad，2026-07-23 那条 dithering 同步时**漏了这一处**——预览页进入即前置取 token，点「开始投屏」出帧零等待；失败静默）。
  - **本轮未验证**：本机无 Flutter SDK，`dart analyze` / 真机均未跑。仅人工核对：`_http.getJson` 支持 `query:`（`getBasicData` 同款）、`_uri` 过滤条件 `value.toString().isNotEmpty` 对 int `0` 成立、`DitheringApi` 已在 `cast_preview_page.dart` 相对路径 `../../../network/dithering_api.dart` 可达、`prefetchAuthToken` 为 static。
- 2026-07-23（补记：昨日 dithering 管线同步，当时漏记本日志）：seekink 抖动接口整链路已落 App —— `dithering_api.dart`（手拼 multipart + 裸 httpClient 收 arraybuffer、会话级 token 缓存/在途去重/401 刷新、`typeForDevice` 判 3.7/5.8 寸）、`projection_service.dart _acquireFrame` 两路网络并行（设备帧走 `DitheringApi.requestFrameBin`、记录走 `setUserProductUpload` 传原图只建记录）、再次/重新投屏并入正常链路（旧 imgBle 直传 `recastRecord` 已删）。对齐小程序 `docs/server-image-processing-ble-transfer.md` 07-22/07-23。
  - ⏳ **仍未同步（本轮明确不做，理由见下）——投屏预览页 07-22「照片预览需求调整」大改**（小程序 `docs/2026-07-22-照片预览需求调整.md`）：
    - 需求：删「裁剪/旋转/保存」按钮只留「原图」；新增 **竖向/横向分段控制器**（el-segmented 式滑块，横向=宽高对调可视区、图不动靠拖动取景）；**常驻编辑**（默认双指缩放+旋转，无需先点进入编辑态）；**按张编辑状态**切图保存/恢复；图右上角**「转90°」FAB**；去掉左右滑动切图、改「上一张/下一张」按钮；点「开始投屏」才按框内所见烘焙。
    - **导出铁律（务必照搬，get反了会花屏且接口不报错）**：两方向恒导出**竖向设备物理分辨率**；竖向直画；横向把框内所见整幅转 **270°** 进竖向画布（90° 进竖向 + 180° 真机倒置校正）。**横向绝不能直接输出横向尺寸**（字节数相同、设备按竖向行宽解析必整幅花屏）。imgBle 直传判定/`cropW>0` 未编辑判定不能走样。
    - **为何本轮不做**：App 现状 `cast_preview_page.dart` 是 `PageView` 左右滑 + 原生 `image_cropper` 裁剪 + `RotatedBox` 预览旋转的**旧模型**，与新交互是两套架构；改造 = 用 `GestureDetector`(scale/rotate/pan via Matrix4) 手搓常驻编辑层 + 分段控制器 + 按张 transform 态 + 烘焙管线（很可能用 `RepaintBoundary.toImage(pixelRatio)` 把编辑视图渲成设备分辨率，含 270° 横向规则）+ 新增 4 条 l10n（竖向/横向/上一张/下一张），约 400~600 行新代码。**本机无 Flutter SDK 无法编译/真机验证**，而烘焙几何（尤其横向 270°）是「错了不报错、设备直接花屏」的静默失败——盲改替换一个能用的页面风险过高。建议接入编译器/真机后单独一轮做，届时对照本条铁律逐项验证。

- 2026-07-25（三项同步：投屏预览页大改 + AI 对话模块 + 调试台第三方 Token；另修一处**已存在的编译错误**）：
  - **⚠️ 先修编译错误**：`cast_management_figma_page.dart` 与 `cast_preview_page.dart` 仍在向 `CastingProgressPage`
    传 `recastImgBle / recastUpirId / recastImgUrl`，而这三个参数早在 07-23「再次投屏并入正常链路」时就随
    .bin 链路删掉了 —— 该状态下项目**无法编译**（07-23 那轮无 SDK、未跑 analyze 才漏掉）。本轮一并清理：
    投屏记录页「再次投屏」的门槛由「有 imgBle 设备帧」改为「有服务器图片地址」（对齐小程序 records.js
    doRetryProjection），下载失败直接提示中止（`castRecordImageDownloadFailed`），不再有 imgBle 直传回退分支。
  - **投屏预览页整页重写**（`cast_preview_page.dart`，对齐小程序 07-22 ~ 07-25 三轮重构）：
    - 交互：常驻编辑层用 `Listener` 独占指针，1:1 复刻小程序的手势状态机（none/idle/swipe/drag/pinch）——
      单指默认判「左右滑动切图」，按住几乎不动满 **1s** 进拖拽（震动 + 「拿起」放大回弹），双指随时缩放+旋转；
      底层 `PageView` 只做过场动画（`NeverScrollableScrollPhysics`），切图由 `_commitSwipe` 提交。
      **不用 GestureDetector 的 onScale**：那套仲裁与「同一根手指长按后转拖拽」冲突，且与小程序手感对不齐。
    - 几何：`_frameFor`（取景框）/`_clampTransform`（最小 zoom 包住旋转后的框 + 平移夹取）与小程序逐行同构。
    - **烘焙导出铁律照搬**：`ui.PictureRecorder` + `Canvas` 按与小程序 canvas **完全相同的绘制顺序**合成
      （`translate(中心) → [横向 rotate(270°)] → translate(tx*k,ty*k) → rotate(用户角) → scale(s)`），
      画布恒为竖向设备物理分辨率；JPEG 编码走 `CastImageEditor.encodeRgbaToJpeg`（dart:ui 只出 png/rawRgba）。
      **横向绝不能直接输出横向尺寸**（字节数相同、接口不报错、设备按竖向行宽解析必花屏）。
    - **展示与烘焙共用同一份 `ui.Image`**（解码一次、`RawImage` 渲染）：规避「ImageDescriptor 的尺寸未必
      带 EXIF 方向、而 Image 组件显示的是带方向的」这类静默错位。
    - 同步小程序 07-25 的 4 项修复：① 编辑层起来时底层轮播整条隐藏（`Visibility(maintain*)`），
      否则横向取景框上下会露出竖向底图；② 竖/横/原点击区放大（`_ToolButton` padding 28×10）；
      ③ 长按 2s→1s（含 `castEditHint` 文案）；④ 切图前先烘焙进预览缓存（`_previews`，有编辑才出图并弹
      「处理中」，无编辑无缝切），指纹 `_signatureOf` 与投屏出图共用，命中即复用不重复出图。
    - 顺带：`_startCast` 补传 `originalPaths`（投屏记录/图库存**原图**，对齐小程序 `setUserProductUpload` 传 `_origSrc`）；
      `CastImageEditor.rotate` 与 `image_cropper` 调用下线（pubspec 依赖暂留，等真机验证后再决定摘不摘）；
      l10n 删 `castPrevPhoto/castNextPhoto`（07-24 需求已取消上/下一张按钮），新增 `castCasting/castNoPhotos`。
  - **AI 对话模块（星宝）移植**（新增 `network/boltstar_ai_api.dart`、`features/ai/{ai_i18n,ai_entry}.dart`、
    `features/ai/presentation/ai_{chat,sessions}_page.dart`）：
    - 接口层独立于 `ApiClient`（第三方 FC，响应结构/错误码体系完全不同），失败统一抛 `AiApiException`；
      `AiCall.abort()` 用 `http.Client.close()`（IOClient 是 force close）实现「停止生成」。
    - 与小程序同样**走非流式 URL + 客户端打字机 30ms/字**：App 本可以走 SSE，但先与小程序保持同一条链路，
      少一处联调面；流式地址留在 `streamBaseUrl` 备用。
    - 已覆盖：会话新建/切换/历史（10001 过期提示）、图文多模态（相册多选≤4 张→立即上传→缩略图停在输入框内、
      纯图片不可发）、一键生图 + 比例、长按下载/投屏/删除、封禁 22002/22003、Token 余额本地模拟、无绑定设备拦截。
    - **投屏复用现有链路**：AI 图下载成本地文件 → （必要时选设备并连接）→ 进 `CastPreviewPage`，与手选照片同链路。
    - **入口按小程序现状屏蔽**：`kAiEntryEnabled = false`；开放时改这一处，并在 `home_page`/`mine_page`
      各自的自绘 tab 栏中间调 `openAiChat`（两处都要）。屏蔽期入口 = 调试台底部暗门（口令与小程序一致）。
    - ⚠️ **两处有意差异**（无对应端能力，未擅自加依赖）：① 语音输入——小程序录音后提示「转文字插件待接入」，
      App 无录音/转写依赖，只给同语义占位提示；② 「下载」——Flutter 无内置相册写入能力（需 gal 之类插件），
      本轮只落到应用缓存目录，文案如实说明。要补齐这两项需先确认可加依赖。
    - ⚠️ 小程序 `checkDeviceBound` 的「去绑定」直接跳绑定页；App 的绑定流程是首页内嵌浮层、没有独立路由，
      故只能退回上一页由用户在首页「添加设备」绑定。
  - **调试台第三方 Token 卡片**（`ble_debug_page.dart`，对齐小程序 07-24 debug 改动）：
    「获取 Token」(`isNewLogin=0`) / 「强制重新登录取 Token」(`isNewLogin=1`) 两颗按钮 + 常驻展示 + 复制，
    失败原因也常驻；归一化逻辑与 `DitheringApi._normalizeToken` 一致（那份私有，这里复制一份，同小程序做法）。
    纯网络请求、不依赖蓝牙连接。同页底部加 AI 入口暗门（输对口令才显露按钮）。
    ⚠️ 调试台整页仅 `kDebugMode` 可达（`app_routes`），所以 release 包里 AI 页暂时**没有任何入口**——
    这与小程序略有差异（小程序调试台在正式包里仍可达），入口正式开放后即消失。
  - **本轮未验证**：本机无 Flutter SDK，`dart analyze` / `flutter test` / 真机**均未跑**。仅人工核对了符号与签名
    （l10n 键、`BoltFoxApi.getXTYUserToken({isNewLogin})`、`CastPhotoPicker.pickFromAlbum(limit:)`、
    `state.currentUser/devices/refreshDevices/connectDevice/deviceById`、`FigmaScreen/FigmaPrimaryButton/PageLoading`
    参数、`showAppConfirmDialog` 具名参数）。**接入编译器后请优先跑一次 `dart analyze lib`**，
    再按上面的铁律逐项真机验证横向投屏是否花屏。
- **2026-07-27（AI 模块追平小程序 07-25 二次 ~ 07-27 全部改动）**。小程序侧首版移植（07-25）之后又改了七轮，
  本轮把 AI 模块**整体追平**。落点：`network/boltstar_ai_api.dart`、`features/ai/ai_i18n.dart`、
  新增 `features/ai/ai_image_compress.dart`、`features/ai/presentation/ai_{chat,sessions}_page.dart`、
  `shared/l10n/app_l10n.dart`。⚠️ 本机无 Flutter SDK，`dart analyze` / 真机**均未跑**。

  ### 接口层（对齐 API 文档 v1.0.3 → v1.0.4）
  - `chat()` 删掉 `new_session` 参数（v1.0.4 废弃，会话是不是新的由后端自判）。本项目从没有调用方传过它，
    属清理死代码，运行行为不变。
  - 删掉 `clearHistory()`（`DELETE /chat/history/clear`）——**本模块不再提供任何清空能力**，原处留注释挡回加。
  - `newSession()` 补 20013 `MAX_SESSIONS_REACHED`（每用户上限 20 个会话）说明。
  - 「你好，我是星宝✨」接口不再返回，明确为前端静态展示：App 本来就是静态招呼语，无需改，只记注释
    免得以后有人去剥前缀。

  ### 错误分发
  - `ai_i18n` 补 `error.20013` 四语种；`handleError` 新增 `onSessionLimit` 分支——重试对它没意义，
    传了回调就弹「去清理」确认框把人送到会话列表页删旧的（没传退回 toast，与 30xxx 的 onRetry 同套路）。

  ### 会话创建时机收敛（小程序 07-25 三 + 五，两次拍板）
  - **建会话只剩「首次发送」一个时机**：`initState` 不再 `_createSession()`（那是「点进 AI 页就凭空多一条
    空会话」的根因）、`_resetToNewSession()` 也不建。点「新对话」只把界面退回空态；**已经在空态再点就
    toast「已经在新对话中」**（判据 `isPristineNewSession` = 无 sessionId 且无消息，**不看输入草稿**，
    只提示不清草稿）。
  - `_onSendTap` 改「**先建会话、再清输入框**」：顺序反了的话建会话一失败（网络 / 20013），
    用户打的字和选的图就白没了。
  - `_createSession` 加在途去重 `_createReq`：await 期间 `_sending` 仍 false、输入框也没清，
    连点发送会看到两次 `_sessionId` 为空 → 建出两条会话（后一条还是空的）。
  - 标题本地同步按 `_kSessionTitleMax = 20` 截断（v1.0.4 §二后端只取前 20 字），
    否则列表页重拉后标题会突然变短、两处对不上。

  ### 会话列表「原路径返回」（小程序 07-25 六·二）
  - 点会话 / 点「新建对话」都改成**列表页自己 push 一页新聊天页**，列表留在栈里 → 新聊天页的返回键
    天然原路退回列表。原实现是 `pop(AiSessionPick)` 让下层聊天页就地换会话，返回键会直接退出 AI，
    点「新建对话」还会把下层那段对话抹掉。`AiSessionPick` 整个类删除。
    下层已是同一条会话 / 已是干净空态时不叠页，直接 pop。
  - **删会话改点对点通知**：`AiChatPage.notifySessionDeleted(sessionId)` 遍历「活着的聊天页」注册表
    （`_livePages`，initState 注册 / dispose 注销），只让**正打开这条会话**的那一页退回空态。
    等价于小程序用 `getCurrentPages()` 找页面实例的做法；广播式标记会被新 push 的聊天页吃掉，
    导致刚打开的会话瞬间被清成空白页。
  - 列表页因此**常驻页面栈**，补了从聊天页退回时的静默刷新（不显整页 loading、失败不打扰、
    保持已翻到的行数），并只把「刚聊过那条」从 `_counted` 里剔除重新补条数。
  - 🔶 小程序还有一套「页面栈 ≥9 层就降级成就地换会话」的兜底（微信硬上限 10 层）；Flutter 没有这个
    限制，直接 push，故 `applySessionFromList` 那条降级路径**不移植**。

  ### 「清空全部」整功能下线（小程序 07-25 六）
  - 删 `_clearAll()`、标题栏右上角「清空」入口、`aiClearAll/aiClear/aiClearing/aiCleared/
    aiClearAllTitle/aiClearAllMessage` 六条文案。理由（记下来别再加回去）：接口**没有批量删除能力**，
    只能 for 循环串行 `DELETE /session`（最坏 20 个请求），中途任一条失败就留下「删了一半且无法回滚」的状态。
  - 改为长按逐条删，列表底部补 `aiLongPressToDelete` 提示。

  ### 「N 条消息」恒为 0 的前端兜底（小程序 07-25 四）
  - 结论是**后端 `msg_count` 本身回 0**（前端取值无误：同一对象的 title/updated_at 都正常）。
    新增 `_fillMsgCounts()`：对 0 的行逐条取 `/chat/history?page=1&page_size=1` 的 `total` 补数。
    代价是 N+1 请求，故严格设限：只补**已渲染出来的行**、并发 4、失败静默、每条只试一次（`_counted`）、
    结果攒齐后只 setState 一次。
  - 列表展示同步改成：条数未知时**只显示时间**，不摆一个明知是错的「0 条消息」。
  - ⚠️ 后端修好 `msg_count` 后，把 `_fillMsgCounts/_counted/_kHistoryFillConcurrency` 及两处调用整块删掉即可。

  ### 2026-07-27 六组体验修复
  1. **上传前压到 ~100KB**：新增 `AiImageCompress.toTarget()`（`compute` 里跑，理由同 `CastImageEditor`：
     解码+重编码几百毫秒，放 UI isolate 会掉帧）。策略**先缩分辨率（长边≤1600）再逐档降质**
     （80/62/48/36/26，第 3 档起每轮再砍一半分辨率）——降质会糊掉文字细节、AI 反而看不清，缩分辨率对
     「看懂内容」几乎无损。解码失败/压完更大/抛异常一律回原图，绝不因压缩失败发不出图。
     - ⚠️ **别和 `CastImageEditor.coverCropToSize` 混用**，两者目标相反：那套是「缩到设备物理分辨率
       **保画质**」（六色帧靠它出细节）、不看体积；这套是「压到目标字节数」省流量。两边注释都写了这条。
     - 顺带把压缩时**白拿的像素尺寸**带回来（`AiCompressedImage.width/height`）给用户图片气泡预占高宽——
       App 的 `CastPhotoPicker` 只回路径、拿不到相册宽高（小程序能拿到），这是等效替代。
  2. **图片按 `img_orientation` 预占高宽**：`AspectRatio(100 / pad)` 先把高度占住（pad = 高/宽×100），
     图加载完再用**真实尺寸**校正（`_AiBubbleImage` 自己 resolve 一遍同一个 `CachedNetworkImageProvider`，
     命中同一份缓存不多下一次；只在被真的构建出来时才 resolve，所以屏幕外的几十张历史图不会被一次性拉下来）。
     - 🔴 **待后端确认的比例分歧**：用户口述 `{square 1:1, landscape 16:9, portrait 9:16}`，但 API 文档 v1.0.4
       写的是 `1104×1472(3:4) / 1472×1104(4:3) / 1328×1328(1:1)`，横竖比例对不上。**按文档取值**
       （同文档 20007 明确「仅 horizontal/square/vertical」，传 landscape/portrait 必报错）。
       真改成 16:9/9:16 只需动 `_kOrientationPad` 三个数（横 56.25 / 竖 177.78）。
     - 另加 `_kOrientationAlias` + `_normalizedOrientation`：不管界面用哪套叫法，发给接口的永远是它认的三个值。
  3. **打字机更顺滑**：`Timer.periodic(30ms)`×3 字 → **递归 `Timer`(16ms)** 每帧 1 字起
     （periodic 遇 setState 变慢会**堆帧**、追上来一次吐一大段＝「卡一下蹦一截」）；
     每帧字数 = `ceil(总字数/420)`，长回复自动加快、整段最长 ~6.7s。
     顺手修真 bug：切字从 `split('')` 改 `runes` —— `split('')` 按 UTF-16 码元切，会把 emoji 的**代理对
     劈成两半**，打到一半渲染乱码方块（星宝回复里 ✨ 相当常见）。
  4. **滚动跟不上**：`_scrollToBottom` 每次 `animateTo(180ms)` 在 60fps 出字下必然越追越远。改 `_stickToBottom`：
     打字期间 `jumpTo` + 80ms 节流、**关动画**，发消息/打完才 `animateTo`；并加「用户上翻（距底 > 60px）
     就别拽回来」（Flutter 直接有 `maxScrollExtent`，不必像小程序那样先量聊天区高度）。
     🔶 小程序的「底部内容被『停止生成』浮标遮住」不适用：那颗是 `position: fixed` 悬浮件，App 这颗在
     Column 里占正常一行，不存在遮挡，故**不移植**底部留白。
  5. **AI 回复图文合并进一个气泡**：`_MsgKind.rich` + `_AiMessage.images`，图不再各自成一条消息；
     占位气泡（三点 loading）就是最终那个气泡。**历史消息同样合并**（连着的 assistant 图片行并回前一条，
     一轮 = 1 user + 1 assistant 文字 + N 图，故前提成立），重进会话与刚回复时长得一样。
     ⚠️ 一条消息因此可能对应**多个 message_id**，`_deleteMessage` 逐个删，漏一个重进只剩半条。
     长按分两层：气泡本体 = 删整条 / 气泡里某张图 = 下载·投屏·只删这张。
  6. **首屏「先渲染 → 贴底 → 再显形」**：`_chatReady` 为 false 时列表 `Opacity(0)` **但已渲染**
     （`wx:if`/`if` 换掉就没有布局、滚都滚不动），两层 `addPostFrameCallback` 串「有布局 → jumpTo → 显形」，
     用户就看不到「从最老一条一路飞到最新」那一下；loading 改成盖在列表上（`Stack`）而不是替换列表。
  7. **气泡样式**：AI 侧**去头像** + 气泡 `width: double.infinity` 铺满、气泡里的图跟着铺满气泡宽度；
     用户侧一行未动（右对齐、按内容宽、图片 maxWidth 220）。
  8. **＋ 工具栏点外面收起**（小程序 07-27 追加）：`_closeTools()` 挂三处——消息区 tap、顶部工具行 tap、
     输入框 onTap（键盘和工具栏不该同时占着底部）。**故意不做全屏遮罩**：遮罩会把拖动一起吃掉、
     工具栏开着时聊天记录就滑不动；挂容器 onTap 只吃点击，拖动仍归 ListView。气泡里的图有自己的 onTap
     （要看大图），点图不收工具栏，与小程序一致。

  ### 仍然有意不同（无对应端能力，未擅自加依赖）
  - **语音输入**：小程序已接微信「同声传译」插件（按住说话、上滑取消、松手直发、动效盖住整个输入区、
    录音期间不显示识别文字）。**这套插件是小程序独有**，App 要做得引入录音插件 + 第三方 STT 服务，
    本轮不擅自加依赖，按住仍只给同语义占位提示（`aiVoicePending`）。要补齐请先确认可以加依赖。
  - **保存到系统相册**：Flutter 无内置相册写入能力（需 gal / image_gallery_saver），「下载」仍只落应用缓存目录。
  - **小程序侧的滚动条隐藏**（`::-webkit-scrollbar`）是 WebView 专属问题，App 无需同步。

## 2026-07-27 同尺寸多设备身份校验与电量缓存复核

- **确认 Flutter 存在“点击 A 可能连接 B”的同类问题并已修复**：
  `matchScannedDevice` 原来仅用广播 4 字节短 ID + 屏幕尺寸选第一个候选，连接后没有用 `0x01`
  的 6 字节完整 ID 验证用户点击的后端记录；活动会话复用也可能被共享短 ID 误命中。
- 现改为“广播仅筛候选 → 建连读取完整 ID → 严格确认 → 不一致断开并排除候选后继续扫描”。
  后端已有完整 ID 时绝不降级为短 ID；名称仍不作为物理身份依据。
- 落点：`lib/src/device/serial_match.dart`、`lib/src/device/ble_controller.dart`、
  `test/serial_match_test.dart`。
- **电量策略同步复核**：小程序改回 15 秒缓存优先、旧值持续展示；Flutter 原本就由
  `DeviceItem.batteryLevel` + `_carryOverBleFields` 保留旧值，页面刷新 `0x01` 前不清空，
  读取成功后原位更新、失败保持旧值，因此没有 `-- → 真值` 闪烁，无需改成先清空。
- 详细根因、规则和真机验收见
  同目录 `2026-07-27-同尺寸设备身份校验与电量缓存.md`。

## 2026-07-28 完整设备身份与 0x04 电量策略最终同步

- 修正 07-27 复核中的两项过渡结论：
  - 后端短 ID 不再兼容。后端记录、绑定判重/入库、活动会话认领和连接后验身均要求
    有效完整 6 字节 ID；广播短 ID 仅筛选扫描候选。
  - 电量不再依赖 `0x01`。Flutter 新增以完整设备 ID 为键的 15 秒缓存，过期后台读
    `0x04`，并发读取合并；`0%` 合法，失败保留旧值，从未读到显示 `--`。
- 绑定流程删除广播短 ID / BLE `remoteId` 入库兜底；历史不完整记录提示删除后重绑。
- 再次投屏、AI 会话/图文消息、Seekink 强制刷新和预览 1 秒长按均已在 Flutter 现有
  代码中存在，本轮只修正相关陈旧文档/注释，没有重复实现。
- 小程序 `docs/protocols/ota-dfu.md` 与当前两端 OTA 源码存在协议冲突，因此没有把该
  文档内容同步到 Flutter。详情见
  `2026-07-28-小程序近期修复同步.md`。
