# setApplePayVerifyReceipt —— 完整前端代码示例

涵盖三种客户端栈：

| 文件 | 栈 | 用途 |
|---|---|---|
| `ios/IosPurchaseService.swift` | Swift / StoreKit 2 | iOS 原生 App 内购 + 调后端验单全流程 |
| `ios/IosPurchaseService.SwiftPMDemo.swift` | SwiftPM | 独立跑的最小 Demo（脱离项目结构也能验） |
| `ts/payApi.ts` | TypeScript | 封装的 HTTP API 层，Flutter/RN/Web 通用 |
| `ts/useIapPurchase.ts` | React Hook | App 内「点购买按钮 → 成功后刷新权益」的业务示例 |

---

## 一、TypeScript HTTP API 层（Flutter / RN / Web 通用）

```typescript
// ts/payApi.ts
// 项目里如果已有统一的 request 封装（axios/fetch），把 BASE_URL 和 request
// 替换成你们项目自己的即可。这里用原生 fetch 实现，无任何第三方依赖。

// ========== 统一响应结构（后端 BaseOutput<T>） ==========
export interface BaseOutput<T> {
  retCode: number;        // 1 = 成功，其他 = 失败
  retMsg: string;
  retData: T;
}

// ========== 验单请求 / 响应类型 ==========
export interface VerifyReceiptRequest {
  receiptData: string;         // iOS 收据的 base64
  orderNo: string;             // 平台订单号（下单接口返回）
  transactionId: string;       // Apple 交易标识（StoreKit 回调返回）
  excludeOldTransactions?: boolean; // 默认 true
}

export interface VerifyReceiptResponse {
  status: number;              // 0 = Apple 验证成功，非 0 = 21xxx 错误码
  environment: 'Production' | 'Sandbox' | string;
  latestReceipt?: string;      // 续订场景下 Apple 返回的最新收据（base64）
  responseData?: string;       // Apple 原始 JSON（排查用）
  exceptionMsg?: string;
}

// ========== 下单接口（前置） ==========
export interface CreateOrderRequest {
  goodsId: string;   // 平台商品 ID
  payType: number;   // 1=微信, 2=IOS内购, 3=PayPal → 内购传 2
}

export interface CreateOrderResponse {
  orderNo: string;
  payState?: number;
}

// ========== 配置 ==========
const BASE_URL = 'https://yourdomain.com';
const USER_TOKEN_HEADER = 'userToken'; // 后端从 header 里读

// ========== 通用请求 ==========
async function request<T>(
  path: string,
  method: 'GET' | 'POST',
  body?: any,
  userToken?: string,
): Promise<BaseOutput<T>> {
  const headers: Record<string, string> = {
    'Content-Type': 'application/json',
  };
  if (userToken) headers[USER_TOKEN_HEADER] = userToken;

  const res = await fetch(`${BASE_URL}${path}`, {
    method,
    headers,
    body: body ? JSON.stringify(body) : undefined,
  });

  if (!res.ok) {
    throw new Error(`HTTP ${res.status} ${res.statusText}`);
  }
  return (await res.json()) as BaseOutput<T>;
}

// ========== 导出方法 ==========

/** 下单（拿 orderNo） */
export function createOrder(
  params: CreateOrderRequest,
  userToken: string,
): Promise<BaseOutput<CreateOrderResponse>> {
  return request<CreateOrderResponse>(
    '/Client/Pay/setCreatePay',
    'POST',
    params,
    userToken,
  );
}

/**
 * 验单（本文档主角）
 *
 * @param params.receiptData  iOS 收据的 base64 编码字符串
 * @param params.orderNo      下单接口返回的平台订单号
 * @param params.transactionId StoreKit 回调返回的 Apple 交易标识
 * @param userToken           用户登录令牌
 */
export function verifyReceipt(
  params: VerifyReceiptRequest,
  userToken: string,
): Promise<BaseOutput<VerifyReceiptResponse>> {
  return request<VerifyReceiptResponse>(
    '/Client/Pay/setApplePayVerifyReceipt',
    'POST',
    params,
    userToken,
  );
}
```

---

## 二、React Hook 业务示例（「点购买 → 成功刷新权益」）

