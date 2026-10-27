# BoltStar App ↔ 微信小程序当前对齐矩阵

> 文档类型：Cross-client Integration  
> 状态：Active  
> 最后核验：2026-07-31  
> 对照仓库：`D:\Work\learn\photo-album`  
> 覆盖说明：矩阵吸收了截至 2026-07-31 的增量同步；上一次从头逐页完整复核为
> 2026-07-14，后续仍应安排下一次完整复核。

## 1. 对齐原则

- 两端共有的页面、接口参数、BLE 语义、用户结果和主要视觉行为以小程序产品规则为基准。
- App 使用 Flutter/Android/iOS 的合适实现，不复制小程序沙箱限制。
- 邮箱账号、移动应用微信授权、App 版本升级等平台专属能力保留 App 方案。
- `✅` 表示当前实现已对齐；`🔶` 表示平台实现不同但产品结果一致；`⚠️` 表示仍需真机、
  后端或下一轮完整审查确认。

## 2. 页面与能力

| 模块 | 小程序 | Flutter | 状态 | 当前结论 |
| --- | --- | --- | --- | --- |
| 首页 | `pages/home` | `features/home` | ✅ | 已绑定/未绑定、多设备轮播、头像、投屏与绑定入口一致 |
| 登录 | `pages/login` | `features/account` | 🔶 | 小程序微信快捷登录；App 支持邮箱和移动应用微信登录。**2026-07-31：注册页四个输入行的图标—文字间距 14 → 8（`AuthPillTextField.iconGap`），登录页保持 14** |
| 我的 | `pages/mine` | `features/mine` | ✅ | 资料、计数、设备、指南和设置入口一致。**2026-08-04：常用功能由三卡改两卡——「设备照片」「投屏管理」合并为「我的相册」，卡片改等分宽度**。**2026-07-31：昵称展示前解一次 `\uXXXX` / `\u{XXXXX}` / `&#123;` / `&#x1F31F;` 转义（`shared/display_text.dart`），历史数据里的 emoji 才能显示成表情而不是一串转义码**。**2026-08-19 补三处对齐（上游 08-11/08-12）**：去掉「常用功能」标题（间距挪给宫格）、「星币管理」行右侧显示「剩余 N 星币」（取 `getUserInfo.availableToken`，缺失才回退 `getUserAccount`）、删掉「官方图库」行（已进底栏）。服务与帮助现为**星币管理 → 操作指南 → 设置**三行，与小程序逐行一致 |
| 绑定设备 | `subpackages/device/bind` | `features/devices/.../bind_device_flow.dart` | ✅⚠️ | **2026-07-31 起绑定成功不再弹「绑定成功」提示，改为在当前页弹带默认名的设备命名弹窗（弱性强制，可点「稍后」跳过；该按钮 2026-08-02 由「暂不修改」改名），保存后再按原逻辑返回**；同时把这台记入「最近绑定」供设备列表排序用。只允许 0x01 完整 6 字节 ID 判重/入库；广播短 ID 与 BLE 句柄不兜底。**2026-07-29 起「搜到一个显示一个」**：扫描窗口 12s→20s；安卓 low-latency + legacy 1M + 持续重复回调，名称首包丢失时可由后续包/厂商数据补入；新扫描接管旧会话，返回/侧滑 dispose 停扫，旧响应不覆盖新状态；搜索动效在结果出现前后保持 280×280。静态检查无新增诊断，⚠️仍需 Android/iOS 真机弱信号回归 |
| 设备列表 | `subpackages/device/list` | `devices_page.dart` / `my_devices_page.dart` | ✅⚠️ | 列表、选择、连接/断开、投屏和重命名一致。**2026-07-31 起排序为「已连接 → 最近绑定 → 接口原序」**，切换连接设备时新连上那台有 520ms 上移入场动效；重命名改用统一样式的设备名称弹窗（20 个 Unicode 字符、实时计数）。⚠️未编译/未真机 |
| 设备详情 | `subpackages/device/detail` | `device_details_page.dart` | ✅⚠️ | 连接、投屏、轮播、清空、删除和 OTA 入口一致。**2026-07-31 起：「分辨率」→「屏幕尺寸」（换绘制型图标）、「设备内存」→「最大照片数量」、一键清空提示改为「将清空彩色墨水屏设备内所有照片，同时清空小程序/APP的图库…」，原「删除设备」拆成「解除绑定」（保留设备照片，一次确认）与底部新增的「删除设备」（一键清空 + 断开 + 解除绑定，需已连接，两道二次确认）**；**2026-07-29 起「设备ID」下方新增分辨率行**（如 `680*960`，连上取 0x01 真机宽高 → 后端记录宽高 → `--`）。分辨率是产品静态属性，**不随连接状态置 `--`**；两端都不由 `screenType` 反查（会臆造尺寸）。⚠️本机无 Flutter SDK，未编译/未真机 |
| BLE 调试 | `subpackages/device/debug` | `ble_debug_page.dart` | 🔶 | 两端均保留工程调试能力，release 用户入口受控 |
| 轮播 | `subpackages/device/slideshow` | `carousel_settings_page.dart` | ✅ | 断线重连、0x10 模式/间隔与失败回滚一致。**2026-07-31 修「已连接却提示请先连接设备」**：`refreshDevices` 里判连接态的那步移到身份补齐之后，入口门禁改走 `resolveDeviceConnected`（先查身份登记表补完整 6 字节 ID 再判），等价小程序 `inheritStableIdentity` |
| OTA | `subpackages/device/ota` | `ota_upgrade_page.dart` | ✅⚠️ | 两端当前源码流程一致；小程序新协议文档与两端源码冲突，修正文档前不可据其改协议 |
| 投屏预览 | `subpackages/projection/preview` | `cast_preview_page.dart` | ✅⚠️ | 2026-07-25 起使用常驻编辑层；横竖取景、多图切换、旋转和 Canvas 烘焙规则一致。**2026-07-31：长按 1s → 0.5s；缩放去掉「必须 cover 取景框」与「平移不越出图片」两道夹取，只留 0.02~8，可任意缩小自由构图；取景框与轮播底色改白，与导出白底一一对应（所见即所得）；切图过场 300ms → 360ms Banner 式**。导出铁律未动。**2026-10-22：同步小程序圆屏预览——`shapeType == 1` 时预览图与取景框裁圆、竖向/横向置灰不可点，取景与出帧尺寸改用设备列表宽高**。⚠️仍需真机回归 |
| 投屏过程 | `subpackages/projection/result` | `projection_service.dart` / `casting_progress_page.dart` | ✅ | 服务端六色帧、部分成功、空间检查、记录回写与 BLE 图传一致 |
| 投屏记录 | `subpackages/projection/records` | `cast_management_figma_page.dart` | ✅⚠️ | 成功/失败分页、再次投屏、删除与重入刷新一致。**2026-07-31 起按设备分类**：下拉与「我的相册」共用 `shared/widgets/device_filter_chip.dart`，选项按设备ID去重、重名补序列号尾 4 位、**正在连接的设备排最前并默认选中**；拉取带 `userProductId`，本地再筛一层兜底。**2026-08-04：两端都把「我的」里的入口去掉了**（成功照片进「我的相册」），本页保留用于查看失败记录/重新投屏；再次投屏的图片下载改用共用的 `RecastDownload`。**2026-08-12：两端把投屏结果页那一行「投屏明细」也改成进「我的相册」了 → 本页自此没有任何入口**（页面没下线，等产品定新入口挂哪）。⚠️未编译/未真机 |
| 我的相册 | `subpackages/album/list` | `gallery_page.dart` | ✅⚠️ | **2026-08-04：「设备照片」+「投屏管理」合并为「我的相册」**——列表数据源改为**投屏成功记录**（`deviceUploadState:1`，按 `userProductId` 分类），相册列表退居槽位账本 + 原图来源；底部第一枚圆钮由「刷新屏幕(0x24)」改为「再次投屏」（单选投一张、多选/全选走批量传输，上限 `CastUploadLimit.batchLimit`）；删除改为「设备 0x12 + 删相册记录 + 删来源投屏记录」三步。**2026-08-17：两端把「我的图库」接口整体删掉**——数据源只剩设备列表与投屏成功记录，删除只认**记录自己的 `imgIndex`**（缺索引整批终止，绝不推算），端上删除 = 设备槽位 `0x12` + 删投屏记录，图库照片的清理归后端；再次投屏直接用 `record.img`；默认设备规则四档→三档（保留当前选中 → 连接中的设备 → 第一台）。随之下线的还有 `AlbumPhoto` 账本、`refreshAlbum`、`CastRecord.photoId` 与手动刷屏入口。⚠️ 明确保留一键清空提醒（`getUserProductClearImg`，UserProduct 侧设备状态）。设备筛选、清空提示、跨设备保护、同名设备消歧、下拉每次展开重拉设备接口均保持不变。⚠️未编译/未真机；见 `history/2026-08/2026-08-04-我的相册合并与折叠屏核对.md` |
| AI 星宝 | `subpackages/ai` | `features/ai` | ✅⚠️ | **2026-07-31 已比对小程序当日三个样式提交并补齐差异**：方向按钮尾图标 17→11、「重新生成」的 ↻ 加固定 18×18 居中盒；返回键/历史入口几何补偿、Token 胶囊填充与投影、会话左滑删除（删除键与卡片同轨、被 overflow 裁掉）此前已一致；`.bubble--image .img-box` 那条不适用（Flutter 图本就填满父约束）。会话、图文消息及按用户 ID 隔离的 AI 服务协议确认已对齐；入口两端均已开放（小程序 `aiEntryEnabled: true`；App 2026-08-19 起 `kAiEntryEnabled = true`，首页/我的底栏中间加「AI助手」一格）。**2026-08-28 语音输入与保存相册两条产品规则补齐**：按住说话改走系统语音识别（`speech_to_text`，端上转文字、接口不参与，交互同小程序：上滑取消 / 松手直发 / 录音期不显示识别文字；🔶 App 多支持日语，安卓无 GMS 机型如实提示不支持）；AI 生成图的「下载」改走原生相册写入（Android MediaStore / iOS Photos addOnly），不再只落应用缓存目录。**2026-07-29 起发送入口加同步闸**（`_guardedSend`/`_submitting`）：治「首次在空态发第一条时按钮不及时变灰、连点重复发送」（`_sending` 要等请求真正发出才置起，前面还隔着协议确认+建会话）；加载中气泡（三个跳点）不再铺满屏宽。**2026-08-12 同步小程序同日一轮**：`/chat` 加 `usertoken`（登录接口下发的 `userToken`，**不是** jwtToken，参数名全小写）；图片上限 4→5 张、提示改「当前AI只允许上传5张图」；「Token」文案一律改「星币」；**星币余额由本地假值（恒 100、本地扣 1）换成真实账户 `availableToken`，拦截改由服务端裁决**（`GET /Client/Order/chkAiDialogue`，⚠️「不够」是 `retCode 403`+`retMsg` 而不是 `retData false`），且校验**提前到建会话之前**（否则余额见底的用户每点一次发送就占一条空会话，上限 20 条）；等待气泡由静态图改成「胶囊 + 三点动画」。**2026-09-18 星币不足弹窗两端同步**：弹窗里先显示一条「当前余额 N 星币」，「知道了」右边补一颗「去充值」，**直达套餐确认**（两端都是两跳：先进星币管理页、拉完套餐由它把确认页推上来——确认页要一个具体套餐，而列表在管理页拉；返回栈里留着管理页，用户想换一档退一步就能换）。小程序那颗原名「去购买」，同轮改名对齐。⚠️ 同轮把 App 默认选中的档位由**第一档改成第二档**（设计稿高亮的主推档），与小程序 `packages[1] || packages[0]` 对齐——原来 App 的注释写着「与小程序一致」但其实差一张，直达确认页之后这个差异会变成「两端确认不同的套餐」。**2026-10-10：按用户要求恢复 iOS 星币入口供截图**，「我的」星币管理、AI 余额胶囊及「去充值」均可进入已有套餐页面；只解除 `StarPayType.moduleHiddenOnThisApp` 隐藏，2026-10-12 已接入 Apple 内购，商品查询和权限通过后可购买；当前验收边界见 [iOS 内购](IOS_IN_APP_PURCHASE.md)。另：余额读不到时两端都**保持上一次的数字**，不再抹成 `--`。⚠️本机无 Flutter SDK，未编译/未真机 |
| 设置 | `subpackages/settings/index` | `settings_page.dart` | ✅ | 联系、用户/隐私/AI 服务协议、退出、注销和失败留页一致；App 协议正文为四语种。**2026-07-31：注销账号第一次确认按钮由「确定」改「继续」（非终局操作）、检查更新图标改 `set-icon05.png`** |
| 个人资料 | `subpackages/settings/profile` | `profile_page.dart` | ✅ | 进入刷新、头像本地预览与保存时提交一致 |
| 邮箱 | `bind-email/change-email` | `bind_email_*` / `modify_email_page.dart` | ✅ | 验证码和 `changeUserEmail` 参数一致 |
| 语言 | `subpackages/settings/language` | `language_settings_page.dart` | ✅🔶 | 四项 UI 一致；App 同时切换本地内置文案。**2026-08-28：App 首启跟随手机系统默认语言**（`SystemLanguage`，见 `history/2026-08/2026-08-28-App跟随系统语言.md`）——用户在本页存过的语种优先级最高，没存过才看系统语言，且跟随系统时不写盘。🔶 **兜底有意不同**：系统语言不在四语种内时 App 落 **英文**，小程序 `utils/language.js` 落 `zh-Hans`（归一规则本身两端一致：繁体认 Hant/TW/HK/MO）|
| 操作指南 | `subpackages/settings/guide` | `guide_page.dart` | ✅ | 全量分页、默认收起、语种刷新一致；HTML 渲染技术不同 |
| 协议/隐私 | settings agreement/privacy | 对应 settings 页面 | ✅ | 标题、日期、章节和正文一致 |
| App 更新 | 小程序更新页 | `update_boltstar_page.dart` | 🔶 | App 走原生版本检查和安装包下载 |
| 官方图库 / 我的收藏 | `subpackages/gallery` | `features/gallery/official` | ✅⚠️ | **2026-08-12 App 侧补齐**：列表（分类条 + 端上补的「全部」+ 右端固定「收藏」入口 + 两列瀑布流 + 上拉续页）、详情（沉浸式大图 + 收藏 + 开始投屏，走与「再次投屏」同一条链路）、我的收藏。接口 `/Client/Product/{getImgCategory,getProductImgList,getProductImgDetail,setImgCollected,getProductImgCollectionList}`，字段口径与小程序逐条对齐。⚠️ 两处后端缺口两端同款兜底：列表项**没有图片比例**（先按 3:4 占位、加载完校正那一张，**不重新分列**）、**没有收藏态**（另拉一页收藏列表在端上标记）。**2026-08-19 入口对齐**：底栏由两格扩到四格，官方图库进第三格（与小程序同位），「我的 → 服务与帮助」里那一行同步删掉。⚠️未编译/未真机 |
| 星币（支付体系） | `subpackages/token` | `features/star` | 🔶 | 管理、套餐、余额与购买/消费记录已有。小程序=微信虚拟支付(1)、安卓=PayPal(3)、iOS=Apple 内购(2)。iOS 2026-10-12 接入商品查询、原生购买、传统 Base64 收据及交易恢复；匹配交易、订单已支付和余额到账后才结束交易。验收据提交订单号/苹果交易号，后端负责发币；新返回结构/幂等及 iOS 沙盒仍待验收，见 [iOS 内购契约](IOS_IN_APP_PURCHASE.md)。安卓 PayPal 流程保留，联调说明见 `../runbooks/PAYPAL_REDIRECT.md`。 |
| App 邮箱注册/改密 | 不适用 | `features/account` | 🔶 | App 平台专属 |

