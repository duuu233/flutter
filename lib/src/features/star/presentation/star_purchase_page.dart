import 'package:flutter/material.dart';

import '../../../network/api_exception.dart';
import '../../../shared/l10n/app_l10n.dart';
import '../../../shared/widgets/app_dialog.dart';
import '../../../shared/widgets/figma_common.dart';
import '../star_coin_api.dart';
import '../star_purchase.dart';
import 'star_card.dart';

/// 确认购买（**安卓 PayPal**，2026-08-27 接入），对照小程序 `subpackages/token/confirm`。
///
/// 2026-08-28 起版式与小程序 confirm 页一致：**只呈现选好的那一档**（概览卡：数量 / 售价 /
/// 赠送 / 合计获得）+ 支付方式 + 贴底金额与「立即购买」。套餐的挑选放在星币管理页
/// （[StarCoinPage] 的横滑套餐条），本页不再自己拉一遍 `getGoodsList` —— 同一份列表拉两次、
/// 两处各存一份选中态，是「选了 A 进来却按 B 建单」这类错的温床。
///
/// ⚠️ **支付方式按端**（需求 8）：**安卓只画 PayPal 一项；iOS 不画支付方式**——
/// Apple 内购尚未接入（[StarPayType.supportedOnThisApp] 为 false），
/// 画一行点不动的「Apple 内购」比不画更让人困惑。iOS 上改为一句说明 + 置灰的按钮，
/// 页面本身照常可进、金额照常看得见（需求 7：页面和交互先有，支付后接）。
///
/// ⚠️ **页面状态机的关键一环是「跳出去再回来」**：跳 PayPal 之后 App 进后台，
/// 用户授权完自己切回来（后端 `return_url` 目前不是 App 的 scheme，见 [StarPurchase] 文件头）。
/// 所以本页监听 [AppLifecycleState.resumed] 自动开始确认到账，另给一颗「我已完成支付」
/// 手动兜底 —— 有些机型/浏览器回前台不发 resumed，只靠生命周期会永远停在等待态。
class StarPurchasePage extends StatefulWidget {
  const StarPurchasePage({super.key, required this.package});

  /// 星币管理页选好的那一档。本页只确认与支付，不负责挑选。
  final StarPackage package;

  @override
  State<StarPurchasePage> createState() => _StarPurchasePageState();
}