```typescript
// ts/useIapPurchase.ts
import { useCallback, useState } from 'react';
import {
  createOrder,
  verifyReceipt,
  type VerifyReceiptResponse,
} from './payApi';

// 这里的 iosPurchaseBridge 是 **iOS 原生和 RN/Flutter 的桥接**：
//   - React Native: NativeModules.IosPurchase
//   - Flutter:      MethodChannel('ios_purchase')
//   - Web/H5:       空实现（Web 不能做内购）
// 接口统一成下面这样，方便跨端调用
interface IosPurchaseBridge {
  /** 调 StoreKit 发起内购，成功后返回 { transactionId, receiptData } */
  purchase(productId: string): Promise<{ transactionId: string; receiptData: string }>;
}

export interface UseIapPurchaseResult {
  loading: boolean;
  /** 发起内购全流程：下单 → StoreKit → 验单 → 刷新权益 */
  purchase: (goodsId: string, productId: string) => Promise<VerifyReceiptResponse>;
}

/**
 * @param iosBridge      iOS 原生桥接对象（见上文说明）
 * @param userToken      登录 token
 * @param onRefreshUser  成功后回调（一般是刷新用户权益 / 拉新的 profile）
 */
export function useIapPurchase(
  iosBridge: IosPurchaseBridge,
  userToken: string,
  onRefreshUser: () => Promise<void>,
): UseIapPurchaseResult {
  const [loading, setLoading] = useState(false);

  const purchase = useCallback(async (goodsId: string, productId: string) => {
    if (loading) throw new Error('已在支付中');
    setLoading(true);
    try {
      // ① 下单（payType = 2 表示 IOS 内购）
      const orderRes = await createOrder({ goodsId, payType: 2 }, userToken);
      if (orderRes.retCode !== 1 || !orderRes.retData?.orderNo) {
        throw new Error(orderRes.retMsg || '下单失败');
      }
      const orderNo = orderRes.retData.orderNo;

      // ② 调 iOS 原生 StoreKit 内购
      const { transactionId, receiptData } = await iosBridge.purchase(productId);

      // ③ 发给后端验单
      const verifyRes = await verifyReceipt(
        { orderNo, transactionId, receiptData },
        userToken,
      );
      if (verifyRes.retCode !== 1) {
        throw new Error(verifyRes.retMsg || verifyRes.retData?.exceptionMsg || '验单失败');
      }
      if (verifyRes.retData.status !== 0) {
        // status 是 Apple 原始返回码（21007 等），后端已经自动切过沙箱了
        throw new Error(
          `Apple 验证失败 status=${verifyRes.retData.status}，response=${verifyRes.retData.responseData}`,
        );
      }

      // ④ 刷新权益
      await onRefreshUser();

      return verifyRes.retData;
    } finally {
      setLoading(false);
    }
  }, [loading, iosBridge, userToken, onRefreshUser]);

  return { loading, purchase };
}
```

**业务层调用示例（按钮 onClick）：**

```tsx
import { useIapPurchase } from './useIapPurchase';

function VipPurchaseButton({ goodsId, productId }: { goodsId: string; productId: string }) {
  const iosBridge = /* 从 RN NativeModules / Flutter MethodChannel 拿 */;
  const userToken = /* 用户登录 token */;
  const refreshUser = /* 刷新用户权益的 Promise */;

  const { loading, purchase } = useIapPurchase(iosBridge, userToken, refreshUser);

  return (
    <button
      disabled={loading}
      onClick={async () => {
        try {
          await purchase(goodsId, productId);
          alert('✅ 支付成功，权益已到账');
        } catch (err: any) {
          alert('❌ ' + (err?.message || '支付失败'));
        }
      }}
    >
      {loading ? '支付中...' : '购买 VIP'}
    </button>
  );
}
```

---

## 三、iOS 原生端 StoreKit 2 完整实现（Swift）