## 2.1 WiFi 版（`main-wifi` 分支，2026-10-27 起）

两端都是双长期分支：`main` 为线上蓝牙版、互相对齐；`main-wifi` 开发 WiFi 版设备、互相对齐，`main` 修的问题及时合入 `main-wifi`。
下表只在 `main-wifi` 成立，记录见 [`../history/2026-10/2026-10-27-wifi-version-sync.md`](../history/2026-10/2026-10-27-wifi-version-sync.md)。

| 模块 | 小程序 | Flutter | 状态 | 当前结论 |
| --- | --- | --- | --- | --- |
| 广播匹配 / 扫描 | `utils/broadcast-match.js`、`bluetooth.js includeWifi` | `device/wifi/broadcast_match.dart`、`FrameBleClient.scan(includeWifi)` | ✅⚠️ | `*` 模板 + 内置 `IJ_*`，中间 12 位为 deviceNo；只有搜索页收录 WiFi 版 |
| 搜索设备列表 | `subpackages/device/bind` | `bind_device_flow.dart` / `bind_device_found.dart` | ✅⚠️ | 第二行「类型标签包住尺寸 → 电量 → 信号 + 信号格」；WiFi 行查规格、未知设备拦截、「立即配网」先 BluFi 连接 |
| 配网三页 | `wifi-list` / `wifi-config` / `wifi-provision` | `features/wifi/presentation/` 三页 | ✅⚠️🔶 | 流程、文案、四步时序一致；🔶 App 不保持屏幕常亮、手机网络判断改为解析 IoT 域名 |
| BluFi | `utils/blufi.js` | `device/wifi/blufi.dart` | ✅⚠️ | 帧格式、分片、两种 WiFi 列表回包、JSON 指令回执口径一致；不加密 |
| IoT 服务 | `utils/iot-*.js` | `network/iot/` | ✅⚠️ | 错误码同表（App 四语种）；401 登出、503 不登出；WS 心跳 / 退避 / 补订一致 |
| 我的设备 | `subpackages/device/list` | `my_devices_page.dart` | ✅⚠️ | WiFi版 / 蓝牙版分组；WiFi 卡云端状态 + 投屏 / 刷新状态 |
| WiFi 设备详情 | `subpackages/device/wifi-detail` | `wifi_device_detail_page.dart` | ✅⚠️ | 设备信息行、`device.status` 自动重查；蓝牙详情入口自动分流 |
| WiFi 投屏 | `utils/wifi-projection.js`、`projection/wifi-result` | `wifi_projection.dart`、`wifi_cast_result_page.dart` | ✅⚠️ | 上传进度、WS + 状态查询兜底、TIMEOUT 修正窗口、90 秒未知；不写投屏记录 |
| 首页 / 图库详情 / 选设备弹层 | `home`、`gallery/detail`、`device-picker-sheet` | `home_*`、`official_gallery_detail_page.dart`、`device_picker_sheet.dart` | ✅⚠️ | WiFi 卡云端状态、投屏只确认在线、弹层「WiFi版」角标 |
| IoT 联调卡 | `subpackages/device/debug` | — | 🔶 | App 调试台未加 |
| AI 对话 / 我的相册再次投屏 | 未接 | 未接 | ⚠️ | 两端一致：选 WiFi 版仍走蓝牙，会失败 |

