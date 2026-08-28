import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

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
/// ⚠️ **仍未决**（见 `docs/history/2026-08/2026-08-27-安卓PayPal支付对接.md`）：
/// **`return_url` 配的是什么** —— 能配成 App 的自定义 scheme 才谈得上精确回跳；
/// 当前按「用户自己切回 App」处理（页面监听 `AppLifecycleState.resumed`），
/// 另给一颗「我已完成支付」的手动按钮兜底。
class StarPurchase {
  const StarPurchase._();

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
