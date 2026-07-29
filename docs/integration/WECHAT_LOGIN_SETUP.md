# App 微信快捷登录专项记录

> 文档类型：Integration Runbook / Troubleshooting
> 状态：Active（客户端已按确认接口接通，待真机验收）
> 最后核验：2026-07-29
> 适用范围：Flutter Android / iOS App 的微信开放平台移动应用 OAuth 登录
> 不适用范围：微信小程序手机号快捷登录
> 本文件是 App 微信快捷登录的当前权威记录；其他文档中的旧接口描述待后续同步。

## 一、结论

App 不需要手工下载并导入微信 SDK。项目已经通过 `fluwx 6.0.0` 接入微信原生 SDK：

- Android 已解析 `com.tencent.mm.opensdk:wechat-sdk-android:6.8.34`。
- `fluwx` 的 Manifest 会自动合并微信回调 Activity；当前构建产物中已经存在
  `com.boltfox.boltstar.wxapi.WXEntryActivity`。
- Flutter 已调用 `registerApi()`，并通过 `snsapi_userinfo` 拉起微信移动应用授权。

2026-07-29 更新：App 专用后端接口已确认为 `POST /Client/User/setWechatAuthorizLogin`
（swagger 摘要「微信授权登录」，入参 `WechatAuthorizLoginApiIn`），客户端已按它改完（见第八节）。

剩余阻塞项：

1. 后端是否已配置移动应用 AppID 对应的 AppSecret（`wx4cf0c5f38a70d0bc`，不是小程序的那把）。
2. 微信开放平台移动应用是否已过审并开通「微信登录」、正式签名是否已登记。
3. iOS 的 Universal Link 与 Bundle ID 仍是占位（见第三、九节），iOS 侧尚不能验收。

## 二、必须区分的两条登录链路

### 2.1 微信小程序手机号快捷登录

接口：

```text
POST /Client/User/setWechatAppLogin
```

Swagger 描述：

```text
微信小程序授权手机号码 一键登录返回登录token
```

请求模型包含：

```json
{
  "code": "微信小程序授权 code",
  "device": "通过公共参数传递",
  "language": "通过公共参数传递",
  "terminal": "3",
  "wxEncrypData": "小程序手机号解密数据",
  "wxIvData": "小程序手机号解密 IV"
}
```

这是小程序专用业务，不是 Flutter App 移动应用 OAuth 登录接口。App 不应向该接口提交移动应用
SDK 返回的 OAuth code，也不应提交 `wxEncrypData` / `wxIvData`。

### 2.2 Flutter App 微信开放平台移动应用登录

正确流程应为：

```text
Flutter App
  → fluwx / 微信原生 SDK
  → scope=snsapi_userinfo
  → 得到一次性 OAuth code
  → POST /Client/User/setWechatAuthorizLogin（App 专用，见第五节）
  → 后端调用微信 /sns/oauth2/access_token
  → 后端按 openid / unionid 创建或关联用户
  → 后端返回 BoltStar userToken 和用户信息
```

移动应用 OAuth 不使用小程序 `/sns/jscode2session`，也不使用小程序手机号解密数据。

## 三、当前项目已确认配置

### 3.1 AppID

```text
wx4cf0c5f38a70d0bc
```

代码未传 `--dart-define` 时也会使用该默认值。正式构建仍建议显式传入，避免环境混淆。

### 3.2 Android

应用包名：

```text
com.boltfox.boltstar
```

正式签名 MD5：

```text
带冒号：93:D4:D7:61:71:33:40:C5:64:5D:C4:FA:A3:78:DD:D1
微信后台常用格式：93d4d761713340c5645dc4faa378ddd1
```

debug 签名 MD5：

```text
54f75118337069150ae37d0f109cf564
```

正式应用登录应使用 release 签名包验证。若微信开放平台只登记了正式签名，普通 debug 包不能作为
最终验收依据。

### 3.3 iOS

- `Info.plist` URL Scheme：已填真实 AppID `wx4cf0c5f38a70d0bc`（2026-07-29 由占位符改正）。
- `Info.plist` `LSApplicationQueriesSchemes`：已含 `weixin` / `weixinULAPI` 等。
- `Runner.entitlements` Associated Domain：仍是占位 `applinks:example.boltfox.cn`。
- `WECHAT_UNIVERSAL_LINK`：仍需在构建时传入真实值。

Universal Link 未落地前，iOS 微信登录仍不能视为配置完成（`FluwxWeChatAuthorizationClient`
在 iOS 上会因为 Universal Link 为空直接以 `config` 错误拒绝拉起，不会发出无效请求）。

### 3.4 Android 包可见性

