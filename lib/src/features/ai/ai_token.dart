import '../../network/api_exception.dart';
import '../../network/boltfox_api.dart';

/// AI 模块的**星币**（原文案「Token」，2026-08-12 全站改称星币；后端字段仍叫
/// `availableToken`）余额，以及「能不能发起一次对话」的闸。
///
/// ## 2026-08-12：由本地演示逻辑切到真实账户（同步小程序 08-11 / 08-12 两轮）
///
/// 此前这里是一套 `SharedPreferences` 里的假余额（恒 100、每次对话本地扣 1、`limitEnabled=false`），
/// AI 侧显示的数字与用户真实账户毫无关系——支付体系上线后这就是明摆着的错数。
///
/// 现在：
/// - **读**：`GET /Client/Order/getUserAccount` 的 `availableToken`（String，端上转数字）。
///   取不到返回 [unknownBalance]（null），页面显示 `--`，**绝不用 0 兜底**——
///   那会让有余额的用户看到「0 星币」而不敢用；余额真的是 0 就显示 0。
/// - **写**：没有。swagger 的 `/Client/Order` 下没有「消费星币」的端点，消费记录能从
///   `getUserAccountTrade(inOutType=2)` 查到 —— 扣费发生在服务端（AI 网关侧），
///   端上再自己减一次就是双重记账。原来的 `spend()` 已删除。
/// - **拦**：[canDialogue]，由服务端裁决（见其文档）。原来那对 `limitEnabled` / 余额比大小
///   的假闸一并删除 —— 端上根本不知道一轮对话扣多少星币，留着两个口径不一致的闸，
///   出问题时「到底谁拦的」无从查起。
class AiToken {
  const AiToken._();

  /// 余额未知（接口挂了 / 未登录）。页面渲染成 `--`。
  static const int? unknownBalance = null;

  /// 登录 / `getUserInfo` 带回的余额（2026-08-11 同步小程序：这两个接口新增了
  /// `availableToken` 出参）。**进页面即有、无需等网络**，页面先拿它渲染，再异步刷权威值。
  /// null＝这次响应没带这个字段或未登录，页面显示 `--`（绝不用 0 兜底）。
  static int? _cachedBalance;

  /// 由 `PhotoFrameState._applyUserInfo` 在登录/刷新用户信息时写入。
  static void cacheBalance(int? balance) => _cachedBalance = balance;

  /// 同步可得的余额（可能过期一点点）。用于「先显示、再刷新」的第一帧。
  static int? cachedBalance() => _cachedBalance;

  static int? _toBalance(Object? value) {
    if (value == null) {
      return unknownBalance;
    }
    final text = '$value'.trim();
    if (text.isEmpty) {
      return unknownBalance;
    }
    final number = num.tryParse(text);
    if (number == null) {
      return unknownBalance;
    }
    return number < 0 ? 0 : number.toInt();
  }

  /// 权威余额。失败返回 [unknownBalance]，**不弹错误**——余额只是页面上的一个数字，
  /// 为它弹红字会盖住 AI 的主流程。
  ///
  /// 拉到的值同时回填 [cachedBalance]，下次进页面第一帧就有数。
  static Future<int?> fetchBalance() async {
    try {
      final data = await BoltFoxApi.getUserAccount();
      if (data is Map) {
        final balance = _toBalance(data['availableToken']);
        if (balance != unknownBalance) {
          _cachedBalance = balance;
        }
        return balance;
      }
      return unknownBalance;
    } catch (_) {
      return unknownBalance;
    }
  }

  /// 页面展示：未知显示 `--`，其余显示数字本身（0 就显示 0，那是真实状态）。
  static String displayBalance(int? balance) =>
      balance == null ? '--' : '$balance';

