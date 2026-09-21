# BoltStar 打包发布指南（Android + iOS）

> 文档类型：Release Runbook
> 状态：Active
> 最后核验：2026-09-21
> 微信登录的完整平台配置见 `../integration/WECHAT_LOGIN_SETUP.md`。
> 2026-07-16 全面审查后整理。本次审查已修复的构建阻断项：
> ① 主 Manifest 缺 `INTERNET` 权限（release 包全部网络请求失败）；
> ② iOS 缺微信回调 `CFBundleURLTypes` 与 Associated Domains entitlements；
> ③ App Store 1024 图标含 alpha 通道（上传直接被拒，已转 RGB）；
> ④ Android 8+ 无自适应图标（已补 `mipmap-anydpi-v26`）。

## 更新记录

| 日期 | 主题 | 落点 |
| --- | --- | --- |
| 2026-09-21 | 定下「不是必须就不动依赖和环境、Flutter 不升级」；9-18 的升级经核实不是必须，列出回退步骤（待 ltt 执行） | 新增 〇.6、〇.7 |

## 〇、打包前必须核对的微信配置

| 位置 | 当前值 | 要求 |
| --- | --- | --- |
| `ios/Runner/Info.plist` → `CFBundleURLSchemes` | `wx4cf0c5f38a70d0bc` | 必须与微信开放平台移动应用 AppID 一致 |
| `ios/Runner/Runner.entitlements` → `associated-domains` | `applinks:badmin.boltfox.cn` | 与 Universal Link 同域名 |
| `WECHAT_UNIVERSAL_LINK`（Dart 默认值 / `--dart-define`） | `https://badmin.boltfox.cn/app/` | 与 entitlements、微信后台、AASA 四处逐字符一致 |
| 构建命令 `--dart-define` | `WECHAT_APP_ID=wx4cf0c5f38a70d0bc` / `WECHAT_UNIVERSAL_LINK=https://badmin.boltfox.cn/app/` | 与上述配置一致 |
| `ios/Runner/Info.plist` → `FlutterDeepLinkingEnabled` | `false` | 微信回跳由 fluwx 原生回调消费；开着会把回跳 URL 当路由名推给 Flutter（`Route not found`），见 `WECHAT_LOGIN_SETUP.md` 9.5 |
| `ios/Runner/SceneDelegate.swift` → `scene:openURLContexts:` | 已覆写并转发到 app delegate 链 | fluwx 没实现该 scene 方法且被引擎的 app 兜底跳过；删掉它 = URL Scheme 回跳再次丢失 |

AppID 于 2026-08-05 由作废的 `wx5bc2000b3207f370` 更正为 `wx4cf0c5f38a70d0bc`：Android 与 iOS、
debug 与 release 必须是同一个值（Dart 默认值已同步，不传 `--dart-define` 也一致）。旧 AppID 打出的
安装包一律作废重打。Universal Link 于 2026-08-11 由占位改为 `https://badmin.boltfox.cn/app/`，
Dart 默认值同样已同步。

微信侧配套（不做则微信登录不可用）：
- ⚠️ **`badmin.boltfox.cn` 部署 `/.well-known/apple-app-site-association`** —— 2026-08-11 实测
  该地址返回的是管理后台 SPA 的 HTML，**尚未部署**；文件原文与 nginx 配置见
  `../integration/WECHAT_LOGIN_SETUP.md` 9.2（appID `S2HZK3227W.com.boltfox.boltstar`）。
  没有它，iOS 打包再正确，微信授权后也回不到 App。
- 微信开放平台后台填写同一 Universal Link（后台保存时会自己抓 AASA 校验，必须先做上一条）；
- **Android**：开放平台登记 `boltstar-release.jks` 的 MD5；debug/profile/release 已统一使用这把证书。

## 〇.5、国内网络前置：pub.dev 镜像（不配则 pub get 报 socket error）

打包机在国内访问 pub.dev 不通（报 `Got socket error trying to find package xxx at https://pub.dev`），
先配 Flutter 官方中国镜像（一次性，`setx` 后**新开终端**生效）：

```bat
setx PUB_HOSTED_URL "https://pub.flutter-io.cn"
setx FLUTTER_STORAGE_BASE_URL "https://storage.flutter-io.cn"
```

已开系统代理的机器可改用 `HTTPS_PROXY` 环境变量，二选一，别混用。

## 〇.6、环境与依赖基线：不是必须就不动

**基线：Flutter 3.44.x stable（自带 Dart 3.12.x）。** 所有打包机、开发机用同一个版本。

规则（2026-09-21 定）：

