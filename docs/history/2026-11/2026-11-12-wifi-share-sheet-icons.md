# WiFi 分享弹层改图标宫格、加系统分享（main）

> 类型：Historical Implementation Record
> 日期：2026-11-12；环境：远程 SSH 服务器；分支：main；修改前：7aa0118
> 依据：产品要求「分享设备」弹层（发给微信好友 / 复制链接）改成带图标的样式，并兼容海外社交分享；`runbooks/WIFI_SHARE_H5.md` 一节已列出「网页卡片 / 系统分享 / 复制链接」三种发法。

## 改动

- `wifi_share_page.dart`：弹层由两行列表改为图标宫格 + 底部「取消」。三格依次为：
  - 「微信好友」：用微信图标 `pay-wechat.png`，发网页卡片。只有装了微信才显示，海外用户多半没装。
  - 「更多应用」：调起系统分享面板，发「邀请文案 + 链接」纯文本，WhatsApp、LINE、Messenger、Telegram、邮件、短信等都能收。
  - 「复制链接」。
- 系统分享走原生通道 `shareText`，没有新增 Flutter 依赖，`pubspec.lock` 不变：
  - Android：`MainActivity` 用 `ACTION_SEND` 选择器。
  - iOS：`AppDelegate` 用 `UIActivityViewController`，iPad 上以 popover 弹出，并带锚点。
  - Dart 侧入口是 `NativeDeviceApi.shareText`。
  - 能拉起分享面板就返回 true，拉不起提示「分享失败」。
- 文案：`wifiShareToWeChat` 改为「微信好友 / WeChat」，以便放进宫格。新增 `wifiShareMoreApps`（更多应用 / More apps / 他のアプリ）。
- `test/wifi_share_link_test.dart`：新增源码断言，覆盖弹层、Dart 通道和两端原生实现。

## 验证

本机无 Flutter / Dart / Xcode / Android SDK，analyze、test、编译和真机都没跑；新增断言已用 python 对源码核对，`git diff --check` 通过。原生代码需要打包验证，重点看 iPad 的 popover 和 Android 选择器标题。