`AndroidManifest.xml` 的 `<queries>` 已声明 `com.tencent.mm`。Android 11+（targetSdk ≥ 30）
缺这一条时微信 SDK 的 `isWXAppInstalled` 恒为 false，表现为装了微信仍提示「请先安装微信」。

## 四、微信开放平台配置步骤

登录微信开放平台，进入“管理中心 → 移动应用”，找到 AppID
`wx4cf0c5f38a70d0bc` 对应的移动应用并逐项确认：

1. 移动应用已经审核通过。
2. “微信登录”能力已经开通。
3. Android 包名为 `com.boltfox.boltstar`。
4. Android 应用签名为 `93d4d761713340c5645dc4faa378ddd1`。
5. iOS Bundle ID 与 Xcode 工程实际 Bundle ID 完全一致。
6. 获取的是该移动应用自己的 AppSecret，不是小程序或公众号 AppSecret。

AppSecret 只能存放在服务端，不得写入 Flutter 源码、`dart-define`、APK、iOS App 或 Markdown。

## 五、App 专用后端接口（已确认）

```text
POST /Client/User/setWechatAuthorizLogin
```

swagger 摘要：`微信授权登录`；入参 `WechatAuthorizLoginApiIn`；
响应 `BaseOutput«UserInfoDetailApiOut»`（与邮箱登录同一响应模型）。

`WechatAuthorizLoginApiIn` 字段（`/v2/api-docs` 原文）：

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `code` | string | 微信授权 code，必填 |
| `device` | string | 手机机型（**通过 headers 传递**） |
| `language` | int | 语言 0/1=英语,2=简中,3=繁中,4=日文（**通过 headers 传递**） |
| `terminal` | int | 1=安卓,2=苹果,3=小程序（**通过 headers 传递**） |

后三个字段 DTO 里带着但注明走 headers，即公共参数，App 侧由 `ApiClient` 统一注入
（header 与 `/Client/` query 各一份），body 只发 `code`：

```http
POST /Client/User/setWechatAuthorizLogin?terminal=1&language=2&device=…
Content-Type: application/json
terminal: 1
language: 2
device: Android设备型号
```

```json
{
  "code": "微信移动应用 SDK 本次返回的一次性 OAuth code"
}
```

公共参数：

- Android：`terminal=1`
- iOS：`terminal=2`
- 小程序：`terminal=3`，走的是 `setWechatAppLogin`，不进本接口

响应 `retData`（`UserInfoDetailApiOut`）：`userToken` / `jwtToken` / `userNo` /
`nickName` / `avatar` / `userEmail` / `userMobile` / `imgCount` / `productCount`。
App 要求 `userToken` 与 `jwtToken` 同时非空才置登录态（与邮箱登录同门槛），
其余字段直接回填个人资料，不再多打一次 `getUserInfo`。

建议服务端环境变量：

```text
WECHAT_MOBILE_APP_ID=wx4cf0c5f38a70d0bc
WECHAT_MOBILE_APP_SECRET=<移动应用对应的AppSecret>
```

## 六、后端换码要求

后端收到 App 的一次性 code 后，应调用：

```text
GET https://api.weixin.qq.com/sns/oauth2/access_token
```

参数：

```text
appid=wx4cf0c5f38a70d0bc
secret=<移动应用AppSecret>
code=<本次新code>
grant_type=authorization_code
```

禁止调用：

```text
https://api.weixin.qq.com/sns/jscode2session
```

成功后微信返回的数据通常包含：

```json
{
  "access_token": "...",
  "expires_in": 7200,
  "refresh_token": "...",
  "openid": "...",
  "scope": "snsapi_userinfo",
  "unionid": "..."
}
```

后端再按 `unionid` 优先、`openid` 兜底创建或关联 BoltStar 用户，并返回现有业务登录响应，至少包含：

```json
{
  "userToken": "BoltStar业务登录凭证"
}
```

## 七、一次性 code 约束

移动应用 OAuth code 只能成功消费一次。正确的 App 专用接口接通后必须遵守：

- 同一个 code 不自动重试。
- 超时或连接中断后，不再次向微信提交原 code。
- 用户重新操作时必须重新拉起微信，取得新的 code。
- 服务端若需要幂等处理，应以 code 哈希建立短期幂等记录，不能重复调用微信换码接口。

客户端已按上述约束实施（见第八节），三道闸：SDK 层同一次授权只在途一个请求、
业务层拒收提交过的 code、网络层对该接口关掉全部自动重试。

## 八、Flutter 侧改动（2026-07-29 已完成）

1. `lib/src/network/boltfox_api.dart` `weChatMobileLogin()` 改调
   `/Client/User/setWechatAuthorizLogin`（原先错发到小程序的 `setWechatAppLogin`）。
