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
          --JS--> boltstar://pay/paypal/return?token=..&PayerID=..
          --> 安卓 PayPalRedirectActivity（记一次性标记 + 把 App 原任务提回前台）
          --> 确认购买页 resumed 时读走
          --> GET /Client/Pay/getPayPalNotify?token=..&PayerID=..
              （**后端据此 capture 扣款、入账**）
          --> 照旧轮询余额确认到账

用户取消：PayPal --302--> https 中转页 --JS--> boltstar://pay/paypal/cancel
          --> 当场提示「已取消支付」，不走轮询
```

### ⚠️ 中间那个 https 页不能省

别改成让 PayPal 直接 302 到 `boltstar://`，两个原因：

1. PayPal 对 `return_url` 按 URI 校验，**非 http(s) 收不收没有保证**。被拒的表现是
   `setCreatePay` 当场失败、连授权页都拿不到 —— 整条链在最前面就断了。
2. 更要命的是 **Chrome 会拦掉「服务端 302 直跳自定义 scheme」**这种非用户手势的外跳，
   表现是用户停在空白页、**什么都不发生且不报错**。

中转页里的跳转属于页面内导航，绕开了这条限制；安卓还能用 `intent://` 写法；
拉不起 App 时页面还能给一句「请返回 App 查看」的兜底。

## 二、部署

把两个文件放到 https 站点上，默认路径：

```
https://<域名>/pay/paypal/return.html
https://<域名>/pay/paypal/cancel.html
```

域名/路径换了**不用改代码**，打包时覆盖即可（默认值指向 `badmin.boltfox.cn`）：

```bash
--dart-define=PAYPAL_RETURN_URL=https://实际域名/pay/paypal/return.html
--dart-define=PAYPAL_CANCEL_URL=https://实际域名/pay/paypal/cancel.html
```

### 五个注意点

| # | 注意点 |
| --- | --- |
| ① | **路径必须与 App 传的一致**。两处对不上时表现为「PayPal 跳到 404，用户停在错误页」。 |
| ② | ⚠️ **最容易踩的：SPA 的 catch-all 会把它吃掉。** 放在 `badmin.boltfox.cn` 这类管理后台域名下时，nginx 大概率有 `try_files $uri /index.html` 的兜底——那样访问中转页返回的是后台首页 HTML，脚本根本不执行。**要在 SPA 规则之前把 `/pay/paypal/` 前缀排除掉。** |
| ③ | **必须 https 且证书有效**。PayPal 只接受 http(s)，浏览器对混合内容也会拦。 |
| ④ | **页面不许有任何外部依赖**。现在是纯内联 HTML+CSS+JS，没有 CDN、字体、图片。用户此刻在海外网络、刚付完钱，多一个外部请求就多一分失败——**别顺手加统计脚本**。 |
| ⑤ | **页面不调任何后端接口**。capture 已约定由 App 调 `getPayPalNotify` 完成，中转页多调一次等于对同一单**重复 capture**。 |

### 页面自带的兜底（改页面前先读这段）

- 安卓走 `intent://`（成功率最高）；`browser_fallback_url` 指回本页的 `#manual`，
  拉不起来时**不会跳应用商店**，而是回到本页显示「返回 App」按钮（`#manual` 不再自动跳，不成环）。
- 2.5 秒仍停在本页也会显示那颗按钮。**手动点击属于用户手势**，浏览器对外跳限制最松，
  成功率比自动跳高得多。
- 文案**不写「支付失败」**：那一刻钱多半已经授权成功，只是 App 没被唤起。

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
https://<域名>/pay/paypal/return.html?token=TESTTOKEN&PayerID=TESTPAYER
```

应当自动拉起 App。**如果看到的是管理后台首页 → 就是注意点 ② 那个 catch-all 问题。**

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
[PayPal] getPayPalNotify 返回 paid=true ...
[PayPal] 到账确认：+N（orderNo=...）
```

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
| PayPal 跳过去是 404 / 后台首页 | 部署路径不对，或 SPA catch-all（注意点 ①②） |
| 停在中转页、按钮点了也没反应 | 深链没接上：核对 `AndroidManifest.xml` 的 `PayPalRedirectActivity` 与 `StarPurchase.appReturnLink` 是否逐字一致（`test/star_purchase_test.dart` 有一条测试专门比对这两处） |
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
