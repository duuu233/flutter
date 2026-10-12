# iOS 星币内购与传统收据验证

> 文档类型：Integration
> 状态：Active
> 最后核验：2026-10-12（源码、Swagger 与 Flutter 测试；未完成 iOS 真机联调）

## 1. 应用身份与商品

iOS Runner 的 Debug、Profile、Release 均配置 `PRODUCT_BUNDLE_IDENTIFIER = com.boltfox.boltstar`，
`Info.plist` 的 `CFBundleIdentifier` 引用该构建变量。后端应将 **`com.boltfox.boltstar`** 作为本应用的
Bundle ID 配置并核对收据中的 `receipt.bundle_id`。`com.boltfox.boltstar.RunnerTests` 属于测试目标。
App Store Connect 的实际应用、签名和上传包必须使用相同标识；本轮未访问 App Store Connect。

星币为消耗型内购。`getGoodsList` 下发的每档 `appleProductId` 必须对应此应用在 App Store Connect
配置的商品，并与该档 `goodsId`、基础/赠送星币数量关联。确认页先查询 StoreKit 商品和支付权限，
使用苹果返回的本地化价格；商品不存在或不允许支付时不建业务订单、不发起扣款。

## 2. 客户端流程

```text
getGoodsList.appleProductId
  → StoreKit 商品/权限预检
  → getUserAccount（记录购买前余额）
  → addOrder(goodsId, payType=2)
  → 持久化用户、orderNo、商品与随机 UUID
  → StoreKit add(payment)，quantity=1、applicationUsername=UUID
  → purchased 回调
  → Bundle.main.appStoreReceiptURL 读取二进制并 Base64 编码
  → setApplePayVerifyReceipt(receiptData, excludeOldTransactions=false)
  → 验证当前苹果 transaction_id / product_id
  → getPayQuery(orderNo, payType=2) + getUserAccount
  → 满足订单/到账条件并持久化确认后 finishTransaction
```

- Dart 编排在 `lib/src/features/star/apple_iap.dart`，原生桥接在 `ios/Runner/AppDelegate.swift`，
  通道为 `com.boltfox.boltstar/apple_iap`。原生实现使用原始 StoreKit API，以适配后端已确认的
  **传统 Base64 应用收据**，不把 StoreKit 2 的 JWS 当收据提交。
- iOS 不调用 PayPal 的 `setCreatePay`、不走银行卡 Apple Pay，也不调用另外两种 Apple 验证接口。
- Controller 为进程内单例。购买页关闭后仍保留待处理交易；登录、回到前台和原生事件触发恢复。
- 已有同账号待处理购买时不新建另一张订单。扣款前保存失败会阻止支付；原生回执丢失时保存原订单，
  原生 UUID/队列检查阻止再次 `add(payment)`。
- `deferred` 等待家长等批准，不提交收据、不结束交易。取消/失败交易由原生结束，并保存结果直到
  Dart 清除对应业务记录并确认；成功交易在服务端交付确认之前留在 StoreKit 队列。
- 消耗品不使用“恢复购买”按钮重新发币。这里恢复的是仍在队列中的未完成购买。

## 3. HTTP 契约

`POST /Client/Pay/setApplePayVerifyReceipt`，JSON body：

```json
{
  "receiptData": "<二进制应用收据的 Base64 字符串>",
  "excludeOldTransactions": false
}
```

公共参数由 `ApiClient` 携带：`terminal=2`、当前 `language`、登录 `userToken`、原生设备型号 `device`。
按既有接口兼容规则同时写入 header/query。Bundle ID 是后端核验配置，本接口当前 DTO 没有该入参，
客户端不会擅自添加。请求 body 与此接口响应日志均脱敏，收据及嵌在 `responseData` 中的收据不输出。

2026-10-12 的 Swagger 仍只有上述两个 body 字段，无 `orderNo`、`orderId`、`transactionId`、
`productId`。出参 `retData` 声明 `status`、`environment`、`latestReceipt`、`responseData`，
未声明“此交易已经发币”的字段。

`retCode=200` 仅表示业务接口正常返回。客户端另要求：

1. `retData.status=0`；
2. `responseData` 是苹果验证结果 JSON 字符串或对象，其中 `receipt.in_app`（兼容
   `latest_receipt_info`）存在与原生回调相同的 `transaction_id` 和 `product_id`，无取消字段，
   `quantity` 缺省或为 1；
3. 对应 `orderNo` 的 `getPayQuery.payState=1`；
4. 当前余额至少为购买前余额 + 本档基础/赠送星币总数。

只有四项都满足才保存到账确认并结束苹果交易。缺少苹果明细、只有验收据成功、只有无关余额增长，
都会停在待确认。读取不到购买前余额时也不猜测到账。余额确认窗口为 0/1/2/3 秒间隔，之后可手动确认。
这些是当前接口下客户端采用的保守条件，不能替代后端将具体苹果交易与业务订单及发币流水绑定。

## 4. 重试与账号隔离

- 本地 `boltstar.appleIap.pending.v1` 仅保存用户 ID、订单号、商品 ID、UUID、星币数、余额基线、
  苹果交易号和处理标记，不保存收据、登录 token 或苹果密钥。
