# BoltStar App ↔ 微信小程序当前对齐矩阵

> 文档类型：Cross-client Integration  
> 状态：Active  
> 最后核验：2026-07-30  
> 对照仓库：`D:\Work\learn\photo-album`  
> 覆盖说明：矩阵吸收了截至 2026-07-30 的增量同步；上一次从头逐页完整复核为
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
| 登录 | `pages/login` | `features/account` | 🔶 | 小程序微信快捷登录；App 支持邮箱和移动应用微信登录 |
| 我的 | `pages/mine` | `features/mine` | ✅ | 资料、计数、图库、设备、投屏记录、指南和设置入口一致 |
| 绑定设备 | `subpackages/device/bind` | `features/devices/.../bind_device_flow.dart` | ✅⚠️ | 只允许 0x01 完整 6 字节 ID 判重/入库；广播短 ID 与 BLE 句柄不兜底。**2026-07-29 起「搜到一个显示一个」**：扫描窗口 12s→20s；安卓 low-latency + legacy 1M + 持续重复回调，名称首包丢失时可由后续包/厂商数据补入；新扫描接管旧会话，返回/侧滑 dispose 停扫，旧响应不覆盖新状态；搜索动效在结果出现前后保持 280×280。静态检查无新增诊断，⚠️仍需 Android/iOS 真机弱信号回归 |
| 设备列表 | `subpackages/device/list` | `devices_page.dart` / `my_devices_page.dart` | ✅ | 列表、选择、连接/断开、投屏和重命名一致 |
| 设备详情 | `subpackages/device/detail` | `device_details_page.dart` | ✅⚠️ | 连接、投屏、轮播、清空、删除和 OTA 入口一致；**2026-07-29 起「设备ID」下方新增分辨率行**（如 `680*960`，连上取 0x01 真机宽高 → 后端记录宽高 → `--`）。分辨率是产品静态属性，**不随连接状态置 `--`**；两端都不由 `screenType` 反查（会臆造尺寸）。⚠️本机无 Flutter SDK，未编译/未真机 |
| BLE 调试 | `subpackages/device/debug` | `ble_debug_page.dart` | 🔶 | 两端均保留工程调试能力，release 用户入口受控 |
| 轮播 | `subpackages/device/slideshow` | `carousel_settings_page.dart` | ✅ | 断线重连、0x10 模式/间隔与失败回滚一致 |
| OTA | `subpackages/device/ota` | `ota_upgrade_page.dart` | ✅⚠️ | 两端当前源码流程一致；小程序新协议文档与两端源码冲突，修正文档前不可据其改协议 |
| 投屏预览 | `subpackages/projection/preview` | `cast_preview_page.dart` | ✅⚠️ | 2026-07-25 起使用常驻编辑层；横竖取景、多图切换、旋转和 Canvas 烘焙规则一致，仍需真机回归 |
| 投屏过程 | `subpackages/projection/result` | `projection_service.dart` / `casting_progress_page.dart` | ✅ | 服务端六色帧、部分成功、空间检查、记录回写与 BLE 图传一致 |
| 投屏记录 | `subpackages/projection/records` | `cast_management_figma_page.dart` | ✅ | 成功/失败分页、再次投屏、删除与重入刷新一致 |
| 图库 | `subpackages/album/list` | `gallery_page.dart` | ✅⚠️ | 设备筛选、批量删除、清空提示、0x24 刷屏和跨设备保护一致；下拉按后端设备ID，同名设备用序列号尾号消歧；胶囊/菜单文字单行省略；**每次展开下拉都重新请求设备列表接口并显示菜单内 loading**，不以进页时列表作缓存。静态检查无新增诊断，⚠️仍需同名设备真机验证 |
| AI 星宝 | `subpackages/ai` | `features/ai` | ✅⚠️ | 会话、图文消息及按用户 ID 隔离的 AI 服务协议确认已对齐；两端正式入口均关闭，语音输入仍为 App 占位。**2026-07-29 起发送入口加同步闸**（`_guardedSend`/`_submitting`）：治「首次在空态发第一条时按钮不及时变灰、连点重复发送」（`_sending` 要等请求真正发出才置起，前面还隔着协议确认+建会话）；加载中气泡（三个跳点）不再铺满屏宽。⚠️本机无 Flutter SDK，未编译/未真机 |
| 设置 | `subpackages/settings/index` | `settings_page.dart` | ✅ | 联系、用户/隐私/AI 服务协议、退出、注销和失败留页一致；App 协议正文为四语种 |
| 个人资料 | `subpackages/settings/profile` | `profile_page.dart` | ✅ | 进入刷新、头像本地预览与保存时提交一致 |
| 邮箱 | `bind-email/change-email` | `bind_email_*` / `modify_email_page.dart` | ✅ | 验证码和 `changeUserEmail` 参数一致 |
| 语言 | `subpackages/settings/language` | `language_settings_page.dart` | ✅🔶 | 四项 UI 一致；App 同时切换本地内置文案 |
| 操作指南 | `subpackages/settings/guide` | `guide_page.dart` | ✅ | 全量分页、默认收起、语种刷新一致；HTML 渲染技术不同 |
| 协议/隐私 | settings agreement/privacy | 对应 settings 页面 | ✅ | 标题、日期、章节和正文一致 |
| App 更新 | 小程序更新页 | `update_boltstar_page.dart` | 🔶 | App 走原生版本检查和安装包下载 |
| App 邮箱注册/改密 | 不适用 | `features/account` | 🔶 | App 平台专属 |

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
  - Android `autoConnect` 兜底：常规建连全部失败后改由控制器白名单低占空比持续等广播，
    对弱信号/广播间隔长的设备成功率明显更高；超时必须显式断开，否则幽灵连接会占住设备。
  - Android 起扫频率账本：系统 30s 内起扫超 5 次会**静默降级**扫描（整窗几乎收不到广播），
    App 侧自行限流；小程序共用一路硬件扫描，天然少踩这条。
  - 系统已连接表兜底：设备被系统层占着时不广播、扫描永远搜不到，App 用 `systemDevices` 直接建连。
  - 连接优先级：建连后 2s 内请求 HIGH，让服务发现/MTU/开通知/读 0x01 跑在短间隔上。
  - 极弱信号档（2026-07-30）：RSSI < -80dBm 时常规 `connectGatt` 的 CONNECT_IND 命中率接近零，
    直接跳过常规阶梯上 autoConnect，省下的 5s 原样加进 autoConnect 预算，总耗时预算不变。
  - 断开落地等待（2026-07-30）：重试前等 `connectionState` 真到 disconnected（上限 600ms）。
    半连状态上重连是安卓 `status=133` 的常客，且每轮会新建一个 GATT client，攒满后表现为
    「怎么连都是 133、重启 App 才好」。微信侧无此语义。
