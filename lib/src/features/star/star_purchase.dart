import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../native_device_api.dart';
import 'star_coin_api.dart';

/// 星币购买链路的编排（**安卓 = PayPal**，2026-08-27 接入）。
///
/// 完整五步，与小程序 `utils/token-api.js purchase()` 同结构，只是第 ③④ 步换了渠道：
///   ① `getGoodsList` 取套餐（页面做）
///   ② `POST /Client/Order/addOrder` 在我们平台建单 → 拿 `orderNo`
///   ③ `POST /Client/Pay/setCreatePay`（`payType=3`）→ 拿 `payPalApproveUrl`
///   ④ 跳出去让用户在 PayPal 授权
///   ⑤ **回到 App 后轮询 `getUserAccount`，余额变多才算买到了**
///
/// ⚠️ **铁律：不拿「用户跳回来了」当成功。**（对齐小程序：不拿支付 success 回调加余额。）
/// PayPal 的 approve 只是授权，扣款/发货是渠道回调打到我们后端之后的事，端上唯一可信的
/// 判据是**服务端余额变多**。用户在 PayPal 页面点了取消同样会跳回 App，把「跳回来」
/// 当成功会直接给出「购买成功」的假消息。
///
/// ✅ **capture（实际扣款）由后端在回调里做**（2026-08-27 后端确认）。PayPal Orders v2 是
/// create → approve → capture 三步，第三步是 PayPal 的**服务端** API（要商户 secret 换的
/// OAuth2 token），端上做不了也不该做。所以本链路第 ④ 步跳完就没端上的事了，
/// 第 ⑤ 步单纯等「后端 capture 完 → 加星币 → 余额变多」。
/// ⚠️ 这意味着到账要经过「PayPal 回调 → 后端 capture → 入账」两跳，比小程序的微信回调更长；
/// [confirmDelays] 那 9.4s 是照搬小程序的节奏，**联调时要实测**，常态兜不住就把尾巴加长。
///
/// ✅ **回跳口径（2026-08-31 定稿，成功与取消两条都有）**：
///
/// `setCreatePay` 的两个入参 `payPalReturnUrl` / `payPalCancelUrl` **都由端上传**，
/// 传的是我们自己的 **https 中转页**（[returnUrl] / [cancelUrl]），中转页再用
/// `boltstar://` 把 App 拉起来（[appReturnLink] / [appCancelLink]）：
///
/// ```
/// 授权成功：PayPal --302--> https 中转页?token=..&PayerID=..
///           --JS--> boltstar://pay/paypal/return?token=..&PayerID=..
///           --> 原生 PayPalRedirectActivity --> [consumeReturn]
///           --> GET /Client/Pay/getPayPalNotify（后端据此 capture 扣款、入账）
///           --> 照旧轮询余额确认到账
///
/// 用户取消：PayPal --302--> https 中转页 --JS--> boltstar://pay/paypal/cancel
///           --> [consumeCanceled] --> 当场提示「已取消支付」
/// ```
///
/// ⚠️ **中间那个 https 页不能省**（别改成让 PayPal 直接 302 到 `boltstar://`）：
/// ① PayPal 对 return_url 按 URI 校验，非 http(s) 收不收没有保证，拒了的话 `setCreatePay`
///    当场就失败、连授权页都拿不到；② 更要命的是 Chrome 会拦掉「**服务端 302** 直跳自定义
///    scheme」这种非用户手势的外跳 —— 表现是用户停在空白页、什么都不发生且**不报错**。
///
/// ⚠️ **capture 是被 [notifyReturn] 触发的**，也就是说用户点了同意却**没跳回 App**
///（关掉浏览器 / 中转页没拉起 App / 进程被回收）时扣款不会发生。端上补不了这一段，
/// 需要后端有 webhook 兜底（已提醒后端，待确认）。
class StarPurchase {
  const StarPurchase._();

  // ── 两组地址，别混用 ────────────────────────────────────────────────
  //
  // [returnUrl] / [cancelUrl]  = **交给 PayPal 的**，必须 https（见文件头）。
  // [appReturnLink] / [appCancelLink] = **中转页把 App 拉起来用的**，自定义 scheme，
  //                                     只在「中转页 ↔ App」之间约定，PayPal 不认识它。

