import 'dart:io' show Platform;

import '../../network/boltfox_api.dart';

/// 星币（原「Token」，2026-08-12 全站改称；后端字段名仍是 `availableToken` 等）的数据层。
///
/// 账户、套餐、记录、消耗规则四个读接口 + 购买链路（建单 → 创建支付 → 查单）。
///
/// ⚠️ **支付渠道按端分工**（产品口径）：小程序=微信支付、**安卓=PayPal**、iOS=Apple 内购。
/// 2026-08-27 接的是**安卓 PayPal 这一条**；iOS 的 IAP 仍未接，[StarPayType.supportedOnThisApp]
/// 为 false 时页面不给购买入口——建单即在后台留下待支付单，付不了就别建。
///
/// 购买编排（余额基线 → 建单 → 拉起 → 轮询到账）在 `star_purchase.dart`，本文件只管接口与归一。
///
/// 余额与「能不能发起 AI 对话」的闸在 `features/ai/ai_token.dart`（AI 侧要用，独立一份）。
class StarCoinApi {
  const StarCoinApi._();

  static const int recordPageSize = 20;

  static int _toInt(Object? value) {
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse('${value ?? ''}'.trim()) ?? 0;
  }

  static double _toDouble(Object? value) {
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse('${value ?? ''}'.trim()) ?? 0;
  }

  static String _toText(Object? value) => '${value ?? ''}'.trim();

  /// 取第一个非空串（同一个信息后端可能给在不同字段名下，见 [StarPayCreation.fromJson]）。
  static String _firstNonEmpty(List<String> values) {
    for (final value in values) {
      if (value.isNotEmpty) {
        return value;
      }
    }
    return '';
  }

  /// 列表出参归一：分页壳（`pageData`）、`list` 包一层、裸数组三种都认。
  /// ⚠️ `list` 这一路是 2026-08-27 补的（对齐小程序 `pageRows`）——`getGoodsList`
  /// 到底包哪层未联调过，认错一层的表现是「套餐页空列表」而不是报错，很难查。
  static List<Map<String, dynamic>> _rows(Object? data) {
    Object? list = data;
    if (data is Map) {
      list = data['pageData'] ?? data['list'];
    }
    if (list is! List) {
      return const [];
    }
    return list.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
  }

  /// 整数去掉小数点（后端 `30.0` → `30`）；真有小数最多留两位。
  /// 星币是整数计价，`.0` 只会让人以为还有小数位。
  static String formatAmount(Object? value) {
    final number = _toDouble(value);
    if (number == number.roundToDouble()) {
      return '${number.toInt()}';
    }
    return number
        .toStringAsFixed(2)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }

  /// 账户概览。三个字段后端都是 **String**，这里统一转数字。
  static Future<StarAccount> fetchAccount() async {
    final data = await BoltFoxApi.getUserAccount();
    if (data is! Map) {
      return const StarAccount(balance: 0, totalPurchased: 0, totalSpent: 0);
    }
    return StarAccount(
      balance: _toInt(data['availableToken']),
      totalPurchased: _toInt(data['totalToken']),
      totalSpent: _toInt(data['consumeToken']),
    );
  }

  /// 套餐列表（`GET /Client/Order/getGoodsList`）。
  ///
  /// 拉不到或空列表都返回空表，由页面决定怎么呈现（购买页空表 = 不给按钮，
  /// 而不是给一颗点了必然失败的「立即购买」）。
  static Future<List<StarPackage>> fetchPackages() async {
    final data = await BoltFoxApi.getGoodsList();
    return _rows(data).map(StarPackage.fromJson).toList();
  }

