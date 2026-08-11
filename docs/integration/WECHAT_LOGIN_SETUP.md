# App 微信快捷登录专项记录

> 文档类型：Integration Runbook / Troubleshooting
> 状态：Active（客户端已就绪；**卡在后端**：接口未放行未登录调用，见第五节 5.1）
> 最后核验：2026-08-11
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

2026-08-04 更新（安卓真机现象定位）：**微信侧是通的，卡在后端**。
现象是「点微信图标 → 微信授权界面 → 回到登录页弹『请重新登录』」，那句提示不是微信 SDK 报的，
是 BoltFox 对 `setWechatAuthorizLogin` 返回的 `retCode 406 / retMsg 请重新登录！`——
该接口没进后端的免登录白名单，未带 `userToken` 的请求根本进不到业务逻辑（复现见 5.1）。
换句话说：授权成功、code 已拿到，死在换 token 这一步。

2026-08-05 更新：移动应用 AppID 更正为 `wx4cf0c5f38a70d0bc`（此前配置的 `wx5bc2000b3207f370`
不是本 App 对应的移动应用，已作废）。iOS URL Scheme、Flutter 默认 `WECHAT_APP_ID`、打包命令
三处同步为同一值，Android 与 iOS、debug 与 release 一致。Android 的 debug/profile/release
三种构建统一使用 `boltstar-release.jks`，包名与签名不再因构建类型变化。

2026-08-11 更新：iOS Universal Link 定为 `https://badmin.boltfox.cn/app/`。客户端三处已落地
（`Runner.entitlements` 的 `applinks:badmin.boltfox.cn`、`WECHAT_UNIVERSAL_LINK` 默认值、
Info.plist URL Scheme 保持 AppID）。**但服务端 AASA 尚未部署**：实测
`https://badmin.boltfox.cn/.well-known/apple-app-site-association` 返回 200 但内容是
管理后台 SPA 的 `index.html`（`content-type: text/html`），该域名对任意路径都做 SPA 兜底。
AASA 落地前 iOS 微信登录仍不可用，详见第九节。

剩余阻塞项：

1. **（当前唯一实锤阻塞）** 后端把 `/Client/User/setWechatAuthorizLogin` 加入免登录白名单，
   与 `userLogin` / `userRegister` / `setWechatAppLogin` 同级 —— 它是登录接口，
   调用时用户按定义就没有 `userToken`。
2. 后端是否已配置移动应用 AppID 对应的 AppSecret（`wx4cf0c5f38a70d0bc`，不是小程序的那把，
   也不是旧的 `wx5bc2000b3207f370`）。
3. 微信开放平台移动应用是否已过审并开通「微信登录」、正式签名是否已登记。
4. iOS Bundle ID 当前为 `com.boltfox.boltstar`，仍需确认已在微信开放平台登记；Universal Link
   已定为 `https://badmin.boltfox.cn/app/`，但**域名侧 AASA 未部署**（见第三、九节），
   iOS 侧尚不能验收。

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

代码未传 `--dart-define` 时也会使用该默认值，因此 Android 与 iOS、debug 与 release 天然一致
（Android 不在原生侧写 AppID，fluwx 由 Dart 侧 `registerApi()` 注入；iOS 只有 URL Scheme
需要同步）。正式构建仍建议显式传入，避免环境混淆。

⚠️ 旧值 `wx5bc2000b3207f370` 已作废（2026-08-05 更正），源码与文档中不应再出现；
用旧值打出的安装包必须重打，否则微信侧按未登记的 AppID 处理。

### 3.2 Android

应用包名：

```text
com.boltfox.boltstar
```

统一签名 MD5（debug/profile/release）：

```text
带冒号：93:D4:D7:61:71:33:40:C5:64:5D:C4:FA:A3:78:DD:D1
微信后台常用格式：93d4d761713340c5645dc4faa378ddd1
```

三个构建类型都由 `android/app/build.gradle.kts` 绑定到同一个 release signingConfig。
因此 debug 包也可以验证微信授权；任何产包环境都必须配置同一份 `android/key.properties`
和 `boltstar-release.jks`，不再允许静默回退到机器各自的 debug.keystore。

