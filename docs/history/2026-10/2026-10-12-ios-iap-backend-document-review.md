# 2026-10-12 iOS 支付后端文档审查

> 文档类型：Historical Review Record
> 状态：Historical
> 审查基线：main / caa6ec2
> 对齐问题：[后端文档与客户端对照](../../integration/IOS_IAP_BACKEND_ALIGNMENT.md)
> 当前协议：[iOS 内购](../../integration/IOS_IN_APP_PURCHASE.md)

## 范围与结论

读取最新四个内购相关提交及构建号提交，审查后端两份材料、Word 内全部七张截图、当前 Dart/Swift 实现及 2026-10-12 19:37（Asia/Shanghai）无缓存线上 Swagger。

- 验收据请求的 orderNo/transactionId 已在 Swagger 发布，旧 excludeOldTransactions 已移除；成功返回 DTO 仍为 status/environment/latestReceipt/responseData/exceptionMsg。
- 线上声明成功码为 200，建单为 addOrder；示例的 retCode=1 与 setCreatePay(goodsId) 和线上 DTO 不符。保留现有客户端协议，记录示例纠正事项。
- 异步发币、当前交易精确匹配、明细可选、重复验单和已发币查询仍需后端确认，形成六项可转发的问题稿。
- 更新当前内购文档、API 文档、上下文和文档索引；新增独立审查记录。没有修改支付源码、依赖或平台构建配置。

## 验证与限制

Flutter 3.44.6 / Dart 3.12.2；四个既有相关测试文件共 61 项通过，测试使用隔离的后端与原生替身。差异、文档引用和信息隔离检查通过；CodeGraph 已按当前代码同步。

Windows 未编译 iOS/Swift，未联调实际购买、账户发币、苹果商品或服务端幂等；Swagger 与示例不等于服务端运行验收。原生 StoreKit 1 方案保留。待确认的交付条件、完整差异及问题稿统一维护在上述对照文档。

## 原始材料完整性

两份用户提供的未跟踪材料仅只读审查，pull 前后和交付前 SHA256 一致，未纳入本轮提交：

- `docs/ios-iap-frontend-examples.md`：`B6ABDC8DA8A0F9BE85B2460123107FB9FCE9F3BE9F1DE04CD576A16AA6054A9A`。
- `docs/前端对接ios支付流程.docx`：`FC4B16C1A65A946A42FB10EA1F2F0CABAF21959F15D588F437284096E299546F`。
