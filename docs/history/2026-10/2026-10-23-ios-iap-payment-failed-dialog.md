# iOS 苹果付款框关闭时提示“支付失败，请重新支付”

> 类型：Historical Implementation Record
> 日期：2026-10-23；环境：远程 SSH 服务器；分支：main；修改前：032ac5d
> 当前契约：[iOS 星币内购](../../integration/IOS_IN_APP_PURCHASE.md) §4.0

## 背景

产品要求：拉起苹果支付后，用户主动点取消，或面容识别失败、密码错误等导致苹果付款框关闭，要弹一个系统提示框“支付失败，请重新支付”，支持多语种。此前只在确认购买页说明处显示“已取消支付” / “本次支付未完成，可以重新购买”，没有弹框。

## 改动

- `AppleIapController`：拉起付款前记下本进程拉起过付款框的订单号；清理 `canceled` / `failed` 交易时，若该订单是本进程拉起的，生成待提示失败 `unannouncedFailure`，`takeFailure()` 取走。换账号、沙盒清理时清除。重启后才清理的上次失败不提示。
- `StarPurchasePage`（iOS）：取走待提示失败后弹 `showAppNoticeDialog`“支付失败，请重新支付”，关掉后留在本页，按钮为“立即购买”；页面打开时丢弃之前的失败；与“购买成功”弹框共用防重入标记，弹框期间又有待提示时关掉后接着处理。
- 文案 `starApplePayFailedRetry`：中“支付失败，请重新支付”、繁“支付失敗，請重新支付”、英“Payment failed. Please try again.”、日“お支払いに失敗しました。もう一度お支払いください。”。
- 测试：取消用例断言提示一次；新增“只提示本进程拉起的付款、重启后清理的失败不提示”；页面取消用例断言弹框、关掉后留在本页且可立即购买。

## 验证

本机无 Flutter，测试、分析未运行；未编译 iOS、未真机。需运行 `flutter test test/apple_iap_test.dart test/apple_iap_reorder_test.dart test/apple_iap_sandbox_reset_test.dart` 与 `flutter analyze`，并在真机沙盒验证：付款框点取消、面容失败后取消、密码输错后关闭，各弹一次；切换英 / 日 / 繁语种文案正确。

## 说明

- 面容识别失败本身苹果会让用户重试或改用密码，付款框不会马上关；最终关闭时 StoreKit 返回取消或失败交易，两种都弹同一句。
- 拉起付款框之前的错误（商品不可用、设备不允许支付等）不弹此框，仍按原说明处理。

## 回滚

撤销本提交即可，无数据迁移。
