# 2026-10-12 iOS 星币内购接入

> 文档类型：Historical Change Record
> 状态：Historical
> 当前契约：[iOS 内购](../../integration/IOS_IN_APP_PURCHASE.md)

## 交付

- iOS 确认页查询 App Store 商品和价格，建 `payType=2` 订单后通过原生 StoreKit 购买。
- 后端确认接收传统 Base64 收据，新契约提交 `receiptData/orderNo/transactionId`，验成功后由后端发币；新增对应封装并使用本次持久化订单及原生交易号。
- 新增按账号持久化的购买编排，处理取消、失败、延迟批准、前台恢复、重启、手动重试和重复回调。
- 匹配苹果交易、订单已支付及余额完整到账后保存确认并结束交易；验收据成功不等于已发币。
- 新增四语种提示及接口日志脱敏。安卓 PayPal 流程保留；未增加依赖、升级 SDK 或改动平台设置。
- 已核对 Runner 三种配置的 Bundle ID：`com.boltfox.boltstar`，已写入对接文档。

## 验证

- Flutter 3.44.6 / Dart 3.12.2，4 个相关测试文件共 **61 项通过**。
- 改动 Dart 文件静态分析无错误或警告，保留应用层/原 PayPal 页的 5 条既有 info。
- Windows 无 iOS 编译工具链，Swift/iOS 编译、App Store Connect 商品和真实沙盒购买未验收。
- 未调用真实扣款/发币接口，测试使用隔离的原生/后端替身。
- `pubspec.lock` 和 Android 问题报告属于本轮前已有改动，保留且不纳入本次提交。

## 后端待确认

后端正在发布三个请求参数的新版本，已确认验成功负责发币；按用户安排，发布后再核对接口文档。
仍需核对成功返回、按交易幂等发币及到账查询契约，以及真实商品配置。
没有完整交付证据时客户端保持 pending，不结束成功的消耗品交易。详细字段与真机清单只维护在当前契约文档。