  /// 星币消耗规则表（`GET /Client/Order/getAiConfigList`）。
  ///
  /// `retData` 是**裸数组**（不是分页壳）。⚠️ **顺序原样保留**：后端按 `grade`(权重) 排好再下发，
  /// Client 出参里没有这个字段，端上重排只会和后台配置对不上。
  /// 「最低账户余额」那条（`aiModel=3` 会话条件）也在这个列表里，就是规则表的第一行。
  static Future<List<StarRule>> fetchRules() async {
    final data = await BoltFoxApi.getAiConfigList();
    return _rows(data)
        .map(
          (item) => StarRule(
            id: _toInt(item['aiConfigId']),
            name: _toText(item['aiProject']),
            cost: formatAmount(item['num']),
            remark: _toText(item['remark']),
          ),
        )
        // 没有服务类型的脏数据不进表：画出来就是一行空白
        .where((rule) => rule.name.isNotEmpty)
        .toList();
  }

  /// 记录里那句 `description` 中的星币数量（2026-08-13 两端同改）。
  ///
  /// 产品口径：**购买/消费记录上「XXX 星币」的数量以 `description` 为准**——后端在这个字段里
  /// 给的就是这笔的数量（例「200 token」），而 `num` 在这两个出参里并不总是有值，
  /// 照它渲染就会出现「描述写着 200 token、右边却是 0 星币」。
  ///
  /// 取第一个数字；一个数字都没有时返回 null，由调用方回落 `num`
  /// （宁可退回旧口径，也不要把一条真实记录显示成 0）。消费侧可能带负号，一律取绝对值
  /// （减号由页面自己写）。
  static int? _tokensFromDescription(String description) {
    final matched = RegExp(r'-?\d+(?:\.\d+)?').firstMatch(description);
    if (matched == null) {
      return null;
    }
    final number = double.tryParse(matched.group(0)!);
    if (number == null) {
      return null;
    }
    return number.abs().round();
  }

  /// `description` 是不是「纯数量」（例「200 token」「200星币」）。
  static bool _isQuantityOnlyDescription(String description) =>
      RegExp(
        r'^\s*-?\d+(?:\.\d+)?\s*(?:tokens?|星币)?\s*$',
        caseSensitive: false,
      ).hasMatch(description);

  /// 购买 / 消费记录（分页）。[spend] = true 取消费记录（`inOutType=2`）。
  static Future<StarRecordPage> fetchRecords({
    required bool spend,
    int pageIndex = 1,
  }) async {
    final data = await BoltFoxApi.getUserAccountTrade(
      inOutType: spend ? 2 : 1,
      pageIndex: pageIndex,
      pageSize: recordPageSize,
    );
    final rows = _rows(data);
    final pageCount = data is Map ? _toInt(data['pageCount']) : 0;
    return StarRecordPage(
      records: rows
          .map(
            (item) {
              final description = _toText(item['description']);
              final described = _tokensFromDescription(description);
              return StarRecord(
                time: _toText(item['joinTime']),
                // 数量以 description 为准（见 [_tokensFromDescription]），取不到才回落 num
                amount: described ?? _toInt(item['num']),
                gift: _toInt(item['giveNum']),
                money: _toDouble(item['amount']),
                // 「场景」那一行：description 只是个数量时不再重复画一遍（右边已经写着数量）
                scene: _isQuantityOnlyDescription(description) ? '' : description,
                // ⚠️ 数值 + 「已转文字」两个都留着（swagger `ClientUserAccountTradeApiOut`
                // 同时给了 payType/payTypeMsg、orderState/orderStateMsg）：
                // **后端忽略 language 参数，两个 Msg 恒为中文**，英/日/繁用户会直接看到
                // 「已完成」「微信支付」。展示一律走 AppL10n 的本地化，原文只作兜底。
                payType: _toInt(item['payType']),
                channel: _toText(item['payTypeMsg']),
                orderState: _toInt(item['orderState']),
                status: _toText(item['orderStateMsg']),
              );
            },
          )
          .toList(),
      pageIndex: pageIndex,
      // 判停优先 pageCount：只看条数会在「后端无视 pageSize 按自己的默认值分页」时提前停
      hasMore: pageCount > 0
          ? pageIndex < pageCount
          : rows.length >= recordPageSize,
    );
  }