  /// 授权成功后 PayPal 把浏览器跳去的 https 中转页（`setCreatePay` 的 `payPalReturnUrl`）。
  ///
  /// PayPal 会往它后面追加 `?token=<PayPal订单号>&PayerID=<付款人>`，中转页把这串 query
  /// **原样**接到 [appReturnLink] 后面再拉起 App。
  ///
  /// ✅ **2026-09-01 域名已定**：`pp.boltfox.cn`，两个页面都在根级、带 `.html` 后缀。
  ///
  /// 用的是**支付专用的独立域名**（不是挂在管理后台 `badmin.boltfox.cn` 下）——
  /// 这样就不会撞上后台那种 SPA 的 `try_files $uri /index.html` 兜底
  /// （撞上的表现是 PayPal 跳过去返回的是后台首页，脚本根本不执行）。
  ///
  /// 页面源码在仓库的 `deploy/paypal/return.html`，部署与联调见
  /// `docs/runbooks/PAYPAL_REDIRECT.md`。
  /// 换域名/路径**不必改代码**：打包时 `--dart-define=PAYPAL_RETURN_URL=https://…` 覆盖即可。
  static const String returnUrl = String.fromEnvironment(
    'PAYPAL_RETURN_URL',
    defaultValue: 'https://pp.boltfox.cn/return.html',
  );

  /// 用户点「Cancel and return」后 PayPal 跳去的 https 中转页
  /// （`setCreatePay` 的 `payPalCancelUrl`）。域名与约定同 [returnUrl]，可用
  /// `--dart-define=PAYPAL_CANCEL_URL=https://…` 覆盖。
  static const String cancelUrl = String.fromEnvironment(
    'PAYPAL_CANCEL_URL',
    defaultValue: 'https://pp.boltfox.cn/cancel.html',
  );

  /// 中转页拉起 App 用的深链（授权成功）。
  ///
  /// ⚠️ 与安卓清单里 `PayPalRedirectActivity` 的 intent-filter **必须逐字一致**
  /// （scheme=boltstar / host=pay / path=/paypal/return），改一处就要改两处 ——
  /// `test/star_purchase_test.dart` 有一条测试直接拿清单来比对，防止只改一处。
  static const String appReturnLink = 'boltstar://pay/paypal/return';

  /// 中转页拉起 App 用的深链（用户取消）。约束同 [appReturnLink]。
  ///
  /// 取消是端上**唯一一个确凿的负向信号**：cancel_url 只有「没付成」才会被跳到，
  /// 与「余额没变」那种分不清是取消还是回调慢的情形不是一回事，所以读到它就敢把话说死
  /// 成「已取消支付」。（这不违背文件头那条铁律 —— 铁律管的是**不许把跳回来当成功**，
  /// 这里下的是失败结论，依据是 PayPal 自己跳的这条 url，不是「用户回来了」。）
  static const String appCancelLink = 'boltstar://pay/paypal/cancel';

  /// 支付回来后等服务端「发货」（渠道回调 → 加星币）的轮询节奏，与小程序 `CONFIRM_DELAYS` 一致。
  ///
  /// 渠道回调是异步打到我们后端的，用户刚跳回来时余额通常还没变，直接拉一次必显示成没到账。
  /// 递增退避、总时长约 9.4s：够覆盖正常回调，又不至于让用户对着转圈干等。
  /// **超时不算失败** —— 钱可能已经付了，转成「稍后到账」的措辞，别把用户吓着。
  static const List<Duration> confirmDelays = [
    Duration(milliseconds: 900),
    Duration(milliseconds: 1200),
    Duration(milliseconds: 1800),
    Duration(milliseconds: 2500),
    Duration(milliseconds: 3000),
  ];

  /// 读一次余额作为「到账判据」的基线。
  ///
  /// 读失败返回 null（不阻断购买，也不弹错）：用户点的是「立即购买」，为一次基线读取
  /// 先看到一条红字很莫名。⚠️ 基线为 null 时 [confirm] **不做差值判定**、只认 `getPayQuery`
  /// —— 拿「余额 > 0」当到账，会把「本来就有余额、这次却没付成」误报成买到了。
  static Future<int?> readBaselineBalance() async {
    try {
      return (await StarCoinApi.fetchAccount()).balance;
    } catch (_) {
      return null;
    }
  }