⚠️ App 侧未编译、未真机、未与 IoT 联调。

## 3. 全局行为

| 项目 | 状态 | 当前规则 |
| --- | --- | --- |
| 公共请求参数 | ✅ | BoltFox 请求注入 `terminal/language/device/userToken` |
| 密码/验证码 | ✅ | 密码小写 MD5；验证码统一 `sendEmail` |
| 设备名称 | ✅ | 去首尾空格、非空、最多 6 个 Unicode 码点 |
| 设备身份 | ✅ | 后端/绑定/会话只认完整 6 字节 ID；广播短 ID 只筛候选。**2026-07-30 起两端各有一张身份登记表**（小程序 `utils/device-identity.js`、App `device_identity_registry.dart`），在列表接口漏发 `deviceId` 时兜底补齐，避免正常设备被身份闸报成「请删除后重新绑定」；补齐链同为「记录自身 > 本地上一版 > 登记表」，只收完整 ID、不反向覆盖后端值。两端触发路径不同（小程序在详情页继承，App 在 `refreshDevices` 整体替换列表）；App 侧另有 64 条上限、超限丢最早一条（防偏好文件被异常写入撑大），小程序未设上限，不影响语义 |
| 设备电量 | ✅ | `0x04` 单一数据源、15 秒缓存、并发合并、失败保留旧值、0% 合法 |
| 单连接 | ✅ | 新目标会话建立前回收旧连接，展示状态只认活动会话 |
| BLE 主协议 | ✅ | 帧头、CRC、236 字节分包、ACK、屏型/格式一致 |
| 图传参数 | ✅ | 默认 pace 3ms、窗口 10、累计 ACK、自适应节奏 |
| 投屏编辑 | ✅ | JPEG 92%，最终图严格为设备物理分辨率 |
| 投屏转帧 | ✅ | 原图/编辑图由服务端转设备帧，App 不自研六色量化 |
| `imgIndex` | ✅⚠️ | 优先真实槽位，无索引旧记录才回退推算；后端唯一性仍待确认 |
| 自动重连 | ✅🔶 | 首页/列表/详情/图库/轮播按目标设备重连。**2026-07-30 起两条快路径**：系统已连接表兜底（App 专属）→ 本机直连缓存短超时直连（对齐小程序 `device-conn-cache`）→ 完整扫描。两端同用 -70dBm/1.5s 弱信号闸、120ms 停扫沉淀、[5s, 8s] 建连超时阶梯；快路径一律由 0x01 完整 ID 验身，不降低身份安全性。App 另有 -80dBm 极弱档（跳过常规建连直接 autoConnect），属安卓专属手段，见下节 |
| 页面刷新 | ✅ | 首页、资料、图库、投屏记录按进入/返回时机刷新 |
| FAQ | ✅ | 全量分页、后端排序、随语言重载、空结果覆盖旧列表 |