  // ==================== 购买链路（2026-08-27，安卓 PayPal）====================

  /// 建单（`POST /Client/Order/addOrder`）→ [StarOrder]。
  ///
  /// ⚠️ 调用方要先确认这一端**付得了**（[StarPayType.supportedOnThisApp]）：
  /// 建单即在后台留下一条待支付单，付不掉的单子攒着只会让对账多一堆垃圾。
  static Future<StarOrder> createOrder({
    required StarPackage package,
    required int payType,
  }) async {
    final data = await BoltFoxApi.addOrder(
      goodsId: package.goodsId,
      payType: payType,
    );
    final order = StarOrder.fromJson(
      data is Map ? data.cast<String, dynamic>() : const {},
      payType: payType,
    );
    if (order.orderNo.isEmpty) {
      // orderNo 是后面两步的钥匙，缺了就没法继续；这里挑明，别让 setCreatePay 拿空串去问。
      throw StarPurchaseException(
        StarPurchaseError.orderNoMissing,
        '下单成功但未拿到订单号',
      );
    }
    return order;
  }

  /// 创建支付（`POST /Client/Pay/setCreatePay`）→ [StarPayCreation]。
  ///
  /// [payPalCancelUrl]：用户在 PayPal 点取消后浏览器跳的地址（2026-08-31 后端新增入参）。
  /// 端上传 App 的自定义 scheme 深链，取值见 `star_purchase.dart` 的 `StarPurchase.cancelReturnUrl`
  /// （本文件被 star_purchase.dart 依赖，反向 import 只为一句注释不值当）。
  static Future<StarPayCreation> createPay({
    required String orderNo,
    required int payType,
    String? payPalCancelUrl,
  }) async {
    final data = await BoltFoxApi.setCreatePay(
      orderNo: orderNo,
      payType: payType,
      payPalCancelUrl: payPalCancelUrl,
    );
    return StarPayCreation.fromJson(
      data is Map ? data.cast<String, dynamic>() : const {},
    );
  }

  /// 查支付侧订单（`GET /Client/Pay/getPayQuery`）。
  ///
  /// **静默失败返回 null**：这一步只用来把提示措辞说准（「已付款、稍后到账」还是
  /// 「结果确认中」），不该再弹一个错盖住主流程的结果弹窗。
  static Future<StarPayQuery?> queryPay({
    required String orderNo,
    required int payType,
  }) async {
    if (orderNo.isEmpty) {
      return null;
    }
    try {
      final data = await BoltFoxApi.getPayQuery(
        orderNo: orderNo,
        payType: payType,
      );
      return StarPayQuery.fromJson(
        data is Map ? data.cast<String, dynamic>() : const {},
      );
    } catch (_) {
      return null;
    }
  }
}

/// 售价货币符号的**兜底默认值**。
///
/// ✅ 2026-08-31 核 swagger：`ClientGoodsApiOut` 本来就有 **`currencySymbol`**（描述「币种符号$,¥」），
/// 币种由**后端按商品下发**，端上不该写死 —— 见 [StarPackage.currencySymbol]。
/// 这个常量只在后端没给（空串）时顶上，免得价钱前面空一块。
///
/// ⚠️ 别再拿它当「就是人民币」的依据：PayPal 侧若收美元，后端会把 `currencySymbol` 给成 `$`，
/// 而写死 `¥` 的表现正是最坏的那种——**页面写着 ¥、PayPal 扣的是 $**。
const String kStarCurrencySymbol = '¥';

/// `addOrder` / `setCreatePay` / `getPayQuery` 的 `payType`（swagger `ClientOrderAddApiIn.payType`）。
///
/// ⚠️ **按端分工，不是三端同一套**（产品口径 2026-08-27）：
/// 小程序=[wechat]、**安卓=[paypal]**、iOS=[apple]。
class StarPayType {
  const StarPayType._();