- 原生 `UserDefaults` 保存请求 UUID 与失败结果。成功扣款的真实交易仍由 StoreKit 队列保存。
- 退出/会话过期后停止业务恢复；切换账号会使正在执行的请求结果失效，不能拿 B 账号完成 A 的购买。
  未完成记录不随图片缓存清理删除，A 重新登录才处理 A 的记录。注销后的未交付订单由后端制定处置规则。
- 验证 POST 的超时/连接错误均关闭自动 HTTP 重试。首次提交前保存 `verificationAttempted`，
  自动恢复不会重复可能已执行成功的提交。用户点击“重新确认支付”才允许再次提交，必须依靠后端幂等。
- `receiptVerified` 已保存时只查订单和余额，不再次 POST。苹果收据缺失时，只有手动确认才触发
  `SKReceiptRefreshRequest`，避免前台恢复自动弹出 Apple ID 登录提示。
- 保存到账确认后再结束交易；若结束成功但本地删除失败，下次恢复可安全收尾。
- 删除 App 会丢失本地订单/用户映射；陌生队列交易不自动归属当前账号。重新安装、孤立 UUID 或
  长期未交付交易需要后端提供按苹果交易查交付/归属的恢复协议，不能让客户端猜账号。

## 5. 后端必须确认的交付契约

| 项目 | 当前事实 / 需要后端提供 |
| --- | --- |
| 应用校验 | Bundle ID 为 `com.boltfox.boltstar`；服务端核验签名、应用、环境、商品、数量和交易有效性 |
| 商品配置 | 各档真实可购买的 `appleProductId`，及其对应 `goodsId`、发币数量 |
| 订单关联 | 当前验证入参没有订单号；需明确如何把具体苹果交易关联到 `addOrder(payType=2)` 的订单，不能仅按“最近一张待支付单”猜测 |
| 幂等发币 | 全量收据可能包含多笔交易，同一 `transaction_id` 在重复提交、不同设备或账号下只能交付一次；明确已经处理的返回语义 |
| 苹果验证明细 | 当前实现需要 `status=0` 与 `responseData` 中的匹配交易；若后端不返回原始明细，需提供并约定具体交易的验证/交付结果 DTO 后再调整客户端 |
| 交付查询 | 需确保已关联的 `getPayQuery.payState=1` 与实际发币一致；更可靠的长期契约是按交易/订单返回 `credited`、到账星币数及归属，解决余额已消费或基线缺失时无法确认的问题 |
| 沙盒与生产 | 服务端负责环境判断、传统验收据的 21007 沙盒回退及错误状态分类；端上只调用业务服务 |
| 异常恢复 | 明确无本地映射、删 App、注销账号、退款/撤销和长期 pending 的查询与补偿方案 |

“接受 Base64”只确认了凭证格式，未确认订单关联和发币已实现。上述契约及真实商品未联调前，
不能把本轮前端实现描述为已完成生产支付验收。服务器密钥和苹果验证调用始终留在服务端。

## 6. 验证与 iOS 联调

Flutter 基线保持 3.44.6 / Dart 3.12.2；未新增依赖或修改平台构建设置。

```powershell
flutter test --no-pub test/apple_iap_test.dart test/star_purchase_test.dart test/star_package_amount_no_ellipsis_test.dart test/ai_token_short_dialog_l10n_test.dart
```

2026-10-12：61 项通过。覆盖商品/权限失败不建单、持久化失败不扣款、付款回执丢失不重复下单、
验收据成功但未到账、无关余额增长、匹配订单完整到账、基线缺失、断网手动重试、收据缺失、延迟批准、
取消、重启、账号切换、重复回调、Base64 HTTP body/无自动重试/日志脱敏、iOS 中文购买与苹果价格、
原生通道参数及四语种文案。静态分析无错误/警告，5 条原有 info 保留。

本轮在 Windows 执行，未编译 Swift/iOS、未调真实支付或发币接口、未完成沙盒/真机验收。
Mac 上须先编译 Runner，再使用当前 Bundle ID 对应的真实沙盒商品检查：

1. 各档商品、本地化价格、成功支付、取消和系统不允许支付；中文 iOS 不受安卓 PayPal 人民币限制。
2. Ask to Buy 延迟批准与批准后回调；付款前后杀进程、离开页面、断网、服务器响应丢失。
3. 登录 A 购买、切 B 不处理 A、回 A 恢复；一次发币后再买同档能产生独立交易。
4. 验证明细正确、订单关联正确、幂等发币、`payState` 与余额同步后才 finish；未交付时队列保留。
5. 无收据手动刷新、基线缺失、余额已消费、重新安装和孤立交易的后端恢复方案。

官方依据：[收据验证](https://developer.apple.com/documentation/storekit/validating-receipts-with-the-app-store)、
[结束交易](https://developer.apple.com/documentation/storekit/finishing-a-transaction)。原始 API 及
`verifyReceipt` 已被苹果标为弃用；本次按已确认的传统收据后端兼容。迁移到现代签名交易协议需要双方另行约定。
