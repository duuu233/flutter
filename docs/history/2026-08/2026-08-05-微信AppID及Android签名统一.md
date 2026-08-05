# 微信 AppID 及 Android 构建签名统一

> 文档类型：Change Record
> 日期：2026-08-05
> 权威运行手册：`../../integration/WECHAT_LOGIN_SETUP.md`
> ⚠️ 本文中的 AppID `wx5bc2000b3207f370` 当日晚些时候即被判定为错误应用，已由
> `2026-08-05-微信AppID更正为wx4cf0c5f38a70d0bc.md` 取代；Android 签名统一部分仍然有效。

## 变更

- 微信开放平台移动应用 AppID 统一修正为 `wx5bc2000b3207f370`。
- Flutter 默认 `WECHAT_APP_ID`、iOS URL Scheme、打包命令与集成文档同步到同一值。
- Android 包名保持 `com.boltfox.boltstar`。
- Android debug/profile/release 全部使用 `android/key.properties` 指向的正式签名证书。
- 三种构建的微信开放平台应用签名统一为
  `93d4d761713340c5645dc4faa378ddd1`（MD5，小写无冒号）。

## 原因

微信开放平台按“AppID + Android 包名 + 签名证书”识别移动应用。之前 debug/profile 使用
各开发机自己的 debug.keystore，签名与 release 不同，导致相同代码在调试包和正式包上的微信授权
行为不一致。现在所有 Android 构建类型共用正式签名，避免跨电脑和构建类型漂移。

## 构建要求

每台 Android 开发机都必须在不纳入 Git 的 `android/key.properties` 中配置同一把正式 JKS。
缺少配置时 debug/profile/release 对应构建会直接失败，不再生成签名不匹配的调试包。

微信开放平台与后端还需要同步核对：

- AppID：`wx5bc2000b3207f370`
- Android 包名：`com.boltfox.boltstar`
- Android 应用签名：`93d4d761713340c5645dc4faa378ddd1`
- 后端 AppSecret：必须属于上述移动应用，且只能保存在服务端

## 验证结果

- `:app:signingReport`：debug/profile/release/debugAndroidTest 均为 `Config: release`，证书 MD5 一致。
- debug、profile、release 及其分 ABI APK 均构建成功；旧的 `BoltStar-test-arm64-v8a.apk`
  已由新 arm64 profile 产物覆盖。
- `aapt dump badging`：上述 APK 包名均为 `com.boltfox.boltstar`。
- `apksigner verify --print-certs`：上述 APK 的证书 MD5 均为
  `93d4d761713340c5645dc4faa378ddd1`。
- 源码和 `build/app` 产物均已确认不再包含旧 AppID。
- 微信登录相关测试通过；全量测试仍有一个既存的首页文案断言失败，与本次配置变更无关。
