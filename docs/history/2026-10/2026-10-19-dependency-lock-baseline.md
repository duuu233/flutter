# 恢复 SDK 锁定基线并忽略 Android 报告

> 文档类型：Historical Change Record
> 日期：2026-10-19
> 环境：办公室
> 分支与起始版本：main / 2e3a72b
> 当前约定：../../runbooks/BUILD_RELEASE.md 〇.6a

## 需求与同步

用户要求忽略 HTML 构建报告，结合近期提交检查全部依赖，判断是否删除锁文件或放宽版本，并自行实测打包后提交。开始时仅 pubspec.lock 和 Android HTML 有已有本地差异；保留两文件显式快进拉取 origin main 成功，未切分支、stash 或覆盖用户源码。读取项目规则、上下文、文档入口和构建指南，拉取后同步已有索引，并通过 CodeGraph 核对近期支付桥接。

## 根因与选择

- 本机配置明确指向的 SDK 实际为 Flutter 3.44.6 stable / Dart 3.12.2，与项目既定基线一致；不是仅凭 PATH 未发现 flutter 就认定 SDK 缺失。
- 已批准回退 a84ea3f 的锁文件 Git blob 为 77c16f5479ab96faa158bd7088abfa67a44f9ff7；本轮修复后的锁文件完全一致。960d2f3 在修改构建号时再次提高 intl、matcher、meta、test_api、vector_math 五项版本，与该 Flutter SDK 的精确约束冲突。之后至起始 HEAD 的依赖清单只改构建号，没有新的业务依赖要求。
- 本轮按用户授权有意修复这五项锁定结果及校验值，不删锁文件、不放宽约束、不升级工具链、不增加 overrides；pubspec.yaml、原生平台设置、签名及业务/测试源码均未改动。多数直接依赖原本已是 caret 或区间，现有 image 精确限制也不顺手改。
- Android .gitignore 增加 /build/；原报告仅从 Git 索引移除，本机文件保留并可由本次构建更新，不重写历史。开始时本地报告及锁文件已备份，不提交备份、报告、APK 或完整原始日志。

## 依赖核对

- `flutter pub get --enforce-lockfile` 成功；lock blob 始终不变。127 个锁定包及项目自身共 128 个配置节点，逐包 manifest/lock 版本、188 项 Dart/Flutter 环境约束、319 条实际依赖版本边全部通过；14 项 Flutter SDK 精确钉版本一致。临时核对脚本最初把目录 URI 当文件 URI 处理，修正目录尾斜杠后重新核验通过，不把脚本初次误报当作缺失包。
- 五项恢复：intl 0.20.2、matcher 0.12.19、meta 1.18.0、test_api 0.7.11、vector_math 2.2.0；其它所有锁定包保持。关键既有版本含 flutter_blue_plus 2.3.10、fluwx 6.0.0、image_picker 1.2.3、image_picker_android 0.8.13+17、image_cropper 12.2.1、shared_preferences 2.5.5、speech_to_text 7.4.0、image 4.9.1、objective_c 9.4.1，不追随可用更新。

## 实际验证

| 检查 | 结果 |
| --- | --- |
| 强制锁文件解析、全部依赖约束核验 | 通过，未改写锁文件 |
| 全量 flutter test --no-pub | 308 通过，5 失败，退出1 |
| 五文件苹果内购、重下单及充值展示专项 | 95 通过，退出0 |
| flutter analyze --no-pub | 68 项：1 error、10 warning、57 info，退出1 |
| Android release 三 ABI APK | 成功，Gradle 190.6秒，总命令约194.4秒 |
| APK ZIP、ABI关键条目、aapt元数据 | 通过，包名 com.boltfox.boltstar，versionName 1.0.0，versionCode 2008，minSdk 24、targetSdk/compileSdk 36 |

构建沿用既有签名配置及微信公开配置，执行 `flutter build apk --release --no-pub --split-per-abi --obfuscate --split-debug-info=build/symbols` 并传既有 WECHAT_APP_ID / WECHAT_UNIVERSAL_LINK。没有更改版本号或上传安装包。产物为本轮新生成，不引用旧 APK 作为成功证据：

| 产物（build/app/outputs/flutter-apk 下） | 字节数 | SHA-256 |
| --- | ---: | --- |
| app-armeabi-v7a-release.apk | 22627836 | CDBBCF0C9209526908B707A2DBFABC3F4AEFD7B6A7B946E5C5553C5A242CF35B |
| app-arm64-v8a-release.apk | 24936676 | 828BA2029F2B77CB416987D1D3C5A97059F229DC5D62237E05BA194EB58186FD |
| app-x86_64-release.apk | 26460032 | D9801A482D8200467C13894A7BDEE27C28507427DBAB4882B2FBD41C56B69E13 |

## 未通过项与边界

- 全量失败是现有测试中的 AppLanguage 未导入/未定义（user_agreement_content_test.dart:113）、unused_assets_test 的未引用图片检查、widget_test 的首页/英文/日文启动断言三项。本轮未修改 lib/ 或 test/，不为凑绿灯删除断言、资源或改业务；不声称全量检查通过。
- 静态分析 error 同为测试 AppLanguage 未定义，另有10项既有源码未使用元素/恒真判断警告和57项提示；未做无关清理。
- doctor 仍提示 Android cmdline-tools 缺失/许可证状态未知及 Windows 桌面工具链缺失；本次 Android 构建实际成功，不据此认定环境所有项目均合格，未自动安装组件或接受许可证。
- 构建输出有生成 ELF 含未混淆 DWARF 调试信息的警告。本轮保留原构建配置和符号产物，不声称已完成发布安全审查。
- Windows 不能运行 Xcode/CocoaPods 或生成 IPA。iOS 当前 Podfile 和 Runner deployment target 仍为15.0，原回退待办未处理；只证明 Dart/Flutter 约束和 Android release，不承诺全部 iOS 原生依赖已编译或 StoreKit、微信、BLE 真机行为均正确。支付专项使用模拟桥接，不是真实扣款/发币验收。

## 交付与恢复

提交前核对差异、忽略、业务与测试源码未变和信息隔离；只提交依赖基线、忽略及维护文档。按要求提交当前 main，推送前再次显式快进拉取，再推送同名分支；不合并、部署或打标签，最终提交号以 Git 输出为准。

其它电脑使用 Flutter 3.44.6 / Dart 3.12.2，拉取后执行 `flutter pub get --enforce-lockfile`，避免用不同 SDK 重新污染锁文件。删除锁文件后的构建报错通常可以定位部分约束/编译问题，但无法证明所有运行路径或未来解析稳定，因此本轮保留经过核对的精确版本。需要撤回时单独回退本轮提交，回到修复前锁文件会重新引入与既定 SDK 的冲突，不能当作长期解决方案。