- 临时：App 内置「安卓原生 vs `flutter_blue_plus`」连接 A/B 探针（性能自检页首卡，仅安卓可用），
  用于判定是否值得把传输层原生化，**不是产品能力**，定版后整体拆除；见
  `../history/2026-07/2026-07-30-安卓原生连接AB对比.md`。
- AI 语音：小程序可使用微信能力；App 尚未接录音与 STT。

## 5. 当前待确认

- 下一轮需要从头执行一次完整逐页审查，而不是只依赖 07-14 后的增量日志。
- 投屏常驻编辑层、iOS BLE 性能和多设备验身需要持续保留真机回归。
- 后端需确认同一设备 `imgIndex` 唯一性。
- AI 正式入口启用前需补齐语音/下载产品规则并完成发布级验收。
- 小程序 `docs/protocols/ota-dfu.md` 与当前 `utils/ota-ble.js` / Flutter
  `ota_ble.dart` 在 DATA 帧序号、`0xF3` 方向和最小固件大小上冲突。修正文档前以两端
  已运行源码和真机协议为准，不同步冲突文字。

## 6. 维护规则

- 本文只保存当前矩阵，不追加逐日操作日志。
- 一次性同步过程写入 `../history/YYYY-MM/`，完成后回到本文修正最终结论。
- 当前代码位置、路由和调用链以 CodeGraph 为准。