1. **Flutter 不升级。** 不跑 `flutter upgrade`，也不切 channel。提示有新版本不用理。
2. **依赖只装不升。** 拉代码后只用 `flutter pub get`；不用 `flutter pub upgrade`（含 `--major-versions`），
   不看着 `pub outdated` 顺手升，不加 `dependency_overrides`。
3. **构建环境不随手改。** `ios/Podfile` 的 `platform :ios`、Xcode 的 `IPHONEOS_DEPLOYMENT_TARGET`、
   `pubspec.yaml` 里 `flutter: config:`（如 SwiftPM 开关）、Gradle / AGP / Kotlin / compileSdk 等保持现状。
   Flutter 打印的「will soon be dropped」「建议升级」类警告只是预告，不用处理。
4. **`pubspec.lock` 只在有意改依赖时提交。** 执行 `flutter pub get` 后如果 lock 变了而你并没有改依赖，
   **不要提交**，先查原因——绝大多数是本机 Flutter 版本和基线不一致。
5. **什么算「必须」：** 有具体报错挡住了构建或上架（贴报错原文），或某个功能明确需要新版本
   （写清是哪个功能、要求哪个版本），或应用商店的硬性政策（附官方链接）。
   确属必须时：先在本节写清原因、影响和各机器要怎么配合，通知其他人，**所有机器一起升级**后再提交 lock。

反例（为什么要这么定）：2026-09-18 的 `219ad59` 在 Flutter 3.47 上跑了依赖升级，赶上 `objective_c 9.6.1`
这个坏版本（所有 iOS 构建失败），于是加了 `objective_c: 9.6.0` 强制版本；这个版本又把 `meta` 拉到 1.19，
3.44 解不开，结果安卓打包机被迫跟着升 Flutter。整条链没有一个功能需要它，见 〇.7。

## 〇.7、待 ltt 执行：回退 9-18 的 Flutter 3.47 连带改动

> 状态：**待执行**。做完后把这里改成「已完成（提交号）」，并把 〇.6 的基线补上具体补丁号。

**已核实不是必须（2026-09-21）：**
- 现在这份 `pubspec.lock` 自己写的就是 `flutter: ">=3.44.0"`、`dart: ">=3.12.0"`：除了上面那处 `meta` 冲突，
  没有任何包要求 3.47；
- `objective_c` 只被 `path_provider_foundation 2.6.0` 依赖（要求 `^9.2.1`）。在 3.44 上 pub 根本选不到 9.6.x
  （9.6.x 需要 `meta` 1.19），坏掉的 9.6.1 也就碰不到——**强制版本是升了 Flutter 才需要的**，9.6.1 如今也已被官方撤回；
- 所有 Pod 要求的最低 iOS 都 ≤ 13.0（speech_to_text、image_picker_ios、url_launcher_ios、shared_preferences_foundation
  为 13.0，其余 12.0）；iOS 15 只是 Flutter 3.47 新模板的默认值；
- SwiftPM 在 3.44 stable 也是默认开启，7 月就是这样打出 iOS 包的；
- 7-16 ~ 8-28 的 lock 就是 `objective_c 9.4.1`，当时 Flutter stable 只有 3.44.x，7 月的 iOS 正式包在真机上测过。

**步骤（在 Mac 上做，iOS 能验证）：**

1. **Flutter 回到 3.44.x**：`flutter downgrade`（回到上一次 `flutter upgrade` 之前的版本），
   `flutter --version` 确认是 3.44.x。`downgrade` 不可用时，在 Flutter SDK 目录里 `git checkout <3.44.x 的 tag>`。
2. **还原依赖**（都以 `219ad59` 的上一个提交为准）：
   - `pubspec.yaml`：删掉整段 `dependency_overrides:`（`objective_c: 9.6.0`），删掉 `flutter:` 下的
     `config: enable-swift-package-manager: false`；**`version:` 不动**（发版号，与本次回退无关）；
   - `git checkout 219ad59~1 -- pubspec.lock`，然后 `flutter pub get`，再看 `git diff pubspec.lock`：
     **任何包的 `version` 都不应该变**（应为 `meta 1.18.0`、`objective_c 9.4.1`）；只要有版本变化就停下，
     把 diff 贴出来，不要提交。
3. **还原 iOS 最低版本**：`ios/Podfile` 改回 `platform :ios, '13.0'`；`ios/Runner.xcodeproj/project.pbxproj` 里
   6 处 `IPHONEOS_DEPLOYMENT_TARGET = 15.0;` 改回 `13.0;`。
   （建议一并改：`96752a2` 把 Runner 的 `CURRENT_PROJECT_VERSION` 写死成 `4`，改回 `$(FLUTTER_BUILD_NUMBER)`，
   构建号以后只改 `pubspec.yaml` 的 `+N` 一处，`--build-number` 也才生效。）