```swift
// ios/IosPurchaseService.swift
// iOS 原生 App 直接用这个。Flutter/RN 把它的 purchase() 暴露给桥接层即可。
//
// ⚠️ 必须满足：StoreKit 2（iOS 15+）、App Store Connect 已配置内购产品、
//    付费 App 协议（Paid Applications Agreement）已签署。

import Foundation
import StoreKit

// ========== 配置 ==========
struct PurchaseConfig {
    static let baseURL = "https://yourdomain.com"
    static let userToken: String {
        // 从你们 App 的登录状态里读，这里给占位
        return UserDefaults.standard.string(forKey: "userToken") ?? ""
    }
}

// ========== 验单请求结构（和后端 VerifyReceiptApiInput 对齐） ==========
struct VerifyReceiptBody: Encodable {
    let receiptData: String
    let orderNo: String
    let transactionId: String
    let excludeOldTransactions: Bool = true
}

// ========== 验单响应结构 ==========
struct VerifyReceiptResponse: Decodable {
    let retCode: Int
    let retMsg: String
    let retData: VerifyReceiptData?
}
struct VerifyReceiptData: Decodable {
    let status: Int
    let environment: String
    let latestReceipt: String?
    let responseData: String?
    let exceptionMsg: String?
}

enum PurchaseError: LocalizedError {
    case orderCreateFailed(String)
    case skProductNotFound
    case skPurchaseFailed(String)
    case skUserCancelled
    case receiptEmpty
    case verifyFailed(String)

    var errorDescription: String? {
        switch self {
        case .orderCreateFailed(let m):    return "下单失败：\(m)"
        case .skProductNotFound:           return "App Store 未找到该产品"
        case .skPurchaseFailed(let m):     return "StoreKit 购买失败：\(m)"
        case .skUserCancelled:             return "用户取消支付"
        case .receiptEmpty:                return "收据为空"
        case .verifyFailed(let m):         return "后端验单失败：\(m)"
        }
    }
}

// ========== 服务类 ==========
@MainActor
final class IosPurchaseService {

    /**
     * 完整购买流程：
     *   ① 下单拿 orderNo → ② StoreKit 内购 → ③ 后端验单
     *
     * @param goodsId       平台商品 ID（传给 /setCreatePay）
     * @param productId     App Store Connect 上的 Product ID（如 com.boltfox.vip1month）
     * @return 成功时返回 (orderNo, transactionId, verifyResponse)
     */
    func purchase(goodsId: String, productId: String) async throws -> (
        orderNo: String,
        transactionId: String,
        verifyResponse: VerifyReceiptResponse
    ) {
        // ① 下单（payType = 2 表示 IOS 内购）
        let orderNo = try await createOrder(goodsId: goodsId, payType: 2)

        // ② StoreKit 2 内购
        let (transaction, receiptData) = try await doSk2Purchase(productId: productId)

        // ③ 调后端验单
        let verifyRes = try await verifyReceipt(
            orderNo: orderNo,
            transactionId: transaction.id,
            receiptData: receiptData
        )

        // ④ 告诉 StoreKit 这笔交易已处理（消耗型产品必须 finish）
        await transaction.finish()

        return (orderNo, transaction.id, verifyRes)
    }

    // ---------- ① 下单 ----------
    private func createOrder(goodsId: String, payType: Int) async throws -> String {
        let url = URL(string: "\(PurchaseConfig.baseURL)/Client/Pay/setCreatePay")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(PurchaseConfig.userToken, forHTTPHeaderField: "userToken")
        req.httpBody = try JSONEncoder().encode([
            "goodsId": goodsId,
            "payType": payType,
        ])

        let (data, httpResp) = try await URLSession.shared.data(for: req)
        guard (httpResp as? HTTPURLResponse)?.statusCode == 200 else {
            throw PurchaseError.orderCreateFailed("HTTP \((httpResp as? HTTPURLResponse)?.statusCode ?? -1)")
        }
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard json?["retCode"] as? Int == 1,
              let orderNo = json?["retData"] as? [String: Any],
              let no = orderNo["orderNo"] as? String else {
            throw PurchaseError.orderCreateFailed(json?["retMsg"] as? String ?? "unknown")
        }
        return no
    }

    // ---------- ② StoreKit 2 内购 ----------
    private func doSk2Purchase(productId: String) async throws -> (
        transaction: Transaction,
        receiptData: String
    ) {
        // 拉产品
        let products = try await Product.products(for: [productId])
        guard let product = products.first else {
            throw PurchaseError.skProductNotFound
        }

        // 发起购买
        let purchaseResult: Product.PurchaseResult
        do {
            purchaseResult = try await product.purchase()
        } catch {
            throw PurchaseError.skPurchaseFailed(error.localizedDescription)
        }

        // 判断结果
        switch purchaseResult {
        case .success(let verification):
            let transaction: Transaction
            switch verification {
            case .verified(let t):
                transaction = t
            case .unverified:
                throw PurchaseError.skPurchaseFailed("交易签名校验失败")
            }

            // 取 receipt（从 appStoreReceiptURL）
            guard let receipt = loadReceiptData() else {
                throw PurchaseError.receiptEmpty
            }
            return (transaction, receipt)

        case .pending:
            throw PurchaseError.skPurchaseFailed("等待家长同意或网络问题，请稍后重试")
        case .userCancelled:
            throw PurchaseError.skUserCancelled
        @unknown default:
            throw PurchaseError.skPurchaseFailed("未知的 StoreKit 结果")
        }
    }

    // ---------- 从 appStoreReceiptURL 取 base64 ----------
    private func loadReceiptData() -> String? {
        guard let url = Bundle.main.appStoreReceiptURL else { return nil }
        guard let data = try? Data(contentsOf: url) else { return nil }
        return data.base64EncodedString()
    }

    // ---------- ③ 调后端验单 ----------
    private func verifyReceipt(orderNo: String, transactionId: String, receiptData: String)
        async throws -> VerifyReceiptResponse {

        let url = URL(string: "\(PurchaseConfig.baseURL)/Client/Pay/setApplePayVerifyReceipt")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(PurchaseConfig.userToken, forHTTPHeaderField: "userToken")

        let body = VerifyReceiptBody(
            receiptData: receiptData,
            orderNo: orderNo,
            transactionId: transactionId
        )
        req.httpBody = try JSONEncoder().encode(body)

        let (data, httpResp) = try await URLSession.shared.data(for: req)
        guard (httpResp as? HTTPURLResponse)?.statusCode == 200 else {
            throw PurchaseError.verifyFailed("HTTP \((httpResp as? HTTPURLResponse)?.statusCode ?? -1)")
        }

        let resp = try JSONDecoder().decode(VerifyReceiptResponse.self, from: data)
        guard resp.retCode == 1, resp.retData?.status == 0 else {
            let msg = resp.retMsg
                   ?? resp.retData?.exceptionMsg
                   ?? "Apple status=\(resp.retData?.status ?? -1)"
            throw PurchaseError.verifyFailed(msg)
        }
        return resp
    }
}
```

