# iOS 微信回跳补链：`SceneDelegate` 转发 URL Scheme + 关掉 Flutter 深链

> 文档类型：Historical Change Record
> 日期：2026-08-11
> 范围：仅 iOS 原生配置（`SceneDelegate.swift` / `Info.plist`），Dart 与 Android 未动
> 当前权威文档：[`../../integration/WECHAT_LOGIN_SETUP.md`](../../integration/WECHAT_LOGIN_SETUP.md) 9.5

## 症状

iOS 点「微信登录」→ 微信授权页 → 选完回到 App，落在一个标题为 `Route not found` 的空白页
（`AppRoutes` 的 `default:` 分支 `_UnknownRoutePage`）；`FluwxWeChatAuthorizationClient.authorize()`
的 `Completer` 一直等不到 code，2 分钟后按 `timeout` 收场。Android 无此现象。

## 根因（逐段核对源码，不是推测）

核对对象：`fluwx 6.0.0`（pod `fluwx 2.0.5`）与 `.metadata` 锁定的引擎版本
`cc0734ac716fbb8b90f3f9db8020958b1553afa7`（Flutter 3.41 stable）。

1. AASA 未部署（见 9.2，当天二次复核仍返回后台 SPA 的 `text/html`，Apple CDN 侧 404），
   Universal Link 关联不成立 → 微信降级用 URL Scheme
   `wx4cf0c5f38a70d0bc://oauth?code=…&state=…` 回跳。
2. 本工程启用 `UIApplicationSceneManifest`，scheme 回跳只会触发
   `UISceneDelegate.scene:openURLContexts:`，**不再触发** `application:openURL:options:`。
3. `FluwxPlugin.h` 声明 `<FlutterPlugin, FlutterSceneLifeCycleDelegate>`，但 `FluwxPlugin.m`
   只实现了 `scene:continueUserActivity:`（UL），**没有** `scene:openURLContexts:`
   —— 声明「已迁移 scene」，实际只迁了一半。
4. 引擎 `FlutterSceneLifeCycle.mm` 的 `scene:openURLContexts:` 先问 scene 链（无人认领），
   再走 app 兜底 `sceneFallbackOpenURLContexts:`；而
   `FlutterPluginAppLifeCycleDelegate.mm` 的兜底里有一句
   `if (isFallback && [self pluginSupportsSceneLifecycle:delegate]) continue;`，
   判断就是 `conformsToProtocol:@protocol(FlutterSceneLifeCycleDelegate)`
   —— **fluwx 因为第 3 条的声明被跳过**，它的 `application:openURL:options:` 永远收不到。
5. 两条链都没人处理 → `handleDeeplink:`；`FlutterSharedApplication.isFlutterDeepLinkingEnabled`
   在 `Info.plist` 缺该键时**默认 YES**，于是整条 URL 被当路由名推给 Flutter
   → `onGenerateRoute` 的 `default:` → `Route not found`。

一句话：**不是 AASA 缺失导致「打不开 App」，而是 scheme 兜底路径上 fluwx 被引擎跳过。**

## 改动

| 文件 | 改动 |
| --- | --- |
| `ios/Runner/SceneDelegate.swift` | 覆写 `scene:openURLContexts:`，逐条把 URL 转回 `UIApplication.shared.delegate` 的 `application:openURL:options:`（还原 `sourceApplication`/`annotation`/`openInPlace`）；全部没人认领时才调 `super` |
| `ios/Runner/Info.plist` | 新增 `FlutterDeepLinkingEnabled = false` |

为什么转回 app delegate 就能通：`FlutterAppDelegate.application:openURL:options:` 走的是
`isFallbackForScene:NO` 的那条分支，不做第 4 条的跳过，fluwx 照常
`WXApi.handleOpenURL:delegate:` → 事件回到 Dart 订阅者。

两条改动互补，缺一不可：转发治「拿不到 code」，关深链治「弹 `Route not found`」。

## 关深链的第二个理由（UL 通了之后同样受益）

fluwx 的 `scene:continueUserActivity:` 实现写成了 `void` 返回，而引擎协议
`FlutterSceneLifeCycleDelegate` 声明的是 `BOOL`——引擎读到的是未定义返回值。一旦读成 NO，
引擎会拿 `userActivity.webpageURL` 去做深链，且那条路径是 `relayToSystemIfUnhandled:YES`
（Flutter 报未处理就把链接甩回系统 → 跳去 Safari）。`FlutterDeepLinkingEnabled=false`
把这两种后果一并掐掉，所以 AASA 部署后这两条改动**不撤**。

## 覆盖不到的情况

App 在用户停留微信期间被系统回收：回跳 URL 只出现在 `scene:willConnectTo:options:` 的
`connectionOptions`，且 Dart 侧等 code 的 `Completer` 已随进程消失——再转发也补不回这次登录，
用户重新点一次微信登录即可。有 `FlutterDeepLinkingEnabled=false` 兜着，至少不会弹
`Route not found`。故本次**不**在 `scene:willConnectTo:` 上加转发（加了也只是把事件送给一个
没人监听的通道）。

## 仍然阻塞（本次未解决，也无法在客户端解决）

1. `badmin.boltfox.cn` 部署 `/.well-known/apple-app-site-association`（nginx 片段与自查命令见
   9.2 / 9.4，待部署的 JSON 原文在 `docs/integration/apple-app-site-association.json`）。
2. 微信开放平台移动应用 `wx4cf0c5f38a70d0bc` 登记 Bundle ID + Universal Link（顺序必须 9.2 → 9.3）。
3. 后端把 `/Client/User/setWechatAuthorizLogin` 加入免登录白名单（5.1，Android/iOS 共同的最终阻塞）。

即使本次补链让 iOS 能拿到 code，走到后端仍会撞上第 3 条的 `406 请重新登录！`。

## 验证

- `ios/Runner/Info.plist`、`ios/Runner/Runner.entitlements` 经 `plistlib` 解析通过，
  `FlutterDeepLinkingEnabled=False`、URL Scheme 与 SceneDelegate 类名不变。
- 结论逐条对齐引擎与 fluwx 源码（版本号见上），非经验推断。
- ⚠️ 本次在无 Xcode / 无 Flutter SDK 的 Linux 开发机上完成，**未编译 iOS 工程、未跑
  `flutter analyze` / `flutter test`**（本次没有 Dart 改动）。Swift 侧需在 macOS 上编译一次，
  并按第十节做真机往返验收。