  /// 微信支付（小程序=虚拟支付）。App 两端都不走这条。
  static const int wechat = 1;

  /// iOS 内购。⚠️ 通道未接入，[supportedOnThisApp] 在 iOS 上因此为 false。
  static const int apple = 2;

  /// PayPal。安卓端 2026-08-27 接入。
  static const int paypal = 3;

  /// 当前平台该用哪个 `payType`。
  ///
  /// ⚠️ 别在业务里按平台现写 if：这个映射是产品口径（安卓不是「安卓内购」而是 PayPal），
  /// 分散写必然有人照旧文档写成 IAP。
  static int get forCurrentPlatform => Platform.isIOS ? apple : paypal;

  /// 这一端的通道**是否真的能付**。iOS 的 IAP 尚未接入 → false，
  /// 页面据此不给购买入口（付不了就别建单，见 [StarCoinApi.createOrder]）。
  static bool get supportedOnThisApp => Platform.isAndroid;
}

/// 套餐（`ClientGoodsApiOut`）。
class StarPackage {
  const StarPackage({
    required this.goodsId,
    required this.name,
    required this.tokens,
    required this.gift,
    required this.price,
    required this.currencySymbol,
    required this.wxProductId,
    required this.appleProductId,
  });

  factory StarPackage.fromJson(Map<String, dynamic> json) {
    return StarPackage(
      goodsId: StarCoinApi._toInt(json['goodsId']),
      name: StarCoinApi._toText(json['goodsName']),
      tokens: StarCoinApi._toInt(json['num']),
      gift: StarCoinApi._toInt(json['giveNum']),
      price: StarCoinApi._toDouble(json['amount']),
      // 币种符号由后端按商品下发（swagger `ClientGoodsApiOut.currencySymbol`，「币种符号$,¥」）。
      // 后端没给才退回 [kStarCurrencySymbol]：符号跟着钱走，端上写死就会出现
      // 「页面写着 ¥、PayPal 扣的是 $」。
      currencySymbol: StarCoinApi._firstNonEmpty([
        StarCoinApi._toText(json['currencySymbol']),
        kStarCurrencySymbol,
      ]),
      // 两个渠道商品 id 端上都不直接拿去调支付（微信侧由服务端签进 signData；
      // PayPal 侧订单也由服务端建），留着是为了排查「这档在这一端配没配」。
      wxProductId: StarCoinApi._toText(json['wxProductId']),
      appleProductId: StarCoinApi._toText(json['appleProductId']),
    );
  }

  final int goodsId;
  final String name;

  /// 基础星币数。
  final int tokens;

  /// 赠送星币数。
  final int gift;

  /// 售价。币种见 [currencySymbol]，两者必须一起用，别把数字单拎出去配别的符号。
  final double price;

  /// 售价的货币符号（后端 `ClientGoodsApiOut.currencySymbol`，如 `¥` / `$`）。
  /// 后端没给时是 [kStarCurrencySymbol]。
  final String currencySymbol;

  final String wxProductId;
  final String appleProductId;

  /// 合计获得 = 基础 + 赠送。购买页与记录页共用，避免两处各算一遍算出不同的数。
  int get totalTokens => tokens + gift;

  /// 单价（约）。⚠️ 按**含赠送**总数算：否则赠送多的档位单价反而显得更贵，
  /// 与「越买越划算」的排序相悖。不用后端的 `unitPrice`（integer 且不含赠送，会显示成 0）。
  /// ⚠️ 展示时的货币符号取 [currencySymbol]，别另配一个。
  String get unitPrice {
    final total = totalTokens;
    if (total <= 0) {
      return '0.00';
    }
    return (price / total).toStringAsFixed(2);
  }
}

/// 建单结果（`ClientAddOrderApiOut`）。微信侧的签名三件套 PayPal 用不到，不在这里落地。
class StarOrder {
  const StarOrder({
    required this.orderNo,
    required this.orderId,
    required this.amount,
    required this.payType,
  });

