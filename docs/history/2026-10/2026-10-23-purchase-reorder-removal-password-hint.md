# 确认购买页去掉重新下单入口、密码规则提示补充不支持符号

> 类型：Historical Implementation Record
> 日期：2026-10-23；环境：远程 SSH 服务器；分支：main；修改前：d845231
> 当前契约：[iOS 星币内购](../../integration/IOS_IN_APP_PURCHASE.md) §4.1

## 背景

1. 产品要求去掉「确认购买」页下方的“重新确认只处理原交易，不会再次付款。需要新订单时，请使用下方入口。”说明和“重新下单支付”按钮。
2. 核对邮箱账号密码规则是否支持符号；不支持则在规则报错提示里写明。

## 结论与改动

- 确认购买页（`star_purchase_page.dart`）：删除上述说明与按钮（`Key('apple-new-order')`）及其二次确认逻辑；页面只保留底部“重新确认支付”。`_buyApple` 不再带 `newOrder` 参数。删除不再使用的文案 `starAppleNewOrder` / `starAppleNewOrderNote` / `starAppleNewOrderConfirm`；`starAppleNewOrderBlocked` 保留（控制器仍可能给出 `new_order_blocked`）。
- `AppleIapController.buy(newOrder: true)` 的阻断与 `supersededBy` 逻辑及其单元测试不动，仅无界面入口。
- 密码规则：注册、忘记密码、修改密码三处同一正则 `^(?=.*[A-Za-z])(?=.*[0-9])[A-Za-z0-9]{6,12}$`，**只允许字母和数字，不支持符号**；登录页不校验格式。与 FAQ（`content/操作手册与常见问题-四语种.md`）一致。`accPasswordRuleError` 三语补充：
  - 中文：密码需为6-12位数字和英文字母组合，不支持符号
  - English: Password must be 6-12 characters and contain both letters and digits. Symbols are not supported.
  - 日本語：パスワードは英字と数字を含む6〜12桁で入力してください（記号は使用できません）
- 测试：`apple_iap_reorder_test.dart` 中重新下单的界面用例改为断言按钮与说明不存在、重新确认仍不再次付款；删除取消/阻断两条界面用例；小屏大字用例改为只看重新确认；本地化用例去掉已删文案。

## 验证

本机无 Flutter，测试与分析未运行，未编译、未真机。需在有 Flutter 的环境运行 `flutter test test/apple_iap_reorder_test.dart` 与 `flutter analyze`，并在 iOS 真机确认确认购买页底部只剩“重新确认支付”。

## 回滚

撤销本提交即可恢复入口与文案，无数据迁移。
