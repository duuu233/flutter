# WiFi 分享改为直接调系统分享（main）

> 类型：Historical Implementation Record
> 日期：2026-11-12；环境：远程 SSH 服务器；分支：main；修改前：770d64f
> 依据：产品要求点「分享设备」直接调起系统级分享，不再先弹自定义面板。

## 改动

- `wifi_share_page.dart`：去掉图标宫格弹层（`_pickShareWay` / `_ShareWay`）。原有的置灰校验和取服务器时间戳不变，生成邀请链接后直接调用 `NativeDeviceApi.shareText`，发「邀请文案 + 链接」纯文本。Android 用 `ACTION_SEND` 选择器，标题「分享设备」；iOS 用 `UIActivityViewController`。原生实现沿用 770d64f。面板拉不起时提示「分享失败」。
- 微信、WhatsApp、LINE、Messenger、Telegram、邮件、短信、复制都由系统面板提供。微信里收到的是文字链接，不再是带缩略图的网页卡片。
- 删除只给分享发网页卡片用的 `wifi_wechat_share.dart`，以及不再使用的文案：微信好友、复制链接、更多应用、已复制、未装微信、卡片描述。微信登录的 fluwx 不受影响。
- `test/wifi_share_link_test.dart`：断言改为直接调系统分享，并确认不再有自定义弹层和微信卡片。`docs/runbooks/WIFI_SHARE_H5.md`、`docs/integration/APP_VS_MINIPROGRAM.md` 同步更新。

## 验证

本机无 Flutter / Dart / Xcode / Android SDK，analyze、test、编译和真机都没跑；断言已用 python 对源码核对，`git diff --check` 通过。