  /// ②③④ 三步：建单 → 创建支付 → 跳 PayPal 授权页。
  ///
  /// 返回的 [StarPendingPayment] 交给页面保管，用户回到 App 后用它调 [confirm]。
  /// 失败一律抛 [StarPurchaseException]（页面按 reason 分支措辞）或 `ApiException`（接口层的）。
  static Future<StarPendingPayment> start({
    required StarPackage package,
    required int payType,
    void Function(StarPurchaseStage stage)? onStage,
  }) async {
    if (!StarPayType.supportedOnThisApp) {
      // 付不了就别建单：后台留一串永远付不掉的待支付单，对账时全是垃圾。
      throw StarPurchaseException(
        StarPurchaseError.channelUnavailable,
        '当前端的支付通道尚未接入',
      );
    }

    // 丢掉可能残留的旧回跳标记：App 进程被回收时深链会把标记置在一个没人来读的新进程里
    // （见 PayPalRedirectActivity 的类注释）。不先清掉的话，这一单刚跳出去、用户一切回来
    // 就会被上一单的旧标记判成「已取消」或误触发一次 capture 通知。
    await NativeDeviceApi.clearPayPalRedirect();

    onStage?.call(StarPurchaseStage.order);
    final order = await StarCoinApi.createOrder(
      package: package,
      payType: payType,
    );
    debugPrint(
      '[PayPal] 建单完成 orderNo=${order.orderNo} orderId=${order.orderId} '
      'amount=${order.amount} payType=$payType',
    );

    onStage?.call(StarPurchaseStage.pay);
    final creation = await StarCoinApi.createPay(
      orderNo: order.orderNo,
      payType: payType,
      // 只对 PayPal 有意义（字段名就带 PayPal）。将来 iOS 接内购复用这条链路时，
      // 别把一对 PayPal 专用的回跳地址塞给苹果那条单。
      payPalReturnUrl: payType == StarPayType.paypal ? returnUrl : null,
      payPalCancelUrl: payType == StarPayType.paypal ? cancelUrl : null,
    );
    debugPrint(
      '[PayPal] setCreatePay 返回 payPalOrderId=${creation.payPalOrderId.isEmpty ? '(空)' : creation.payPalOrderId} '
      'approveUrl=${creation.payPalApproveUrl.isEmpty ? '(空)' : '有'} '
      // status 只在后端透传 PayPal 原始返回时才有值（CREATED/APPROVED/COMPLETED），
      // 用来一眼看出「后端到底映没映射这一层」
      'status=${creation.status.isEmpty ? '(空)' : creation.status} '
      'exceptionMsg=${creation.exceptionMsg.isEmpty ? '(空)' : creation.exceptionMsg}',
    );

    if (creation.payPalApproveUrl.isEmpty) {
      throw StarPurchaseException(
        StarPurchaseError.approveUrlMissing,
        '未拿到 PayPal 支付地址',
        detail: creation.exceptionMsg,
      );
    }

    final uri = Uri.tryParse(creation.payPalApproveUrl);
    if (uri == null) {
      throw StarPurchaseException(
        StarPurchaseError.approveUrlMissing,
        'PayPal 支付地址无法解析',
        detail: creation.payPalApproveUrl,
      );
    }

    // 外部浏览器 / PayPal App，**不用内嵌 WebView**：
    // ① PayPal 出于安全会拒绝一部分内嵌 WebView 的登录（风控直接卡在登录页）；
    // ② 内嵌要新引一个 webview 依赖，而回跳仍要靠后端配 return_url，省不掉；
    // ③ 装了 PayPal App 时 externalApplication 能直接唤起它，登录态是现成的。
    var launched = false;
    try {
      launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (error) {
      debugPrint('[PayPal] 跳转授权页异常：$error');
      launched = false;
    }
    if (!launched) {
      throw StarPurchaseException(
        StarPurchaseError.launchFailed,
        '无法打开 PayPal 支付页面',
        detail: creation.payPalApproveUrl,
      );
    }

    onStage?.call(StarPurchaseStage.approving);
    return StarPendingPayment(
      order: order,
      package: package,
      payPalOrderId: creation.payPalOrderId,
    );
  }

  /// 读走「授权成功回跳」这一次信号（安卓深链，见 [appReturnLink]），返回 PayPal 带回来的
  /// `{token, PayerID}`；没有这一跳返回 null。
  ///
  /// 拿到之后要调 [notifyReturn] 把这两个值转给后端 —— **后端据此 capture 扣款**。
  static Future<Map<String, String>?> consumeReturn() =>
      NativeDeviceApi.consumePayPalReturn();

  /// 把回跳带回来的 `token` / `PayerID` 原样转给后端（`getPayPalNotify`），触发 capture。
  ///
  /// ⚠️ 返回值**只用来把最终的提示说得更准**，不据此直接报「购买成功」——
  /// 到账判据始终是 [confirm] 里的「服务端余额变多」（文件头那条铁律）。
  /// 两个参数任一为空时不调接口：中转页把 query 丢了，转过去后端也没法 capture，
  /// 如实退回余额轮询兜底。
  static Future<StarPayNotify> notifyReturn(Map<String, String> payload) async {
    final token = payload['token']?.trim() ?? '';
    final payerId = payload['PayerID']?.trim() ?? '';
    debugPrint(
      '[PayPal] 收到授权回跳 token=${token.isEmpty ? '(空)' : token} '
      'PayerID=${payerId.isEmpty ? '(空)' : payerId}',
    );
    if (token.isEmpty || payerId.isEmpty) {
      return StarPayNotify.failed;
    }
    final result = await StarCoinApi.notifyPayPalReturn(
      token: token,
      payerId: payerId,
    );
    debugPrint(
      '[PayPal] getPayPalNotify 返回 paid=${result.paid} '
      'message=${result.message.isEmpty ? '(空)' : result.message}',
    );
    return result;
  }

  /// 读走「用户在 PayPal 点了取消」这一次信号（安卓深链，见 [appCancelLink]）。
  ///
  /// 页面在每次 `resumed`、以及手动点「我已完成支付」时**先问这一句**：读到 true 就是
  /// 用户自己取消的，当场说「已取消支付」，[confirm] 那条轮询压根不用跑。
  ///
  /// 读不到返回 false（iOS 没这条通道、通道异常、或者用户没走深链而是自己切回来的），
  /// 调用方退回 [confirm] 的余额判定 —— 也就是说这条信号**只用来把提示说得更准**，
  /// 缺了它一切照旧。
  static Future<bool> consumeCanceled() =>
      NativeDeviceApi.consumePayPalCancel();

  /// ⑤ 以**服务端余额**为准确认到账。用户从 PayPal 回到 App 后调。
  ///
  /// 按 [confirmDelays] 退避轮询，余额比 [baselineBalance] 多了才算到账。
  /// 轮询期间的接口错误一律吞掉（中途一次网络抖动就弹红字，用户会以为钱没了）。
  ///
  /// 轮询超时**不等于失败**：再查一次 `getPayQuery`，把提示分成
  /// 「已付款、稍后到账」（`payState=1`）和「结果确认中」（其余）。
  ///
  /// [baselineBalance] 为 null（购买前没读到余额）时不做差值判定，只认 `getPayQuery` ——
  /// 拿「余额 > 0」当到账会把「本来就有余额、这次却没付成」误报成买到了。
  static Future<StarPurchaseResult> confirm(
    StarPendingPayment pending, {
    int? baselineBalance,
  }) async {
    StarAccount? account;
    for (final delay in confirmDelays) {
      await Future<void>.delayed(delay);
      StarAccount? latest;
      try {
        latest = await StarCoinApi.fetchAccount();
      } catch (_) {
        // 轮询期间的接口错误一律吞掉：中途一次网络抖动就弹红字，用户会以为钱没了。
        latest = null;
      }
      if (latest == null) {
        continue;
      }
      account = latest;
      if (baselineBalance != null && latest.balance > baselineBalance) {
        final gained = latest.balance - baselineBalance;
        debugPrint('[PayPal] 到账确认：+$gained（orderNo=${pending.order.orderNo}）');
        return StarPurchaseResult(
          credited: true,
          gained: gained,
          account: account,
          orderNo: pending.order.orderNo,
        );
      }
    }

    final queried = await StarCoinApi.queryPay(
      orderNo: pending.order.orderNo,
      payType: pending.order.payType,
    );
    debugPrint(
      '[PayPal] 余额轮询超时，查单 payState=${queried?.payState} '
      'payNo=${queried?.payNo ?? '(空)'} orderNo=${pending.order.orderNo}',
    );
    return StarPurchaseResult(
      credited: false,
      gained: null,
      account: account,
      orderNo: pending.order.orderNo,
      // ⚠️ 只认 payState==1（枚举后端未给）。查不到也一律不说「失败」。
      paidByQuery: queried?.paid ?? false,
    );
  }
}

/// 购买链路的阶段，页面据此换 loading 文案（这条链路最长约 10s，中间没有反馈用户会以为卡死）。
enum StarPurchaseStage {
  /// 正在建单（`addOrder`）。
  order,

