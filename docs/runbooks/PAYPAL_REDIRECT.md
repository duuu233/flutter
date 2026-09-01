# PayPal 支付回跳中转页：部署与联调

> 文档类型：Release / Integration Runbook
> 状态：Active
> 建立：2026-08-31
> 页面源码：`deploy/paypal/return.html`、`deploy/paypal/cancel.html`（独立目录，**不参与 App 构建**）
> 端上落点：`lib/src/features/star/star_purchase.dart`、`android/.../PayPalRedirectActivity.kt`
> 相关：接口口径见 [`../architecture/API_INTEGRATION.md`](../architecture/API_INTEGRATION.md)「星币（Order / Pay）」一节；
> 打包命令见 [`BUILD_RELEASE.md`](BUILD_RELEASE.md)

## 一、这两个页面是干什么的

PayPal **唯一**会把用户送回来的机制，就是授权/取消之后把浏览器重定向到建单时传给它的
`return_url` / `cancel_url`。所以「支付完怎么回 App」这个问题，等价于「这两个 URL 填什么」。

我们填的是**自己的 https 中转页**，中转页再用 `boltstar://` 深链把 App 拉起来：

```
授权成功：PayPal --302--> https 中转页?token=..&PayerID=..
          --> ① 中转页自己调 GET /Client/Pay/getPayPalNotify?token=..&PayerID=..
              （**后端据此 capture 扣款、入账**）
          --> ② 跳 boltstar://pay/paypal/return?token=..&PayerID=..&notified=1
              （retCode=200 时才带 notified=1）
          --> 安卓 PayPalRedirectActivity（记一次性标记 + 把 App 原任务提回前台）
          --> 确认购买页 resumed 时读走；带 notified=1 就跳过自己那次通知
          --> 轮询余额确认到账

用户取消：PayPal --302--> https 中转页 --JS--> boltstar://pay/paypal/cancel
          --> 当场提示「已取消支付」，不走轮询、也不调任何接口
```

### ⚠️ capture 为什么放在中转页而不是 App

**这样 capture 不依赖 App 能不能被拉起来。** 深链失败、用户手动切回 App、甚至进程被杀，
钱都已经扣了、星币已入账，App 那边照常靠「余额变多」确认得到。
这是本页最大的价值 —— 也大幅缓解（但没根治）第五节那个「用户不回 App 就不扣款」的风险。

**但不能只靠页面**：那次 fetch 可能被跨域拦掉、断网、或后端回非 200。所以：
retCode=200 才在深链上带 `notified=1`；**没带标记时 App 会自己再调一次**。
两条路互为兜底，正常情况下只有一条真的 capture。

✅ **不涉及跨域**：页面与接口同域名，那次 fetch 走相对路径。
（若将来把页面挪到别的域名，就得给 `getPayPalNotify` 加 `Access-Control-Allow-Origin`；
不加也不会崩 —— fetch 被拦 → 不带 notified → App 补调，只是 capture 晚一步。）

### ⚠️ 中间那个 https 页不能省

别改成让 PayPal 直接 302 到 `boltstar://`，两个原因：

1. PayPal 对 `return_url` 按 URI 校验，**非 http(s) 收不收没有保证**。被拒的表现是
   `setCreatePay` 当场失败、连授权页都拿不到 —— 整条链在最前面就断了。
2. 更要命的是 **Chrome 会拦掉「服务端 302 直跳自定义 scheme」**这种非用户手势的外跳，
   表现是用户停在空白页、**什么都不发生且不报错**。

中转页里的跳转属于页面内导航，绕开了这条限制；安卓还能用 `intent://` 写法；
拉不起 App 时页面还能给一句「请返回 App 查看」的兜底。

## 二、部署

✅ **2026-09-01 已部署**，两个页面就放在 **API 同一个域名**下：

```
https://api.boltfox.cn/return.html    ← deploy/paypal/return.html
https://api.boltfox.cn/cancel.html    ← deploy/paypal/cancel.html
```

⚠️ **同源是有意的，别再挪走**：`return.html` 要自己调 `GET /Client/Pay/getPayPalNotify`
触发 capture。放在别的域名下就成了跨域请求，得让后端专门给这个接口放行 CORS；
同源则一行配置都不用（页面里那次 fetch 走的是**相对路径**）。
中途试过 `pp.boltfox.cn` 这个独立域名，就是为了免掉 CORS 才并回 API 域名的。

这两个地址已写进 `StarPurchase.returnUrl` / `cancelUrl` 的默认值，**正常打包不必再传 dart-define**。
换域名/路径时也不用改代码：

```bash
--dart-define=PAYPAL_RETURN_URL=https://实际域名/return.html
--dart-define=PAYPAL_CANCEL_URL=https://实际域名/cancel.html
```

