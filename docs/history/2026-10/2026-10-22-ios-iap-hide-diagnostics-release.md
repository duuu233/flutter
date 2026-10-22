# 正式包隐藏苹果支付诊断面板

> 类型：Historical Implementation Record
> 日期：2026-10-22；环境：远程 SSH 服务器；分支：main；修改前：17bd6fd
> 当前契约：[iOS 星币内购](../../integration/IOS_IN_APP_PURCHASE.md)

## 背景

用户确认 iOS 支付流程已联调通过，马上发正式包，要求去掉「确认购买」页底部的调试日志模块。

## 改动

- 「苹果支付诊断详情」整块（商品预检与购买诊断、复制日志、receiptData 开关、清除沙盒购买记录）改为只在 `!kReleaseMode` 显示：
  - debug / profile 包照旧；
  - release 包（App Store 正式包与 TestFlight）不显示。
- release 包的 `AppleIapController` 不再在内存保留诊断行（验单行含收据原文）；阶段日志打印仍仅 debug。
- 购买、重新确认支付、重新下单支付、交付判定与原生交易处理均未改动。
- 没有删除诊断代码与用例：后续联调可用 debug / profile 包查看；现有面板相关用例在测试（debug 模式）下仍覆盖原行为。

## 验证

本机无 Flutter，测试与分析未运行，未编译 iOS、未真机。需在 Mac 打 release 包确认购买页底部不再出现诊断面板，并完成一次正式环境购买回归。

## 回滚

撤销本提交即恢复所有构建模式显示诊断面板。