  /// 能否发起一次 AI 对话 —— **唯一的闸**，由服务端裁决
  /// （`GET /Client/Order/chkAiDialogue`，2026-08-12 新增）。每次发送前调一次：
  /// 够不够扣、有没有免费额度、账号有没有被停，全在服务端那一个判断里。
  ///
  /// 返回 [AiDialogueVerdict]：`allowed=false` 时 [AiDialogueVerdict.requiredStars] 是后端给的
  /// 最低余额（从 `retMsg` 里抠出来，抠不到为 0），[AiDialogueVerdict.message] 是后端原话，
  /// 供页面在抠不到数字时兜底措辞。
  ///
  /// ⚠️ **只有明确的 403「余额不足」才拦**；校验接口自己出问题（网络抖动、后端 5xx）一律放行：
  /// 读不到判据就把 AI 锁死是更糟的失败模式 —— 真不够的话紧接着那次 `/chat` 服务端照样会拒，
  /// 用户看到的是真实原因，而不是被端上一次网络故障扣上一顶「星币不足」的帽子。
  static Future<AiDialogueVerdict> canDialogue() async {
    try {
      final data = await BoltFoxApi.chkAiDialogue();
      // 200 即放行。**不要求 retData 严格等于 true**：拒绝是由 403 表达的，
      // 真到了这一支还去纠结 retData 是 true 还是 null，只会在后端某天不回这个字段时
      // 把所有人都拦在门外——那比放过去糟得多（/chat 侧服务端还会再拒一次）。
      final blocked = data == false || '$data'.toLowerCase() == 'false';
      return AiDialogueVerdict(allowed: !blocked);
    } on ApiException catch (error) {
      // 按字符串比：`ApiException.code` 是 Object，正常情况下是 int 403，
      // 但后端若把 retCode 回成字符串，api_client 会退化成 -1 —— 那时这里也认不出来，
      // 会走下面的「放行」，与其它接口异常同一口径（/chat 侧服务端还会再拒一次）。
      if ('${error.code}' != '$_forbiddenCode') {
        // 不是「不允许」，是接口本身出问题了 → 放行，由 /chat 侧服务端兜底
        return const AiDialogueVerdict(allowed: true);
      }
      return AiDialogueVerdict(
        allowed: false,
        requiredStars: _parseRequired(error.message),
        message: error.message,
      );
    } catch (_) {
      return const AiDialogueVerdict(allowed: true);
    }
  }

  /// chkAiDialogue 说「不够」时用的业务码（见 [canDialogue]）。
  static const int _forbiddenCode = 403;

  /// 从 `retMsg` 里抠出「最低余额」的数字（"…需要最低余额：30.0 token" → 30）。
  /// 抠不到返回 0，页面据此退回不带数字的措辞——绝不瞎猜一个数写进提示里。
  static double _parseRequired(String message) {
    final matched = RegExp(r'([0-9]+(?:\.[0-9]+)?)').firstMatch(message);
    if (matched == null) {
      return 0;
    }
    final value = double.tryParse(matched.group(1) ?? '') ?? 0;
    return value > 0 ? value : 0;
  }
}

/// [AiToken.canDialogue] 的裁决结果。
class AiDialogueVerdict {
  const AiDialogueVerdict({
    required this.allowed,
    this.requiredStars = 0,
    this.message = '',
  });

  final bool allowed;

  /// 后端给的「发起一次对话至少需要多少星币」，0 = 没抠到（页面退回不带数字的措辞）。
  /// ⚠️ 名字带 Stars 后缀是为了避开 Dart 的 `required` 上下文关键字 —— 叫 `required`
  /// 会和构造函数里的修饰符撞在一起，读起来也像是「这个字段是必填的」。
  final double requiredStars;

  /// 后端原话（含「token」等内部叫法），仅在抠不到数字时兜底展示，展示前要把 token 换成星币。
  final String message;

  /// 星币是整数计价：`30.0` 照抄进提示里只会让人以为还有小数位。
  String get requiredText {
    if (requiredStars <= 0) {
      return '';
    }
    if (requiredStars == requiredStars.roundToDouble()) {
      return '${requiredStars.toInt()}';
    }
    return requiredStars
        .toStringAsFixed(2)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }
}