## 4. 有意的平台差异

- 登录：小程序微信快捷登录；App 为邮箱体系 + 微信开放平台移动应用 OAuth。
  两端**接口不同**：小程序发 `/Client/User/setWechatAppLogin`（授权手机号，带
  `wxEncrypData` / `wxIvData`），App 发 `/Client/User/setWechatAuthorizLogin`（只发 OAuth `code`）。
  App 侧对该接口关闭全部自动重试——微信 code 一次性，详见
  `WECHAT_LOGIN_SETUP.md` 与 `../history/2026-07/2026-07-29-微信授权登录接通App专用接口.md`。
- 相册选图：小程序使用微信选择媒体能力；Android App 使用系统 Photo Picker，只授权用户
  选中的图片，不申请整个媒体库读取权限。
- 图片编辑：两端交互/输出规则一致，但 App 使用 Flutter 手势层、Canvas 和 isolate。
- HTML：小程序 `rich-text`；App 使用 `SimpleHtmlText` 支持受控标签子集。
- 版本升级：App 使用后端版本接口与系统下载/安装能力。
- 后台连接：Android 使用前台服务；iOS 使用 CoreBluetooth 后台模式。
- BLE 搜索/建连的平台专属手段（微信 API 无对应旋钮，属于「原生最优解」而非小程序差异）：
  - Android `autoConnect` **末位**兜底：常规建连全部失败后改由控制器白名单等广播。它的价值
    在于**没有时间上限**（能覆盖「设备此刻不广播、过一会儿才醒」），而不是弱信号命中率——
    它的占空比只有 ≈0.9%，是常规定向连接（≈50%）的约 1/57，3s 广播间隔下期望命中要几分钟
    （2026-08-01 更正，此前记反了）。超时必须显式断开，否则幽灵连接会占住设备。
  - Android 起扫频率账本：系统 30s 内起扫超 5 次会**静默降级**扫描（整窗几乎收不到广播），
    App 侧自行限流；小程序共用一路硬件扫描，天然少踩这条。
  - 系统已连接表兜底：设备被系统层占着时不广播、扫描永远搜不到，App 用 `systemDevices` 直接建连。
  - 连接优先级：建连后 2s 内请求 HIGH，让服务发现/MTU/开通知/读 0x01 跑在短间隔上。
  - 按 RSSI 分档的建连预算（2026-08-01 重排）：正常 5s→8s、弱 12s、极弱 16s 的**定向连接**，
    autoConnect 各留 5~8s 末位兜底。总预算与 2026-07-30 版持平，只是把时间从 ≈0.9% 占空比的
    机制挪回 ≈50% 的那个。小程序 `wx.createBLEConnection` 无此旋钮（只有 timeout）。
  - 连接失败的第二次机会是**原地重连**而不是重扫（2026-08-01）：MAC 不会因一次失败失效，
    而重扫要付 12s + 一个起扫名额；起扫触顶会被系统静默降级，等于重试自己把重试搞垮。
  - 断开落地等待（2026-07-30）：重试前等 `connectionState` 真到 disconnected（上限 600ms）。
    半连状态上重连是安卓 `status=133` 的常客，且每轮会新建一个 GATT client，攒满后表现为
    「怎么连都是 133、重启 App 才好」。微信侧无此语义。
