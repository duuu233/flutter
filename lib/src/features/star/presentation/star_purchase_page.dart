import 'package:flutter/material.dart';

import '../../../network/api_exception.dart';
import '../../../shared/l10n/app_l10n.dart';
import '../../../shared/widgets/app_dialog.dart';
import '../../../shared/widgets/app_widgets.dart';
import '../../../shared/widgets/figma_common.dart';
import '../star_coin_api.dart';
import '../star_purchase.dart';

/// 确认购买（**安卓 PayPal**，2026-08-27 接入），对照小程序 `subpackages/token/confirm`。
///
/// 与小程序的差别只在渠道：小程序是「微信虚拟支付」一项（PayPal 选项在它那边是隐藏的），
/// 这里是 PayPal 一项。iOS 走 Apple 内购、尚未接入，[StarPayType.supportedOnThisApp]
/// 为 false，星币页不会给入口，所以正常路径进不到本页。
///
/// ⚠️ **页面状态机的关键一环是「跳出去再回来」**：跳 PayPal 之后 App 进后台，
/// 用户授权完自己切回来（后端 `return_url` 目前不是 App 的 scheme，见 [StarPurchase] 文件头）。
/// 所以本页监听 [AppLifecycleState.resumed] 自动开始确认到账，另给一颗「我已完成支付」
/// 手动兜底 —— 有些机型/浏览器回前台不发 resumed，只靠生命周期会永远停在等待态。
class StarPurchasePage extends StatefulWidget {
  const StarPurchasePage({super.key});

  @override
  State<StarPurchasePage> createState() => _StarPurchasePageState();
}

/// 售价的货币符号。
///
/// ⚠️ **待后端确认**：套餐的 `amount` 现在是小程序那套人民币价，而 PayPal 侧要 `currency_code`。
/// 若后端对 PayPal 单独换算成美元（或另给一档美元价），这里连同 [StarPackage.price] 的口径
/// 一起改，别只改符号——那会变成「写着 $、扣的是 ¥」。
const String _kCurrencySymbol = '¥';

class _StarPurchasePageState extends State<StarPurchasePage>
    with WidgetsBindingObserver {
  List<StarPackage> _packages = const [];
  StarPackage? _selected;
  bool _loading = true;
  bool _loadFailed = false;

  /// 建单/拉起支付进行中（按钮转圈、不许再点、不许换套餐）。
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
    _load();
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

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadFailed = false;
    });
    try {
      final packages = await StarCoinApi.fetchPackages();
      if (!mounted) {
        return;
      }
      setState(() {
        _packages = packages;
        // 默认选中第一档（后端按档位排好序下发），空列表则不选。
        _selected = packages.isNotEmpty ? packages.first : null;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _packages = const [];
        _selected = null;
        _loading = false;
        _loadFailed = true;
      });
    }
  }

  /// ②③④：建单 → 创建支付 → 跳 PayPal。
  Future<void> _buy() async {
    final package = _selected;
    if (package == null || _busy) {
      return;
    }
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
    final selected = _selected;
    final approving = _pending != null;

    return FigmaScreen(
      title: l10n.starBuyTitle,
      background: Image.asset('assets/images/bg02.jpg', fit: BoxFit.cover),
      body: _loading
          ? const SizedBox(height: 320, child: PageLoading())
          : _loadFailed
          ? SizedBox(height: 320, child: PageLoadError(onRetry: _load))
          : _packages.isEmpty
          ? SizedBox(
              height: 320,
              child: Center(
                child: Text(l10n.starBuyEmpty, style: _BuyStyles.label),
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 8),
                Text(l10n.starBuyChoosePackage, style: _BuyStyles.sectionTitle),
                const SizedBox(height: 10),
                for (final package in _packages) ...[
                  _PackageCard(
                    package: package,
                    selected: identical(package, selected),
                    // 建单/等待授权期间不许换套餐：单已经按这一档建出去了。
                    onTap: _busy || approving
                        ? null
                        : () => setState(() => _selected = package),
                    l10n: l10n,
                  ),
                  const SizedBox(height: 10),
                ],
                const SizedBox(height: 10),
                Text(l10n.starBuyPayChannel, style: _BuyStyles.sectionTitle),
                const SizedBox(height: 10),
                const _PayPalChannelCard(),
                if (approving) ...[
                  const SizedBox(height: 16),
                  _ApprovingCard(l10n: l10n),
                ],
                const SizedBox(height: 28),
              ],
            ),
      bottom: _loading || _loadFailed || _packages.isEmpty
          ? null
          : _BottomBar(
              l10n: l10n,
              package: selected,
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
    required this.package,
    required this.stageText,
    required this.busy,
    required this.confirming,
    required this.approving,
    required this.onBuy,
    required this.onConfirm,
    required this.onGiveUp,
  });

  final AppL10n l10n;
  final StarPackage? package;
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
        if (!approving && package != null) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                Text(l10n.starBuyAmountDue, style: _BuyStyles.label),
                const Spacer(),
                Text(
                  '$_kCurrencySymbol${package!.price.toStringAsFixed(2)}',
                  style: const TextStyle(
                    color: Color(0xFFF2621F),
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    height: 1,
                  ),
                ),
              ],
            ),
          ),
        ],
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
            onPressed: busy || package == null ? null : onBuy,
          ),
      ],
    );
  }
}

