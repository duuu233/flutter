# 系统分享面板预览卡显示 APP 图标（main）

> 类型：Historical Implementation Record
> 日期：2026-11-13；环境：远程 SSH 服务器；分支：main；修改前：1248a69
> 依据：产品要求系统分享面板顶部的图标可自定义，先用 APP 自带图标。

## 改动

- Dart 不改：`NativeDeviceApi.shareText` 已传 `subject`（邀请标题），用作预览卡标题。发出去的内容仍是「邀请文案 + 链接」纯文本。
- iOS `AppDelegate.swift`：分享内容改为 `ShareTextItemSource`（`UIActivityItemSource`）。它用 `activityViewControllerLinkMetadata` 返回 `LPLinkMetadata`：标题是 subject，为空时取 APP 显示名；图标取 Info.plist `CFBundleIcons` 中最大的一张，取不到时退回 `AppIcon`。subject 同时作为邮件等的主题。部署目标 15.0，LinkPresentation 无需版本判断。
- Android：
  - 新增 `ShareIconProvider`：只用系统 API 写的只读 ContentProvider，不导出，authority 为 `${applicationId}.shareicon`。
  - 首次分享时把 `getApplicationIcon`（含自适应图标）画成 192px PNG，存到 `cacheDir/share/app_icon.png`。
  - `MainActivity.shareText` 在 ACTION_SEND 上加 `EXTRA_TITLE`（标题），并加 `ClipData` 与 `FLAG_GRANT_READ_URI_PERMISSION`（缩略图）。图标生成失败时不带缩略图，分享照常。
  - 只有 Android 10+ 的系统分享面板显示预览卡，部分厂商自带的分享面板不显示。
- 不新增依赖，不动 Gradle / Podfile。以后换成后台上传的图片，只需改图标来源。

## 验证

本机无 Flutter / Xcode / Android SDK，编译和真机都没跑。新旧文件的括号配平一致，Manifest 的 XML 解析通过，`git diff --check` 通过。
