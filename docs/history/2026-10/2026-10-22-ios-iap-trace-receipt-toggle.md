# iOS 验单阶段诊断与收据显示开关

> 类型：Historical Implementation Record
> 日期：2026-10-22；分支：main；修改前：b311383
> 当前契约：[iOS 星币内购](../../integration/IOS_IN_APP_PURCHASE.md)

用户反馈支付待确认、后台未见日志，同时完整收据太长，复制后粘贴没有反应。提供的历史日志已到 `verify.response`：status=0、Sandbox、responseData为空、exceptionMsg为“平台产品与凭据不符合”。该次已经获得后端返回，随后因明细不匹配而停在 receipt_unverified。自动恢复跳过重复POST，手动重验才重新提交。Postman只返回“订单已支付”和空明细，尚不能证明客户端原请求上下文、当前明细及到账条件相同。

另有Apple原生弹窗21104。缺少该次原生错误调用阶段，不推断其精确定义，不与Apple验单21004混为一谈。没有改为客户端直连Apple，也没有降低交易归属、SKU/transaction_id、查单和余额交付条件。

实施内容：

- 支付页标题旁增加“显示 receiptData”开关，默认关闭；页面与复制共用过滤结果，保留收据长度、订单号、交易号。打开后完整原文仍可复制，不改真实请求和内存原日志。所有构建模式可用；四语种文案齐全。短屏和大字下标题/开关可换行。
- 剪贴板写入期间阻止重复点击，失败或5秒未响应时提示。系统成功回执不保证目标应用允许粘贴，需真机复核。
- 在验单的异步作用域记录实际HTTP请求、响应和失败：host/scheme/path、attempt、httpStatus、retCode、耗时；不记录query、header和body。不改变原接口三个JSON参数和禁用自动重试的约定。作用域结束释放观察回调，换账号后忽略迟到诊断。
- 交易未匹配、购买中、失败、交易号不符、收据不可用时输出verify.blocked与backendCalled=false。原生付款/收据错误保留脱敏domain/code/message和最多三层底层错误；失败归档保留标量错误字段，不保存完整NSError userInfo。
- 成交后读取本地收据最多3次（0/250/750ms）；只有receipt_missing进入被动重读。手动重验仍缺失时只刷新一次，Apple失败不自动循环。忙碌期间收到手动重验保留manual标记，账号切换清除该标记。

验证：Flutter3.44.6/Dart3.12.2，未升级依赖或平台设置。

```powershell
flutter test --no-pub test/apple_iap_test.dart test/apple_iap_reorder_test.dart test/apple_iap_sandbox_reset_test.dart test/apple_iap_product_diagnostics_test.dart test/apple_iap_trace_toggle_test.dart test/star_purchase_test.dart
```

115项通过，其中新增8项覆盖被动读取迟到收据、手动刷新失败、串行手动重验、真实ApiClient模拟业务拒绝、传输失败无自动重复POST/作用域隔离、16,000字符收据开关与复制、剪贴板失败反馈及四语文案。既有支付、账号隔离、小屏大字和PayPal回归通过。静态检查改动的8个Dart/测试文件，无error/warning及新增info；保留原PayPal页面既有use_build_context_synchronously提示，analyze退出1。

Windows未编译Swift/Runner、未制作新iOS包、未访问App Store Connect、未调真实验单或发币接口。需Mac编译后覆盖安装，在普通Release/TestFlight验证开关与复制，再采集同一订单的分阶段日志；后端核对SKU/Bundle映射、原账号请求与Postman差异及幂等返回/交付协议。当前修改不能视为Apple21104或后端产品不符已经解决。
