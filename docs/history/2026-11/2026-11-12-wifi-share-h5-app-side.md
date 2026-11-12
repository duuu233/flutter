# WiFi 版设备分享改发 H5 链接，App 接受页（main）

> 类型：Historical Implementation Record
> 日期：2026-11-12；环境：远程 SSH 服务器；分支：main；修改前：1099d62
> 依据：产品已把落地页部署到 https://iot.boltfox.cn/h5/share.html（与 `deploy/share/share.html` 一致，仅行尾换成 CRLF），要求接上 App 侧分享与绑定流程。

## 改动

- 分享（`wifi_share_page.dart`）：「分享设备」取服务器时间戳后生成 `WifiShareLink.h5Url`（落地页 + 原 d/p/u/n/o/t 参数），弹层选「发给微信好友」（`fluwx` 网页卡片，缩略图用设备图）或「复制链接」。不再发小程序卡片，置灰条件去掉小程序原始 ID，只剩所有者 / userId / 产品 ID / 设备号；`WifiWeChatShare` 改为 `supported` + `shareWebPage`；删除只给小程序卡片画封面的 `wifi_share_card.dart`。落地页地址可用 `--dart-define=WIFI_SHARE_H5_URL` 改。
- 拉起：
  - Android：新增透明 `ShareLinkActivity`（`boltstar://share/accept`），记下 query 后用启动 intent 把原任务提回前台（与 PayPal 回跳同理，不挂 MainActivity）；`MainActivity` 通道加 `consumeShareLink`。
  - iOS：`Info.plist` 加 `boltstar` URL Scheme；`SceneDelegate` 在 `openURLContexts` 与冷启动 `willConnectTo` 里收下 `boltstar://share/accept`（`ShareLinkStore`，不转给插件 / 引擎，`FlutterDeepLinkingEnabled` 仍关）；`AppDelegate` 通道加 `consumeShareLink`。
  - Dart：`NativeDeviceApi.consumeShareLink` → `WifiShareInbox`；根组件在闪屏结束、登录成功、回前台三处读走，已登录才推接受页，未登录留着等登录。
- 接受页（新增 `wifi_share_accept_page.dart`，同小程序 `wifi-share-accept`）：参数无效 →「分享链接无效」；进页 `chkTimeValid`（新增 `BoltFoxApi.chkTimeValid`）明确过期 →「分享链接已过期」；点「接受」再校验（校验不了不接受）→ 本人分享提示 → 已在列表直接进详情 → `addUserProduct`（`isToHave=0`、`shareUserId`=所有者）→ 重拉列表进设备详情；服务端拒绝提示接口原话。
- 文案四语种（`wifi_l10n.dart`）；分享页提示改为「把链接发给对方，对方用 BoltStar App 打开并接受」。
- 新增 `test/wifi_share_link_test.dart`；`test/debug_log_test.dart` 分享页断言按有意改动改写。

## 已知限制

- 落地页的下载地址取不到：`getLastVersion` / `getAndroidDownload` 未登录调用返回 `retCode 406「请重新登录」`（2026-11-12 实测，iot.boltfox.cn 与 api.boltfox.cn 相同；跨域已放行）。同日产品改为「立即下载」统一跳官网下载页 `https://www.boltstar-ai.com/en/download`，页面不再调这两个接口（`deploy/share/share.html` 的 `DOWNLOAD_URL`，需重新部署）。
- iOS 冷启动那条 `scene(_:willConnectTo:options:)` 覆写依赖 FlutterSceneDelegate 暴露该方法（与已有 `openURLContexts` 覆写同理），未在 Xcode 编译验证。
- 链接参数仍是明文（同小程序卡片），有效期内被转发拿到的人都能加入。

## 验证

- 本机无 Flutter / Dart / Xcode / Android SDK，analyze / test / 构建 / 真机均未跑；新测试断言用 python 对源码核对，括号配平、Info.plist 与 AndroidManifest 解析、git diff --check 通过。