class _PackageCard extends StatelessWidget {
  const _PackageCard({
    required this.package,
    required this.selected,
    required this.onTap,
    required this.l10n,
  });

  final StarPackage package;
  final bool selected;
  final VoidCallback? onTap;
  final AppL10n l10n;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      // 选中环画在**前景**：卡片自带白描边 + 半透明玻璃底，画在背景里只会被压得只剩一丝。
      child: DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          // 与 FigmaGlassCard 默认圆角一致（14），两条边才叠得齐
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? const Color(0xFFFF7A2F) : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: FigmaGlassCard(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          '${package.tokens}',
                          style: const TextStyle(
                            color: Color(0xFF2A2D32),
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            height: 1,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(l10n.aiTokenUnit, style: _BuyStyles.label),
                        if (package.gift > 0) ...[
                          const SizedBox(width: 8),
                          _GiftBadge(text: l10n.starBuyGift(package.gift)),
                        ],
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      // 单价按含赠送总数算，见 StarPackage.unitPrice
                      l10n.starBuyUnitPrice(package.unitPrice, _kCurrencySymbol),
                      style: _BuyStyles.label,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '$_kCurrencySymbol${package.price.toStringAsFixed(2)}',
                style: TextStyle(
                  color: selected
                      ? const Color(0xFFF2621F)
                      : const Color(0xFF2A2D32),
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  height: 1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GiftBadge extends StatelessWidget {
  const _GiftBadge({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0x1AFF7A2F),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Color(0xFFF2621F),
          fontSize: 11,
          fontWeight: FontWeight.w600,
          height: 1,
        ),
      ),
    );
  }
}

/// 支付方式：安卓端只有 PayPal 一项（产品口径：小程序=微信支付、安卓=PayPal、iOS=Apple 内购）。
/// 只有一项也照画一行 —— 用户要看得见「这笔钱从哪走」，且将来加渠道时这里是现成的位置。
class _PayPalChannelCard extends StatelessWidget {
  const _PayPalChannelCard();

  @override
  Widget build(BuildContext context) {
    return FigmaGlassCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Row(
        children: [
          const Icon(Icons.account_balance_wallet_rounded,
              size: 22, color: Color(0xFF0070BA)),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              // 渠道名是品牌名，四语种都写 PayPal，不进 l10n。
              'PayPal',
              style: TextStyle(
                color: Color(0xFF2A2D32),
                fontSize: 15,
                fontWeight: FontWeight.w600,
                height: 1,
              ),
            ),
          ),
          const Icon(Icons.check_circle_rounded,
              size: 20, color: Color(0xFFFF7A2F)),
        ],
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