---

## 四、Swift 调用示例（UIViewController 里）

```swift
// 在你的购买按钮点击事件里
Task {
    let service = IosPurchaseService()
    do {
        let (orderNo, transactionId, resp) = try await service.purchase(
            goodsId: "vip_monthly_001",
            productId: "com.boltfox.boltstar.vip1month"
        )
        // 成功 → 刷新用户权益
        showAlert(title: "支付成功", message: "orderNo=\(orderNo), status=\(resp.retData?.status ?? -1)")
        await refreshCurrentUser()

    } catch let error as PurchaseError {
        showAlert(title: "支付失败", message: error.localizedDescription)
    } catch {
        showAlert(title: "支付失败", message: error.localizedDescription)
    }
}

func showAlert(title: String, message: String) { ... }
func refreshCurrentUser() async { ... }
```

---

## 五、Flutter 桥接层（Dart 侧）

如果是 Flutter 项目，iOS 原生 Swift 代码通过 MethodChannel 暴露给 Dart：

```dart
// dart/iap_bridge.dart
import 'package:flutter/services.dart';

const _channel = MethodChannel('com.boltfox/ios_purchase');

class IosPurchaseBridge {
  /// 调 iOS 原生 StoreKit，返回 { transactionId, receiptData }
  Future<Map<String, String>> purchase(String productId) async {
    return await _channel.invokeMapMethod('purchase', productId)
        ?? <String, String>{};
  }
}
```

```swift
// ios/Runner/SwiftIapBridge.swift —— Flutter 侧 MethodChannel 对接
import Flutter
import StoreKit

final class SwiftIapBridge {
    static func register(with messenger: FlutterBinaryMessenger) {
        let channel = FlutterMethodChannel(
            name: "com.boltfox/ios_purchase",
            binaryMessenger: messenger
        )
        let instance = SwiftIapBridge()
        channel.setMethodCallHandler(instance.handle)
    }

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "purchase":
            guard let productId = call.arguments as? String else {
                result(FlutterError(code: "BAD_ARGS", message: "productId required", details: nil)); return
            }
            Task { @MainActor in
                do {
                    let (tx, receipt) = try await self.doSkPurchase(productId: productId)
                    result(["transactionId": tx.id, "receiptData": receipt])
                } catch {
                    result(FlutterError(code: "SK_FAIL", message: error.localizedDescription, details: nil))
                }
            }
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // ↓↓↓ 这里复用上面 IosPurchaseService 里的 doSk2Purchase 逻辑 ↓↓↓
    private func doSkPurchase(productId: String) async throws -> (Transaction, String) {
        let products = try await Product.products(for: [productId])
        guard let product = products.first else {
            throw NSError(domain: "IAP", code: -1, userInfo: [NSLocalizedDescriptionKey: "产品不存在"])
        }
        let res = try await product.purchase()
        switch res {
        case .success(let ver):
            let tx: Transaction
            guard case .verified(let t) = ver else {
                throw NSError(domain: "IAP", code: -2, userInfo: [NSLocalizedDescriptionKey: "签名无效"])
            }
            tx = t
            guard let receipt = loadReceiptData() else {
                throw NSError(domain: "IAP", code: -3, userInfo: [NSLocalizedDescriptionKey: "收据为空"])
            }
            return (tx, receipt)
        case .userCancelled:
            throw NSError(domain: "IAP", code: -99, userInfo: [NSLocalizedDescriptionKey: "用户取消"])
        default:
            throw NSError(domain: "IAP", code: -4, userInfo: [NSLocalizedDescriptionKey: "购买失败"])
        }
    }

    private func loadReceiptData() -> String? {
        guard let url = Bundle.main.appStoreReceiptURL,
              let data = try? Data(contentsOf: url) else { return nil }
        return data.base64EncodedString()
    }
}
```

