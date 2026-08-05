# BoltStar 打包发布指南（Android + iOS）

> 文档类型：Release Runbook
> 状态：Active
> 最后核验：2026-08-05
> 微信登录的完整平台配置见 `../integration/WECHAT_LOGIN_SETUP.md`。
> 2026-07-16 全面审查后整理。本次审查已修复的构建阻断项：
> ① 主 Manifest 缺 `INTERNET` 权限（release 包全部网络请求失败）；
> ② iOS 缺微信回调 `CFBundleURLTypes` 与 Associated Domains entitlements；
> ③ App Store 1024 图标含 alpha 通道（上传直接被拒，已转 RGB）；
> ④ Android 8+ 无自适应图标（已补 `mipmap-anydpi-v26`）。

## 〇、打包前必须核对的微信配置

| 位置 | 当前值 | 要求 |
| --- | --- | --- |
| `ios/Runner/Info.plist` → `CFBundleURLSchemes` | `wx5bc2000b3207f370` | 必须与微信开放平台移动应用 AppID 一致 |
| `ios/Runner/Runner.entitlements` → `associated-domains` | `applinks:example.boltfox.cn` | 真实 Universal Link 域名 |
| 构建命令 `--dart-define` | `WECHAT_APP_ID=wx5bc2000b3207f370` / `WECHAT_UNIVERSAL_LINK` | 与上述配置一致 |

微信侧配套（不做则微信登录不可用）：
- 域名根目录部署 `/.well-known/apple-app-site-association`（含 TeamID `S2HZK3227W` + bundle id `com.boltfox.boltstar`）；
- 微信开放平台后台填写同一 Universal Link；
- **Android**：开放平台登记 `boltstar-release.jks` 的 MD5；debug/profile/release 已统一使用这把证书。

## 〇.5、国内网络前置：pub.dev 镜像（不配则 pub get 报 socket error）

打包机在国内访问 pub.dev 不通（报 `Got socket error trying to find package xxx at https://pub.dev`），
先配 Flutter 官方中国镜像（一次性，`setx` 后**新开终端**生效）：

```bat
setx PUB_HOSTED_URL "https://pub.flutter-io.cn"
setx FLUTTER_STORAGE_BASE_URL "https://storage.flutter-io.cn"
```

已开系统代理的机器可改用 `HTTPS_PROXY` 环境变量，二选一，别混用。

## 一、Android（Windows 打包机，keystore 路径由 `android/key.properties` 指定）

```bash
flutter clean
flutter pub get

# 上架 Google Play（AAB）：
flutter build appbundle --release ^
  --obfuscate --split-debug-info=build/symbols ^
  --dart-define=WECHAT_APP_ID=wx5bc2000b3207f370 ^
  --dart-define=WECHAT_UNIVERSAL_LINK=https://你的域名/app/
# 产物: build/app/outputs/bundle/release/app-release.aab

# 直接分发 APK（可选）：
flutter build apk --release --split-per-abi ^
  --obfuscate --split-debug-info=build/symbols ^
  --dart-define=WECHAT_APP_ID=wx5bc2000b3207f370 ^
  --dart-define=WECHAT_UNIVERSAL_LINK=https://你的域名/app/
# 产物: build/app/outputs/flutter-apk/app-arm64-v8a-release.apk 等
```

### Debug 包（排错用，不分发）

```bash
flutter build apk --debug ^
  --dart-define=WECHAT_APP_ID=wx5bc2000b3207f370 ^
  --dart-define=WECHAT_UNIVERSAL_LINK=https://你的域名/app/
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
  --dart-define=WECHAT_APP_ID=wx5bc2000b3207f370 \
  --dart-define=WECHAT_UNIVERSAL_LINK=https://你的域名/app/
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
4. iOS 真机确认微信回调经 Scene 生命周期可达（fluwx 5.7.7 早于 scene 适配期，
   若回调丢失：升级 fluwx，或删除 Info.plist 的 `UIApplicationSceneManifest` 段
   + `SceneDelegate.swift` 回退经典生命周期）。
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