class _StarPurchasePageState extends State<StarPurchasePage>
    with WidgetsBindingObserver {
  /// 建单/拉起支付进行中（按钮转圈、不许再点）。
  bool _busy = false;

  /// 当前阶段文案（null = 不显示）。这条链路最长约 10s，中间没反馈用户会以为卡死。
  String? _stageText;

  /// 已拉起、等用户在 PayPal 侧完成授权的那一单。非 null = 页面处于「等待授权」态。
  StarPendingPayment? _pending;

  /// 购买前的余额基线，到账判据要用（读不到就是 null，见 [StarPurchase.confirm]）。
  int? _baseline;

  /// 正在轮询确认到账，挡住 resumed 与手动按钮的重入。
  bool _confirming = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      return;
    }
    // 从 PayPal 回到 App：自动开始确认到账。用户是「付完了」还是「取消了」端上分不清，
    // 一律走同一条确认链路，由**服务端余额**下结论。
    if (_pending != null && !_confirming) {
      _confirm();
    }
  }

  /// ②③④：建单 → 创建支付 → 跳 PayPal。
  Future<void> _buy() async {
    // iOS：通道没接，**不建单**（后台留一串永远付不掉的待支付单，对账时全是垃圾）。
    // 按钮此时本就是置灰的，这里只是兜底。
    if (_busy || !StarPayType.supportedOnThisApp) {
      return;
    }
    final package = widget.package;
    final l10n = AppL10n.of(context);
    setState(() {
      _busy = true;
      _stageText = l10n.starBuyStageOrder;
    });

    // 基线读失败不阻断购买（只是事后少一个增量数字），也不弹错。
    _baseline = await StarPurchase.readBaselineBalance();
    if (!mounted) {
      return;
    }

    try {
      final pending = await StarPurchase.start(
        package: package,
        payType: StarPayType.forCurrentPlatform,
        onStage: (stage) {
          if (!mounted) {
            return;
          }
          setState(() {
            _stageText = switch (stage) {
              StarPurchaseStage.order => l10n.starBuyStageOrder,
              StarPurchaseStage.pay => l10n.starBuyStagePay,
              StarPurchaseStage.approving => null,
              StarPurchaseStage.confirming => l10n.starBuyStageConfirm,
            };
          });
        },
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _pending = pending;
        _busy = false;
        _stageText = null;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _busy = false;
        _stageText = null;
      });
      AppToast.warn(context, _errorText(error, l10n));
    }
  }

  /// ⑤：以服务端余额为准确认到账。
  Future<void> _confirm() async {
    final pending = _pending;
    if (pending == null || _confirming) {
      return;
    }
    final l10n = AppL10n.of(context);
    setState(() {
      _confirming = true;
      _stageText = l10n.starBuyStageConfirm;
    });

    final result = await StarPurchase.confirm(
      pending,
      baselineBalance: _baseline,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _confirming = false;
      _stageText = null;
      _pending = null;
    });

    if (result.credited) {
      await showAppNoticeDialog(
        context,
        title: l10n.starBuySucceeded(result.gained ?? 0),
      );
      if (!mounted) {
        return;
      }
      // 带 true 回去，星币页据此重拉余额。
      Navigator.of(context).pop(true);
      return;
    }

    if (result.paidByQuery) {
      // 钱已经付了、只是还没到账：同样算「买过了」，回星币页刷新一次余额。
      await showAppNoticeDialog(
        context,
        title: l10n.starBuyPendingPaid,
      );
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(true);
      return;
    }

    // 余额没变、查单也没说已支付：可能用户取消了，也可能回调慢。**不说失败**，
    // 留在本页——真是取消的话用户多半想换一档再买，弹回上一页反而多一次跳转。
    await showAppNoticeDialog(context, title: l10n.starBuyPendingUnknown);
  }

  /// 放弃本次支付：只丢掉端上的等待态，**不动后端那张单**。
  ///
  /// 端上没有取消订单的端点，也不该有——用户在 PayPal 侧可能已经付了，
  /// 端上单方面撤单只会和真实结果打架。这张待支付单由后端按自己的超时规则收口。
  void _giveUp() {
    setState(() {
      _pending = null;
      _stageText = null;
    });
  }

  String _errorText(Object error, AppL10n l10n) {
    if (error is StarPurchaseException) {
      return switch (error.reason) {
        StarPurchaseError.channelUnavailable => l10n.starPurchaseUnavailable,
        StarPurchaseError.orderNoMissing => l10n.starBuyOrderFailed,
        StarPurchaseError.approveUrlMissing => l10n.starBuyCreatePayFailed,
        StarPurchaseError.launchFailed => l10n.starBuyLaunchFailed,
      };
    }
    // 接口层的失败优先用后端 retMsg（「库存不足」这类只有它说得清），拿不到才用兜底文案。
    if (error is ApiException && error.message.trim().isNotEmpty) {
      return error.message;
    }
    return l10n.starBuyOrderFailed;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final approving = _pending != null;
    final payable = StarPayType.supportedOnThisApp;

    return FigmaScreen(
      title: l10n.starBuyTitle,
      background: Image.asset('assets/images/bg02.jpg', fit: BoxFit.cover),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 概览卡距顶：小程序 `.summary-card` 的 margin-top 40rpx。
          const SizedBox(height: 20),
          _SummaryCard(package: widget.package, l10n: l10n),
          // 区块标题上下 = 小程序 `.token-section-title` 的 margin 56rpx 0 24rpx。
          const SizedBox(height: 28),
          // 需求 8：安卓只有 PayPal 一项；iOS 不画支付方式（Apple 内购未接），
          // 改为一句说明——画一行点不动的选项比不画更让人困惑。
          if (payable) ...[
            Text(l10n.starBuyPayChannel, style: _BuyStyles.sectionTitle),
            const SizedBox(height: 12),
            const _PayPalChannelCard(),
          ] else
            _ApplePendingNote(l10n: l10n),
          if (approving) ...[
            const SizedBox(height: 16),
            _ApprovingCard(l10n: l10n),
          ],
          const SizedBox(height: 28),
        ],
      ),
      bottom: _BottomBar(
        l10n: l10n,
        payable: payable,
        stageText: _stageText,
        busy: _busy,
        confirming: _confirming,
        approving: approving,
        onBuy: _buy,
        onConfirm: _confirm,
        onGiveUp: _giveUp,
      ),
    );
  }
}

