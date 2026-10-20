# 2026-10-20 iOS 沙盒支付强制清理与队列诊断

> 类型：Historical Implementation Record
> 环境：work；main；两仓干净、先显式同名 pull 成功。

## 现场与范围

用户在非 debug 包支付页看到初始化 pendingCount=0，随后 unmatched_transaction、pendingCount=1；普通购买已建单却被 payment_busy 拦截，手动重验 matchedCount=0。pendingTransactions 聚合 StoreKit 队列、本地请求占位及失败记录，不等于苹果购买历史条数。用户已清空沙盒历史，明确要求页面按钮强制清理后重新开始；本轮不执行手机操作或真实支付。

## 使用方式

安装包含本轮修改的新 iOS 包，进入当前商品的确认购买页。在底部“苹果支付诊断详情”内点击“清除沙盒支付记录”，阅读范围并确认。原生收据位置为 sandboxReceipt 时才显示入口，Release/TestFlight 同样可用；环境未知或正式收据时隐藏，原生方法也会重新拒绝非沙盒调用。

清理仅作用于当前商品的可结束测试交易、请求占位和失败记录，其他账号在本机已有订单映射关联的交易保留。当前账号、当前商品的恢复记录标记 sandboxDiscarded 并保留原字段归档；其他账号和其他商品记录不删除。原生被处理的交易摘要及占位/失败快照保存在本机专用归档键，不输出账户 UUID 或凭证。结束苹果交易不可撤销，不发币，不退款，不删除后台业务订单，也不自动重新付款。

## 行为及边界

- 原生仅结束 purchased/restored/failed；当前商品若存在 purchasing/deferred/未知状态，整次清理在修改前拒绝。用户先在 Apple 完成或取消，不能对 purchasing 调 finish 导致异常。
- 当前账号其他商品仍有活动恢复记录时拒绝；其他账号或其他商品的原生队列记录保留，并通过“清理尚未完成”反馈，不能显示假成功。
- 原生清理后重新查询全部 pending 记录；仅无剩余且本地归档保存成功才输出 sandbox.reset.completed / pendingCount=0，重置为 idle。持久化失败保留原恢复记录，可再次清理。
- 本轮清理过的交易 ID 保存在原生归档中；沙盒同一交易重投递时只重复结束已明确放弃的交易，不污染新的订单。正式环境不使用这条调试恢复路径。
- 清理与购买/重验串行；当前账号切换期间只归档发起清理的账号。原生实际范围同时受保护账号 token 和商品限制。
- 普通购买与重新下单都先查询原生队列；已有阻塞记录时在建单前拒绝，避免继续生成未发起 Apple 支付的业务订单。查询后的极短竞态仍由原生 buy 门禁保护。
- recovery.queue.entry / purchase.queue.entry 及 sandbox.reset.before/remaining 记录 source（storekit/request/failure）、state、商品、匹配数量；已知其他账号的交易号不展示，账户 UUID 不打印。
- 原有 verify.request 完整 receiptData 与 verify.response 完整 responseData/exceptionMsg 页面输出保持。强制清理不是验单成功，原后端 responseData 明细与发币联调问题仍待验收。

## 验证

Flutter 3.44.6 / Dart 3.12.2；新增沙盒清理、隔离、拒绝、重启、持久化失败、串行和页面确认/取消/小屏大字回归，连同既有三个苹果支付文件一起运行。最终四文件共 **72 项测试通过**（含新增15项）；修改Dart文件专项无error/warning，保留PayPal页面既有跨异步context info；本机 Windows 无 Xcode，未编译 Swift、未打 iOS 包、未做 TestFlight/沙盒真机操作。Dart fake 与 MethodChannel 模拟不等同于 StoreKit 实机验证。

全库静态检查发现既有 test/user_agreement_content_test.dart 的 AppLanguage 未定义及其他既有诊断，不能写为全库通过。原有跨异步 PayPal 页面提示保留；本轮新增诊断修复后按修改文件专项复核。

参考：[苹果 finishTransaction 状态约束](https://developer.apple.com/documentation/storekit/skpaymentqueue/finishtransaction%28_%3A%29)、[沙盒购买历史管理](https://developer.apple.com/help/app-store-connect/test-in-app-purchases/manage-sandbox-apple-account-settings/)。