4. `cd ios && pod install && cd ..`，让 `Podfile.lock` 按 3.44 重新生成（`speech_to_text` 这些 Pod 会保留，别手改）。
5. **验证**：`flutter analyze`、`flutter test`，`flutter build ipa`（命令见「二」），真机过一遍微信登录回跳、
   AI 按住说话（语音识别）、选图裁剪、蓝牙连接投屏。
6. **提交推送**，提交信息例如：`revert: 回退 219ad59 的 Flutter 3.47 连带改动，回到 3.44 基线`。
7. **任何一步在 3.44 上确实过不去**：说明真的是必须——不要推半截，把报错原文写进本节，和大家商量后再决定全队升级。

**其它机器（安卓打包机 2026-09-21 为了打当前 main 临时升到了 3.47.5）：** 等上面的回退推上去后，先
`flutter downgrade` 回到 3.44.x，再拉代码、`flutter clean`、`flutter pub get`，确认 `pubspec.lock` 没有变化。
**顺序不能反**：还在 3.47 的机器对回退后的 lock 跑 `pub get`，会把 `meta` 又升到 1.19 并改写 lock。

## 一、Android（Windows 打包机，keystore 路径由 `android/key.properties` 指定）

> ⚠️ **下面这些命令里的 `^` 是 cmd 的续行符，PowerShell（VSCode 终端的默认 shell）不认。**
> 直接粘进 VSCode 终端会报「一元运算符"--"后面缺少表达式」——那是 PowerShell 把第二行往后
> 各自当成了新语句。两条出路：**把命令合成一行**（最省事，各 shell 通吃），
> 或把 `^` 换成 PowerShell 的续行符**反引号 `` ` ``**（必须是行尾最后一个字符，
> 后面多一个空格就失效）。同理 `&&` 要 PowerShell 7.0+ 才支持，老版本用 `;`。

```bash
flutter clean
flutter pub get

# 上架 Google Play（AAB）：
flutter build appbundle --release ^
  --obfuscate --split-debug-info=build/symbols ^
  --dart-define=WECHAT_APP_ID=wx4cf0c5f38a70d0bc ^
  --dart-define=WECHAT_UNIVERSAL_LINK=https://badmin.boltfox.cn/app/
# 产物: build/app/outputs/bundle/release/app-release.aab

# 直接分发 APK（可选）：
flutter build apk --release --split-per-abi ^
  --obfuscate --split-debug-info=build/symbols ^
  --dart-define=WECHAT_APP_ID=wx4cf0c5f38a70d0bc ^
  --dart-define=WECHAT_UNIVERSAL_LINK=https://badmin.boltfox.cn/app/
# 产物: build/app/outputs/flutter-apk/app-arm64-v8a-release.apk 等
```

### Debug 包（排错用，不分发）

```bash
flutter build apk --debug ^
  --dart-define=WECHAT_APP_ID=wx4cf0c5f38a70d0bc ^
  --dart-define=WECHAT_UNIVERSAL_LINK=https://badmin.boltfox.cn/app/
# 产物: build/app/outputs/flutter-apk/app-debug.apk（含全部 ABI，直接安装）
```

- debug/profile/release 全部使用 `key.properties` 指向的正式证书；缺配置时对应构建会主动失败。
- debug 包不做 R8 混淆/资源裁剪，但包名、微信 AppID、签名与 release 完全一致，可以验证微信登录。
- 崩溃二分：debug 不崩 + release 崩 → 查 R8/proguard；两者都崩 → 查渲染驱动（Impeller）或代码，
  看 App 启动弹窗的崩溃日志或 `adb logcat -b crash -d`。
- 手机连电脑时优先 `flutter run`（debug 模式 + 终端实时堆栈 + 热重载），比打包快。

说明：
- 统一签名已接线 `android/key.properties`，所有 Android 产包环境都必须持有同一把正式 JKS。
- Flutter 3.4x 默认对 release 开 R8 + shrinkResources；本次已补 `android/app/proguard-rules.pro`
  （微信 OpenSDK / uCrop keep 规则）。
- `--split-debug-info` 的符号表（build/symbols）要留存，崩溃堆栈还原用。
- Google Play 自 **2026-08-31** 起新包必须 targetSdk 36 —— 当前 Flutter 3.41+ 默认 36，满足。

## 二、iOS（macOS + **Xcode 26+**，App Store 自 2026-04-28 起强制 iOS 26 SDK）

```bash
flutter clean
flutter pub get
cd ios && pod install --repo-update && cd ..   # Podfile.lock 严重过期，必须跑一次
flutter build ipa --release --export-method app-store \
  --obfuscate --split-debug-info=build/symbols \
  --dart-define=WECHAT_APP_ID=wx4cf0c5f38a70d0bc \
  --dart-define=WECHAT_UNIVERSAL_LINK=https://badmin.boltfox.cn/app/