### 3.3 iOS

| 项 | 值 | 状态 |
| --- | --- | --- |
| Bundle ID | `com.boltfox.boltstar` | Xcode 三套构建配置一致 |
| Apple Team ID | `S2HZK3227W` | `project.pbxproj` 的 `DEVELOPMENT_TEAM` |
| `Info.plist` URL Scheme | `wx4cf0c5f38a70d0bc` | 已填真实 AppID（2026-08-05 更正，与 Android 同值） |
| `Info.plist` `LSApplicationQueriesSchemes` | `weixin` / `wechat` / `weixinULAPI` / `weixinURLParamsAPI` | 已配 |
| Universal Link | `https://badmin.boltfox.cn/app/` | 已定（2026-08-11） |
| `Runner.entitlements` Associated Domain | `applinks:badmin.boltfox.cn` | 已配 |
| `WECHAT_UNIVERSAL_LINK` 默认值 | `https://badmin.boltfox.cn/app/` | 已配，不传 `--dart-define` 也一致 |
| `https://badmin.boltfox.cn/.well-known/apple-app-site-association` | — | ❌ **未部署**（返回后台 SPA 的 HTML） |
| 微信开放平台 Universal Link 登记 | — | ⬜ 待确认 |

AASA 未部署前，iOS 微信登录仍不能视为配置完成：系统不会把该域名与 App 关联，微信按
Universal Link 回跳时落回 Safari，App 收不到授权回调。客户端侧的空值拦截（Universal Link
为空即以 `config` 错误拒绝拉起，不发无效请求）现在因为有了默认值不会再触发——**这意味着
iOS 上会真的拉起微信，失败点后移到回跳**，排查时看的是「授权完能不能回到 App」。

Universal Link 回调不需要额外 Swift 代码：本工程用了 `UIApplicationSceneManifest` +
`SceneDelegate`，而 fluwx 的 `FluwxPlugin` 同时实现了
`application:continueUserActivity:restorationHandler:` 与 `scene:continueUserActivity:`，
`FlutterSceneDelegate` 会把 scene 生命周期转发给插件。

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

### 5.1 ⚠️ 该接口目前拒绝未登录调用（2026-08-04 实测，安卓真机现象的根因）

安卓真机现象：点微信图标 → 微信授权界面 → 选择后回到登录页 → 弹「请重新登录」。
那句提示来自后端 `retMsg`（`AppL10n._serverMessages` 把「请重新登录！」重译后展示），
不是微信 SDK 的任何一个错误码——**微信授权其实已经成功、code 已经拿到**。

curl 直打生产复现（无需 App）：

```bash
curl -s -X POST "https://api.boltfox.cn/Client/User/setWechatAuthorizLogin?terminal=1&language=2" \
  -H 'content-type: application/json' -H 'terminal: 1' -H 'language: 2' \
  -d '{"code":"probe"}'
# {"retCode":406,"retMsg":"请重新登录！","retData":null}
```

对照组（同样不带 `userToken`，全部正常进入业务逻辑）：

| 接口 | 响应 | 说明 |
| --- | --- | --- |
| `/Client/User/userLogin` | `403 Email does not exist` | 已进业务逻辑 |
| `/Client/User/userRegister` | `403 Please enter the correct email address` | 已进业务逻辑 |
| `/Client/User/setWechatAppLogin` | `retMsg "40029, errmsg"` | 已进业务逻辑，且确实拿 code 找微信换过 |
| `/Client/User/setWechatAuthorizLogin` | `406 请重新登录！` | **没进业务逻辑** |

进一步排除参数因素——下列变体全部返回同一条 406，说明拦截发生在业务逻辑之前：
`terminal` 改 3、不带任何 query 只发 headers、`userToken` 传空串、`userToken` 传垃圾值、
body 连 `code` 都不发。