/// 底部操作区。两种形态：未拉起支付时是「立即购买」；已跳出 PayPal 后换成
/// 「我已完成支付 / 放弃本次支付」——用户回来时该看到的是「怎么继续」，不是再买一次。
class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.l10n,
    required this.payable,
    required this.stageText,
    required this.busy,
    required this.confirming,
    required this.approving,
    required this.onBuy,
    required this.onConfirm,
    required this.onGiveUp,
  });

  final AppL10n l10n;

  /// 这一端的支付通道接没接（iOS 的 Apple 内购未接 → false，按钮置灰）。
  final bool payable;

  final String? stageText;
  final bool busy;
  final bool confirming;
  final bool approving;
  final VoidCallback onBuy;
  final VoidCallback onConfirm;
  final VoidCallback onGiveUp;

  @override
  Widget build(BuildContext context) {
    final stage = stageText;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ⚠️ **不画「应付金额」那一行**（2026-08-28 对齐小程序 confirm 页）：那边底部只有一枚
        // 「立即购买」，金额由概览卡右上角那个 42rpx 的橙色数字承担。两处都写价钱既重复，
        // 又会让人以为是两笔（套餐价 vs 应付）。
        if (stage != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              stage,
              textAlign: TextAlign.center,
              style: _BuyStyles.label,
            ),
          ),
        if (approving)
          Row(
            children: [
              Expanded(
                child: FigmaSecondaryButton(
                  label: l10n.starBuyApprovingGiveUp,
                  onPressed: confirming ? null : onGiveUp,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FigmaPrimaryButton(
                  label: l10n.starBuyApprovingDone,
                  loading: confirming,
                  onPressed: confirming ? null : onConfirm,
                ),
              ),
            ],
          )
        else
          FigmaPrimaryButton(
            label: l10n.starBuyNow,
            loading: busy,
            // iOS：通道未接，按钮置灰（原因写在上面那句 [_ApplePendingNote] 里）。
            onPressed: busy || !payable ? null : onBuy,
          ),
      ],
    );
  }
}

/// 已选套餐的概览卡，逐项对齐小程序 confirm 页的 `.summary-card`：
/// 首行「星币数 + 售价」基线对齐两端排，赠送单列一枚描边胶囊，分隔线以下是「合计获得」。
///
/// | 元素 | 小程序 | 这里 |
/// | --- | --- | --- |
/// | 卡 | 白 .86 / 描边白 .9 / 圆角 24rpx / 投影 `0 16 38 rgba(125,148,181,.1)` | [StarCard] 同值 |
/// | 内边距 | 34 32 30(rpx) | 17 / 16 / 15 |
/// | 星币数 | #2a2d32 42rpx w700 + 单位 #7c828a 30rpx | 21 / 15 |
/// | 售价 | #f2621f 42rpx w700 | 21 |
/// | 赠送 | 高 46rpx、上 20rpx、左右 20rpx、描边 rgba(255,106,30,.45)、底 .08 | 23 / 10 / 10 |
/// | 分隔线 | `margin: 28 0 26`(rpx)、rgba(207,214,224,.7) | 14 / 13 |
/// | 合计 | 标签 #9aa0a8 28rpx、数字 #2a2d32 36rpx w700、单位 #7c828a 28rpx | 14 / 18 / 14 |
///
/// ⚠️ **不画单价**：小程序这张卡上没有这一行（单价只出现在星币管理页的套餐卡上）。
class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.package, required this.l10n});

  final StarPackage package;
  final AppL10n l10n;

  @override
  Widget build(BuildContext context) {
    return StarCard(
      padding: const EdgeInsets.fromLTRB(16, 17, 16, 15),
      fill: 0.86,
      border: 0.90,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: Text(
                  '${package.tokens}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF2A2D32),
                    fontSize: 21,
                    fontWeight: FontWeight.w700,
                    height: 1,
                  ),
                ),
              ),
              const SizedBox(width: 5),
              Text(
                l10n.aiTokenUnit,
                style: const TextStyle(
                  color: Color(0xFF7C828A),
                  fontSize: 15,
                  height: 1,
                ),
              ),
              const Spacer(),
              const SizedBox(width: 12),
              Text(
                '$kStarCurrencySymbol${package.price.toStringAsFixed(2)}',
                style: const TextStyle(
                  color: Color(0xFFF2621F),
                  fontSize: 21,
                  fontWeight: FontWeight.w700,
                  height: 1,
                ),
              ),
            ],
          ),
          if (package.gift > 0) ...[
            const SizedBox(height: 10),
            // 宽度按文字撑开（Align 收窄），不铺满整行 —— 小程序 `.summary-gift` 是 inline-flex。
            Align(
              alignment: Alignment.centerLeft,
              child: _GiftBadge(text: l10n.starPackageGift(package.gift)),
            ),
          ],
          const Padding(
            padding: EdgeInsets.only(top: 14, bottom: 13),
            child: Divider(height: 1, color: Color(0xB3CFD6E0)),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                l10n.starBuyTotalGain,
                style: const TextStyle(
                  color: Color(0xFF9AA0A8),
                  fontSize: 14,
                  height: 1,
                ),
              ),
              const Spacer(),
              Text(
                // 合计 = 基础 + 赠送，见 StarPackage.totalTokens
                '${package.totalTokens}',
                style: const TextStyle(
                  color: Color(0xFF2A2D32),
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  height: 1,
                ),
              ),
              const SizedBox(width: 5),
              Text(
                l10n.aiTokenUnit,
                style: const TextStyle(
                  color: Color(0xFF7C828A),
                  fontSize: 14,
                  height: 1,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// iOS 上顶替「支付方式」那一块的说明（需求 8：苹果不显示支付方式）。
class _ApplePendingNote extends StatelessWidget {
  const _ApplePendingNote({required this.l10n});

  final AppL10n l10n;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Text(
        l10n.starBuyApplePending,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Color(0xFF888F99),
          fontSize: 12,
          height: 1.5,
        ),
      ),
    );
  }
}