# 产物: build/ios/ipa/BoltStar.ipa → Transporter / Xcode Organizer 上传
```

说明：
- 首次在 Xcode 打开时确认 Signing & Capabilities 里 Associated Domains 已生效
  （本次已创建 `Runner.entitlements` 并接线三个构建配置）。
- `ITSAppUsesNonExemptEncryption=false` 已写入 Info.plist，上传免答加密题。
- iPhone 已锁竖屏（页面全按 375 宽竖屏设计）。
- 权限文案（蓝牙/相册/相机/定位）目前是中文；若主打海外市场，
  建议补 `InfoPlist.strings` 英/日本地化。

## 三、每次发版检查清单

1. `pubspec.yaml` 版本号递增：`1.0.0+1` → `1.0.1+2`（`+N` 是 versionCode/CFBundleVersion，
   Play/TestFlight **不允许重复**）。
2. 开发机先跑 `flutter analyze`（本次改动较多，务必过一遍零告警再打包）。
3. **release 包**真机回归以下重点链路（debug 包正常不代表 release 正常，混淆/权限差异都在 release 才暴露）：
   - 登录 + 任一接口连通（验证 INTERNET 权限）；
   - 微信授权完整往返（验证 URL Scheme / Universal Link / 签名 MD5 / R8 keep）；
   - Android 投屏多选、AI 多选、首页头像和资料头像均打开系统 Photo Picker，且不会先弹
     照片/媒体整库授权框；
   - 投屏预览常驻编辑层：平移、缩放、旋转、横竖取景与最终设备分辨率导出；
   - BLE 扫描 → 连接 → 投屏 → OTA（重点回归本次的 OTA 提速与 ACK 事件驱动改动）。
   - 如有 Android 10/11 旧设备，验证首次扫描会弹**定位授权**且能搜到设备（本次修复项）。
4. iOS 真机确认微信回调经 Scene 生命周期可达。两条回跳路径的现状（2026-08-11 核对
   `fluwx 6.0.0` / pod `fluwx 2.0.5` 与引擎源码）：
   - **Universal Link**：`FluwxPlugin` 实现了 `scene:continueUserActivity:`，
     `FlutterSceneDelegate` 会转发，不需要动原生代码；
   - **URL Scheme**（UL 不可用时微信的降级路径）：fluwx **没有**实现
     `scene:openURLContexts:`，且引擎的 app 兜底会跳过它 —— 已在
     `ios/Runner/SceneDelegate.swift` 手工转发，配合 `FlutterDeepLinkingEnabled=false`，
     详见 `../integration/WECHAT_LOGIN_SETUP.md` 9.5。**这两处不要删**。
   若回调仍丢失，先按 `../integration/WECHAT_LOGIN_SETUP.md` 9.4 排 AASA（**改完 AASA 必须
   删 App 重装**，系统只在安装时抓一次）；最后才考虑回退经典生命周期（删 Info.plist 的
   `UIApplicationSceneManifest` 段 + `SceneDelegate.swift`——注意那会连同上面的转发一起删掉，
   回退后 URL Scheme 回跳改由 `AppDelegate` 的 `application:openURL:options:` 天然承接）。
5. 商店素材：Android 自适应图标为**白底**（`ic_launcher_background.xml` = `#FFFFFF`）+ inset
   前景，对齐 iOS「白底橙标」。⚠️ 不要改回品牌橙底——前景 PNG 的白色星形/十字缝是透明的，
   橙底会把它吃掉、桌面呈现一整块橙色 LOGO 消失（2026-07 已修，见
   `mipmap-anydpi-v26/ic_launcher.xml` 注释）。前景 inset 30%（保证圆形/圆角遮罩下
   内容不被切）。上传前在 Android 8+ 真机桌面确认观感；App Store 1024 图标已去 alpha。
6. 设置页联系邮箱 `99999@qq.com` 形似占位数据——确认是否真实客服邮箱（商店审核可能核验）。

## 四、已知残留（后端/异步事项）

- `userToken` 拼在 URL query（后端鉴权协议决定，与小程序一致）：推动后端支持 header 鉴权后移除；
  短期确认服务端 access log 对 `userToken` 参数脱敏。
- 固件下载接口无 hash 字段，无法做完整性校验；后端补 `md5/sha256` 后可加提示级校验。
- BLE/OTA 深层协议错误文案仍为中文（服务层，项目既定暂缓项）；`ble_debug_page` 为内部调试页未翻译。
- 图库批量删除最长约 180s 的阻断 loading 尚无 x/N 进度展示。

