# 2026-07-19 操作指南 / 常见问题 五项反馈（App + 小程序双端）

> 本机无构建链，**静态实施未编译**。合入前请在开发机执行 `flutter analyze` + `flutter test`，
> 小程序侧用微信开发者工具真机预览。

接口事实全部以 swagger 为准（`https://api.boltfox.cn/v2/api-docs`，v3 返回 500）：

- `ClientProductFaqApiOut` = `faqId` / `faqTitle` / `faqContent`（**列表就带 content**）
- 分页壳 `BasePageOutput` = `pageData` / `pageCount` / `recordCount` / `pageIndex` / `surplusCount`
- 入参 = `pageIndex` / `pageSize`(默认10) / `keyword` / `startDate` / `endDate` + 公共的 `terminal`/`language`/`device`/`userToken`
- `language`：0=英语, 1=英语, 2=简中, 3=繁中, 4=日文
- **权重 `grade` 只在后台 DTO `ProductFaqApiOut`**，Client 侧取不到
- Client 侧**没有 productId 参数**；query 里的 `device` 是手机机型串，不是设备分类

---

## 1. 全额读取常见问题（不区分设备，按权重排序）

**改法**：两端都改成按分页元数据**翻页读完全部**，不再只发一页。

停止条件的顺序很关键（这也是「只显示几条」的成因）：

1. 空页 → 停
2. `recordCount > 0 && 已收集 >= recordCount` → 停
3. `pageCount > 0 && pageIndex >= pageCount` → 停
4. **两个元数据都缺**时，才退回「返回条数 < 请求 pageSize 即最后一页」

> ⚠️ 不能把第 4 条当主判据：后端可能**无视** `pageSize` 按自己的默认 10 条分页，
> 第一页就 `10 < 50` → 直接停 → 只拿到 10 条。

另配 `MAX_PAGES = 20` 死循环闸（触顶时 App 侧 `debugPrint` 告警），并按 `faqId` 去重
（翻页之间后端顺序可能变动）。

- **不区分设备**：Client 侧接口本就没有 productId，代码里也不加任何过滤条件。
- **按权重排序**：`grade` 前端拿不到 → **排序是后端的责任**，前端原样保留返回顺序、不做客户端重排。

落点：`lib/src/state.dart` `refreshFaq()` / `subpackages/settings/guide/guide.js` `fetchAllFaq()`

## 2. 操作指南支持超出屏幕后滑动

- **小程序**（原本裁掉且滚不动）：`guide.json` 有 `disableScroll:true`，`.settings-shell` 又是
  `overflow:hidden`，页面级滚动本就滚不了。改为 `scroll-view` 承载列表：
  `.guide-shell` 竖向 flex + `.guide-scroll{flex:1;min-height:0}`。
  **`min-height:0` 不能少**——flex 子项默认 `min-height:auto`，会被内容撑高而滚不起来。
  底部 `margin-bottom: calc(var(--safe-bottom) + 24rpx)` 避开 Home Indicator。
- **App**：原本就是 `Expanded > SingleChildScrollView`，无需改动（已复核无裁剪）。

## 3. App 未识别 `<p>` 等 HTML 标签

小程序用微信原生 `rich-text` 正常；App 之前直接把 `faqContent` 塞进 `Text`，标签原样显示。

新增 **`lib/src/shared/widgets/simple_html_text.dart`**：零依赖 HTML 子集渲染器。

- 支持：`p/div/br/h1~h6/ul/ol/li/blockquote/hr/tr` + `b/strong/i/em/u/s/del/a/span/font/td`
  + `img`（走 `CachedNetworkImage`）+ 内联样式（color/font-size/font-weight/font-style/
  text-decoration/text-align）+ HTML 实体；丢弃 `script`/`style` 及其内容与注释。
- **没引 `flutter_html`**：本机装不了工具链、无法验证依赖解析，且 FAQ 用到的标签集很窄，
  自绘更可控（也符合「实现取原生最优解」的项目原则）。
- 两个实现要点：
  - 行内样式栈**按标签名弹栈**——富文本编辑器常产未闭合标签（`<p><span>x</p>`），
    无脑 `removeLast` 会把不相干的样式弹掉，导致后续文字串味；
  - **即使无样式也压栈**，否则嵌套 `<span>` 的内层闭合会误弹外层。