---

## 六、curl 快速验证接口联通性（后端 & 测试同事用）

```bash
# 1. 替换 URL / userToken / orderNo / transactionId / receiptData
curl -X POST 'https://yourdomain.com/Client/Pay/setApplePayVerifyReceipt' \
  -H 'Content-Type: application/json' \
  -H 'userToken: <YOUR_USER_TOKEN>' \
  -d '{
    "receiptData": "<BASE64_FROM_IOS>",
    "orderNo":     "2026101215300001",
    "transactionId":"2000000123456789",
    "excludeOldTransactions": true
  }'

# 成功响应示例：
# {
#   "retCode": 1,
#   "retMsg":  "操作成功",
#   "retData": {
#     "status": 0,
#     "environment": "Production",
#     "responseData": "{...Apple原始JSON...}"
#   }
# }
```

---

## 七、关键对照速查表

| 后端校验 | 前端要做什么 |
|---|---|
| `orderNo` 必须存在 & 状态=待支付 | 先调 `/setCreatePay`（payType=2）拿到 orderNo，再内购 |
| `receiptData` base64 合法 | iOS 直接从 `Bundle.main.appStoreReceiptURL` 读 Data → `.base64EncodedString()` |
| `transactionId` 在 receipt 里 | 用 StoreKit 2 `Transaction.id` 或 StoreKit 1 `SKPaymentTransaction.transactionIdentifier` |
| `result.contains("com.boltfox.boltstar")` bundleId | 前端没法改后端，确保 App Store Connect bundleId 和后端硬编码一致 |
| `result.contains(goodsName)` 产品名 | 下单时 goodsName 用 App Store 的 Product ID 最稳 |
| transactionId 不能重复 | 同一个 Apple 交易只能消耗一次，失败重试换别的 transactionId |
| `retCode==1 && status==0` 才算成功 | React Hook / Swift 里双重判断 |

---

## 八、StoreKit 1 兼容实现（iOS 14 及以下）

```swift
// 如果你们 App 最低 iOS 版本 < 15，用这个 Observer 替代上面的 StoreKit 2 代码
import StoreKit

final class LegacyIosPurchaseObserver: NSObject, SKPaymentTransactionObserver {
    static let shared = LegacyIosPurchaseObserver()

    private var pendingContinuation: CheckedContinuation<(transactionId: String, receipt: String), Error>?
    private var orderNo: String = ""

    /// 发起购买（StoreKit 1）
    func purchase(productId: String, orderNo: String)
        async throws -> (transactionId: String, receipt: String) {
        self.orderNo = orderNo
        SKPaymentQueue.default().add(self)
        defer { SKPaymentQueue.default().remove(self) }

        return try await withCheckedThrowingContinuation { cont in
            self.pendingContinuation = cont
            let product = SKProduct() // 实际项目里先 requestProducts
            let payment = SKPayment(product: product)
            SKPaymentQueue.default().add(payment)
        }
    }

    func paymentQueue(_ queue: SKPaymentQueue, updatedTransactions transactions: [SKPaymentTransaction]) {
        for tx in transactions {
            switch tx.transactionState {
            case .purchased:
                SKPaymentQueue.default().finishTransaction(tx)
                guard let tid = tx.transactionIdentifier,
                      let receipt = loadReceiptData() else {
                    pendingContinuation?.resume(throwing: NSError(domain: "IAP", code: -3))
                    return
                }
                pendingContinuation?.resume(returning: (tid, receipt))

            case .failed, .restored:
                SKPaymentQueue.default().finishTransaction(tx)
                pendingContinuation?.resume(throwing: NSError(domain: "IAP", code: -99))

            default: break
            }
        }
    }

    private func loadReceiptData() -> String? {
        guard let url = Bundle.main.appStoreReceiptURL,
              let data = try? Data(contentsOf: url) else { return nil }
        return data.base64EncodedString()
    }
}
```

---

这样前端同事拿到这套代码，Swift 原生的直接 `IosPurchaseService().purchase(goodsId:productId:)`，Flutter/RN 的用桥接层 + `payApi.ts`，都能直接跑通。