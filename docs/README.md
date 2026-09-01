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
| PayPal 回跳中转页部署与联调 | [`runbooks/PAYPAL_REDIRECT.md`](runbooks/PAYPAL_REDIRECT.md) |

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
| [`runbooks/PAYPAL_REDIRECT.md`](runbooks/PAYPAL_REDIRECT.md) | PayPal 支付回跳的 https 中转页（源码在 `deploy/paypal/`）：为什么不能让 PayPal 直接 302 到自定义 scheme、部署五个注意点（⚠️ 最容易踩的是 SPA 的 catch-all 把页面吃掉）、五步联调（含「不点回跳」那条兜底测试）、卡住时的对照表。⚠️ 记着一条待后端确认的链路风险：**capture 是 App 调 `getPayPalNotify` 才触发的**，用户不跳回 App 就不扣款也不入账，端上补不了，需要后端 webhook 兜底 |

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
| [`history/2026-08/2026-08-07-AI流式SSE与JWT补齐.md`](history/2026-08/2026-08-07-AI流式SSE与JWT补齐.md) | Historical Change Record（双端同步；⚠️ 补上了 07-29 起就欠着的 `Authentication` 头 —— 此前 AI 请求全都会被网关 403，只是入口屏蔽着没炸出来。同时 `/chat` 改 SSE、进度补间、一键生图即时上屏） |
| [`history/2026-08/2026-08-05-微信AppID更正为wx4cf0c5f38a70d0bc.md`](history/2026-08/2026-08-05-微信AppID更正为wx4cf0c5f38a70d0bc.md) | Historical Change Record（AppID 更正为 `wx4cf0c5f38a70d0bc`，Android/iOS、debug/release 同值） |
| [`history/2026-08/2026-08-05-首页未绑定态样式错乱与滚动条修复.md`](history/2026-08/2026-08-05-首页未绑定态样式错乱与滚动条修复.md) | Historical Change Record（仅 App；底部 Tab 移出滚动区 + 可压缩留白 `_CollapsibleGap`，普通手机不再挤成一坨并出滚动） |
| [`history/2026-08/2026-08-11-相册删除跳过空槽位与AI八项优化.md`](history/2026-08/2026-08-11-相册删除跳过空槽位与AI八项优化.md) | Historical Change Record（双端同步小程序 08-10 两份变更；⚠️ 顺带修掉 `deleteImage` **吞掉失败结果码**——固件回 0x04/0x07/0x09 时 App 会当成删除成功照删后端记录。AI 侧第 5 项顶栏排布两端有意不同） |
| [`history/2026-08/2026-08-11-文案口径统一与多图首图刷新.md`](history/2026-08/2026-08-11-文案口径统一与多图首图刷新.md) | Historical Change Record（双端同步小程序 08-04 文案清单 + 08-05「我的相册」默认选中；短标签「设备」/ 完整提示语「电子纸设备·e-paper device·電子ペーパー」、称谓「您」，四语种共 200+ 处；多图投屏收尾改刷**首张**槽位。⚠️ 08-04 清单里的「竖向固定 180°」已被同日 `verticalRotation` 变更取代，**未执行**） |
| [`history/2026-08/2026-08-11-iOS微信UniversalLink定为badmin域名.md`](history/2026-08/2026-08-11-iOS微信UniversalLink定为badmin域名.md) | Historical Change Record（仅 App/iOS；Universal Link = `https://badmin.boltfox.cn/app/`，entitlements + Dart 默认值已落地。⚠️ 域名侧 AASA **未部署**，实测返回后台 SPA 的 HTML，iOS 微信登录仍不可验收） |
| [`history/2026-08/2026-08-11-iOS微信回跳SceneDelegate补链与关深链.md`](history/2026-08/2026-08-11-iOS微信回跳SceneDelegate补链与关深链.md) | Historical Change Record（仅 App/iOS；治「授权完回到 App 弹 `Route not found`、拿不到 code」——fluwx 声明已迁移 scene 却没实现 `scene:openURLContexts:`，被引擎 app 兜底跳过。已补 `SceneDelegate` 转发 + `FlutterDeepLinkingEnabled=false`。⚠️ 是兜底，不替代 AASA 部署） |
| [`history/2026-08/2026-08-12-OTA中断收尾与身份读不到不再拉黑设备.md`](history/2026-08/2026-08-12-OTA中断收尾与身份读不到不再拉黑设备.md) | Historical Change Record（同步小程序 08-12 那一轮，逐条对照后**只改了两条**：① `_verifyBoundDeviceIdentity` 由 `bool` 改三态枚举——「0x01 读不到」不再被当成「不是这台」而排除候选 + 删直连缓存，那正是 OTA 失败后必然踩到的一支，现场表现是「设备就在眼前却一路未搜索到」；② 升级中断新增设备侧收尾（断链让 DFU 状态机复位），并给 `_doStart`/头信息重发循环补 `shouldAbort`。小程序的无主连接清道夫、收尾力度分级、`setSelectedDevice` 合并三条 **App 不适用**（已有更优实现或本就没那个问题）。⚠️ **未编译未真机**） |
| [`history/2026-08/2026-08-12-补齐官方图库与星币模块.md`](history/2026-08/2026-08-12-补齐官方图库与星币模块.md) | Historical Change Record（把上一份记为「模块级缺口」的三块补上：**官方图库**（列表/详情/我的收藏，接 `/Client/Product/*` 五个接口）与**星币**（管理页含消耗规则表 + 购买/消费记录）。⚠️ 星币页**只读**——App 的 IAP 未接，故意不实现 addOrder，页面如实提示去小程序购买；⚠️ 图库沿用小程序那两处后端缺口的兜底（列表项**没有比例**→先按 3:4 占位再按加载完的真实宽高校正**那一张**、**不重新分列**；列表项**没有收藏态**→另拉一页收藏列表在端上标记）；入口挂在「我的 → 服务与帮助」（App 底栏只有首页/我的两格，没法照小程序放 tab）。⚠️ **未编译未真机**） |
| [`history/2026-08/2026-08-12-AI星币闸与文案同步.md`](history/2026-08/2026-08-12-AI星币闸与文案同步.md) | Historical Change Record（同步小程序同日四份变更，11 条里落 6 条：`/chat` 加 `usertoken`（**不是** jwtToken，全小写）、图片上限 4→5、「Token」文案改「星币」、**星币闸由本地假余额换成服务端裁决**（`chkAiDialogue`；⚠️「不够」是 `retCode 403` 不是 `retData false`，只认 retData 会放行；校验提前到建会话之前，免得余额见底的用户每点一次就占一条空会话）、等待气泡三点改动画、投屏明细改进我的相册（⚠️ 投屏管理页自此无入口）。官方图库/收藏/支付三块 **App 侧没有模块**，属缺口不是漏同步。⚠️ **未编译未真机**） |
| [`history/2026-08/2026-08-13-小程序08-11至08-13积压同步.md`](history/2026-08/2026-08-13-小程序08-11至08-13积压同步.md) | Historical Change Record（一次性追平小程序 08-11~08-13 的 8 份变更：**设备ID 四/六字节兼容**（广播解析回退 + 候选强弱两轮 + 兜底候选 + 会话认领只认 0x01）、**删掉整套干跑/mock 升级**、**详情页固件行改版本比对结论**（判定与 OTA 页同源）、OTA 升级页三项版式（auto 不闪帧 / 去返回箭头 / 进行中两条规则）、AI 入口续聊、图库详情大图不裁 + 切分类清屏、星币规则表两列、`availableToken`、重绑带出后端昵称、**AI 供应商改火山引擎并升 `CONSENT_VERSION` v3 + 新增境外传输告知**、**隐私政策换成法务 v3.0 全文且固定英文**（`LegalDocumentView` 随之支持小节标题/要点/表格）。⚠️ 小程序的「蓝牙栈硬复位」与「通知分发器收口」**不适用**（无对应 API / App 无同构写法），但其中「中断收尾第二刀砍到用户新连接」App 同款，已按忙判定修掉。⚠️ **未编译未真机**） |
| [`history/2026-08/2026-08-14-投屏传输参数与进度条平滑同步.md`](history/2026-08/2026-08-14-投屏传输参数与进度条平滑同步.md) | Historical Change Record（同步小程序 08-14 那轮：**图传参数升为默认值**——0x21 每包 236→**489**（`imgDataChunkMax`；夹取规则不变，仍是「数据 ≤ MTU-11」，MTU 247→236、185→174 自动收缩）、窗口上限与默认 10→**50**、**legacy 调速换成 AIMD**（丢包记忆 capWindow 类 ssthresh + pace 退让上限 16ms/干净窗口砍半回落 + 自适应 ACK 超时 + 宽限一轮且重试不重置 + 会话级 `_tunedWindow` 稳态记忆）。⚠️ **窗口 50 与 AIMD 是同一个决定的两半，回滚必须一起回**：老策略在大窗口下会退化成「灌满→缓冲溢出→整窗作废→整窗重发」的死循环。改前 App 的减速兜底与小程序 legacy **连 bug 都一样**（被配置值封顶、实际永远降不下速）。**传输速率未变**：连接间隔仍 Android 7.5 / iOS 15ms、每包间隔仍 3ms。另加 `BleTuning` **口径版本戳**——默认值改了但 SharedPreferences 里还存着旧 window=10 的话新默认等于没生效（小程序真机踩过，一度误判成「50 包压垮设备」），版本不匹配即整组作废回落出厂值。**进度条改连续平滑**：新增 `smooth_progress.dart`（与小程序同源，四版演进：追平即停→按间隔铺开→计划超前 1.5 倍吸抖→**受控前瞻 ≤3%**，两条腿取较大者），不变量含「未真实完成前 99 封顶、100% 只能来自真实完成」「落后 ≤12」「**失败即 freeze 并把领先部分钳回真实目标**」；橙条补间 250ms→33ms。⚠️ 小程序真机踩到的 `setBLEMTU` 虚报/会话复用陈旧 MTU 是**微信 API 特有**，FBP 理论上不会虚高，故未做等价处理——**真机若「传几十包后停住」第一嫌疑就是它**。⚠️ **未编译未真机**：本机无 Flutter SDK，`dart analyze`/`flutter test` 均未跑，合入前必须补跑） |
| [`history/2026-08/2026-08-17-我的相册去掉我的图库接口同步.md`](history/2026-08/2026-08-17-我的相册去掉我的图库接口同步.md) | Historical Change Record（同步小程序 08-17：**「我的图库」两个接口从端上整体删除**——`getUserProductImgList` / `delUserProductImg` 连同 `AlbumPhoto` 账本、`refreshAlbum`、`CastRecord.photoId`、按上传先后推算槽位的两个回退、手动刷屏入口 `refreshGalleryPhotoOnScreen` 一并下线。「我的相册」的数据源只剩设备列表与投屏成功记录：删除只认**记录自己的 `imgIndex`**（新 `resolveDeleteSlots`，缺索引/越界整批终止，绝不推算），设备侧那一半收成 `deleteDevicePhotoSlots`（0x12 + 删到屏显图时补刷屏），来源投屏记录由页面删——**端上删除 = 设备槽位 + 投屏记录**，图库照片的清理归后端。默认设备规则四档→三档；再次投屏直接用 `record.img`。顺带修掉「一个用不上的接口有权把整页打成加载失败」（图库接口原本与设备接口并列在首屏 `Future.wait` 里）。⚠️ 明确保留 `getUserProductClearImg` 的一键清空提醒（UserProduct 侧设备状态，不属于图库链路）。⚠️ **未编译未真机**） |
| [`history/2026-08/2026-08-20-批量投屏收尾刷屏同步.md`](history/2026-08/2026-08-20-批量投屏收尾刷屏同步.md) | Historical Change Record（同步小程序 08-20 口径修正：批量投屏的收尾刷屏 0x24 由「**最后一张传完**」改为「**整个投屏流程结束**」触发——全部传完 / 中途某张失败 / 用户中断三条路径都收尾刷一次，索引仍取本批**第一张成功写入的真实槽位**。「第一张成功就刷」两端从来没有过（`firstSuccessfulIndex ??=` 只记不刷，`int?` 哨兵因为槽位 0 合法）；缺的是「任一张失败即中断本单」叠加后的那支：**选 5 张第 3 张失败**时前 2 张已物理写进设备、结果也按 `uploaded>=1` 判部分成功，却一次 0x24 都没发过，相框还停在投屏前那张。改法是抽出 `scheduleFinalRefresh()` 局部函数在三处收尾调用，整单只刷一次、中途张一律不刷（固件收 0x24 会断蓝牙）、fire-and-forget、`endTransferSession` 仍等在途刷屏跑完，全部不变。⚠️ **未编译未真机**） |
| [`history/2026-08/2026-08-20-固件升级行与相册删除同步.md`](history/2026-08/2026-08-20-固件升级行与相册删除同步.md) | Historical Change Record（同步小程序 08-20 的另两份：**详情页「固件升级」行右侧回到设备当前版本号**（`0x03 GET_SW_VER`）、有无新版本改由箭头旁一颗红点表达（`.firmware-dot` ≈ 7dp/#FF3B30），并且**未连接时整行 `--`、红点恒灭**——没有版本依据就不报警；红点与 `startOtaFlow` 的 `canUpgradeNow` 同源（含 `unknown` 退回后端 `isUpdate`），唯一故意不同源的是「未连接恒灭」，方向只有「红点比点击更保守」这一个。⚠️ App 侧 `DeviceItem.firmwareVersion` 是**粘性**的（断开后不清，小程序会清），所以必须由新的 `_liveFirmwareVersion` + `connected` 闸来对齐，否则未连接会显示上一次连接留下的版本。判定本体 `evaluateFirmwareUpdate` 一字未动；顺带删掉已无消费方的 `devFirmwareUpdateAvailable` / `devFirmwareUpToDate`。**「我的相册」删除改为两半互不阻断**：设备侧 0x12 无论成败都继续删投屏记录（新 `DevicePhotoDeleteOutcome` 取代 `ActionFeedback` 的两态返回，掩码回读的设备忙分支一并放行），四分支合并提示；连接前置**仍然拦着**（连不上则两半都不执行）。代价（产品已确认接受）：设备没删掉时记录先没了 → 幽灵图只能靠一键清空。另搬来四条对账日志（开场 `curImgIndex`/写入后 IMG_MASK 落点/0x20 帧头/0x24 请求与回显）——小程序真机已把「投完屏显示的不是这张」定性为**固件忙窗口拒了 0x24**，App 同固件。⚠️ 小程序那份里的「收尾刷屏临时屏蔽开关」当日已恢复，**不搬**。⚠️ **未编译未真机**） |
| [`history/2026-08/2026-08-21-首页六宫格与底栏两格同步.md`](history/2026-08/2026-08-21-首页六宫格与底栏两格同步.md) | Historical Change Record（同步小程序 08-21 那四份：**底栏由四格收回两格（首页/我的）**，原中间两格「AI助手」「官方图库」连同「我的上传」「我的设备」一起收进**首页 3×2 六宫格**（新 `_HomeEntryCard`，旧 `_CastEntryCard` 删除；小标题「选择投屏方式」按产品要求去掉；卡宽仍不写死——rpx 是按屏宽等比的单位）。⚠️ 与小程序**有意不同**：`kAiEntryEnabled`/`kGalleryEntryEnabled` 两个灰度开关**保留**（App 要过审发版，应急退路不能丢），关掉时宫格回落 5 项。**全站背景换成小程序那张浅蓝墙面**，落成本地 `assets/images/bg02.jpg`、12 处引用一并改指，旧 `bg01.png` 按产品要求留着（代价：包体多约 1 MB；→ **2026-08-27 已删除**）。**新增低电量提醒**（10%~4% / ≤3% 两段文案，3% 归第二档）：纯逻辑分档 `lowBatteryBandFor` + `showLowBatteryTipIfNeeded`，电量走既有 15 秒缓存（`state.batteryForActionTip`），挂在首页与设备列表的**主动操作连接口**——⚠️ 不挂 `state.connectDevice`，那条也被投屏内部续连调用，挂上去会在图传中途弹窗；⚠️ 我的相册再投/删除、轮播保存、一键清空、OTA 尚未覆盖，留下一轮（→ 2026-08-27 已补齐）。详情页轮播行改「已开启」。**两项核对为不适用**：主按钮小程序当天已反转回渐变、App 本来就是渐变（顺手删掉零引用的 `primary-btn-bg.png`）；图片详情断层是小程序特有的「大图与滚动区起点差一个导航高度」，App 的 Stack 两者同起点、无此问题。素材：12 张新图标拷入，⚠️ 旧 `home-icon02` 更名 `home-device-thumb` 并改全 **6 个引用点**（小程序那边漏改五处翻过车），删掉 8 个孤儿素材约 187 KB。**并把 `assets/images` 里全部无引用素材一并清了**：再删 33 个约 1.85 MB（`device_scanning_art.gif` 1MB、`home-bg01/02.png`、`logoV2` 两份、四张 `tabbar-*.svg` 等），⚠️ 含 `device-list-icon04/05` —— 那批图虽有动态拼接 `device-list-icon0$n`，但 `n=(index%3)+1` **永远取不到 4/5**，说明白名单要写到「能取到的范围」而不是只写前缀；顺带修掉一处**断链引用**（`FigmaHomeBackground` 引用两张从不存在的图、靠 errorBuilder 兜着，且该类全项目没人用，已整类删除）。`assets/images` **161 个/5391.5 KB → 129 个/4354.6 KB**（已含新增的 bg02.jpg 993KB 与 12 张图标）。新增 `test/unused_assets_test.dart` 作为长期防线：**引用的图必须存在** + **图必须有活着的引用**，动态白名单会回源码核对拼接仍在、保留项要求认领注释还在。⚠️ **未编译未真机**：本机无 Flutter SDK，新增的 `test/low_battery_band_test.dart` 一个用例都没跑过，合入前必须补跑） |
| [`history/2026-08/2026-08-24-我的页计数与相册删除繁忙中止同步.md`](history/2026-08/2026-08-24-我的页计数与相册删除繁忙中止同步.md) | Historical Change Record（同步小程序 08-24 两份：①「我的」页两张卡的数字都改取 `GET /Client/User/getUserInfo`——设备数 `productCount`、上传数 `imgCount`，`MinePage._reload()` 三个并发请求收成一个（去掉设备列表兜底与投屏成功记录计数），两张卡的 `loaded` 统一看 `userLoaded`；这是对 2026-08-05「张数改用投屏成功记录条数」的**有意回退**（卡片文案已是「我的上传」，口径就是上传过的张数），`refreshMineCastSuccessCount()` 与新 getter `mineCastSuccessCount` 保留备用。卡片标题一并追平小程序：`mineMyGallery` 改名 `mineMyUploads`（我的上传 / My Uploads / マイアップロード，繁中自动转「我的上傳」），旧 key 只有这一个消费方；与首页宫格的 `homeEntryUploadsTitle` 文案相同但**故意各留一份**（两处不同产品件）；目的地不变，仍是投屏成功记录列表。顺带删掉 `docs/l10n-review.html`（2026-08-05 文案审阅的一次性生成物、无生成脚本，内容已过时）。②「我的相册」删除**捕捉到设备繁忙 `0x0B` 即整批中止**：`0x01` 回读与 `0x12` 应答两处都拦，以 `DevicePhotoDeleteOutcome.blockedMessage` 返回，调用方照既有 `blocked` 分支 toast 后直接 return——记录一条不删、列表不刷新、选中态保留供重试；繁忙是设备回帧主动拒绝、指令根本没执行（规格书 v1.5 §6.6.1），没有「删了一半」的中间态，先删记录只会白留幽灵图，而 `0x04`/`0x09`/断连超时仍走 2026-08-20 的「两半互不阻断」。判据新增 `FrameBleException.isBusy`（先认 `resultCode`，再兜文案；**刻意不看 `kind`**——`FrameBleErrorKind.busy` 被本地图传门闩复用）。新增 4 例纯逻辑用例。⚠️ **未编译未真机**：本机无 Flutter SDK，`dart analyze` / `flutter test` 均未跑，合入前必须补跑） |
| [`history/2026-08/2026-08-27-低电量提醒补齐剩余入口.md`](history/2026-08/2026-08-27-低电量提醒补齐剩余入口.md) | Historical Change Record（补完 08-21 那轮记着「留作下一轮」的低电量提醒入口：详情页「连接 / 投屏 / 一键清空 / 固件升级」、OTA 页「连接并升级」、轮播设置页开关、我的相册「再次投屏 / 删除」、投屏记录「再次投屏」、投屏结果页「继续投屏」、官方图库详情页与 AI 对话页的「投屏」共 12 处。小程序靠 `ensureConnectedForAction` 一处收口，App 侧没有同名收口、只能各入口手补，故新增 `test/low_battery_entries_test.dart` 钉住覆盖面：**登记在册的入口必须调** + **没登记的新调用点一律红**（逼着下一个人先分清主动点击与自动重连）+ `state.dart`/`cast_preview_page`/`projection_service`/`ble_controller` 四处自动连接链路**一律不许弹**（红线）。⚠️ 两处相对小程序**有意收窄**：删除与轮播保存的扫连发生在 state 层内部、页面拿不到「刚连上」那一刻，故只在**本来就连着**时提醒（电量未知不弹）；投屏结果页「继续投屏」同理（连接发生在下一页，属自动连接）。OTA 那条链路用一次性标记 `_lowBatteryTipDoneByEntry` 只吞掉「详情页立刻更新 → 自动开始」那一跳，保证「一次点击只弹一次」而手动重试仍会弹。⚠️ **未编译未真机**：本机无 Flutter SDK，`dart analyze` / `flutter test` 均未跑，合入前必须补跑） |
| [`history/2026-08/2026-08-27-删除旧背景与无引用素材.md`](history/2026-08/2026-08-27-删除旧背景与无引用素材.md) | Historical Change Record（产品确认不会换回旧背景，`assets/images/bg01.png`（1.12 MiB）**删除**，`unused_assets_test` 里那条断言**反向**——原来是「必须还在 + 认领注释还在」，现在是「不许再出现」，`parked` 白名单随之清空。删前先复核两端确是同一张：小程序在用的 `oss.boltfox.cn/prodFile/202608211340094498724.jpg` 与 `assets/images/bg02.jpg` **sha256 一致**（1,016,886 字节 / 1159×2535），铺法 `BoxFit.cover` ≡ `aspectFill`。**顺带清掉另外 13 张无引用素材**（31.5 KB）——四张 `tabbar-*.svg`（⚠️ 端上活着的是**同名 `.png`**，没删；本仓没有 SVG 依赖）、`mine-icon01/02/03` 与 `mine-icon-right`（⚠️ 现用的是 `mine-icon04~07`）、`radio-button-icon01/02`、`search-icon01`、`pay-wechat.png`、`device-detail-screen-size.svg`（详情页那枚图标是 `_ScreenSizePainter` 画的，坐标原件在小程序仓库）。其中 **11 张是当天 `b1ab4ad` 刚加回来的**（08-21 已作为孤儿删过一次），同批 `1cc0efe` 还删了两张**小程序专用**的 `*-bg-placeholder.jpg`，像是把小程序 assets 往这边同步过一次——⚠️ **根因没查，同步流程若还在下次还会再进来一批**。顺带把 11 个文件里**写着 bg01、实际早就是 bg02** 的过期注释一并改口（闪屏/登录/改邮箱/我的相册/首页/更新页/loading 文案/根节点转场），并补清 `home-bg01/02.png`（卡面+投影底图，08-21 已删）与页面背景 `bg01/bg02` 是**两组不同文件**。`assets/images` **141 个/3183.1 KB → 128 个/3151.6 KB**（合计 −1.15 MiB）。⚠️ **未编译未真机**） |
| [`history/2026-08/2026-08-27-安卓PayPal支付对接.md`](history/2026-08/2026-08-27-安卓PayPal支付对接.md) | Historical Change Record（**口径变更**：支付渠道按端分工——小程序=微信支付(1)、**安卓=PayPal(3)**、iOS=Apple 内购(2) 仍未接，推翻此前「App 两端都走 IAP」的写法。安卓补齐购买链路：`getGoodsList` → `addOrder` → **`POST /Client/Pay/setCreatePay`**（⚠️ 小程序没走过这一步，它那边 `addOrder` 直接回微信签名三件套，故接口矩阵里查不到、无可对照实现）→ 外跳 `payPalApproveUrl` → 回到 App **轮询余额确认到账**。⚠️ **铁律：不拿「用户跳回来了」当成功**——approve 只是授权、点取消也会跳回来，唯一可信判据是**服务端余额变多**（退避 ~9.4s，与小程序 `CONFIRM_DELAYS` 逐值相同）；超时**不说失败**，改查 `getPayQuery` 分成「已付款稍后到账」（⚠️ `payState` 枚举后端未给，只认 1）与「结果确认中」。回跳靠 `AppLifecycleState.resumed` + 「我已完成支付」手动兜底（后端 `return_url` 不是 App scheme）；外部浏览器而非内嵌 WebView（PayPal 风控拒内嵌登录），配套在 `<queries>` 补 http/https VIEW 意图（Android 11+ 不声明则「点了没反应」，顺带修好既有的 APK 下载跳转）。✅ **capture 后端在回调里做**（确认于当日；那是要商户 secret 的 PayPal 服务端 API，端上不调——`links` 里的 `rel:"capture"` 一概不解析），⚠️ 代价是到账走「PayPal 回调 → 后端 capture → 入账」两跳，9.4s 窗口需联调实测，兜不住的表现是一片「结果确认中」。⚠️ **仍待确认**：`setCreatePay` 出参形状（文档写 `payPalApproveUrl`、后端样例却给 PayPal 原始 `id`/`status`/`links[]`——端上**两种都认**，认错的表现是「200 却提示未能拉起支付」）、`return_url` 配什么、套餐 `amount` 对 PayPal 的币种。⚠️ **未编译未真机未联调**） |
| [`history/2026-08/2026-08-28-App跟随系统语言.md`](history/2026-08/2026-08-28-App跟随系统语言.md) | Historical Change Record（**App 端独有**：冷启动语种由写死的简体中文改为**跟随手机系统默认语言**，不在四语种内一律**兜底英文**——新增 `lib/src/shared/l10n/system_language.dart`（`zh/zh-CN/zh-SG/Hans`→简中；`Hant`**或** TW/HK/MO→繁中，两条并列是因为部分安卓机只报地区不报脚本；`en*`/`ja*` 按前缀；其余→英文）。生效顺序三层：用户在「语种设置」存过的 `app_language` > 系统语言 > 英文；**跟随系统时不写盘**（写了就等于替用户做了选择），运行期改系统语言走 `didChangeLocales`、先查偏好再决定跟不跟。⚠️ 初始语种在 `_state` 的**字段初始化处**就定（不是 initState 的异步回调），否则英文系统用户首帧会先闪一屏简中；`PhotoFrameState.seeded()` 同时把 `ApiSession.setLanguage` 一并对齐，不然是英文外壳配简中后端文案。🔶 与小程序**有意不同**：小程序 `utils/language.js` 兜底 `zh-Hans`，App 兜底英文，小程序侧本轮不动。测试：新增 `test/system_language_test.dart`；⚠️ `test/widget_test.dart` 两个断言中文的老用例必须显式钉 zh-CN（测试环境默认 en-US）。⚠️ **未编译未真机**）|
| [`history/2026-09/2026-09-01-图片详情整图可见同步.md`](history/2026-09/2026-09-01-图片详情整图可见同步.md) | Historical Change Record（**两端同一轮**，官方图库·图片详情：① 白卡不再压住图片下沿 —— `spacerHeight` 由 `heroHeight - 屏高*0.03` 改 `heroHeight`，那 3% 是设计稿的「圆角压图」，压住的正是图的下沿；② **整张图要看得全** —— 大图 `Positioned` 垫在滚动区下面、**不跟着滚**，一屏放不下的部分等于永远看不到，故新增 `_kCardMinHeight = 210`（内边距16+标题/收藏行36+简介11+两行45+让开贴底按钮98，另加 `padding.bottom`；与小程序 `--detail-card-min: 420rpx` 同一笔账）并把大图高度封顶在 `屏高 − (210 + 安全区)`；⚠️ 配套 `fit` 必须由 `BoxFit.cover` 改 **`BoxFit.contain`** —— 封顶后盒子比例不再等于图片比例，cover 会放大填满再裁两边，把 08-13「不裁图」的结论又推翻，空档由外层 `ColoredBox(0xFFDFE3E9)` 兜底（与小程序 `.detail-hero` 同色）；③ **App 独有的一条**：白卡 `minHeight` 由写死的 `size.height * 0.45` 改 `size.height - spacerHeight`，横图（图矮、留白也矮）时白卡下沿原来会停在屏幕中段、底下露出一条页面米色、贴底按钮浮在米色上。⚠️ **有意不同步**：小程序留白还要减一个实测导航高度（那边大图从屏幕顶端起算、滚动区从导航栏下沿起算，2026-08-21 修的断层），App 两者同在一个 `Stack`、同起点，别照抄。⚠️ 取舍：矮屏（屏高 ≤ 667）上连 3:4 兜底图也会被封顶，两侧各留约 14~16 的灰底。版式不变量由小程序侧 `tests/gallery-detail-hero.test.js` 守着，App 这边没有单独用例。⚠️ **未编译未真机**：本机无 Flutter SDK，`dart analyze` / `flutter test` 均未跑） |
| [`history/2026-09/2026-09-01-首页六宫格文案适度放大.md`](history/2026-09/2026-09-01-首页六宫格文案适度放大.md) | Historical Change Record（**仅 App 端**，iOS 真机走查：首页 3×2 六宫格的卡片文案偏小、而卡里还有余量。标题基准字号 13 → **15**（2026-08-31 为治英文截断顺手缩的那一号放回来）——⚠️ 这是**上限不是最终值**：`_entryTitleFontSize` 仍按最长标题算六张卡的共用字号，而「放得下的最大值」= 可用宽 ÷ 单位字号宽度、**与基准无关**，所以抬基准对任何语言**只会不变或变大**（日文「マイアップロード」照旧压在 ≈11.5，一个像素不动），不可能新增截断。副标题新增 `_entrySubtitleFontSize`：与标题同口径（六张共用、不许出「...」）但方向相反 ——**从上限 11 往下试、第一个「六条都能在两行里放下」的字号就是答案，一个都试不成退回基准 9**（退回时与改前逐像素相同）。⚠️ 副标题不能照标题按宽度比例反推：它最多两行、会换行，「两行装不装得下」由词边界决定，故改用 `TextPainter(maxLines:2)` + `didExceedMaxLines` 实测，可用宽度取含箭头的 `subtitleHorizontalReserve`，参与计算的名单跟着两个灰度开关走。顺手补一处：两处 `TextPainter` 都带上 `textScaler: media.textScaler` —— 原来按「不缩放」量宽度，用户调大系统字体后真实文字比量出来的宽、照样会被截，而这条算式的全部意义就是不截。🔶 **小程序有意不动**：`.entry-name` 是 28rpx、按屏宽等比，390 屏上本就是 14.6，这轮改的正是把 App 补到同一观感。⚠️ **未编译未真机**：本机无 Flutter SDK） |
| [`history/2026-09/2026-09-01-安卓六宫格副标题降一号.md`](history/2026-09/2026-09-01-安卓六宫格副标题降一号.md) | Historical Change Record（**仅 App 端、且只影响安卓**：首页 3×2 六宫格的**第二行文案（副标题）安卓再小一号，iOS 保持不变**。上一轮把副标题从写死的 9 改成「放得下就往上长、最多 11」，iOS 真机正合适、安卓同一个 `fontSize` 显得更满（两端字体不同：SF vs Roboto/思源）。新增 `_entrySubtitleAndroidDelta = 1`，在 `_entrySubtitleFontSize` 的**三个返回点**统一减掉；⚠️ 减法放在**最后一步**，`TextPainter` 量的仍是未减的字号 —— 量出来的是「两行放得下的最大值」，比它小必然也放得下，所以**只减不加、不可能新增「...」**，六张卡仍共用同一个值；⚠️ 差值加在**最终值**上而不是把上限/基准各减 1 —— 若改成「从 10 往 8 试」，某些语种会落成「iOS 10.5 / 安卓 10」只差半号，不是需求那一档；⚠️ 平台判断用 `Theme.of(context).platform` 而非 `Platform.isAndroid`（纯布局计算，可被测试覆盖，不依赖进程环境）。标题字号与 `entrySubtitle` 基准 9 都没动，卡内高度只会更矮。🔶 小程序不动。⚠️ **未编译未真机**） |
| [`history/2026-09/2026-09-01-安卓六宫格副标题中文不换行.md`](history/2026-09/2026-09-01-安卓六宫格副标题中文不换行.md) | Historical Change Record（**仅 App 端、且只影响安卓**：首页 3×2 六宫格副标题**再缩一档，保证中文不换行；英文仍是两行完整展示**。上一轮那个「安卓减一号」是观感档位、不是几何约束 —— 中文最长一条约 7 个字身宽，360dp 屏上可用宽只有 ≈65，10 号要 ≈70，于是「拍摄照片并投屏」被折成两行。本轮把 `_entrySubtitleFontSize` 拆成两步：第一步两端共用（两行放得下的最大字号，安卓再减一号，**与上一轮逐像素相同**），第二步**仅安卓**从第一步的结果继续往下试、第一个「六条都能单行装下」的字号就是最终值。⚠️ 第二步**从第一步结果起步往下**，所以只会更小或不变；⚠️ 第二步返回量出来的字号本身、**不再减一次** `_entrySubtitleAndroidDelta`（起点已减过，再减就成「小两号」），下限仍是 `基准 9 − 1 = 8`，安卓最终值恒在 8~10；⚠️ 卡片 `maxLines` **仍是 2 没改成 1** —— 中文不换行靠选字号、不靠砍行数，砍成 1 行会把英文重新截成半句（08-31 治过的毛病）。英文/日文一行怎么都放不下（"Generate images with AI" 8 号就要 ≈90 宽），第二步一路试空、原样返回，**与上一轮逐像素相同**；iOS 在第二步之前就 return，四种语言全不变。量文字抽成 `_subtitlesFitInLines`（两步共用，只差 `maxLines`，仍带 `textScaler`）。⚠️ **已知边界**：320dp 及更窄的屏（中文单行要 ≤7.4 号）与用户放大系统字体时会跌破下限 8，回落成上一轮的两行行为、不再往下砸字号。顺手订正 `subtitleHorizontalReserve` 上那句「副标题不参与字号计算」的过期注释。🔶 小程序不动。⚠️ **未编译未真机**） |
| [`history/2026-09/2026-09-01-安卓六宫格副标题再降一号.md`](history/2026-09/2026-09-01-安卓六宫格副标题再降一号.md) | Historical Change Record（**仅 App 端、且只影响安卓**：首页 3×2 六宫格副标题在上一轮两步算出来的结果上**再统一减一号**，中文照旧单行、英文照旧两行完整，只是整体小一档；iOS 一个像素不动。新增 `_entrySubtitleAndroidFinalDelta = 1`，作为 `_entrySubtitleFontSize` 的**第三步**、放在两步量文字之后。⚠️ **不能改成把 `_entrySubtitleAndroidDelta` 从 1 调到 2** —— 第二步挑的是「一行装得下的**最大**字号」，360dp 上那个最大值就是 9，把第一步的差值调大只是让第二步的**起点**从 10 降到 9、挑出来的还是 9，结果成了「英文小一号、中文原地不动」，不是需求那一档；差值必须加在**两步都走完之后**。配套把第二步的 `return size` 改成 `result = size; break;`，让两条出路汇到同一个出口，第三步只写一次；`available <= 0` 那个兜底出口一并减，`finalDelta` 在 iOS 上恒为 0 所以所有出口都能无脑减。⚠️ 仍是**只减不加**：比「两行放得下」的字号更小必然还是两行放得下、比「一行放得下」的更小必然还是一行放得下，既不新增「...」也不会把中文重新顶成两行；`maxLines` 仍是 2、基准 9 与标题字号都没动。实测预期（中文）：360dp 9→**8**、384/390/412dp 10→**9**，全部仍单行。⚠️ **已知边界**：下限从 8 降到 `9−1−1=7`，320dp 及更窄的屏或放大系统字体时会落到那里、中文回落两行（但不出「...」）。🔶 小程序不动。⚠️ **未编译未真机**） |
| [`history/2026-09/2026-09-01-安卓六宫格副标题再小两号.md`](history/2026-09/2026-09-01-安卓六宫格副标题再小两号.md) | Historical Change Record（**仅 App 端、且只影响安卓**：首页 3×2 六宫格副标题在上一轮的结果上**再小两号**，中文照旧单行、英文照旧两行完整；iOS 一个像素不动。需求原文那两句「保证中文不换行、英语二行可以展示完整」上一轮起就已经是算式自带的不变量（第二步挑「一行装得下的最大字号」、第三步只做减法），所以本轮真正要动的只有「副标题安卓端需要再小二个字号」—— 改动就是 `_entrySubtitleAndroidFinalDelta` **1 → 3**（第四轮 1 + 本轮 2），一行代码，三个出口的结构都没动。⚠️ **仍然不能改成把 `_entrySubtitleAndroidDelta` 从 1 调到 3** —— 第二步挑的是「一行装得下的**最大**字号」，360dp 上那个几何上限就是 9，调大第一步的差值只是压低第二步的**起点**、挑出来的还是 9，结果成了「英文小两号、中文原地不动」；差值必须加在**两步都走完之后**。⚠️ 三条不变量不变：只减不加故不新增「...」、比「一行放得下」的字号更小仍是一行、六张卡仍共用一个值；`maxLines` 仍是 2、基准 9 与标题字号都没动。实测预期（中文）：360dp 8→**6**、384/390/412dp 9→**7**，全部仍单行；英文/日文只是整体小两号、仍两行完整。⚠️ **已知边界（本轮要真机复看的一条）**：下限从 7 降到 `9−1−3=5`，而 360dp 上中文落到 **6**，已是设计稿 `.entry-desc`（18rpx≈9）的三分之二，**贴着可读性下沿**，再要小建议改口径（放宽中文两行、或给副标题设绝对下限）而不是继续加这个差值。🔶 小程序不动。⚠️ **未编译未真机**） |
| [`history/2026-09/2026-09-02-安卓六宫格副标题回调一号.md`](history/2026-09/2026-09-02-安卓六宫格副标题回调一号.md) | Historical Change Record（**仅 App 端、且只影响安卓**：上一轮一次性调小的两号被真机否掉一号 —— 首页 3×2 六宫格副标题**回调一号**，`_entrySubtitleAndroidFinalDelta` **3 → 2**（第四轮 +1、第五轮 +2、本轮 −1），安卓最终字号 5~7 → **6~8**；iOS 一个像素不动。上一轮那份记录里预警的「360dp 上中文落到 6、已是设计稿 `.entry-desc`（18rpx≈9）的三分之二、贴着可读性下沿」被产品复看证实。⚠️ **方向反了但仍然安全**：前五轮的论证是「只减不加」，这轮得换个说法 —— `result` 是第一/二步**量出来的**「放得下的字号」，最终值 `result - finalDelta` 只要差值 ≥ 0 就**永远不越过它**，把 3 收到 2 只是更靠近那条几何上限，中文照旧单行、英文照旧两行完整、不出「...」；真正不能碰的是 `result` 本身。⚠️ **仍然不去动 `_entrySubtitleAndroidDelta`**：把它从 1 调到 0 只是把第二步的**起点**从 10 抬到 11，往下试命中的仍是那条几何上限 9，中文一个像素不动、只有英文变大。实测预期（中文）：360dp 6→**7**、384/390/412dp 7→**8**，全部仍单行；下限从 5 回到 `9−1−2=6`。两端对照：iOS 9~11、安卓 6~8，安卓仍比 iOS 小 3 号。🔶 小程序不动。⚠️ **未编译未真机**） |
| [`history/2026-09/2026-09-02-安卓六宫格副标题再回调一号.md`](history/2026-09/2026-09-02-安卓六宫格副标题再回调一号.md) | Historical Change Record（**仅 App 端、且只影响安卓**：真机复看仍嫌小，首页 3×2 六宫格副标题**再回调一号**，`_entrySubtitleAndroidFinalDelta` **2 → 1**（第四轮 +1、第五轮 +2、09-02 两次回调各 −1，净值 1），安卓最终字号 6~8 → **7~9**；iOS 一个像素不动。⚠️ **走了一圈又回到 09-01 第四轮那一档**（与那一轮逐像素相同）——09-01 第五轮那「再小二个字号」是一次性调过头（360dp 上中文被压到 6，只有设计稿 18rpx≈9 的三分之二），09-02 分两次退回来；四轮里口径没变过，动的只有档数。⚠️ **0 是这条路的终点**：安全论证是「`result` 是量出来的『放得下的字号』，最终值 `result - finalDelta` 只要差值 ≥ 0 就不越过它」，**差值变负这条论证就断了**（中文重新折行、英文重新出「...」）。下一轮若还嫌小的四条出路写在文档第二节的表里：本常量 1→0（取消第三步、退回 09-01 第三轮，安卓 8~10）；`_entrySubtitleAndroidDelta` 1→0（两端同号 9~11）；动 `_entrySubtitleMaxFontSize`/基准（两端一起变，但英文/日文可能一个像素不动 —— 它们本就顶在几何上限上）；❌ 不要把本常量设成负数。实测预期（中文）：360dp 7→**8**、384/390/412dp 8→**9**，全部仍单行；下限从 6 回到 `9−1−1=7`。两端对照：iOS 9~11、安卓 7~9，小 2 号。🔶 小程序不动。⚠️ **未编译未真机**） |
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
