# 首页设备卡进我的设备默认对应 Tab、分享设备按钮置灰排查、联调日志浮窗（main）

> 类型：Historical Implementation Record
> 日期：2026-11-12；环境：远程 SSH 服务器；分支：main；修改前：42ae540
> 依据：产品反馈 ① 首页点蓝牙版设备卡进列表要默认显示蓝牙版 Tab，WiFi 版同理（与小程序同日改动一致）；② WiFi 设备「共享设备」页的「分享设备」点不了，提示「暂时无法分享，请稍后重试」，先查前端还是后端原因；③ APP 加一个和小程序类似的左下角联调日志。

## ① 首页设备卡 → 我的设备默认 Tab

- `home_widgets.dart` `_DeviceCarousel.onOpenDevice` 带上点的那台；`home_main_view.dart` 新增 `onOpenDeviceCard`，六宫格「我的设备」仍走无参的 `onOpenDevices`。
- `home_page.dart` `_openDeviceList({MyDevicesTab? tab})`：设备卡按 `isWifi` 传 `MyDevicesTab.wifi / ble` 作路由参数。
- `app_routes.dart` 参数是 `MyDevicesTab` 才认，交给 `DevicesPage.initialTab` → `MyDevicesPage.initialTab`；`initState` 里按「用户选过」处理（`_tabChosen = true`），之后刷新列表不被默认规则改掉，该类没有设备就显示该 Tab 的空态。我的页入口、六宫格入口不带参数，默认规则不变。

## ② 「分享设备」置灰的原因

结论：**前端打包配置问题，不是后端**。

- 按钮置灰（半透明）+ 点了提示「暂时无法分享，请稍后重试」，对应 `wifi_share_page.dart` 的 `_canShare == false` 分支。条件有五个：所有者、`WifiWeChatShare.configured`、当前用户 `userId`、设备 `productId`、设备号。
- `WifiWeChatShare.configured` 要求 `--dart-define=WECHAT_MINI_PROGRAM_USERNAME=gh_…`（小程序原始 ID，且小程序与 App 同在一个微信开放平台账号下）。它**没有默认值**，`docs/runbooks/BUILD_RELEASE.md` 的打包命令与 `.vscode/launch.json` 都没传 → 只要按现有命令打包，按钮必然置灰。10-29 加分享时已写明「未配置时按钮置灰、点了提示暂时无法分享」。
- 后端只可能影响另一条路径：按钮正常、点了以后 `getCurrentTime` 取不到服务器时间戳，也会提示同一句话；那种情况按钮不是灰的。`userId` 来自 `getUserInfo` 出参，取不到也会置灰，日志能区分。
- 本次加了排查日志（进联调日志浮窗）：进页加载完写「身份 所有者 / 接收者」与「分享按钮置灰：原因……」或「可以分享 设备 … 产品 … 用户 …」；点按钮时再写一次；微信未安装、取不到时间戳、拉起微信成功 / 失败各一行。
- 要真正能分享：拿到小程序原始 ID 后打包加 `--dart-define=WECHAT_MINI_PROGRAM_USERNAME=gh_…`（或写进 `WifiWeChatShare.miniProgramUserName` 的默认值，同 `WECHAT_APP_ID` 的做法）。本次没有原始 ID，未改。

## ③ 联调日志浮窗（同小程序 `components/debug-log`）

- `lib/src/shared/debug_log.dart` `DebugLog`：`main()` 最先 `install()` 接管全局 `debugPrint`（控制台照常输出，同时记一份）；最近 500 行只在内存，单行超 2000 字截断；token / 密码类字段入库前打码（与小程序同一套正则）；通知合并到微任务，build 里打日志也不会触发 setState 报错。
- `lib/src/shared/widgets/debug_log_overlay.dart` `DebugLogOverlay`：挂在 `MaterialApp.builder` 上，所有页面（含弹窗之上）左下角一颗「日志 N」药丸（底部抬高 110，不压底部 Tab 与按钮栏），点开 56% 屏高日志框：复制（全部）/ 清空 / 关闭，停在底部时自动跟到最新一行。`DebugLogRouteObserver` 记「页面 → 路由名」（没起名的路由记路由类型）。
- 网络摘要：`api_client.dart` 原只在 debug 包打的 `[HTTP]` 请求 / 返回，开了联调日志的包也打（凭证照旧打码）；`iot_client.dart` 每次 GET / POST / 上传一行「`[IoT]` 方法 路径 参数 → 成功 / 失败 耗时 返回」；`iot_ws.dart` 记「`[WS]` 状态 →」「发 →」「收 ←」，心跳 ping / pong 不记。MQTT 配网参数里的 `pwd` 按打码规则显示为 `***`。
- 开关 `DebugLog.enabled` = `--dart-define=APP_DEBUG_TOOLS`，**默认 debug / profile 开、release 关**（对应小程序「开发版 / 体验版有、正式版没有」）。release 包联调时加 `--dart-define=APP_DEBUG_TOOLS=true`，上架包不要传。
- 花盆APP 的同类浮层是逐条业务日志 + 页面 DP 快照；这里按小程序的口径做成「全局 debugPrint 汇总」，项目里已有的 `[WiFi投屏]`、`[WiFi分享]`、`[BluFi]` 等日志不改就能看到。

## 测试

- 新增 `test/debug_log_test.dart`（打码、500 行上限、截断、接管 debugPrint、通知合并，以及挂载 / 网络层 / 分享页的源码静态核对）、`test/my_devices_initial_tab_test.dart`（源码静态核对）。

## 验证

- 本机无 Flutter / Dart，未 analyze / test / 真机；静态核对的匹配与打码正则用 python 对实际源码 / 同等正则核对通过，git diff --check 通过。
- 需真机看：首页点两类设备卡进列表的 Tab；左下角药丸位置是否挡住各页底部按钮、日志框复制；共享设备页日志里的置灰原因。
