# iOS 微信 Universal Link 定为 `https://badmin.boltfox.cn/app/`

> 文档类型：Historical Change Record
> 日期：2026-08-11
> 范围：仅 App（iOS 侧配置），Android 不受影响
> 当前权威文档：[`../../integration/WECHAT_LOGIN_SETUP.md`](../../integration/WECHAT_LOGIN_SETUP.md) 第三、九节

## 背景

`WECHAT_LOGIN_SETUP.md` 第九节此前是「取得真实 Universal Link 后」的待办清单，
`Runner.entitlements` 里是占位域名 `example.boltfox.cn`，`WECHAT_UNIVERSAL_LINK` 无默认值。
本次确定使用管理后台域名下的 `/app/` 路径。

## 客户端改动

| 文件 | 改动 |
| --- | --- |
| `ios/Runner/Runner.entitlements` | `applinks:example.boltfox.cn` → `applinks:badmin.boltfox.cn` |
| `lib/src/features/account/data/wechat_authorization_client.dart` | `WECHAT_UNIVERSAL_LINK` 增加默认值 `https://badmin.boltfox.cn/app/` |
| `docs/integration/apple-app-site-association.json` | 新增，待部署到域名的 AASA 原文 |

`ios/Runner/Info.plist` 的 URL Scheme（`wx4cf0c5f38a70d0bc`）与 Xcode 三套构建配置的
`CODE_SIGN_ENTITLEMENTS` 早已就位，本次未动。

Team ID `S2HZK3227W`、Bundle ID `com.boltfox.boltstar` 取自
`ios/Runner.xcodeproj/project.pbxproj`，拼成 AASA 的 `appID`。

### 为什么给默认值而不是只靠 `--dart-define`

与 `WECHAT_APP_ID` 同理，避免漏传参数的包在 iOS 上直接被客户端的 `config` 校验拦下。
**副作用要知道**：此前 Universal Link 为空时 iOS 根本不拉起微信；现在会真的拉起，
失败点后移到「授权完能不能回到 App」。AASA 部署前，iOS 真机的表现是
「跳微信 → 授权 → 落回 Safari / 停在微信」，不再是一句配置错误提示。

## 原生回调无需改代码（核实结论）

本工程用了 `UIApplicationSceneManifest` + `SceneDelegate`。核对
`fluwx 6.0.0`（pod `fluwx 2.0.5`）的 `FluwxPlugin.m`：它同时实现了
`application:continueUserActivity:restorationHandler:`（第 445 行）与
`scene:continueUserActivity:`（第 450 行），`FlutterSceneDelegate` 会把 scene 生命周期
转发给插件。`BUILD_RELEASE.md` 里「fluwx 5.7.7 早于 scene 适配期」的旧提示已同步更新。

## ⚠️ 未完成：域名侧 AASA

2026-08-11 实测：

```bash
curl -sSI https://badmin.boltfox.cn/.well-known/apple-app-site-association
# HTTP/2 200, content-type: text/html
```

返回的是管理后台（Vue SPA「曝石相框管理中心」）的 `index.html` —— 该域名对任意路径都做
SPA 兜底，`/notexist-xyz` 同样 200。**AASA 尚未部署，iOS 微信登录仍不可验收。**
需要在 SPA 的 `try_files` 兜底之前加 `location =` 精确匹配，配置与自查命令见
`WECHAT_LOGIN_SETUP.md` 9.2 / 9.4。

顺序上必须先部署 AASA，再去微信开放平台填 Universal Link —— 微信后台保存时会自己抓
AASA 校验。

`https://badmin.boltfox.cn/app/` 目前也只是 SPA 兜底页。建议后端在该路径放一个
「打开 App / 下载引导」静态页，免得用户在浏览器点开落到后台登录界面。

## 验证

- `Runner.entitlements`、`Info.plist` 经 `plistlib` 解析通过；AASA JSON 解析通过。
- ⚠️ 本次改动在无 Flutter SDK 的 Linux 开发机上完成，**未跑 `flutter analyze` 与
  `flutter test`**；Dart 侧只是给 `String.fromEnvironment` 加了 `defaultValue`，
  下次在有 SDK 的机器上补跑。