  /// 正在创建支付（`setCreatePay`）。
  pay,

  /// 已跳出到 PayPal，等用户授权后回到 App。
  approving,

  /// 正在确认到账（轮询余额）。
  confirming,
}

/// 已拉起、等用户在 PayPal 侧完成授权的一单。
class StarPendingPayment {
  const StarPendingPayment({
    required this.order,
    required this.package,
    required this.payPalOrderId,
  });

  final StarOrder order;
  final StarPackage package;

  /// PayPal 侧订单 id，仅供排查（认单一律用 [StarOrder.orderNo]）。
  final String payPalOrderId;
}

/// 到账确认的结果。
///
/// 三种结局，页面措辞必须分开：
/// - [credited]=true：余额真的变多了 → 「购买成功」
/// - [credited]=false 且 [paidByQuery]=true → 「已付款，稍后到账」
/// - 两者皆 false → 「结果确认中」（**不是失败**，可能没付、也可能回调慢）
class StarPurchaseResult {
  const StarPurchaseResult({
    required this.credited,
    required this.gained,
    required this.account,
    required this.orderNo,
    this.paidByQuery = false,
  });

  final bool credited;

  /// 到账增量（[credited]=true 时才有值）。
  final int? gained;

  /// 轮询期间最后一次读到的账户（读失败过则可能为 null），供页面顺手刷新余额。
  final StarAccount? account;

  final String orderNo;

  /// `getPayQuery` 说这单已支付（`payState=1`）。
  final bool paidByQuery;
}
