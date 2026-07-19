# 微信开放平台移动应用登录接入

> **📌 文档维护约定**：本文档随代码演进——**每次修复问题 / 改动后，务必回到对应 .md 在文末「操作日志」追加一条**（日期 + 改了什么 + 对应代码符号/文件），防止文档滞后于代码、误导后续把已修的 bug 又改回去。


当前登录链路为：Flutter 拉起微信客户端授权（`snsapi_userinfo`）→ 获得一次性 `code` →
`POST /Client/User/setWechatAppLogin` → 后端返回 BoltStar `userToken` 和用户信息。

客户端不保存微信 AppSecret，也不直接向微信换取 `access_token`。服务端应根据请求头中的
`terminal`（**Android=1、iOS=2**，小程序=3）区分移动应用与小程序登录流程。

## 构建参数

Android：

```shell
flutter run --dart-define=WECHAT_APP_ID=wx实际AppID
```

iOS：

```shell
flutter run \
  --dart-define=WECHAT_APP_ID=wx实际AppID \
  --dart-define=WECHAT_UNIVERSAL_LINK=https://实际域名/实际路径/
```

## 原生平台待配置项

- 微信开放平台：移动应用需审核通过，并登记 Android 包名 `com.boltfox.boltstar`、正式签名和
  iOS Bundle ID。
- Android：微信回调 Activity 和应用查询声明由当前 SDK 合并；调试包签名未登记时授权会失败。
- iOS：在 Xcode 中添加以 AppID 为值的 URL Scheme，启用 Associated Domains 并添加与
  Universal Link 对应的 `applinks:` 域名；`Info.plist` 已加入微信查询白名单。
- 服务端：用移动应用 AppID/AppSecret 和 code 换取微信身份，再返回现有格式的
  `UserInfoDetailApiOut`（至少包含 `userToken`）。

## 后续替换 SDK

页面只依赖 `WeChatAuthorizationClient`。新 SDK 只需实现其 `authorize()`，返回微信一次性 code，
再把 `defaultWeChatAuthorizationClient` 指向新实现即可；页面、后端请求和登录态代码无需改动。

---

## 操作日志

- 2026-07（本轮）核对：微信配置(terminal/setWechatAppLogin/回调)与代码一致，无变更。
