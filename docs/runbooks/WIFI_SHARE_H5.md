# WiFi 版设备共享邀请 H5 落地页：部署与对接

> 文档类型：Release / Integration Runbook
> 状态：Draft（页面已写好，待部署；App 侧生成链接与接受页待线上地址确定后再做）
> 建立：2026-11-12
> 页面源码：`deploy/share/share.html`（单文件，App 图标已内联；独立目录，**不参与 App 构建**）
> 相关：现行分享（小程序卡片）见 `lib/src/features/wifi/presentation/wifi_share_page.dart`；同类中转页做法见 [`PAYPAL_REDIRECT.md`](PAYPAL_REDIRECT.md)

## 一、为什么改成 H5 链接

原分享是发微信小程序卡片，打包必须带小程序原始 ID（`WECHAT_MINI_PROGRAM_USERNAME`），没带时「分享设备」置灰。
改成分享一个 https 链接后，App 只需发网页卡片 / 系统分享 / 复制链接，不再依赖小程序原始 ID。

## 二、流程

```
房主 App「分享设备」→ https://<域名>/share.html?d=设备号&p=产品ID&u=房主userId&n=设备名&o=房主昵称&t=分享时间戳

接收者打开链接
  ├ 微信 / 企业微信内：不尝试跳转，遮罩引导「点右上角 ··· → 在浏览器打开（iOS：在 Safari 中打开）」
  └ 浏览器内：进页自动试拉起 App，同时有「打开 App 接受邀请」按钮
        ├ 页面被切到后台 → App 已拉起 → App 接受页完成绑定
        └ 约 2.5 秒仍在本页（安卓 Chrome：intent 回落到 #no-app）→ 判定没装
              → 「下载 BoltStar App」+ 1-2-3 步骤；装好后回本页点「已安装，打开 App」

App 接受页（待做）：没登录先登录 → 是本人分享 / 已在列表 → 提示 / 进详情
  → chkTimeValid(t) → addUserProduct（isToHave=0、shareUserId=u）→ 刷新列表 → 进设备详情
```

- 拉起地址：`boltstar://share/accept?<原 query 整串>`；安卓优先 `intent://share/accept?…#Intent;scheme=boltstar;package=com.boltfox.boltstar;S.browser_fallback_url=<本页>#no-app;end`，900ms 还在本页再试朴素 scheme（国产内核不认 intent）。
- 网页没有可靠的「是否已安装」接口，只能「跳一次 + 看页面有没有被切走」。浏览器拦截了非点击触发的跳转时也会被判成没装，所以「没装」状态仍保留「已安装，打开 App」按钮。
- 页面只落地、不登录、不调绑定接口；参数整串透传，不解析重组。只要有 `d`（或将来的分享凭证 `k`）就算有效链接，有效期等校验在 App 里做。
- 文案跟随浏览器语言：简中 / 繁中 / 英 / 日。昵称、设备名一律按纯文本显示。
- 底部「调试日志」默认折叠，`?debug=1` 展开，可复制。

## 三、部署（待做）

1. 上线前在页面顶部配置区填：
   - `IOS_APP_STORE_URL`：App Store 地址（`https://apps.apple.com/app/id<数字ID>`）；
   - `ANDROID_DOWNLOAD_URL`：安卓下载地址。留空时页面会用相对路径调 `/Client/Basic/getAndroidDownload?terminal=1`，**只有页面与 API 同域名时才拿得到**，拿不到就提示去应用商店搜「BoltStar」。
2. 部署位置建议与 PayPal 中转页相同：放在 API 域名下（如 `https://api.boltfox.cn/share.html`），不要挂到跑 SPA 的域名下（nginx 的 `try_files … /index.html` 兜底会把本页换成 SPA 首页）。
3. 部署后把实际网址告诉开发，App 侧据此生成分享链接。

## 四、App 侧还要做（线上地址确定后）

- 分享：「分享设备」改为生成本页链接，走微信网页卡片（`fluwx` 网页分享，只需 App 自己的微信 AppID）、系统分享、复制链接；去掉对小程序原始 ID 的依赖。
- 接收链接：
  - 安卓：`AndroidManifest.xml` 加 `boltstar://share/accept` 的 intent-filter（现有只登记了 `pay/paypal/*`）；
  - iOS：`Info.plist` 的 `CFBundleURLSchemes` 加 `boltstar`（现在只有微信的 `wx…`）。
  - **上面两项做完、发版之前，已安装旧版 App 的手机点链接也拉不起 App，页面会显示「没有检测到 App」。**
- 接受页：照搬小程序 `wifi-share-accept`（未登录先存待接受、登录后继续；本人分享 / 已在列表；`chkTimeValid`；`addUserProduct`）。

## 五、已知限制

- 链接参数是明文的设备号、产品 ID、房主 userId，可被改写后伪造；与小程序卡片现状相同。建议后端提供「生成分享凭证 / 凭凭证接受」接口，链接只带 `k`，本页已兼容。
- 微信内只做引导，不接微信开放标签 `wx-open-launch-app`（那需要公众号与 JS-SDK 签名）。
