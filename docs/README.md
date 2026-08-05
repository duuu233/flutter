# BoltStar 文档中心

> 文档类型：Knowledge Governance  
> 状态：Active  
> 最后核验：2026-07-30  
> 目录约束：项目 Markdown 统一存放在 `docs/` 下

根目录 `AGENTS.md` 是代理执行规则，`AI_CONTEXT.md` 是明确要求的 AI 项目上下文；二者不属于
普通项目文档，必须留在仓库根目录，是本目录约束的两个 Markdown 例外。

## 1. 阅读入口

| 目标 | 文档 |
| --- | --- |
| 快速了解项目 | [`PROJECT_OVERVIEW.md`](PROJECT_OVERVIEW.md) |
| 查看当前代码架构 | [`architecture/PROJECT_STRUCTURE.md`](architecture/PROJECT_STRUCTURE.md) |
| 查看接口与服务 | [`architecture/API_INTEGRATION.md`](architecture/API_INTEGRATION.md) |
| 查看 App/小程序差异 | [`integration/APP_VS_MINIPROGRAM.md`](integration/APP_VS_MINIPROGRAM.md) |
| 打包发版 | [`runbooks/BUILD_RELEASE.md`](runbooks/BUILD_RELEASE.md) |
| iOS BLE 性能排查 | [`runbooks/IOS_BLE_PERFORMANCE.md`](runbooks/IOS_BLE_PERFORMANCE.md) |

## 2. 长期知识

### Architecture

| 文档 | 主职责 |
| --- | --- |
| [`architecture/PROJECT_STRUCTURE.md`](architecture/PROJECT_STRUCTURE.md) | 当前目录、模块、状态、路由、网络、BLE、投屏与测试架构 |
| [`architecture/API_INTEGRATION.md`](architecture/API_INTEGRATION.md) | BoltFox、seekink 抖动服务、BoltStar AI 的当前契约与边界 |
| [`architecture/BLE_CONNECTION_AND_IDENTITY.md`](architecture/BLE_CONNECTION_AND_IDENTITY.md) | 单连接、候选筛选、完整 ID 验身、会话复用和电量规则 |
| [`architecture/IMAGE_SLOT_INDEX.md`](architecture/IMAGE_SLOT_INDEX.md) | `imgIndex` 设备物理槽位与后端记录规则 |
| [`architecture/RESOURCE_LIFECYCLE.md`](architecture/RESOURCE_LIFECYCLE.md) | 图片缓存、临时文件、账号隔离、BLE 租约与进程回收 |

### Integration

| 文档 | 主职责 |
| --- | --- |
| [`integration/APP_VS_MINIPROGRAM.md`](integration/APP_VS_MINIPROGRAM.md) | App 与微信小程序当前能力矩阵和有意差异 |
| [`integration/WECHAT_LOGIN_SETUP.md`](integration/WECHAT_LOGIN_SETUP.md) | 微信开放平台移动应用登录与原生配置 |

### Runbooks

| 文档 | 主职责 |
| --- | --- |
| [`runbooks/BUILD_RELEASE.md`](runbooks/BUILD_RELEASE.md) | Android/iOS 构建、签名、占位符与发布检查 |
| [`runbooks/IOS_BLE_PERFORMANCE.md`](runbooks/IOS_BLE_PERFORMANCE.md) | 正式包自检、RTT、吞吐、日志与 iOS BLE 判定流程 |

### Content

| 文档 | 主职责 |
| --- | --- |
| [`content/操作手册与常见问题-四语种.md`](content/操作手册与常见问题-四语种.md) | FAQ、操作手册和简中/繁中/英文/日文运营录入内容 |

### Generated

| 文档 | 主职责 |
| --- | --- |
| [`generated/IOS_LAUNCH_IMAGE.md`](generated/IOS_LAUNCH_IMAGE.md) | Flutter iOS 启动图资源说明的集中存档 |

## 3. 历史资料

`history/` 只保存当时的审查、变更、进度和旧结构，不承担当前事实：

