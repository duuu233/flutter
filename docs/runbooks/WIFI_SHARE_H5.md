# WiFi 版设备共享邀请 H5 落地页：部署与对接

> 文档类型：Release / Integration Runbook
> 状态：Active（2026-11-12 已部署到 https://iot.boltfox.cn/h5/share.html，App 侧分享与接受页同日接上，见 `../history/2026-11/2026-11-12-wifi-share-h5-app-side.md`）
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

0. ✅ 2026-11-12 已部署：`https://iot.boltfox.cn/h5/share.html`。该域名把 `/Client/*` 代理到同一后端且跨域已放行，页面用相对路径即可，`API_BASE` 保持留空。
   ⚠️ 但 `getLastVersion` / `getAndroidDownload` 未登录调用返回 `retCode 406「请重新登录」`，页面取不到下载地址、只能提示去应用商店搜——**需后端把这两个接口改成免登录**，页面不用改。
1. 下载地址不用写进页面，取后台「版本管理」（2026-11-12 产品确认）：页面进来就在后台调 `GET /Client/Basic/getLastVersion?appVersionNo=0.0.0&terminal=<安卓 1 / iOS 2>&language=…`，取 `retData.downloadPath`（与 App「检查更新」同一字段）；安卓那条没给地址再试 `getAndroidDownload`。所以后台版本管理里，**iOS 那条的下载地址要填 App Store 链接**，安卓填安装包地址。都取不到时提示去应用商店搜「BoltStar」；调试日志里有接口原文。
2. 部署位置建议与 PayPal 中转页相同：放在 API 域名下（如 `https://api.boltfox.cn/share.html`），接口走相对路径、不涉及跨域；也不要挂到跑 SPA 的域名下（nginx 的 `try_files … /index.html` 兜底会把本页换成 SPA 首页）。放到别的域名时，把页面顶部 `API_BASE` 填成 `https://api.boltfox.cn`，并让后端给上面两个接口放行 CORS。
3. 部署后把实际网址告诉开发，App 侧据此生成分享链接。

## 四、App 侧（2026-11-12 已接）

- 分享：「分享设备」生成本页链接（`WifiShareLink.h5Url`，地址可用 `--dart-define=WIFI_SHARE_H5_URL` 改），可「发给微信好友」（网页卡片）或「复制链接」；不再依赖小程序原始 ID。
- 接收：Android `ShareLinkActivity`（`boltstar://share/accept`）、iOS `boltstar` URL Scheme + `SceneDelegate`（含冷启动），记下 query 交给 Dart（`consumeShareLink`）；闪屏结束 / 登录后 / 回前台读走，已登录才打开接受页。
- 接受页 `WifiShareAcceptPage`：同小程序 `wifi-share-accept`（有效期校验、本人分享 / 已在列表、`addUserProduct` 非所有者绑定、进设备详情）。
- **含这些改动的 App 版本发布前，已装旧版的手机点链接仍拉不起 App**（旧版没登记 scheme），页面会显示「没有检测到 App」。

## 五、已知限制

- 链接参数是明文的设备号、产品 ID、房主 userId，可被改写后伪造；与小程序卡片现状相同。建议后端提供「生成分享凭证 / 凭凭证接受」接口，链接只带 `k`，本页已兼容。
- 微信内只做引导，不接微信开放标签 `wx-open-launch-app`（那需要公众号与 JS-SDK 签名）。
