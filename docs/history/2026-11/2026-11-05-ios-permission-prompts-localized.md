# iOS 权限弹框文案按四语种本地化（审核 Guideline 4）

> 类型：Historical Implementation Record
> 日期：2026-11-05；环境：远程 SSH 服务器；分支：main；修改前：68dc1b4

## 背景

App Store 审核 1.0.1 (2)（iPad Air 5th）以 Guideline 4 - Design 驳回：权限请求文案与 App 本地化语言不一致。
App 支持简中 / 繁中 / 英 / 日，系统语言不在四语种内兜底英文；而 `Info.plist` 的权限文案只有简体中文，工程也只有 `en` / `Base` 两个区域，英文系统下界面是英文、授权弹框却是中文。

## 改动

- 新增 `ios/Runner/{en,zh-Hans,zh-Hant,ja}.lproj/InfoPlist.strings`，覆盖全部 8 个权限键：蓝牙（Always / Peripheral）、定位、相册读取、相册写入、相机、麦克风、语音识别。简中沿用原文案；繁中、日文、英文用词对齐 App 内文案（フォトフレーム / キャスト / AIアシスタント、AI Assistant 等）。
- `project.pbxproj`：新增 `InfoPlist.strings` 变体组并加入 Runner 的 Resources；`knownRegions` 补 `zh-Hans`、`zh-Hant`、`ja`。
- `Info.plist`：权限键的值改为英文兜底（系统语言不在四语种内时显示，与 App 兜底英文一致）；新增 `CFBundleLocalizations`（en / zh-Hans / zh-Hant / ja）。
- 权限弹框语言跟随系统语言，不跟随 App 内「语种设置」，这是 iOS 机制。

## 验证

- 本机无 Xcode / Flutter，未构建、未真机；`Info.plist` 用 plistlib 解析通过，pbxproj 括号配平。
- 需在 Mac 上用 Xcode 打开确认 Runner 下出现 InfoPlist.strings（4 个语种），再把系统语言分别切到英文、日文，触发蓝牙 / 相册 / 相机 / 麦克风授权核对文案。
- 提审前递增 build number（当前 `1.0.1+2` 已被审核过）。