  factory StarOrder.fromJson(Map<String, dynamic> json, {required int payType}) {
    return StarOrder(
      orderNo: StarCoinApi._toText(json['orderNo']),
      orderId: StarCoinApi._toText(json['orderId']),
      amount: StarCoinApi._toDouble(json['amount']),
      payType: payType,
    );
  }

  /// **我们平台的订单号**，`setCreatePay` / `getPayQuery` 都按它认单
  /// （不是 PayPal 侧的 `payPalOrderId`，也不是微信侧的 `outTradeNo`）。
  final String orderNo;

  final String orderId;
  final double amount;
  final int payType;
}

/// 创建支付结果。**两种形状都认**（2026-08-27 联调发现后端可能直接透传 PayPal 原始返回）：
///
/// 1. 接口文档写的 `ClientCreatePayApiOut`（三渠道共用壳）：
///    `payPalApproveUrl` / `payPalOrderId` / `exceptionMsg`（+ 微信、支付宝那一堆）；
/// 2. **PayPal Orders v2 建单的原始返回**：`id` + `status` + `links[]`，
///    授权地址在 `links` 里 `rel == "approve"` 的那条的 `href`。
///
/// ⚠️ 两种都认是**有意为之**：后端到底映不映射这一层至今没确认，而认错的表现是
/// 「接口 200、却提示未能拉起支付」——最难查的那种。哪天口径定死了，可以把没用的那条删掉。
///
/// 微信/支付宝那些同壳字段端上一概不落地：App 两端都不走它们，搬进来只会让人以为是活的。
///
/// ⚠️ **`links` 里的 `rel == "capture"` 故意不解析、更不调用**：那是 PayPal 的**服务端** API
/// （`POST /v2/checkout/orders/{id}/capture`），要带商户 client secret 换来的 OAuth2 token。
/// 把它放到端上等于公开发布商户凭证，任何人都能拿去扣款/退款。
/// ✅ 2026-08-27 后端确认：**capture 已经做在回调里**，端上什么都不用调。
class StarPayCreation {
  const StarPayCreation({
    required this.payPalApproveUrl,
    required this.payPalOrderId,
    required this.status,
    required this.exceptionMsg,
  });

  factory StarPayCreation.fromJson(Map<String, dynamic> json) {
    return StarPayCreation(
      // 先认后端映射过的字段，空了再从 PayPal 原始返回的 links 里取
      payPalApproveUrl: StarCoinApi._firstNonEmpty([
        StarCoinApi._toText(json['payPalApproveUrl']),
        _linkHref(json['links'], 'approve'),
      ]),
      payPalOrderId: StarCoinApi._firstNonEmpty([
        StarCoinApi._toText(json['payPalOrderId']),
        StarCoinApi._toText(json['id']),
      ]),
      status: StarCoinApi._toText(json['status']),
      exceptionMsg: StarCoinApi._toText(json['exceptionMsg']),
    );
  }

  /// 从 PayPal 原始返回的 `links[]` 里取指定 `rel` 的 `href`。
  /// 结构不对（不是数组、元素不是对象、没有这个 rel）一律返回空串，交给调用方报「拉不起支付」。
  static String _linkHref(Object? links, String rel) {
    if (links is! List) {
      return '';
    }
    for (final link in links) {
      if (link is! Map) {
        continue;
      }
      if (StarCoinApi._toText(link['rel']).toLowerCase() == rel) {
        return StarCoinApi._toText(link['href']);
      }
    }
    return '';
  }

  /// PayPal 的用户授权跳转地址。空 = 这单拉不起支付。
  final String payPalApproveUrl;

  /// PayPal 侧订单 id。端上只用于日志排查（认单一律用我们平台的 [StarOrder.orderNo]）。
  final String payPalOrderId;

