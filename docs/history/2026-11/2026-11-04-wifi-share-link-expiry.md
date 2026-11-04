# main-wifi：WiFi 版分享卡片带服务器时间戳（分享链接有效期，对齐小程序）

> 对应小程序：`photo-album` main-wifi 6a22233 / 68c8306（2026-11-04：服务端新增 `GET /Client/UserProduct/getCurrentTime`、`GET /Client/UserProduct/chkTimeValid`）

## 做了什么

小程序的分享流程加了有效期：分享时取服务器时间戳写进卡片参数 `t`，被分享人在小程序接受页用 `chkTimeValid(currentTime=t)` 校验，`retData` 为 `false` 显示「分享链接已过期」；**不带 `t` 的卡片小程序一律按「分享链接无效」处理**。App 发出的是同一张小程序卡片，所以必须同步，否则 App 分享出去的卡片全部打不开。

- `BoltFoxApi.getCurrentTime()`：`GET /Client/UserProduct/getCurrentTime`，`retData` 为 long。
- `wifi_share.dart`：新增 `wifiShareTime`（`retData` → 时间戳字符串，原样不换算；不是正整数返回 null）；`WifiShareLink.acceptPath` 新增 `shareTime` → 参数 `t`，与小程序 `buildAcceptPath` 同格式。
- 分享列表「分享设备」：确认装了微信后，**分享这一刻**取一次服务器时间戳写进卡片；取不到不发卡片，提示「暂时无法分享，请稍后重试」。App 没有小程序 `onShareAppMessage` 的同步限制，不需要进页面预取。
- 校验 `chkTimeValid` 只在小程序接受页做（App 没有接受入口），App 不调。

## 测试

- `test/wifi_tf_share_test.dart` 补：卡片路径带 `t`（与小程序同编码）、`wifiShareTime` 对数字 / 字符串 / 空 / 0 / 非数字 / 小数的处理。
- 本机没有 Flutter 工具链，**未 analyze、未跑测试、未编译、未真机**；请本地 `flutter analyze` + `flutter test`。