结论：路径、DTO、公共参数都对（swagger 响应模型是 `BaseOutput«UserInfoDetailApiOut»`，
即它本来就该返回 `userToken`/`jwtToken`），只是**后端拦截器的免登录白名单漏了这个方法**。
客户端无解——登录接口天然拿不出 `userToken`。需要后端把它与 `userLogin` 同级放行。

在后端放行前，客户端已做的兜底（2026-08-04）：`loginWithWeChatCode` 不再把登录接口自身的
401/406 当「本地会话过期」处理，也不再原样透传「请重新登录」，而是提示
「微信登录被服务端拒绝（retCode 406：…）：微信授权本身已成功，是后端接口未放行未登录调用」。

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
5. `ios/Runner/Info.plist` URL Scheme 由占位符改为真实 AppID（2026-08-05 更正为
   `wx4cf0c5f38a70d0bc`）。
6. `android/app/src/main/AndroidManifest.xml` 的 `<queries>` 增加 `com.tencent.mm`。
7. 新增 `test/wechat_login_test.dart`：接口路径与 body、一次调用只发一次 HTTP、
   同一 code 不二次提交、双凭证缺一不置登录态、以及普通接口仍重试的对照组。

Android 构建（debug/release 使用同一 AppID 与签名）：

```powershell
flutter build apk --release `
  --dart-define=WECHAT_APP_ID=wx4cf0c5f38a70d0bc

flutter build apk --debug `
  --dart-define=WECHAT_APP_ID=wx4cf0c5f38a70d0bc
```

## 九、iOS Universal Link（`https://badmin.boltfox.cn/app/`）

### 9.1 客户端（2026-08-11 已完成）

1. `ios/Runner/Info.plist` URL Scheme 保持 `wx4cf0c5f38a70d0bc`。
2. `ios/Runner/Runner.entitlements` → `applinks:badmin.boltfox.cn`。
   （Xcode 三套构建配置的 `CODE_SIGN_ENTITLEMENTS` 早已接线到这个文件，无需再手工加 Capability；
   在 Xcode 里打开时 Signing & Capabilities 会显示 Associated Domains。）
3. `WeChatAuthorizationConfig.fromEnvironment()` 的 `WECHAT_UNIVERSAL_LINK` 默认值
   = `https://badmin.boltfox.cn/app/`，与上面两处同值。
4. 构建时可显式重申（默认值已一致，正式包仍建议写全）：

```shell
--dart-define=WECHAT_APP_ID=wx4cf0c5f38a70d0bc
--dart-define=WECHAT_UNIVERSAL_LINK=https://badmin.boltfox.cn/app/
```

### 9.2 服务端 AASA（⚠️ 未完成，当前 iOS 侧阻塞点）

在 `badmin.boltfox.cn` 部署 `/.well-known/apple-app-site-association`，内容见仓库中的
`docs/integration/apple-app-site-association.json`：

```json
{
  "applinks": {
    "apps": [],
    "details": [
      {
        "appID": "S2HZK3227W.com.boltfox.boltstar",
        "paths": ["/app/", "/app/*"]
      }
    ]
  }
}
```

`appID` = Apple Team ID + `.` + Bundle ID。Team ID `S2HZK3227W` 取自
`ios/Runner.xcodeproj/project.pbxproj` 的 `DEVELOPMENT_TEAM`。

硬性要求（任一不满足，iOS 直接不建立域名关联）：

- 走 HTTPS，证书有效，**不能有任何 301/302 跳转**；
- 文件名就是 `apple-app-site-association`，**没有 `.json` 后缀**；
- 响应体是纯 JSON，`Content-Type: application/json`；
- 不要求签名（iOS 9 以后即可用未签名 JSON）。

**当前实测结果（2026-08-11）**：

```bash
curl -sSI https://badmin.boltfox.cn/.well-known/apple-app-site-association
# HTTP/2 200, content-type: text/html   ← 返回的是管理后台 SPA 的 index.html
```

该域名是 Vue 管理后台（`曝石相框管理中心`），对任意路径都兜底返回 `index.html`，
`/notexist-xyz` 也是 200。所以必须在 SPA 的 `try_files` 兜底**之前**加精确匹配，nginx 示例：