  /// PayPal 原始返回里的订单状态（`CREATED` → 授权前；`APPROVED` → 用户已授权、待 capture；
  /// `COMPLETED` → 已扣款）。后端映射过的出参里没有这个字段，那时是空串。
  /// **只进日志**：端上判「买到没买到」一律以服务端余额为准，不看这个。
  final String status;

  /// 渠道侧异常信息。`retCode=200` 但这个字段有值的情况后端未明确，
  /// 端上按「有 approveUrl 就走、没有就报错」判定，异常信息只进日志与错误详情。
  final String exceptionMsg;
}

/// 查单结果（`getPayQuery`）。
class StarPayQuery {
  const StarPayQuery({
    required this.payState,
    required this.payNo,
    required this.exceptionMsg,
  });

  factory StarPayQuery.fromJson(Map<String, dynamic> json) {
    return StarPayQuery(
      payState: StarCoinApi._toInt(json['payState']),
      payNo: StarCoinApi._toText(json['payNo']),
      exceptionMsg: StarCoinApi._toText(json['exceptionMsg']),
    );
  }

  /// ⚠️ **枚举后端未给**。端上沿用小程序口径：只认 `1 = 已支付`，
  /// 其余值一概按「结果确认中」措辞，不说成失败（钱可能已经付了）。
  final int payState;

  final String payNo;
  final String exceptionMsg;

  bool get paid => payState == 1;
}

/// 购买链路的失败原因。页面按这个分支措辞——「用户自己取消」和「真失败」
/// 不能都弹「购买失败」。
enum StarPurchaseError {
  /// 这一端的支付通道没接入（当前 = iOS）。
  channelUnavailable,

  /// 建单成功但没拿到 `orderNo`（后端出参异常）。
  orderNoMissing,

  /// `setCreatePay` 没回 `payPalApproveUrl`。
  approveUrlMissing,

  /// 跳不起 PayPal 授权页（没有浏览器 / 系统拒绝）。
  launchFailed,
}

class StarPurchaseException implements Exception {
  StarPurchaseException(this.reason, this.message, {this.detail});

  final StarPurchaseError reason;
  final String message;

  /// 排查用的补充信息（渠道 exceptionMsg、URL 等），**不直接展示给用户**。
  final String? detail;

  @override
  String toString() => 'StarPurchaseException($reason, $message, $detail)';
}

class StarAccount {
  const StarAccount({
    required this.balance,
    required this.totalPurchased,
    required this.totalSpent,
  });

  final int balance;
  final int totalPurchased;
  final int totalSpent;
}

/// 星币消耗规则的一行：服务类型 / 消耗 / 说明。
class StarRule {
  const StarRule({
    required this.id,
    required this.name,
    required this.cost,
    required this.remark,
  });

  final int id;
  final String name;
  final String cost;
  final String remark;
}

class StarRecord {
  const StarRecord({
    required this.time,
    required this.amount,
    required this.gift,
    required this.money,
    required this.scene,
    required this.payType,
    required this.channel,
    required this.orderState,
    required this.status,
  });

  final String time;
  final int amount;
  final int gift;
  final double money;
  final String scene;

  /// 支付方式的**数值**（swagger：1=微信支付 2=IOS内购 3=payPal），展示走
  /// `AppL10n.starPayChannel`。
  final int payType;

  /// 支付方式的后端「已转文字」。⚠️ 恒为中文（后端忽略 language），仅作兜底。
  final String channel;

  /// 订单状态的**数值**（swagger `orderState`，⚠️ **枚举后端未给**）。
  /// 因此本地化实际按 [status] 的中文原文查表，这个数值先留着，后端给出枚举后改按它判。
  final int orderState;

  /// 订单状态的后端「已转文字」，如「已完成」。⚠️ 恒为中文，展示走
  /// `AppL10n.starRecordStatus`，这里只作兜底。
  final String status;
}

class StarRecordPage {
  const StarRecordPage({
    required this.records,
    required this.pageIndex,
    required this.hasMore,
  });

  final List<StarRecord> records;
  final int pageIndex;
  final bool hasMore;
}