| 文档 | 状态 |
| --- | --- |
| [`history/2026-07/PROJECT_STRUCTURE_LEGACY.md`](history/2026-07/PROJECT_STRUCTURE_LEGACY.md) | Historical Architecture Snapshot |
| [`history/2026-07/API_INTEGRATION_PROGRESS.md`](history/2026-07/API_INTEGRATION_PROGRESS.md) | Historical Ledger |
| [`history/2026-07/API_INTERFACE_SNAPSHOT.md`](history/2026-07/API_INTERFACE_SNAPSHOT.md) | Historical API Snapshot |
| [`history/2026-07/APP_VS_MINIPROGRAM_SYNC_LOG.md`](history/2026-07/APP_VS_MINIPROGRAM_SYNC_LOG.md) | Historical Cross-client Ledger |
| [`history/2026-07/2026-07-17-optimization-audit.md`](history/2026-07/2026-07-17-optimization-audit.md) | Historical Audit |
| [`history/2026-07/2026-07-17-连接投屏性能对比分析.md`](history/2026-07/2026-07-17-连接投屏性能对比分析.md) | Historical Analysis |
| [`history/2026-07/2026-07-19-bugfix-round.md`](history/2026-07/2026-07-19-bugfix-round.md) | Historical Change Record |
| [`history/2026-07/2026-07-19-faq-guide-round.md`](history/2026-07/2026-07-19-faq-guide-round.md) | Historical Change Record |
| [`history/2026-07/2026-07-20-resource-reclamation.md`](history/2026-07/2026-07-20-resource-reclamation.md) | Historical Audit |
| [`history/2026-07/2026-07-20-单连接合规与跨端审查.md`](history/2026-07/2026-07-20-单连接合规与跨端审查.md) | Superseded |
| [`history/2026-07/2026-07-22-iOS投屏性能优化.md`](history/2026-07/2026-07-22-iOS投屏性能优化.md) | Historical Change Record |
| [`history/2026-07/2026-07-27-同尺寸设备身份校验与电量缓存.md`](history/2026-07/2026-07-27-同尺寸设备身份校验与电量缓存.md) | Historical Decision Record |
| [`history/2026-07/2026-07-28-小程序近期修复同步.md`](history/2026-07/2026-07-28-小程序近期修复同步.md) | Historical Change Record |
| [`history/2026-07/2026-07-28-Android纯Photo-Picker迁移.md`](history/2026-07/2026-07-28-Android纯Photo-Picker迁移.md) | Historical Change Record |
| [`history/2026-07/2026-07-28-AI服务协议.md`](history/2026-07/2026-07-28-AI服务协议.md) | Historical Change Record |
| [`history/2026-07/2026-07-28-AI网关错误与服务协议v2.md`](history/2026-07/2026-07-28-AI网关错误与服务协议v2.md) | Historical Change Record |
| [`history/2026-07/2026-07-29-蓝牙边搜边显示与AI发送去重同步.md`](history/2026-07/2026-07-29-蓝牙边搜边显示与AI发送去重同步.md) | Historical Change Record |
| [`history/2026-07/2026-07-29-微信授权登录接通App专用接口.md`](history/2026-07/2026-07-29-微信授权登录接通App专用接口.md) | Historical Change Record |
| [`history/2026-07/2026-07-29-图库设备筛选按设备ID同步.md`](history/2026-07/2026-07-29-图库设备筛选按设备ID同步.md) | Historical Change Record |
| [`history/2026-07/2026-07-30-蓝牙搜索连接提速.md`](history/2026-07/2026-07-30-蓝牙搜索连接提速.md) | Historical Change Record |
| [`history/2026-07/2026-07-30-FBP连接优化与身份登记表.md`](history/2026-07/2026-07-30-FBP连接优化与身份登记表.md) | Historical Change Record |
| [`history/2026-07/2026-07-30-安卓原生连接AB对比.md`](history/2026-07/2026-07-30-安卓原生连接AB对比.md) | Temporary（临时对照实验，含拆除清单；定版后随代码一并删除） |
| [`history/2026-07/2026-07-31-设备改名保存Loading.md`](history/2026-07/2026-07-31-设备改名保存Loading.md) | Historical Change Record |
| [`history/2026-07/2026-07-31-设备与照片交互优化Flutter同步.md`](history/2026-07/2026-07-31-设备与照片交互优化Flutter同步.md) | Historical Change Record |
| [`history/2026-08/2026-08-01-交互与文案十一项优化.md`](history/2026-08/2026-08-01-交互与文案十一项优化.md) | Historical Change Record |
| [`history/2026-08/2026-08-01-安卓弱信号建连预算重排.md`](history/2026-08/2026-08-01-安卓弱信号建连预算重排.md) | Historical Change Record（结论待真机确认，页面留了对照旋钮） |
| [`history/2026-08/2026-08-02-导航栏设备下拉居中与同宽.md`](history/2026-08/2026-08-02-导航栏设备下拉居中与同宽.md) | Historical Change Record（双端同步） |
| [`history/2026-08/2026-08-02-选图上限与预览切图四项.md`](history/2026-08/2026-08-02-选图上限与预览切图四项.md) | Historical Change Record（双端同步） |
| [`history/2026-08/2026-08-04-我的相册合并与折叠屏核对.md`](history/2026-08/2026-08-04-我的相册合并与折叠屏核对.md) | Historical Change Record（双端同步；折叠屏项为核对结论，App 无需改动） |
| [`history/2026-08/2026-08-05-我的相册计数与折叠屏方案.md`](history/2026-08/2026-08-05-我的相册计数与折叠屏方案.md) | Historical Change Record（双端同步；「我的相册」张数改口径 + `FigmaScreen.fillViewport`） |
| [`history/2026-08/2026-08-04-广播设备ID扩到6字节.md`](history/2026-08/2026-08-04-广播设备ID扩到6字节.md) | Historical Change Record（双端同步；⚠️ 客户端须先于固件灰度上线） |
| [`history/2026-08/2026-08-04-微信登录回登录页弹请重新登录.md`](history/2026-08/2026-08-04-微信登录回登录页弹请重新登录.md) | Historical Change Record（定位为后端 406；待后端放行免登录白名单） |
| [`history/2026-08/2026-08-05-微信AppID及Android签名统一.md`](history/2026-08/2026-08-05-微信AppID及Android签名统一.md) | Historical Change Record（其中的 AppID 已被同日更正记录取代；签名统一部分仍有效） |
| [`history/2026-08/2026-08-05-微信AppID更正为wx4cf0c5f38a70d0bc.md`](history/2026-08/2026-08-05-微信AppID更正为wx4cf0c5f38a70d0bc.md) | Historical Change Record（AppID 更正为 `wx4cf0c5f38a70d0bc`，Android/iOS、debug/release 同值） |
| [`history/2026-07/RUNBOOK_CHANGELOG.md`](history/2026-07/RUNBOOK_CHANGELOG.md) | Historical Change Record |