/// 赠送胶囊（小程序 `.summary-gift`）：高 46rpx、左右 20rpx、
/// 橙色描边 `rgba(255,106,30,.45)` + 浅橙底 `rgba(255,106,30,.08)`、24rpx 字。
class _GiftBadge extends StatelessWidget {
  const _GiftBadge({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 23,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: const Color(0x14FF6A1E),
        border: Border.all(color: const Color(0x73FF6A1E)),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        maxLines: 1,
        style: const TextStyle(
          color: Color(0xFFF2621F),
          fontSize: 12,
          height: 1,
        ),
      ),
    );
  }
}

/// 支付方式一行（小程序 `.pay-row`）：图标 + 名称 + 右侧箭头。
///
/// 安卓端只有 PayPal 这一项（产品口径：小程序=微信支付、安卓=PayPal、iOS=Apple 内购），
/// 只有一项也照画一行 —— 用户要看得见「这笔钱从哪走」，且将来加渠道时这里是现成的位置。
/// 唯一的一项自然处于选中态，按 `.pay-row--active` 画橙色描边 + 橙色柔光。
///
/// 几何逐项对齐：行高 128rpx=64、左右内边距 28rpx=14、图标 64rpx=32（圆角 14rpx=7）、
/// 名称左边距 26rpx=13 / 32rpx=16 / w500、右侧箭头 24rpx=12。
///
/// 🔶 图标与小程序不同：那边用的是 `pay-wechat.png` 那类切图，PayPal 没有对应素材
///（`pay-wechat.png` 已在 2026-08-27 清理无引用素材时删掉），这里用同尺寸的圆角色块 + 内置图标顶上。
class _PayPalChannelCard extends StatelessWidget {
  const _PayPalChannelCard();

  @override
  Widget build(BuildContext context) {
    return StarCard(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      fill: 0.80,
      shadow: 0.12,
      borderColor: const Color(0x8CFF6A1E),
      shadowColor: const Color(0xFFFF6A1E),
      child: SizedBox(
        height: 62, // 64 - 上下各 1 的描边
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xFF0070BA),
                borderRadius: BorderRadius.circular(7),
              ),
              child: const Icon(
                Icons.account_balance_wallet_rounded,
                size: 19,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 13),
            const Expanded(
              child: Text(
                // 渠道名是品牌名，四语种都写 PayPal，不进 l10n。
                'PayPal',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Color(0xFF2A2D32),
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  height: 1,
                ),
              ),
            ),
            const Text(
              '\u203A',
              style: TextStyle(
                color: Color(0xFF777E88),
                fontSize: 24,
                fontWeight: FontWeight.w300,
                height: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 已跳出 PayPal 后的等待说明。
class _ApprovingCard extends StatelessWidget {
  const _ApprovingCard({required this.l10n});

  final AppL10n l10n;

  @override
  Widget build(BuildContext context) {
    return FigmaGlassCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.starBuyApprovingTitle, style: _BuyStyles.cardTitle),
          const SizedBox(height: 8),
          Text(
            l10n.starBuyApprovingDesc,
            style: const TextStyle(
              color: Color(0xFF6F7782),
              fontSize: 12,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _BuyStyles {
  const _BuyStyles._();

  static const TextStyle sectionTitle = TextStyle(
    color: Color(0xFF2A2B2B),
    fontSize: 16,
    fontWeight: FontWeight.w600,
    height: 1,
  );

  static const TextStyle cardTitle = TextStyle(
    color: Color(0xFF2A2D32),
    fontSize: 16,
    fontWeight: FontWeight.w600,
    height: 1,
  );

  static const TextStyle label = TextStyle(
    color: Color(0xFF9AA0A8),
    fontSize: 13,
    height: 1,
  );
}
