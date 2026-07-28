# BoltStar App ↔ 微信小程序当前对齐矩阵

> 文档类型：Cross-client Integration  
> 状态：Active  
> 最后核验：2026-07-28  
> 对照仓库：`D:\Work\learn\photo-album`  
> 覆盖说明：矩阵吸收了截至 2026-07-27 的增量同步；上一次从头逐页完整复核为
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
| 绑定设备 | `subpackages/device/bind` | `features/devices/.../bind_device_flow.dart` | ✅ | 权限、白名单、扫描、候选连接、完整 ID 验身、绑定与返回一致 |
| 设备列表 | `subpackages/device/list` | `devices_page.dart` / `my_devices_page.dart` | ✅ | 列表、选择、连接/断开、投屏和重命名一致 |
| 设备详情 | `subpackages/device/detail` | `device_details_page.dart` | ✅ | 连接、投屏、轮播、清空、删除和 OTA 入口一致 |
| BLE 调试 | `subpackages/device/debug` | `ble_debug_page.dart` | 🔶 | 两端均保留工程调试能力，release 用户入口受控 |
| 轮播 | `subpackages/device/slideshow` | `carousel_settings_page.dart` | ✅ | 断线重连、0x10 模式/间隔与失败回滚一致 |
| OTA | `subpackages/device/ota` | `ota_upgrade_page.dart` | ✅ | 连接门控、版本检查、确认与 DFU 流程一致 |
| 投屏预览 | `subpackages/projection/preview` | `cast_preview_page.dart` | ✅⚠️ | 2026-07-25 起使用常驻编辑层；横竖取景、多图切换、旋转和 Canvas 烘焙规则一致，仍需真机回归 |
| 投屏过程 | `subpackages/projection/result` | `projection_service.dart` / `casting_progress_page.dart` | ✅ | 服务端六色帧、部分成功、空间检查、记录回写与 BLE 图传一致 |
| 投屏记录 | `subpackages/projection/records` | `cast_management_figma_page.dart` | ✅ | 成功/失败分页、再次投屏、删除与重入刷新一致 |
| 图库 | `subpackages/album/list` | `gallery_page.dart` | ✅ | 设备筛选、批量删除、清空提示、0x24 刷屏和跨设备保护一致 |
| AI 星宝 | `subpackages/ai` | `features/ai` | ✅⚠️ | 会话与图文消息已对齐；两端正式入口均关闭，语音输入仍为 App 占位 |
| 设置 | `subpackages/settings/index` | `settings_page.dart` | ✅ | 联系、协议、隐私、退出、注销和失败留页一致 |
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
| 设备身份 | ✅ | 广播短 ID 只筛候选；建连后完整 ID 验身 |
| 单连接 | ✅ | 新目标会话建立前回收旧连接，展示状态只认活动会话 |
| BLE 主协议 | ✅ | 帧头、CRC、236 字节分包、ACK、屏型/格式一致 |
| 图传参数 | ✅ | 默认 pace 3ms、窗口 10、累计 ACK、自适应节奏 |
| 投屏编辑 | ✅ | JPEG 92%，最终图严格为设备物理分辨率 |
| 投屏转帧 | ✅ | 原图/编辑图由服务端转设备帧，App 不自研六色量化 |
| `imgIndex` | ✅⚠️ | 优先真实槽位，无索引旧记录才回退推算；后端唯一性仍待确认 |
| 自动重连 | ✅ | 首页/列表/详情/图库/轮播按目标设备重连 |
| 页面刷新 | ✅ | 首页、资料、图库、投屏记录按进入/返回时机刷新 |
| FAQ | ✅ | 全量分页、后端排序、随语言重载、空结果覆盖旧列表 |

## 4. 有意的平台差异

- 登录：小程序微信快捷登录；App 为邮箱体系 + 微信开放平台移动应用 OAuth。
- 图片编辑：两端交互/输出规则一致，但 App 使用 Flutter 手势层、Canvas 和 isolate。
- HTML：小程序 `rich-text`；App 使用 `SimpleHtmlText` 支持受控标签子集。
- 版本升级：App 使用后端版本接口与系统下载/安装能力。
- 后台连接：Android 使用前台服务；iOS 使用 CoreBluetooth 后台模式。
- AI 语音：小程序可使用微信能力；App 尚未接录音与 STT。

## 5. 当前待确认

- 下一轮需要从头执行一次完整逐页审查，而不是只依赖 07-14 后的增量日志。
- 投屏常驻编辑层、iOS BLE 性能和多设备验身需要持续保留真机回归。
- 后端需确认同一设备 `imgIndex` 唯一性。
- AI 正式入口启用前需补齐语音/下载产品规则并完成发布级验收。

## 6. 维护规则

- 本文只保存当前矩阵，不追加逐日操作日志。
- 一次性同步过程写入 `../history/YYYY-MM/`，完成后回到本文修正最终结论。
- 当前代码位置、路由和调用链以 CodeGraph 为准。