```nginx
location = /.well-known/apple-app-site-association {
    default_type application/json;
    alias /usr/share/nginx/html/.well-known/apple-app-site-association;
    add_header Cache-Control "public, max-age=3600";
}

# 已有的 SPA 兜底放在后面，location = 精确匹配优先级更高，不会被它吃掉
location / {
    try_files $uri $uri/ /index.html;
}
```

`https://badmin.boltfox.cn/app/` 本身目前返回后台 SPA 的 HTML（同样是兜底）。微信要求该
链接可访问即可，不强制是专门页面；但既然 `/app/*` 已划给 App，建议后端在该路径放一个简单的
「打开 BoltStar App / 下载引导」静态页，避免用户在浏览器里点开落到管理后台登录界面。

### 9.3 微信开放平台

在移动应用 `wx4cf0c5f38a70d0bc` 的 iOS 配置中填写：

- Bundle ID：`com.boltfox.boltstar`
- Universal Links：`https://badmin.boltfox.cn/app/`（结尾斜杠要带上，与客户端逐字符一致）

微信后台保存时会自己去抓该域名的 AASA 校验，**AASA 没部署好这一步就过不了**，
所以顺序必须是 9.2 → 9.3。

### 9.4 自查

```bash
# 1. AASA 是 JSON 且无跳转
curl -sSL -D- https://badmin.boltfox.cn/.well-known/apple-app-site-association

# 2. Apple CDN 侧（真机首次安装取的是这条链路，可能有缓存延迟）
curl -sS "https://app-site-association.cdn-apple.com/a/v1/badmin.boltfox.cn"
```

真机侧：**Universal Link 只在安装（或重装）App 时由系统抓取一次 AASA**。改完 AASA 必须
删除 App 重装，仅覆盖安装或重启不会重新拉取。设置 → 开发者 → Universal Links →
Diagnostics 可以逐条验证域名关联状态。

## 十、验收步骤

1. 使用统一正式签名生成的 debug 或 release 包。
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
- [x] 安卓「回登录页弹请重新登录」的归属 —— 后端 406，非微信 SDK（2026-08-04，见 5.1）。
- [ ] **后端把 `/Client/User/setWechatAuthorizLogin` 加入免登录白名单**（当前唯一实锤阻塞）。
- [ ] 微信开放平台移动应用是否已审核通过并开通微信登录。
- [ ] 统一签名 `93d4d761713340c5645dc4faa378ddd1` 是否已登记。
- [ ] 后端是否持有 AppID `wx4cf0c5f38a70d0bc` 对应的移动应用 AppSecret（2026-08-05 换过 AppID，
      后端旧配置必须一并替换）。
- [ ] 后端是否使用 `/sns/oauth2/access_token`（而不是小程序的 `/sns/jscode2session`）。
- [x] iOS Universal Link 取值 —— `https://badmin.boltfox.cn/app/`，客户端三处已同步（2026-08-11）。
- [ ] **`badmin.boltfox.cn` 部署 `/.well-known/apple-app-site-association`**（iOS 侧当前阻塞点，见 9.2）。
- [ ] iOS Bundle ID `com.boltfox.boltstar` 与 Universal Link 在微信开放平台的登记状态（见 9.3）。
- [ ] 真机微信完整往返验收（2026-08-05 已编译 debug/release 并验证包名与签名；尚未真机授权）。
- [ ] 用新 AppID `wx4cf0c5f38a70d0bc` 重打 Android/iOS 包（旧产物内嵌的是作废 AppID）。

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
  `ios/Runner/Info.plist`、`ios/Runner/Runner.entitlements`、
  `ios/Runner.xcodeproj/project.pbxproj`（`DEVELOPMENT_TEAM` / `PRODUCT_BUNDLE_IDENTIFIER`）
- 待部署的 AASA 原文：
  `docs/integration/apple-app-site-association.json`
- BoltFox Swagger：
  `https://api.boltfox.cn/v2/api-docs`
- Android 签名：
  `./gradlew :app:signingReport`
