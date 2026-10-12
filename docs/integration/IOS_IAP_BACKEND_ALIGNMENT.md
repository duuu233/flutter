# iOS 内购后端文档与客户端对照

> 文档类型：Integration Review
> 状态：待后端确认交付语义
> 核验时间：2026-10-12 19:37（Asia/Shanghai）
> 客户端基线：main / caa6ec2
> 当前实现契约：[iOS 星币内购](IOS_IN_APP_PURCHASE.md)

## 1. 结论与证据范围

当前 APP 已提交传统 Base64 应用收据、业务订单号与苹果交易号，商品和应用标识、支付类型、请求头与本轮线上 Swagger 相符。两份后端示例中的建单接口、成功码、重复验单及交易结束时机存在出入，不能整套照搬。

本轮对照了产品提供的 `前端对接ios支付流程.docx`（正文及全部七张内嵌截图）、`ios-iap-frontend-examples.md`、当前 Dart/Swift 源码及 [线上 Swagger 定义](https://api.boltfox.cn/v2/api-docs)。Swagger 已新增 `orderNo/transactionId`，删除旧 `excludeOldTransactions`；此前“仍是旧 DTO”的记录已不代表本轮状态。

Swagger 证明接口的声明结构，不证明部署后的实际返回、异步发币时序或幂等实现。本轮未读取服务端源码，也未执行真实扣款、发币或 iOS 真机测试；下面关于 `contains` 与异步调用的事实来源是后端提供的文档，尚未通过服务端代码证实。

## 2. 已一致的部分

| 项目 | 后端文档与 APP 的对应关系 |
| --- | --- |
| 验单接口 | `POST /Client/Pay/setApplePayVerifyReceipt` |
| 收据 | `Bundle.main.appStoreReceiptURL` 的二进制数据 Base64 编码；不是 StoreKit 2 JWS |
| 关联字段 | `orderNo` 来自当前业务订单，`transactionId` 来自当前 StoreKit 交易；均按字符串传输 |
| iOS 类型 | `payType=2`、`terminal=2` |
| 身份与商品 | Runner Bundle ID 为 `com.boltfox.boltstar`；StoreKit 商品使用 `getGoodsList.appleProductId` |
| 鉴权 | 当前登录 `userToken` 已放 header；保留既有 header/query 公共参数兼容 |
| 验证返回 DTO | Swagger 声明 `status/environment/latestReceipt/responseData/exceptionMsg`；APP 已兼容 |
| 环境 | 后端负责生产/沙盒验证；APP 不直接请求苹果验单服务 |

## 3. 需要对齐的差异

| 编号 | 后端文档或示例 | 当前实现及线上声明 | 处理结论 |
| --- | --- | --- | --- |
| A1 建单接口 | Word 流程及 Markdown 用 `setCreatePay({goodsId,payType:2})` 取得新 `orderNo`，goodsId 示例为字符串 | APP 用 `/Client/Order/addOrder`。Swagger 的 `ClientOrderAddApiIn.goodsId` 是 integer，返回 `ClientAddOrderApiOut.orderNo`；`PayCreateApiInput` 需要已有 `orderNo`、没有 `goodsId`，支付创建输出也没有 `orderNo` | 示例与 Swagger 冲突。按线上声明保留 addOrder；请后端确认 iOS 是否还要求单独创建支付记录，并修正示例的接口与商品 ID 类型 |
| A2 业务成功码 | 两份文档检查 `retCode==1` | `ApiClient._parse` 只认 200；Swagger 的 Apple 验单及建单 BaseOutput 均明确“200=成功，其它失败” | 现有 APP 与 Swagger 一致。请后端修正文档为 200 或提供真实的新返回；不能把全局成功码擅改为 1。HTTP 200 与业务 retCode 是两个层级 |
| A3 验证与发币 | Word 写 `orderPaySuccess` 经 `ConfigKeys.PayExecutorService` 异步执行，却又写 `status=0` 后直接刷新成功；示例随后 finish | APP 在匹配当前交易后查对应订单及余额，实际到账才 finish。Swagger 只声明 Apple status，未声明交付完成标记；getPayQuery 的 payState 无枚举和发币保证 | 异步任务受理不等于交付完成。后端须定义“验单通过 / 处理中 / 已发币 / 失败”的查询及补偿；不得仅凭 status=0 提前 finish |
| A4 苹果明细可选 | Markdown 把 responseData 标成可选，并只检查 status=0 | APP 要求 responseData 中同一条交易的 transaction_id/product_id 精确匹配；缺失明细会保留待确认。Swagger 有此字段但没有 required 保证 | 请确认成功时是否总返回完整有效 JSON。若要省略明细，需要提供可信的当前订单/交易交付结果，再据此调整前端 |
| A5 商品与应用校验 | 文档称后端对整份原始 JSON 做 contains(bundleId/transactionId/goodsName)，建议 goodsName 用 Product ID | APP 按 appleProductId 购买；建单只有 goodsId/payType，没有 goodsName 入参。商品显示名称与苹果 SKU 是独立字段 | 请后端按 goodsId 取该商品 appleProductId，并解析同一条真实交易精确匹配 product_id/transaction_id，以及 receipt.bundle_id；不能让显示名或另一条交易的字段满足本单校验 |
| A6 重复验单 | 文档出现“订单已支付”“已重复的 transactionId”，建议失败重试换 transactionId | APP 手动重试保留原 orderNo/真实 transactionId；成功响应丢失或本地保存失败时，无法凭一条重复错误确认归属和已交付状态 | 同一交易重试不能换号或重新扣款。请后端为同用户、同订单、同交易返回已交付或处理中结果；跨订单/跨账号复用应拒绝，发币去重必须能抵抗并发 |

代码证据：`lib/src/network/boltfox_api.dart` 的 `addOrder/setApplePayVerifyReceipt/setCreatePay/getPayQuery`；`lib/src/network/api_client.dart` 的 `_parse`；`lib/src/features/star/apple_iap.dart` 的 `AppleReceiptVerification.matches`、`AppleIapController.retry/_finish`；`ios/Runner/AppDelegate.swift` 的 `AppleIapHandler`。

## 4. 客户端仍受交付协议限制

现有确认条件为：验单及当前苹果交易匹配、对应订单 `payState=1`、余额至少增加本档基础与赠送星币总数，然后持久化到账确认并 finish。这个条件保护尚未交付的交易，但有实际局限：购买前余额读取失败、星币已在其它页面或设备消费、异步交付超出本轮确认窗口时，已发币的订单也可能保持待确认；原生购买入口会阻止在未收尾交易期间再次扣款。

长期应以服务端按订单/交易保存的交付记录为准，余额只用于刷新展示。可讨论增加 `orderNo/transactionId/productId/deliveryState/creditedTokens`，名称和枚举由双方确认后实施；这些字段目前既不是已上线接口，也不是 APP 已接受的返回。

成功响应丢失时，自动恢复不重复 POST，用户手动确认才会重传同一交易。如果服务端已经处理却只报“订单已支付”，APP 仍可能无法获得可持久化的验单结果而停留待确认。这需要 A6 的幂等返回或可信的订单交付查询，不能用重买一笔解决。

## 5. 示例不能直接复制的其它事项

- `excludeOldTransactions` 在 Markdown 示例中存在，但本轮线上 `VerifyReceiptApiInput` 已没有它；当前三个请求字段保持正确。自动续订、VIP 和 Server Notifications V2 的例子不能直接代替星币消耗品的交付语义。
- APP 使用已有 StoreKit 1 桥接，文档本身也给出此路径，HTTP 协议不要求强制换 StoreKit 2。保持当前工具链、依赖及平台设置。
- Markdown 的 Legacy observer 在后端验单之前 finish，并在 purchase 结束时移除 observer；Swift/Flutter 示例未提供完整的重启、pending、账号切换和交付恢复。当前实现已有持续观察及持久化恢复，应继续保留。
- Swift 示例存在需要修正的类型问题：`Transaction.id` 是 UInt64，却传给 String 参数/返回值；`goodsId` 字符串与 `payType` 整数组成的异构字典不能直接用于所示 JSONEncoder 编码。Flutter 示例也只返回交易，缺少验单交付后的 finish 桥接。这里只做源码审查，未在 Xcode 编译示例。
- Word 将 21008 写成“产品不在账号购买列表”；苹果定义为生产收据发送到测试环境。21002 也不能仅据该码判定 App Store 商品配置错误，需结合苹果原始响应定位。参见 [Apple verifyReceipt](https://developer.apple.com/documentation/appstorereceipts/verify-receipt)。

## 6. 可直接发给后端的确认内容

> 已对照当前 APP、两份 iOS 支付文档和最新线上 Swagger。APP 已按 receiptData/orderNo/transactionId、payType=2、Bundle ID=com.boltfox.boltstar 接好，烦请确认以下六项：
>
> 1. 下单应为 `/Client/Order/addOrder({goodsId:整数,payType:2})`，还是已新增 `setCreatePay(goodsId)` 的能力？当前 Swagger 的 setCreatePay 要已有 orderNo，且不返回 orderNo。iOS 是否还必须额外调用一次 setCreatePay？
> 2. Apple 验单业务成功码是 200 还是 1？当前 Swagger 是 200，两份示例是 1。请统一文档并提供一份脱敏的实际成功及失败 JSON。
> 3. orderPaySuccess 是否异步？验单 status=0 时星币是否已写入账户？请明确 getPayQuery.payState 全部枚举、何值保证本单已发币，以及异步失败/重启后的补偿与查询办法。
> 4. 成功时 responseData 是否保证包含当前交易的有效苹果 JSON？若不保证，请提供能确认当前订单、交易、商品及交付状态的返回/查询。
> 5. 校验商品应按 goodsId 对应的 appleProductId；请确认会解析同一条交易做精确匹配并检查 bundle_id，而不是对整份收据做 contains(goodsName)。goodsName 是展示名，客户端不把它改成苹果 SKU。
> 6. 同一用户、同一订单、同一苹果交易因超时重试时，应幂等返回“已发币”或“处理中”，不能要求换 transactionId。请给重复/并发、跨订单、跨账号重放的规则及示例。
>
> 前端目前到账确认后才 finish。收到明确交付协议后，可把余额差额确认改为订单交付记录，继续保留取消、pending、断网、重启、重复回调和账号隔离。

以上是对齐问题稿，尚未取得本轮后端答复，不能标记为双方已确认或支付已验收。

## 7. 验证

Flutter 3.44.6 / Dart 3.12.2；本轮四个支付相关测试文件共 61 项通过，HTTP/原生/业务支付使用隔离替身。仅更新审查和维护文档，Dart/Swift 及依赖、构建设置未修改。未进行 iOS 编译、沙盒/真机测试或真实发币；上线前仍须覆盖幂等、异步交付、响应丢失及各真实商品。

Apple 明确要求交付内容、持久化购买并更新 UI 后才结束交易，参见 [Finishing a transaction](https://developer.apple.com/documentation/storekit/finishing-a-transaction)。`status=0` 是整份应用收据有效性，参见 [receipt status](https://developer.apple.com/documentation/appstorereceipts/status)，不能单独证明本单星币已到账。
