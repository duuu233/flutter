import '../../network/boltfox_api.dart';

/// 星币（原「Token」，2026-08-12 全站改称；后端字段名仍是 `availableToken` 等）的数据层。
///
/// ⚠️ **App 侧只读**：购买链路（套餐下单 + 支付）目前**只有小程序端**有 ——
/// 小程序走微信虚拟支付，App 侧对应的是 Apple IAP / Android 内购，尚未接入。
/// 所以这里只有账户、套餐（展示用）、记录、消耗规则四个读接口，
/// **没有 addOrder**：没接支付就先别在后台留一串永远付不掉的待支付单。
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

  static List<Map<String, dynamic>> _rows(Object? data) {
    final Object? list = data is Map ? data['pageData'] : data;
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
                channel: _toText(item['payTypeMsg']),
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
    required this.channel,
    required this.status,
  });

  final String time;
  final int amount;
  final int gift;
  final double money;
  final String scene;
  final String channel;
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