- 临时：App 内置「安卓原生 vs `flutter_blue_plus`」连接 A/B 探针（性能自检页首卡，仅安卓可用），
  用于判定是否值得把传输层原生化，**不是产品能力**，定版后整体拆除；见
  `../history/2026-07/2026-07-30-安卓原生连接AB对比.md`。
- 支付渠道（2026-08-27）：**小程序=微信支付、安卓=PayPal、iOS=Apple 内购**，三端各走各的，
  不是同一条链路。小程序端**不需要** PayPal（其确认购买页的 PayPal 选项一直隐藏着、
  `token-api.purchase` 直接 reject `PAYPAL_UNAVAILABLE`）；安卓端**不走内购**（此前文档一律写成
  「Apple IAP / Android 内购」，是旧口径，已按本条改正）。共用的只有前两步（`getGoodsList` /
  `addOrder`）与查单（`getPayQuery`），拉起支付那一步各端不同：小程序 `wx.requestVirtualPayment`、
  安卓 `setCreatePay` → `payPalApproveUrl` 外跳、iOS StoreKit 原生购买 → `/Client/Pay/setApplePayVerifyReceipt`，详见 [iOS 内购](IOS_IN_APP_PURCHASE.md)。
- AI 语音：小程序可使用微信能力；App 尚未接录音与 STT。
- 底栏：两端同为四格（首页 / AI助手 / 官方图库 / 我的），中间两格都不是 tab（各自 push 一个页面，
  返回即回原 tab）。App 侧 2026-08-19 补齐，同时删掉「我的 → 服务与帮助」里的「官方图库」行
  ——两个入口指同一个页面只会让人犹豫点哪个（口径取自小程序 `pages/mine/mine.wxml` 的注释）。

