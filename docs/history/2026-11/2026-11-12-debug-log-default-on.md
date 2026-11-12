# 联调日志浮窗默认开启、分享置灰原因写进提示（main）

> 类型：Historical Implementation Record
> 日期：2026-11-12；环境：远程 SSH 服务器；分支：main；修改前：905b81a
> 依据：产品反馈 iOS 上看不到左下角联调日志，分享仍提示「暂时无法分享，请稍后重试」。

## 原因

- 浮窗开关 `APP_DEBUG_TOOLS` 原默认 `!kReleaseMode`：iOS 测试走 Archive / TestFlight，是 release 包，浮窗整套不生效。
- 「暂时无法分享」现只在：不是所有者 / 取不到当前用户 userId / 设备无产品 ID / 设备号为空，或分享时取不到服务器时间戳（`getCurrentTime`）。bbe207a 之前的包还要求打包传小程序原始 ID，没传就一定是这句；测试包若早于 bbe207a，现象相同。具体卡在哪一条需看日志（本机无法登录用户账号复现）。

## 改动

- `debug_log.dart`：`APP_DEBUG_TOOLS` 默认 `true`（同花盆APP），release / TestFlight 包也有浮窗；正式上架包打包加 `--dart-define=APP_DEBUG_TOOLS=false`。`BUILD_RELEASE.md` 配置表与 AAB / IPA 命令下补提示（测试包不传）。
- `wifi_share_page.dart`：开了联调日志的包，置灰提示直接带原因，如「暂时无法分享，请稍后重试（取不到当前用户 userId）」；取不到服务器时间戳也写明。正式包仍只显示原句。
- `test/debug_log_test.dart` 默认值与提示断言同步。

## 验证

本机无 Flutter / Dart，analyze / test / 真机均未跑；断言用 python 对源码核对，git diff --check 通过。
