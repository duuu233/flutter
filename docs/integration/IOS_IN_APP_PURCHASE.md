# iOS 星币内购与传统收据验证

> 文档类型：Integration
> 状态：Active
> 最后核验：2026-10-16（独立重新验单、受保护的新下单及购买后诊断；Swagger 契约核验仍为2026-10-12，新实现未完成 iOS 编译与真机验收）

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
  → setApplePayVerifyReceipt(receiptData, orderNo, transactionId)
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
  "orderNo": "<本次 addOrder 返回的业务订单号>",
  "transactionId": "<本次 StoreKit purchased 回调的 transactionIdentifier>"
}
```

公共参数由 `ApiClient` 携带：`terminal=2`、当前 `language`、登录 `userToken`、原生设备型号 `device`。
按既有接口兼容规则同时写入 header/query。Bundle ID 是后端核验配置，本接口当前 DTO 没有该入参，
客户端不会擅自添加。请求 body 与此接口响应日志均脱敏，收据及嵌在 `responseData` 中的收据不输出。

2026-10-12 最新线上 Swagger 已列出 `receiptData/orderNo/transactionId`，旧 `excludeOldTransactions` 已移除；
公共参数仍由 ApiClient 注入。验证成功后由后端负责发币。客户端使用持久化业务订单号和原生苹果交易号，
不用 `orderId`、SKU 或 UUID 代替。

本轮同时核验后端提供的流程 Word 与代码示例。线上声明仍为 `retCode=200` 成功，建单为
`/Client/Order/addOrder(goodsId:integer,payType:2)`；`setCreatePay` 要已有 `orderNo`，不返回新订单号。
示例中的 `retCode=1` 和 `setCreatePay(goodsId)` 与线上 DTO 冲突，不能据此改动客户端。
最新验单输出 DTO 为 `status/environment/latestReceipt/responseData/exceptionMsg`，但实际交付时序、
明细是否必返、幂等返回及 `getPayQuery.payState` 枚举仍待后端确认。Word 写明发币异步执行，
`status=0` 不能独立作为到账或 finish 的依据。完整差异与可转发问题见
[后端文档与客户端对照](IOS_IAP_BACKEND_ALIGNMENT.md)。

当前兼容已声明的
`retData.status/environment/latestReceipt/responseData` 出参；为避免提前结束未交付交易，客户端暂要求：

1. `retData.status=0`；
2. `responseData` 是苹果验证结果 JSON 字符串或对象，其中 `receipt.in_app`（兼容
   `latest_receipt_info`）存在与原生回调相同的 `transaction_id` 和 `product_id`，无取消字段，
   `quantity` 缺省或为 1；
3. 对应 `orderNo` 的 `getPayQuery.payState=1`；
4. 当前余额至少为购买前余额 + 本档基础/赠送星币总数。

只有四项都满足才保存到账确认并结束苹果交易。缺少苹果明细、只有验收据成功、只有无关余额增长，
都会停在待确认。读取不到购买前余额时也不猜测到账。余额确认窗口为 0/1/2/3 秒间隔，之后可手动确认。
这些是交付语义尚未确认时保留的保守条件。新后端若只返回业务成功/发币结果，当前实现可能继续
显示待确认，需在发布后按明确的交易交付返回和查单语义调整，不能直接把 HTTP 200 当作完成依据。

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

### 4.1 独立重新确认与重新下单（2026-10-16）

- 只要当前账号有活动待处理记录，主按钮固定为“重新确认支付”，调用 `retry(manual: true)`。即使原状态是 `resume` 也不会走 buy，不建新业务订单、不再次 `add(payment)`；缺收据时允许刷新，验单仍使用原订单号与真实交易号，后端必须幂等。已保存验单成功标记的记录只查交付与收尾，不重复 POST。
- 内容区域另提供“重新下单支付”，需二次确认。调用 `buy(package, newOrder: true)`，先重新读取原生队列（含保存在原生侧的 requested/失败记录）；只要队列非空，或当前账号任一保留记录已有交易号、尝试验单、验单成功或到账标记，就以 `new_order_blocked` 阻断，不新建订单、不强制 finish、不清空 Apple 队列。
- 只有队列为空且没有上述交易/验单依据时，才用原 `addOrder(goodsId,payType=2)` 创建新的业务订单号和随机 UUID。无匹配交易的旧活动记录增加 `supersededBy=<新订单号>`，仍留在同一个持久化文件内，不删除、不伪称服务端已取消；新记录与关联先持久化成功，再拉起 Apple 付款。保存失败不付款。
- `supersededBy` 记录不占用当前下单入口；恢复时先处理活动记录，旧记录若没有匹配队列交易则跳过，不再把新单页面改回 resume。若旧 UUID 的交易迟到，仍用原订单号验单并按原交付条件收尾，不把它错配给新单，也不把旧单交付当成新单的完成弹窗。
- Dart 交易关联、原生队列去重/请求清理使用 UUID 大小写等价匹配；原生 finish 仍要求真实交易号、解析后相同 UUID 及 purchased/restored 状态，不接受其它账号/其它商品的交易。大小写差异是防御性修正，不是已经确认的本次真机根因。
- 这不是“删除已支付订单再买一次”的开关，也不是沙盒历史清理功能。已成功但未交付的交易必须先验单/补偿。单独清 Apple 沙盒购买历史不能清掉 APP 的业务记录；不要靠卸载 APP 或换账号绕过保护。

## 5. 后端必须确认的交付契约

| 项目 | 当前事实 / 需要后端提供 |
| --- | --- |
| 应用校验 | Bundle ID 为 `com.boltfox.boltstar`；服务端核验签名、应用、环境、商品、数量和交易有效性 |
| 商品配置 | 各档真实可购买的 `appleProductId`，及其对应 `goodsId`、发币数量 |
| 订单关联 | 已确认客户端提交 `orderNo` 和 `transactionId`；服务端须核验当前用户、订单商品及真实苹果交易的对应关系 |
| 幂等发币 | 全量收据可能包含多笔交易，同一 `transaction_id` 在重复提交、不同设备或账号下只能交付一次；明确已经处理的返回语义 |
| 成功返回 | 验证成功后后端发币已确认；最新 Swagger 已声明 `status/responseData`；实际成功 JSON、明细必返及异步交付结果仍待确认 |
| 交付查询 | 需确保已关联的 `getPayQuery.payState=1` 与实际发币一致；更可靠的长期契约是按交易/订单返回 `credited`、到账星币数及归属，解决余额已消费或基线缺失时无法确认的问题 |
| 沙盒与生产 | 服务端负责环境判断、传统验收据的 21007 沙盒回退及错误状态分类；端上只调用业务服务 |
| 异常恢复 | 明确无本地映射、删 App、注销账号、退款/撤销和长期 pending 的查询与补偿方案 |

最新 Swagger 已确认 Base64 格式、三个请求参数及验单返回结构；后端负责发币。交付语义、幂等与真实商品
尚未联调，不能把本轮前端实现描述为已完成生产支付验收。服务器密钥和苹果验证调用始终留在服务端。

## 6. 验证与 iOS 联调

Flutter 基线保持 3.44.6 / Dart 3.12.2；未新增依赖或修改平台构建设置。

```powershell
flutter test --no-pub test/apple_iap_product_diagnostics_test.dart test/apple_iap_test.dart test/star_purchase_test.dart test/star_package_amount_no_ellipsis_test.dart test/ai_token_short_dialog_l10n_test.dart
```

2026-10-12：61 项通过。覆盖商品/权限失败不建单、持久化失败不扣款、付款回执丢失不重复下单、
验收据成功但未到账、无关余额增长、匹配订单完整到账、基线缺失、断网手动重试、收据缺失、延迟批准、
取消、重启、账号切换、重复回调、Base64 HTTP body/无自动重试/日志脱敏、iOS 中文购买与苹果价格、
原生通道参数及四语种文案。静态分析无错误/警告，5 条原有 info 保留。

本轮在 Windows 执行，未编译 Swift/iOS、未调真实支付或发币接口、未完成沙盒/真机验收。
Mac 上须先编译 Runner，再使用当前 Bundle ID 对应的真实沙盒商品检查。
使用 `flutter run` 的 **debug 构建**测试，在 Flutter / Xcode 控制台检索 `[AppleIAP]`：

```text
[AppleIAP] verify request: {"receiptData":"[redacted]","receiptDataLength":1234,"orderNo":"<业务订单号>","transactionId":"<苹果交易号>"}
[AppleIAP] verify response: {"retCode":200,"status":0,"environment":"Sandbox","hasResponseData":true,"hasLatestReceipt":true}
```

`receiptDataLength` 是实际提交的 Base64 字符数；订单号、交易号按本次请求原值打印，方便与后端日志关联。
返回摘要只打印数值状态、识别出的苹果环境及字段是否存在，不输出原始收据、`responseData`、
`latestReceipt` 或任意服务端错误正文；公共登录凭证继续脱敏。日志仅在 debug 构建开启，
release / TestFlight 包没有这些调试日志。`status=0` 仍不独立代表发币完成，需结合订单和余额核对。
本轮补充的日志在隔离 HTTP 测试中核对实际 body、摘要字段及收据不泄露；尚未真机采集。

### 商品及购买后诊断：真机页内展示（2026-10-16）

商品业务列表仍取 `/Client/Order/getGoodsList`，`retData` 裸数组由 ApiClient 解包后归一；`appleProductId` 原值交给原生 StoreKit 查询。业务返回有值只证明商品映射存在，苹果实际商品可用性要看 StoreKit 回复。主提示保留“暂时无法加载此苹果商品”，价格查询失败时明确显示“价格获取失败”；本次查询的具体返回和错误直接展示在确认页底部。

安装包含本轮改动的**新iOS包**（普通Release、TestFlight、debug均可），尽量覆盖安装保留原映射，打开确认购买页，底部“苹果支付诊断详情”显示本次商品预检与当前账号的购买后诊断。商品预检错误保留实际code/message/details及可用栈；未知错误字段不因白名单而丢弃，敏感内容脱敏。详情可上下滚动、选择或点“复制日志”复制，不需要连接控制台。

购买后诊断由进程级 controller 持有，独立于商品预检的异步 capture，在 Release/TestFlight 同样可见，保留当前账号最近160项，账号切换清空；离开页面不保留页面回调，重新进入仍可看当前账号尚在内存中的记录，杀进程后不保留诊断。预检重新获取只清预检，不删除交易诊断或待处理订单。记录允许关联的 orderNo/transactionId、状态与数量，不记录账户UUID、用户ID、密码、登录凭证、收据正文、responseData/latestReceipt；收据只记长度。原生收据刷新错误补充脱敏系统描述和 domain/code，仍保留原错误码。

| 阶段 | 用于判断 |
| --- | --- |
| `order.create.request/response`、`order.superseded` | 是否实际创建新订单，以及哪个旧订单被新订单替代；不是只改页面文案 |
| `payment.start.request/accepted/failed` | 是否提交苹果付款；accepted 仅代表原生受理，不代表购买成功 |
| `transaction.updated`、`recovery.queue.response`、`recovery.match.response` | 是否有回调、队列数量、当前订单是否匹配；不输出未知账号的交易内容 |
| `receipt.request/response`、`receipt.read.failed` | 是否在取得收据前失败；长度不等于收据正文 |
| `verify.request/response/failed/skipped` | 是否进入 APP 的 `/Client/Pay/setApplePayVerifyReceipt`，Apple status/environment、明细是否匹配；历史提交需手动确认时明确说明 |
| `delivery.order.response`、`delivery.balance.response` | 对应订单是否已支付、当前/基线/预期余额；只有验单成功仍不足以完成 |
| `transaction.finished`、`phase.changed` | 是否实际完成交付收尾，或以哪种错误停在 pending |

`verify.request` 表示已进入客户端后端调用，仍需网关/服务器访问日志确认真正收到 HTTP；不能把它当成 Apple 主动发到业务后台的通知。`status=21007` 应由后端按现有传统收据协议处理沙盒回退。发生问题先复制本轮日志及查询同一订单，不新买一笔冒充重验。

“重新获取商品”清空上次详情并重置滚动位置，只采集本次商品预检。即使初始化已缓存，本次仍记录运行Bundle ID和支付权限；异步请求分别隔离，结束后释放页面回调，离开页面后到达的结果不更新已销毁页面。查询失败时不再继续显示“正在获取价格…”，购买仍受原商品与权限检查保护。

需要控制台时仍可在debug构建搜索 `[AppleIAP]`；以下是查询阶段摘要示例：

```text
[AppleIAP] prepare.request: {"goodsId":9,"tokens":7500,"productId":"xb2","supported":true}
[AppleIAP] initialize.response: {"bundleId":"com.boltfox.boltstar","canMakePayments":true}
[AppleIAP] product.request: {"productId":"xb2"}
[AppleIAP][native] product.response: {"bundleId":"com.boltfox.boltstar","requestedProductId":"xb2","returnedProductIds":[],"invalidProductIds":["xb2"]}
[AppleIAP] prepare.product.failed: {"reason":"storekit_empty_products","requestedProductId":"xb2","returnedProductIds":[],"invalidProductIds":["xb2"],"bundleId":"com.boltfox.boltstar","code":"product_unavailable",...}
```

以上是诊断格式示例，不是本次真机结论。Dart `AppleIapDiagnostics.capture` 在所有构建模式收集页面所属预检，阶段摘要按白名单脱敏，完整错误保留未知字段并按敏感字段/文本脱敏；原生 `AppleIapHandler` 的错误详情本来就在普通包中通过通道返回。控制台打印仍仅debug，release/TestFlight可直接看页面底部。

| 日志阶段 / reason | 说明与核对方向 |
| --- | --- |
| `prepare.validation.failed` / `apple_product_id_empty` | 选中套餐实际没有苹果商品 ID，核对本次客户端返回 |
| `prepare.validation.failed` / `platform_unsupported` | 运行平台不支持当前内购桥接 |
| `prepare.initialize.failed` / `native_bridge_missing` | 原生通道未注册或运行包尚未包含该实现；其它初始化异常保留 errorType/code，先看初始化阶段 |
| `prepare.permission.failed` / `payment_not_allowed` | `canMakePayments=false`，当前系统不允许内购，尚未查询商品 |
| `prepare.product.failed` / `storekit_empty_products` | 苹果返回无商品；同时核对 returnedProductIds 与 invalidProductIds。无效ID非空时核对苹果商品精确ID、运行Bundle ID与配置；无效ID也为空不能仅据此判定拼写错误 |
| `prepare.product.failed` / `storekit_product_timeout` | 原生30秒未返回商品，核对测试网络及苹果服务 |
| `prepare.product.failed` / `storekit_request_failed` | 输出 nativeErrorDomain/nativeErrorCode/nativeMessage，最多三层 underlyingErrors；按具体系统/网络错误定位 |
| `prepare.product.failed` / `product_id_mismatch`、`localized_price_empty` | 原生返回ID与请求不一致或缺价格，查看 product.response |
| `product.response` | 记录请求/实际商品ID与苹果本地化价格，确认原生查询成功 |

原生请求保留请求对象与ID对应关系，成功/失败/超时均清理；错误仍按原PlatformException码返回，购买权限、建单、扣款、收据或交付条件保持。页面只新增本次预检详情及明确的价格失败状态；安卓PayPal价格和付款逻辑保持。不打印 NSError 的完整userInfo、收据、账户UUID或登录凭证；系统错误描述中的URL、邮箱及凭证文本脱敏并限制长度。

2026-10-13历史回归：页面诊断及原有商品/支付回归合计 **76项通过**；五个修改Dart文件无error/warning、无新增info，原PayPal页有1条既有跨异步context info，analyze因此退出1。新增6项核对底部完整错误与复制、未知/长描述/嵌套凭证脱敏、重试与缓存初始化、短屏大字体滚动、退出及异步采集隔离。测试以模拟原生/HTTP返回完成，页面采集位于debug判断之前；Windows未编译Swift/iOS或普通安装包，尚未确认实际手机的失败原因。

2026-10-16当前回归：新增22项，六个支付相关测试文件共 **98项通过**；六个Dart文件静态检查无error/warning及新增info，仍仅上述PayPal既有info。覆盖新订单真实建单/落盘、各种阻断、旧记录及迟到回调、独立重验、完整诊断脱敏、UUID大小写和小屏大字；未替代Swift编译、覆盖安装及真机沙盒/后端交付联调。

真机检查：

1. 各档商品、本地化价格、成功支付、取消和系统不允许支付；中文 iOS 不受安卓 PayPal 人民币限制。
2. Ask to Buy 延迟批准与批准后回调；付款前后杀进程、离开页面、断网、服务器响应丢失。
3. 登录 A 购买、切 B 不处理 A、回 A 恢复；一次发币后再买同档能产生独立交易。
4. 验证明细正确、订单关联正确、幂等发币、`payState` 与余额同步后才 finish；未交付时队列保留。
5. 无收据手动刷新、基线缺失、余额已消费、重新安装和孤立交易的后端恢复方案。

官方依据：[收据验证](https://developer.apple.com/documentation/storekit/validating-receipts-with-the-app-store)、
[结束交易](https://developer.apple.com/documentation/storekit/finishing-a-transaction)。原始 API 及
`verifyReceipt` 已被苹果标为弃用；本次按已确认的传统收据后端兼容。迁移到现代签名交易协议需要双方另行约定。