## 5. 当前待确认

- 下一轮需要从头执行一次完整逐页审查，而不是只依赖 07-14 后的增量日志。
- 投屏常驻编辑层、iOS BLE 性能和多设备验身需要持续保留真机回归。
- 后端需确认同一设备 `imgIndex` 唯一性。
- AI 正式入口已于 2026-08-19 开放（需求：App 端要和小程序一样看得到 AI助手）。**遗留项照旧**：
  语音输入仍是占位按钮、「下载」只写应用缓存目录，两条产品规则仍需补；网关 JWT
  （`Authentication: Bearer`）与 SSE 链路仍待真机验收（见
  `../history/2026-08/2026-08-07-AI流式SSE与JWT补齐.md`）。验收不过就把开关改回 `false`。
- 小程序 `docs/protocols/ota-dfu.md` 与当前 `utils/ota-ble.js` / Flutter
  `ota_ble.dart` 在 DATA 帧序号、`0xF3` 方向和最小固件大小上冲突。修正文档前以两端
  已运行源码和真机协议为准，不同步冲突文字。

## 6. 维护规则

- 本文只保存当前矩阵，不追加逐日操作日志。
- 一次性同步过程写入 `../history/YYYY-MM/`，完成后回到本文修正最终结论。
- 当前代码位置、路由和调用链以 CodeGraph 为准。