> 放在 API 域名下同时也绕开了下面注意点 ② 那个坑（那台机器不跑 SPA）。

### 六个注意点

| # | 注意点 |
| --- | --- |
| ① | **路径必须与 App 传的一致**。两处对不上时表现为「PayPal 跳到 404，用户停在错误页」。 |
| ② | ⚠️ **别把它挂到跑着 SPA 的域名下。** 那类站点的 nginx 大概率有 `try_files $uri /index.html` 的兜底——访问中转页返回的会是 SPA 的首页 HTML，脚本根本不执行，表现是「PayPal 跳过去看到的是别的站点首页」。当前放在 API 域名下（不跑 SPA）已规避。 |
| ③ | **必须 https 且证书有效**。PayPal 只接受 http(s)，浏览器对混合内容也会拦。 |
| ④ | **页面不许有任何外部依赖**。现在是纯内联 HTML+CSS+JS，没有 CDN、字体、图片。用户此刻在海外网络、刚付完钱，多一个外部请求就多一分失败——**别顺手加统计脚本**。 |
| ⑤ | **`return.html` 只调 `getPayPalNotify` 这一个接口**（`cancel.html` 一个都不调）。别再往里加别的调用：页面跑在支付回来的关键路径上，多一个请求就多一分失败。 |
| ⑥ | **两个页面必须与 API 同域名**（现在都在 `api.boltfox.cn`）。挪走就成跨域，得给 `getPayPalNotify` 加 CORS —— 不加不会崩，但 capture 会退回由 App 补调、晚一步。 |

### 页面自带的兜底（改页面前先读这段）

- 安卓走 `intent://`（成功率最高）；`browser_fallback_url` 指回本页的 `#manual`，
  拉不起来时**不会跳应用商店**，而是回到本页显示「返回 App」按钮（`#manual` 不再自动跳，不成环）。
  回跳时结果也一并带回来（`#manual-paid`）——那时**不能再调一次 `getPayPalNotify`**（会重复 capture），
  不带的话回到本页就只能显示「处理中」。
- 2.5 秒仍停在本页也会显示那颗按钮。**手动点击属于用户手势**，浏览器对外跳限制最松，
  成功率比自动跳高得多。
- 只用 `visibilitychange` / `pagehide` 判断「App 是否已被拉起」，**不认 `blur`**：
  系统那个「要打开 App 吗」的确认框也会让本页 blur，用户点「取消」时什么都没发生。

### ⚠️ 页面上显示的是**支付结果**，不是「跳转结果」（2026-09-01 改）

老版本拉不起 App 时一律显示「支付处理中」，与支付成没成无关 —— 用户和排查的人都以为是**支付**
出了问题，其实那次 `getPayPalNotify` 早就成功了。页面手里就有准信（同源那次 fetch 拿回来的
就是后端 capture 的结论），没道理不说。现在按**三档**措辞：

| 后端响应 | 页面显示 |
| --- | --- |
| `retCode=200` | **支付成功**（绿色）+「星币已到账」 |
| 明确回了非 200 | **支付结果待确认** + **后端原话**（`retMsg` / `exceptionMsg`） |
| 没拿到响应（超时/断网/被拦） | **支付处理中** —— 页面这时确实不知道，不许猜 |

⚠️ 三档都**不写「支付失败」**：重复 capture、回调慢都会回非 200，但钱可能已经扣了。
⚠️ 这不动第六节那条底线：页面这句话只是给用户一个准信，**App 的到账判据仍然是服务端余额变多**。

### 屏幕内调试日志

页面底部有一条「调试日志 (n) ▾」，点开是这次回跳的完整流水（手机上没有 devtools，
链路断在哪只能靠它）。**跳 App 失败时自动展开**；也可以 `?debug=1` / `#debug` 强制展开，
面板里有「复制日志」。记的东西按用途分三样，少一样就定位不了：

- **原始 query 与 UA** —— PayPal 到底带没带 `token`/`PayerID`、当前是什么浏览器内核；
- **HTTP 状态 +「响应原文」** —— 页面故意先 `r.text()` 再自己 `JSON.parse`，
  **不用 `r.json()`**：后端/网关回 HTML（404 页、502 页、SPA 首页）时 `r.json()` 直接抛异常，
  日志里就只剩一句「失败」，看不出是压根没打到接口；
- **每次跳转尝试 + 页面有没有被切到后台** —— 后者是网页里唯一能观测到「深链成没成」的信号。

## 三、联调测试步骤

### 第 1 步：单测深链（不经浏览器，最快验证 App 侧）

App 处于「等待授权」态时执行：

```bash
adb shell am start -a android.intent.action.VIEW -d "boltstar://pay/paypal/cancel"
adb shell am start -a android.intent.action.VIEW -d "boltstar://pay/paypal/return?token=TESTTOKEN&PayerID=TESTPAYER"
```