2. 请求体只提交移动应用 OAuth `code`；`terminal` / `language` / `device` 仍走公共参数。
3. `lib/src/network/api_client.dart` `postJson` 新增 `retryOnConnectionError`
   （原先只有 `retryOnTimeout`，连接中断一律重试）；微信登录两个开关都传 false，
   即超时、连接中断、Socket/TLS 失败都不重试。**该开关只对这一个接口关**，
   其余接口的连接层重试行为不变（测试里有对照组守着）。
4. `lib/src/state.dart` `loginWithWeChatCode()` 记录已提交过的 code，
   同一个 code 第二次提交直接在客户端拒绝，提示重新发起微信登录。
5. `ios/Runner/Info.plist` URL Scheme 由占位符改为真实 AppID。
6. `android/app/src/main/AndroidManifest.xml` 的 `<queries>` 增加 `com.tencent.mm`。
7. 新增 `test/wechat_login_test.dart`：接口路径与 body、一次调用只发一次 HTTP、
   同一 code 不二次提交、双凭证缺一不置登录态、以及普通接口仍重试的对照组。

Android 正式构建建议：

```powershell
flutter build apk --release `
  --dart-define=WECHAT_APP_ID=wx4cf0c5f38a70d0bc
```

## 九、iOS 后续配置

取得真实 Universal Link 和 Bundle ID 后：

1. 将 `Info.plist` 的 URL Scheme 改为 `wx4cf0c5f38a70d0bc`。
2. 在 Xcode 启用 Associated Domains。
3. 将 `Runner.entitlements` 改为真实 `applinks:<域名>`。
4. 在域名部署正确的 `/.well-known/apple-app-site-association`。
5. 微信开放平台登记相同 Bundle ID 和 Universal Link。
6. 构建时传入：

```shell
--dart-define=WECHAT_APP_ID=wx4cf0c5f38a70d0bc
--dart-define=WECHAT_UNIVERSAL_LINK=https://真实域名/真实路径/
```

## 十、验收步骤

1. 使用微信开放平台登记签名对应的 release 包。
2. App 拉起微信并完成授权。
3. Flutter 收到非空 code，且 state 校验通过。
4. App 只调用一次 App 专用 BoltFox 登录接口。
5. 后端日志确认使用 AppID `wx4cf0c5f38a70d0bc`。
6. 后端日志确认调用 `/sns/oauth2/access_token`，没有调用 `/sns/jscode2session`。
7. 后端返回 BoltStar `userToken`。
8. App 写入登录态并进入首页。

日志可以记录：

- trace ID
- terminal
- 实际使用的 AppID
- 微信接口路径
- code 的哈希或脱敏前缀
- 微信原始 `errcode` / `errmsg` / `rid`

日志禁止记录：

- 完整 AppSecret
- 完整 OAuth code
- 微信 access_token / refresh_token
- BoltStar userToken

## 十一、当前待确认项

- [x] App 专用 BoltFox 登录接口的最终路径 —— `/Client/User/setWechatAuthorizLogin`（2026-07-29）。
- [x] App 专用接口的请求和响应字段 —— 见第五节（swagger `WechatAuthorizLoginApiIn` /
      `UserInfoDetailApiOut`）。
- [ ] 微信开放平台移动应用是否已审核通过并开通微信登录。
- [ ] 正式签名 `93d4d761713340c5645dc4faa378ddd1` 是否已登记。
- [ ] 后端是否持有 AppID `wx4cf0c5f38a70d0bc` 对应的移动应用 AppSecret。
- [ ] 后端是否使用 `/sns/oauth2/access_token`（而不是小程序的 `/sns/jscode2session`）。
- [ ] iOS Bundle ID、Universal Link、AASA 配置。
- [ ] 真机验收（本机无 Flutter SDK，未跑 `flutter analyze` / `flutter test` / 未编译）。

## 十二、信息来源

- Flutter 微信授权实现：
  `lib/src/features/account/data/wechat_authorization_client.dart`
- Flutter 当前后端请求：
  `lib/src/network/boltfox_api.dart`
- 公共终端参数：
  `lib/src/network/api_config.dart`、`lib/src/network/api_client.dart`
- Flutter 依赖：
  `pubspec.yaml`、`pubspec.lock`
- Android 构建配置：
  `android/app/build.gradle.kts`
- Android 合并后的 Manifest：
  `build/app/intermediates/merged_manifests/`
- iOS 配置：
  `ios/Runner/Info.plist`、`ios/Runner/Runner.entitlements`
- BoltFox Swagger：
  `https://api.boltfox.cn/v2/api-docs`
- Android 签名：
  `./gradlew :app:signingReport`
