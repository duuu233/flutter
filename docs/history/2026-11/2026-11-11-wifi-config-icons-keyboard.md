# WiFi 配网页图标与小程序一致、输入框橙色边框、配网状态页键盘关不掉（main）

> 类型：Historical Implementation Record
> 日期：2026-11-11；环境：远程 SSH 服务器；分支：main；修改前：aa5d247
> 依据：产品反馈 ① WiFi 配网页顶部图标与小程序保持一致（可直接用小程序的图）；② WiFi 密码输入框的橙色边框显示不正常；③ 设备配网页底部一直有键盘、关不掉，进后续页面也关不掉，挡住按钮；④ 对照小程序把 WiFi 版配网页同步过来。

## 原因

- ② 输入框外层自绘了灰框，内层 TextField 只写了 `border: InputBorder.none`。全局 `AppTheme.inputDecorationTheme` 给了 `filled` 白底和橙色 `focusedBorder`（18 圆角、1.2 描边），`enabledBorder` / `focusedBorder` 不为空时不会回落到 `border`，于是聚焦时橙框画在 `isCollapsed` 的内层上，紧贴文字、被外框裁掉。
- ③ 「下一步」直接 push 配网状态页，靠路由切换把焦点从密码框移走。部分机型上输入连接先断开、键盘没跟着收起；配网状态页没有输入框，全局「点空白收键盘」找不到焦点，收不回来，之后的页面也一直挡着。
- ① 头图原本用 Material 图标拼成（手机 / 相框 / 云三个浅色圆），切换与小眼睛、WiFi 列表行图标也是 Material 图标，和小程序的 svg 不一样。

## 改动

- 新增 `wifi/presentation/wifi_glyphs.dart`：按小程序 `wifi-provision-art.svg`、`wifi-switch.svg`、`eye-open.svg` / `eye-closed.svg`、`badge-wifi.svg` 的同一组坐标用 CustomPaint 绘制（渐变圆、光晕、点线箭头、云朵贝塞尔原样照抄）。本仓无 SVG 依赖，按工具链基线不引入 flutter_svg，做法同设备详情的屏幕尺寸图标。
- `wifi_config_page.dart`：
  - 头图换成 `WifiProvisionArt`（300×120，同小程序 600rpx × 240rpx）；切换图标、小眼睛换成小程序同款，点击区 40 见方。
  - 输入框：内层 `enabled/focused/disabled/error` 边框全部置空、`filled: false`；用 FocusNode 跟踪聚焦，聚焦时整个输入框描 #FF6A24 1.2 边，未聚焦为小程序同款浅灰边（rgba(42,43,43,.06)）、白 86% 底、10 圆角；标题 14 粗体。
  - 设备名与尺寸并排一行（同小程序 `.wifi-device`），间距按小程序换算。
  - 「下一步」与切换图标离开本页前先 `primaryFocus?.unfocus()`，让键盘在输入连接还挂着时正常收起（同登录页提交前的做法）。
- `wifi_provision_page.dart`：
  - 进页时再兜底一次：解除焦点 + `TextInput.hide`，残留的键盘直接收掉。
  - 头图共用 `WifiProvisionArt`；状态列表对齐小程序 `.provision-steps`：每行 48 高、行间细分隔线、文字 14（执行中加粗），状态圈 20 见方——未开始白底灰边序号、执行中橙色转圈、通过橙色渐变打勾、失败红色打叉（固件升级页共用同一状态圈，小程序两页也是同一套样式）。
  - 配网跑完（成功或失败）即恢复息屏，不等离开页面（同小程序 `start()` 的 finally）。
- `wifi_list_page.dart`：每行前的图标换成小程序 `badge-wifi.svg` 同款。
- 新增 `test/wifi_config_keyboard_test.dart`（源码静态核对）。

配网流程本体（四步、MQTT 参数、国家码、绑定参数、120 秒在线轮询）与小程序逐步对照一致，本次未改。

## 验证

- 本机无 Flutter / Dart，未 analyze / test / 真机；新测试的匹配用 python 对实际源码核对通过，括号配平、git diff --check 通过。
- 需真机确认：图标观感；聚焦描边；在密码框弹出键盘后点「下一步」，配网状态页与后续页面不再残留键盘（Android 各厂商键盘与 iOS 都要看）。