- 第一条：应弹回 App 并提示「已取消支付」
- 第二条：应弹回 App，日志出现 `[PayPal] 收到授权回跳 token=TESTTOKEN PayerID=TESTPAYER`

### 第 2 步：单测中转页（验证部署，不涉及 PayPal）

手机浏览器直接打开：

```
https://api.boltfox.cn/return.html?token=TESTTOKEN&PayerID=TESTPAYER
```

应当自动拉起 App。**如果看到的是别的站点首页 → 就是注意点 ② 那个 catch-all 问题。**

### 第 3 步：完整沙箱支付

星币页 → 买一档 → 跳 PayPal → 沙箱买家账号登录 → **Continue to Review Order**
→ 应自动弹回 App → 看余额是否变多。

全程盯日志：

```bash
adb logcat -c && adb logcat | findstr /i paypal      # bash: grep -i paypal
```

关键四行，缺哪一行就知道断在哪：

```
[PayPal] setCreatePay 返回 ... approveUrl=有
[PayPal] 收到授权回跳 token=... PayerID=...
[PayPal] 中转页已完成 getPayPalNotify，App 侧跳过，直接确认到账   ← 正常路径
[PayPal] getPayPalNotify 返回 paid=true ...                        ← 页面那次没成，App 补调
[PayPal] 到账确认：+N（orderNo=...）
```

第 3 行出现哪一条，正好说明中转页那次调用成没成 —— 两条都算正常，只是 capture 早晚之别。
⚠️ **测第 2 步（浏览器直开中转页）时会真的触发一次 capture**，别拿真实订单的 token 反复刷。

### 第 4 步：取消流程

同上，但在 PayPal 页面点 **Cancel and return** → 应弹回 App 并**当场**提示「已取消支付」
（不该转 9.4 秒的轮询）。

### 第 5 步：兜底流程（别跳过）

付完之后**不点回跳、直接手动切回 App** → 应走「我已完成支付」/ `resumed` 的余额轮询，
最终也能确认到账。

这条验证的是「中转页失效时链路还活着」，**同时也是验证后端 webhook 的唯一办法**（见下）。

## 四、卡住时怎么定位

| 现象 | 多半是 |
| --- | --- |
| `setCreatePay` 报错 / `approveUrl=(空)` | 后端没接上 `payPalReturnUrl`，或那两个 URL 传给 PayPal 时被拒。看后端日志 |
| PayPal 跳过去是 404 / 别的站点首页 | 部署路径不对，或域名有 SPA catch-all（注意点 ①②） |
| **停在中转页**（无论显示哪一档文案） | 先点开页面底部的**调试日志**——里面直接写着断在哪一步。停在本页 = 深链没生效，与支付成没成无关 |
| 停在中转页、按钮点了也没反应 | 深链没接上：核对 `AndroidManifest.xml` 的 `PayPalRedirectActivity` 与 `StarPurchase.appReturnLink` 是否逐字一致（`test/star_purchase_test.dart` 有一条测试专门比对这两处）。日志里那条 `② 拉起 App：boltstar://…` 就是这次要跳的地址，可直接复制出来用 adb 试 |
| 日志里「响应原文」不是 JSON | 那次 fetch 没打到接口，被静态站/网关接走了（看原文是 404 页还是别的站点首页），对照注意点 ①② |
| 回到 App 了但余额一直不变 | `getPayPalNotify` 没触发 capture。日志里 `paid=` 就是后端给的结论，拿它去问后端 |
| **第 5 步（不点回跳）余额永远不变** | **后端没有 webhook 兜底**，见下 |

## 五、⚠️ 待后端确认：webhook 兜底

按当前设计，**capture（真扣款）是 App 调 `getPayPalNotify` 才触发的**。也就是说：

> 用户在 PayPal 点了同意，但**没跳回 App**（关掉浏览器 / 中转页没拉起 App / 进程被系统回收），
> `getPayPalNotify` 就永远不会被调用 → **capture 不发生 → 钱没扣、星币也不到账**。

用户视角是「我明明点了同意，怎么什么都没有」。

**端上补不了这一段。** 需要后端接 PayPal 的 webhook（收 `CHECKOUT.ORDER.APPROVED`
后自己 capture，不依赖用户跳不跳回来）。第 5 步就是验证它有没有生效的办法。

## 六、一条不能动的底线

**回跳只是把等待缩短，永远不是付款成功的凭据。** 三个原因：用户可能不点回跳直接切回来、
浏览器可能不跳、回跳还可能早于后端入账。

所以到账判据始终是**服务端余额变多**，`AppLifecycleState.resumed` + 「我已完成支付」
+ 9.4s 退避轮询这套兜底**一条都不能撤**。