- `TapGestureRecognizer` 由 State 持有并 `dispose`（链接可点，失败静默）。
- 纯文本走 `looksLikeHtml()` 短路，仍用普通 `Text`。
- 配套 `test/simple_html_text_test.dart`。

## 4. 取消默认展开

- App：`guide_page.dart` 原来 `initState` 里默认展开首项 + 末项 → 全部移除，默认全收起。
- 小程序：`faqToGuide` 的 `open: index === 0` → `false`；本地兜底数据里两条 `open: true` → `false`。

## 5. 语种切换后按新语种取数并刷新

**App**（`language` 本来就注入 header+query，缺的是缓存失效）：

- `state.dart` 增 `_faqLanguage` + `faqNeedsRefresh`；**打标用请求发起时捕获的语种**，
  不能用 await 结束后的 `_language`（翻页要好几个 RTT，期间切语种会把旧内容标成新语种，
  页面就再也不补拉了）。
- `guide_page.dart` 用 `didChangeDependencies` + `AppLocalizationsScope.languageOf(context)`
  登记依赖：**进入页面**和**停留期间切换语种**都会重拉，并清空展开态。
- 拉取期间又切语种 → 拉完对比 `state.language`，不一致再拉一遍（比较同一个值，失败返回不会空转重试）。
- 缓存语种与当前语种不一致时显示 loading，**不闪一屏旧语种文案**。

**小程序**（问题更靠前：语种选择根本没生效）：

- 原 `saveLanguage()` 只弹「已保存」，**选择从不落盘**；`getLanguageCode()` 只读系统语言
  → 用户选的语种对后端返回什么语种完全无效。
- 新增 **`utils/language.js`** 作单一数据源：落盘 `appLanguage`，取值优先用户选择、其次系统语言；
  `utils/request.js` 与 `utils/system.js` 改为转发（此前这两处各有一份互相打架的映射，
  `system.js` 那份还漏了 `ja`，且登录上报发字符串而请求层发数字）。
- 语种设置页现在会回显当前语种，并在保存时落盘。
- `guide.js` 的 `onShow` 比对语种，变了就重拉（覆盖「切完语种再进操作指南」的场景）。

**两端共同**：请求成功即以后端为准，**返回空也要清列表**（否则旧语种残留冒充新语种）；
只有请求**抛错**才保留现有/内置兜底文案，此时不写语种标记，下次进页面会重试。
App/小程序均补了空态与加载态文案。

---

## 改动文件

**App（flutter/）**

| 文件 | 改动 |
| --- | --- |
| `lib/src/shared/widgets/simple_html_text.dart` | 新增，零依赖 HTML 子集渲染器 |
| `lib/src/features/guide/presentation/guide_page.dart` | 默认收起、语种感知重拉、HTML 渲染、空/加载态 |
| `lib/src/state.dart` | `refreshFaq` 全量翻页 + 语种打标；新增 `_faqLanguage`/`faqNeedsRefresh` |
| `lib/src/shared/l10n/app_l10n.dart` | 新增 `guideEmpty` |
| `test/simple_html_text_test.dart` | 新增解析用例 |
| `docs/接口清单.md`、`docs/app-vs-miniprogram-sync.md` | 同步「不分设备/全量/权重归后端」的定版 |

**小程序（photo-album/）**

| 文件 | 改动 |
| --- | --- |
| `utils/language.js` | 新增，语种单一数据源（落盘 + 优先用户选择） |
| `utils/request.js` | `getLanguageCode` 改为转发 language 模块，删除本地重复映射 |
| `utils/system.js` | 语种逻辑转发到 language 模块（补齐 ja） |
| `subpackages/settings/language/language.js` | 保存时真正落盘；进入时回显当前语种 |
| `subpackages/settings/guide/guide.{js,wxml,wxss}` | 全量翻页、默认收起、scroll-view 滚动、空/加载态、onShow 按语种重拉 |
| `docs/接口清单.md` | 同上 |

## 待验证（开发机）

- `flutter analyze` + `flutter test`（含新增的 `simple_html_text_test.dart`）。
- 真机：切换 简中/繁中/英/日 后进操作指南，确认条目与语种一致、条数为后端全量。
- 后端返回的 `faqContent` 实际标签集：若出现本渲染器未覆盖的标签（如表格布局），按需扩展。
- **需后端确认**：常见问题是否已按 `grade` 权重排序返回（前端不再重排）。
