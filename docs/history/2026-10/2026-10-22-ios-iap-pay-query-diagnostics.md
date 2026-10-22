# iOS 查单诊断记录原始返回

> 类型：Historical Implementation Record
> 日期：2026-10-22；分支：main；修改前：78b8537
> 当前契约：[iOS 星币内购](../../integration/IOS_IN_APP_PURCHASE.md)

## 背景

沙盒订单 `2026102265350540002900223`（xb1，2500 星币）的诊断日志：
- 苹果扣款成功；
- `setApplePayVerifyReceipt` 返回 HTTP 200、retCode 200；
- 苹果明细与本交易匹配（`responseMatches=true`）；
- 余额 6065 → 8565，正好多了 2500。

但 8 次 `delivery.order.response` 都是 `orderPaid=false`，页面停在 `delivery_unconfirmed`，交易未结束。原诊断只记录布尔值，而查单异常也被吞成 `false`，所以分不清是后端返回 `payState≠1`，还是查单请求本身失败。

## 改动

- 苹果查单改为返回 `AppleOrderQuery`：
  - 后端有返回时，保留 `payState` 原值（不做类型转换）、`payNo`、`exceptionMsg`；
  - 请求失败时，保留错误类型、`ApiException` 业务码和信息；其它异常记录其文本。
- `delivery.order.response` 在原 `orderNo/orderPaid` 之后附加上述字段：
  - 有返回：`payState/payNo/exceptionMsg`；
  - 失败：`errorType/code/message`。
- 文本仍经原诊断脱敏规则处理（隐藏 URL、邮箱、token 类字段，超长截断）。
- 判定口径不变：`payState` 按整数解析为 1 才算已支付；查单失败仍按未支付处理、不 finish、不重复验单。PayPal 的查单路径未改。

## 验证

本机（SSH 服务器）没有 Flutter/Dart，测试与静态检查**未运行**，未编译 iOS、未真机。新增用例覆盖：
- 原始 `payState` 字符串 `"0"`、`payNo`、`exceptionMsg` 进入日志；
- `ApiException(500)` 的类型、码、信息进入日志，且不 finish；
- 字符串 `"1"` 仍按已支付完成交付。

需在有 Flutter 3.44.6 的电脑运行：

```powershell
flutter test --no-pub test/apple_iap_test.dart test/apple_iap_reorder_test.dart test/apple_iap_sandbox_reset_test.dart test/apple_iap_product_diagnostics_test.dart test/apple_iap_trace_toggle_test.dart test/star_purchase_test.dart
```

## 使用

重新打包后，在原订单上点「重新确认支付」。看 `delivery.order.response`：
- 出现 `payState`：后端已返回，按其值与 `exceptionMsg` 和后端核对订单状态；
- 出现 `errorType/code/message`：查单请求本身失败。

两种情况都不会重复扣款或重复验单。

## 同日第二轮：诊断台最新在上、复制限量

真机反馈：诊断台整段太长，复制不起作用；需要最新日志放最上面，并且只复制最新的。

- 面板改为倒序展示，最新一条在最上面。商品查询失败的错误行改为按发生顺序追加，倒序后排在本次查询各行之上。
- “复制日志”只从最新开始复制，累计不超过 8,000 字符；最新一条无论多长都完整保留。未全部复制时提示“已复制最新 N 条”（四语种）。
- 显示内容与真实验单参数不变，完整收据仍可打开开关后在页面选择复制。
- 用例：收据开关用例改为验证倒序、复制为最上面的连续一段且不超过上限、开启收据时 16,000 字符收据行不进复制；新增复制上限的纯函数用例。本机无 Flutter，未运行。