## 4. CodeGraph 与 Markdown 的职责

CodeGraph 回答当前代码事实：

- 符号定义和实现位置；
- 调用链与依赖方向；
- 修改影响范围；
- 当前文件和模块结构。

Markdown 回答需要长期解释的知识：

- 产品、协议和架构决策；
- 外部服务和平台约束；
- 发布、诊断和验收步骤；
- 历史审查与变更背景。

发生冲突时：

1. 代码位置、调用关系和当前实现以源码 + CodeGraph 为准。
2. 产品/协议/人工流程以 Active 文档为准。
3. Historical 只代表当时状态。
4. Superseded 不得作为当前规则，只用于追溯。

常用命令：

```powershell
codegraph status .
codegraph explore "问题、符号名或文件名"
codegraph sync .
```

只有 CodeGraph 提示提取器变化、索引损坏或明确建议重建时才执行 `codegraph index .`。

## 5. 文档生命周期

- **Active**：直接维护当前正文，不追加逐次操作日志。
- **Historical**：完成后冻结，只允许补充验收结果或替代关系。
- **Superseded**：顶部必须链接替代文档并说明失效原因。
- **Generated**：只随对应平台/生成机制变化维护。

同一事实只指定一个主文档。其他文档使用链接，不复制大段当前结论。

## 6. 变更触发规则

| 变更 | 必须更新 |
| --- | --- |
| 模块、分层、状态或路由边界 | `architecture/PROJECT_STRUCTURE.md` |
| API、DTO、鉴权或服务边界 | `architecture/API_INTEGRATION.md` |
| BLE 身份、连接或会话规则 | `architecture/BLE_CONNECTION_AND_IDENTITY.md` |
| 图片槽位语义 | `architecture/IMAGE_SLOT_INDEX.md` |
| 缓存、临时文件、退出清理或租约 | `architecture/RESOURCE_LIFECYCLE.md` |
| App/小程序能力差异 | `integration/APP_VS_MINIPROGRAM.md` |
| 微信平台配置 | `integration/WECHAT_LOGIN_SETUP.md` |
| 构建、签名、发版步骤 | `runbooks/BUILD_RELEASE.md` |
| BLE 性能入口、参数或判据 | `runbooks/IOS_BLE_PERFORMANCE.md` |
| 用户流程或四语种文案 | `content/操作手册与常见问题-四语种.md` |

一次性审查或集中修复写入 `history/YYYY-MM/`，然后把最终长期结论更新到对应 Active 文档。

## 7. 维护节奏

### 每次变更

1. 改动前使用 CodeGraph 查看定义、调用链和影响范围。
2. 按第 6 节判断是否更新 Active 文档。
3. 改动后运行分析/测试并检查 `codegraph status .`。
4. 检查新增 Markdown 是否位于 `docs/` 且已加入本索引。

### 每次发版

- 执行构建发布 Runbook。
- 核验接口、跨端矩阵、四语种内容和平台配置。
- 将真机结果写入相应 Active Runbook，不写到多个文档的操作日志。

### 每季度

- 用 CodeGraph 复核架构文档的模块边界。
- 检查 Active 文档的“待确认/待验证”是否仍成立。
- 标记失效历史结论，合并重复的当前事实。
- 按月份归档新增 Historical 文档。
