import 'package:flutter/material.dart';

import '../../../routes/app_routes.dart';
import '../../../shared/l10n/app_l10n.dart';
import '../../../shared/widgets/app_widgets.dart';
import '../../../shared/widgets/figma_common.dart';
import '../star_coin_api.dart';
import 'star_card.dart';
import 'star_coin_records_page.dart';
import 'star_purchase_page.dart';

/// 星币管理，对照微信小程序 `photo-album/subpackages/token/index`
/// （2026-08-12 App 侧补齐；小程序那边叫「星币管理」，原「Token 管理」）。
///
/// ## 2026-08-28：补上「套餐购买」区（本页原来根本不显示可买的 SKU）
/// 版式照小程序 `index.wxml` 逐块对齐：概览卡 → **套餐购买（横滑卡片，可选中）** →
/// 购买&消费记录入口 → 星币消耗规则 → 贴底「立即购买」。选中哪一档由本页保管，
/// 点「立即购买」把它带进 [StarPurchasePage] 确认（确认页因此不再自己拉一遍套餐列表）。
///
/// ⚠️ **支付渠道按端分工**（产品口径 2026-08-27）：小程序=微信支付、**安卓=PayPal**、
/// iOS=Apple 内购。**套餐区与「立即购买」两端都给**——能看到买什么、点进确认页看清金额，
/// 这些都不需要通道；付不付得了是确认页那一步的事（iOS 在确认页不画支付方式、
/// 按钮置灰并说明原因，见 [StarPurchasePage]）。这样 iOS 用户至少看得到价目表，
/// 而不是一句「去小程序买」把整块内容都藏掉。
class StarCoinPage extends StatefulWidget {
  const StarCoinPage({super.key});

  @override
  State<StarCoinPage> createState() => _StarCoinPageState();
}

class _StarCoinPageState extends State<StarCoinPage> {
  StarAccount? _account;
  List<StarRule> _rules = const [];

  /// 可购买的套餐（`getGoodsList`）。与规则表同款**静默失败**：拉不到就整块不渲染，
  /// 不该把「看余额」这件正事挡在错误页后面。
  List<StarPackage> _packages = const [];

  /// 当前选中的那一档，**按列表下标记**。后端按档位排好序下发，默认第一档，
  /// 与小程序 `index.js` 一致。
  ///
  /// ⚠️ **不能按 `goodsId` 记**（2026-09-01 改）：`goodsId` **允许为 0**，也不保证互不相同；
  /// 一旦有两档取值相同（比如都是 0），「按 id 找回选中项」会恒命中**第一档** ——
  /// 用户点第二档，页面高亮跟着走了，带进确认页和 `addOrder` 的却还是第一档的数据。
  /// 那是一个不报错、只在对账时才发现的错，所以选中态一律按下标。
  int _selectedIndex = 0;

  bool _loading = true;
  bool _loadFailed = false;

  StarPackage? get _selected {
    if (_packages.isEmpty) {
      return null;
    }
    // 下标夹回有效范围：重拉后列表可能变短（后端下架了某一档）。
    final index = _selectedIndex.clamp(0, _packages.length - 1);
    return _packages[index];
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// 下拉刷新：重拉余额（星币数）、套餐与规则。
  ///
  /// 本页原来**只在进页时拉一次**，弱网那次拉失败、或在别处消耗了星币再切回来，
  /// 都只能退出去重进才能看到新数字。下拉是这一页最顺手的手动刷新入口。
  ///
  /// ⚠️ 走 `silent: true`：下拉自带转圈，再翻一次整页 loading 是两个加载态叠着闪，
  /// 而且会把列表整块换成占位图、下拉手势当场断掉（沿用官方图库那页的口径）。
  Future<void> _refresh() => _load(silent: true);

  /// [silent] = 不翻整页 loading（下拉刷新用）。
  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _loadFailed = false;
      });
    }
    StarAccount? account;
    var failed = false;
    try {
      account = await StarCoinApi.fetchAccount();
    } catch (_) {
      failed = true;
    }
    // 规则表与套餐表**静默失败**：都是说明性/可选内容，拉不到就整块不渲染，
    // 不该把「看余额」这件正事也一起挡在错误页后面。
    // 两个接口并发拉：串行的话本页要连等三次往返才画得出来。
    List<StarRule> rules = const [];
    List<StarPackage> packages = const [];
    // ⚠️ `then<void>` 的 `<void>` 不能省：不写的话 T 会被推成 List<...>，
    // 而下面 catchError 的处理器返回的是 void —— 真出错时 Dart 会在运行时按
    // `FutureOr<T>` 校验返回值并抛 TypeError（编译期不报，因为 onError 的形参类型是 Function）。
    await Future.wait<void>([
      StarCoinApi.fetchRules()
          .then<void>((value) => rules = value)
          .catchError((Object _) => rules = const []),
      StarCoinApi.fetchPackages()
          .then<void>((value) => packages = value)
          .catchError((Object _) => packages = const []),
    ]);
    if (!mounted) {
      return;
    }
    setState(() {
      if (account != null) {
        _account = account;
      }
      _rules = rules;
      _packages = packages;
      // 选中项跟着新列表走：下标仍在范围内就保持不动（买完回来重拉不该把选择弹掉），
      // 越界（后端下架了某一档）才落回第一档。
      if (_selectedIndex >= packages.length) {
        _selectedIndex = 0;
      }
      _loading = false;
      // 账户读失败且此前没有过成功值才算整页失败（弱网回到本页不该把余额清零）
      _loadFailed = failed && _account == null;
    });
  }

  /// 进确认购买页。买成功（含「已付款、稍后到账」）会带 true 回来 → 重拉余额。
  Future<void> _openPurchase() async {
    final package = _selected;
    if (package == null) {
      return; // 按钮此时本就是置灰的，这里只是兜底
    }
    final bought = await Navigator.of(context).push<bool>(
      AppPageRoute<bool>(builder: (_) => StarPurchasePage(package: package)),
    );
    if (bought == true && mounted) {
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    return FigmaScreen(
      title: l10n.starCoinTitle,
      background: Image.asset('assets/images/bg02.jpg', fit: BoxFit.cover),
      // 下拉刷新余额/套餐/规则。整页 loading、加载失败两态也照样能下拉——
      // 失败态那颗「重试」按钮之外多一条手势入口，不吃亏。
      onRefresh: _refresh,
      body: _loading
          ? const SizedBox(height: 320, child: PageLoading())
          : _loadFailed
          ? SizedBox(height: 320, child: PageLoadError(onRetry: _load))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 概览卡距顶：小程序 `.account-card` 的 margin-top 40rpx。
                const SizedBox(height: 20),
                _AccountCard(account: _account, l10n: l10n),
                // 套餐区（小程序 index.wxml 的「套餐购买」）。标题**恒在**：
                // 后端一档都没下发/接口挂了的时候，与其整块消失（用户反馈的
                // 「看不到能买什么」正是这个观感），不如如实写一句「暂无可购买的套餐」。
                // 区块标题上下间距 = 小程序 `.token-section-title` 的 margin 56rpx 0 24rpx。
                const SizedBox(height: 28),
                Text(l10n.starPackagesTitle, style: _StarStyles.sectionTitle),
                const SizedBox(height: 12),
                if (_packages.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    child: Text(
                      l10n.starBuyEmpty,
                      textAlign: TextAlign.center,
                      style: _StarStyles.label,
                    ),
                  )
                else
                  _PackageStrip(
                    packages: _packages,
                    selectedIndex: _selectedIndex,
                    onSelect: (index) =>
                        setState(() => _selectedIndex = index),
                    l10n: l10n,
                  ),
                const SizedBox(height: 16),
                _RecordsEntry(
                  onTap: () => Navigator.of(context).push(
                    AppPageRoute<void>(
                      builder: (_) => const StarCoinRecordsPage(),
                    ),
                  ),
                ),
                if (_rules.isNotEmpty) ...[
                  const SizedBox(height: 28),
                  Text(l10n.starRulesTitle, style: _StarStyles.sectionTitle),
                  const SizedBox(height: 12),
                  _RulesCard(rules: _rules, l10n: l10n),
                ],
                const SizedBox(height: 28),
              ],
            ),
      // 贴底「立即购买」（小程序的 `.cta-button`）。整页 loading/失败、或后端一档
      // 套餐都没下发时不画：没有可买的东西就别摆按钮。
      bottom: _loading || _loadFailed || _packages.isEmpty
          ? null
          : Padding(
              // 贴底留白补到 30（小程序 `.cta-button` 的 `bottom: 60rpx + safe`）；
              // [FigmaScreen] 的 bottom 槽只给 12，是全站通用值，不为这一页改公共组件。
              padding: const EdgeInsets.only(bottom: 18),
              child: FigmaPrimaryButton(
                label: l10n.starBuyNow,
                onPressed: _selected == null ? null : _openPurchase,
              ),
            ),
    );
  }
}

/// 横滑套餐条（小程序 `.package-scroll` + `.package-row`）。
///
/// 横滑而不是纵向铺开：档位通常 4~6 个，纵向铺完这一屏就只剩套餐了，
/// 记录入口与消耗规则全被顶到折叠线以下。
///
/// 横向留白沿用页面正文的 24（[FigmaScreen.bodyPadding]），首末张与上下各区块左右对齐。
class _PackageStrip extends StatelessWidget {
  const _PackageStrip({
    required this.packages,
    required this.selectedIndex,
    required this.onSelect,
    required this.l10n,
  });

  final List<StarPackage> packages;

  /// 选中项按**下标**，不按 `goodsId`——理由见 [_StarCoinPageState._selectedIndex]。
  final int selectedIndex;

  /// 回传的是**下标**。
  final ValueChanged<int> onSelect;
  final AppL10n l10n;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      // 卡片 124 + 上下留白（阴影与选中角标不能被裁掉）。
      height: 140,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: packages.length,
        separatorBuilder: (context, index) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final package = packages[index];
          return _PackageCard(
            package: package,
            selected: index == selectedIndex,
            onTap: () => onSelect(index),
            l10n: l10n,
          );
        },
      ),
    );
  }
}

/// 单张套餐卡（小程序 `.package-card`，200×248rpx = 100×124）。
///
/// ⚠️ 角标那一行**永远占位**（[_giftSlotHeight]）：选中态的角标贴在卡片右上角、
/// 脱离了正常流，没有这个等高占位，选中那张卡的「星币数」及以下会整体上移半格，
/// 与相邻档位错开一行（小程序踩过同一个坑，见 `.package-gift-slot` 的注释）。
class _PackageCard extends StatelessWidget {
  const _PackageCard({
    required this.package,
    required this.selected,
    required this.onTap,
    required this.l10n,
  });

  final StarPackage package;
  final bool selected;
  final VoidCallback onTap;
  final AppL10n l10n;

  static const double _radius = 10;
  static const double _giftSlotHeight = 16;

  @override
  Widget build(BuildContext context) {
    final accent = selected ? const Color(0xFFF2621F) : const Color(0xFF2A2D32);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        width: 100,
        height: 124,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: selected
                      ? Colors.white
                      : Colors.white.withValues(alpha: 0.72),
                  borderRadius: BorderRadius.circular(_radius),
                  border: Border.all(
                    color: selected
                        ? const Color(0xFFFF6A1E)
                        : Colors.transparent,
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: selected
                          ? const Color(0xFFFF6A1E).withValues(alpha: 0.16)
                          : const Color(0xFF7D94B5).withValues(alpha: 0.08),
                      blurRadius: selected ? 17 : 15,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 11),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 角标占位：未选中时在卡内右对齐画橙色小字，选中时这里留空、
                  // 角标改由下面的 Positioned 贴到卡片右上角。
                  SizedBox(
                    height: _giftSlotHeight,
                    width: double.infinity,
                    child: package.gift > 0 && !selected
                        ? Align(
                            alignment: Alignment.centerRight,
                            child: Text(
                              l10n.starPackageGift(package.gift),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xFFF2621F),
                                fontSize: 11,
                                height: 1,
                              ),
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(height: 9),
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
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            height: 1,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        l10n.aiTokenUnit,
                        style: const TextStyle(
                          color: Color(0xFF7C828A),
                          fontSize: 13,
                          height: 1,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        // 后端按商品下发的币种符号（见 StarPackage.currencySymbol），不写死
                        package.currencySymbol,
                        style: TextStyle(
                          color: accent,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          height: 1,
                        ),
                      ),
                      const SizedBox(width: 3),
                      Flexible(
                        child: Text(
                          package.price.toStringAsFixed(2),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: accent,
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            height: 1,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    // 单价按含赠送总数算，见 StarPackage.unitPrice
                    l10n.starBuyUnitPrice(
                      package.unitPrice,
                      package.currencySymbol,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF9AA0A8),
                      fontSize: 11,
                      height: 1,
                    ),
                  ),
                ],
              ),
            ),
            if (package.gift > 0 && selected)
              Positioned(
                top: 0,
                right: 0,
                child: Container(
                  height: _giftSlotHeight,
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: const BoxDecoration(
                    color: Color(0xFFFF6A1E),
                    borderRadius: BorderRadius.only(
                      topRight: Radius.circular(_radius),
                      bottomLeft: Radius.circular(_radius),
                    ),
                  ),
                  child: Text(
                    l10n.starPackageGift(package.gift),
                    maxLines: 1,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      height: 1,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 概览卡（小程序 `.account-card`）。
///
/// ⚠️ **2026-08-28 重画**：原来是一张全站通用的白玻璃卡（`FigmaGlassCard`），
/// 与小程序差得很明显——小程序是**橙色渐变外卡 + 半透明白内卡**两层，
/// 余额数字是 76rpx 的品牌橙、金币插画是 168×120 的横图。改成逐项对齐：
///
/// | 元素 | 小程序 | 这里 |
/// | --- | --- | --- |
/// | 外卡 | `linear-gradient(115deg,#f9ecdf,#ffceaa)` / 圆角 28rpx / 内边距 28rpx | 同（÷2） |
/// | 标题 | 36rpx w600，`margin: 4 0 24 8`(rpx) | 18 / (2,0,12,4) |
/// | 内卡 | `rgba(255,255,255,.72)` / 圆角 22rpx / 内边距 32 30 28(rpx) | 同（÷2） |
/// | 余额 | #f2621f 76rpx w700 + 单位 #6b7075 32rpx | 38 / 16 |
/// | 金币 | 168×120rpx，不许被压扁 | 84×60 + `flex-shrink:0` 等价写法 |
/// | 分隔线/竖线 | `rgba(226,202,180,.6/.75)` | 同 |
/// | 两列数字 | 40rpx w700，累计购买橙、已消耗 #4a4a4f | 20 / 同色 |
///
/// 渐变底不引设计稿那张 `Surface.png`：小程序那边实测四角就是这两个色值，
/// CSS/Flutter 画出来一模一样，还免掉 57KB 进包与拉伸重采样（原注释同此结论）。
class _AccountCard extends StatelessWidget {
  const _AccountCard({required this.account, required this.l10n});

  final StarAccount? account;
  final AppL10n l10n;

  @override
  Widget build(BuildContext context) {
    final balance = account?.balance ?? 0;
    final purchased = account?.totalPurchased ?? 0;
    final spent = account?.totalSpent ?? 0;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        // 115deg：CSS 的角度从「向上」起顺时针量，换算到 Flutter 的对角向量约是左上 → 右下偏右。
        gradient: const LinearGradient(
          begin: Alignment(-1, -0.72),
          end: Alignment(1, 0.72),
          colors: [Color(0xFFF9ECDF), Color(0xFFFFCEAA)],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 2, 0, 12),
            child: Text(l10n.starMyBalance, style: _StarStyles.accountTitle),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(15, 16, 15, 14),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l10n.starAvailable,
                            maxLines: 1,
                            // nowrap：标签折行会把下面的数字整体下沉（小程序同款注释）
                            overflow: TextOverflow.ellipsis,
                            style: _StarStyles.accountLabel,
                          ),
                          const SizedBox(height: 11),
                          _Amount(
                            value: '$balance',
                            unit: l10n.aiTokenUnit,
                            valueSize: 38,
                            unitSize: 16,
                            valueColor: const Color(0xFFF2621F),
                            unitColor: const Color(0xFF6B7075),
                            gap: 6,
                          ),
                        ],
                      ),
                    ),
                    // 金币插画：余额位数多（万位以上）时也不许被压扁 —— 定宽即可，
                    // Row 里非 flex 子节点本来就不参与收缩。
                    Image.asset(
                      'assets/images/token-coin.png',
                      width: 84,
                      height: 60,
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) => const Icon(
                        Icons.toll_rounded,
                        size: 48,
                        color: Color(0xFFFF8338),
                      ),
                    ),
                  ],
                ),
                const Padding(
                  padding: EdgeInsets.only(top: 13, bottom: 12),
                  child: Divider(height: 1, color: Color(0x99E2CAB4)),
                ),
                // 两列统计。竖线两侧留白相等、高度跟满「标题 + 数字」两行
                //（小程序 `.account-stat-split` 修过的正是「只在右侧留白 + 写死高度」这两点，
                //  App 这边原来也是那个老写法）。IntrinsicHeight 让 stretch 的竖线量得到行高。
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: _AccountStat(
                          label: l10n.starTotalPurchased,
                          value: '$purchased',
                          unit: l10n.aiTokenUnit,
                          valueColor: const Color(0xFFF2621F),
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16),
                        child: SizedBox(
                          width: 1,
                          child: ColoredBox(color: Color(0xBFE2CAB4)),
                        ),
                      ),
                      Expanded(
                        child: _AccountStat(
                          label: l10n.starTotalSpent,
                          value: '$spent',
                          unit: l10n.aiTokenUnit,
                          valueColor: const Color(0xFF4A4A4F),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 概览卡下半部的一列（小程序 `.account-stat`）：标签 + 数字 + 单位。
class _AccountStat extends StatelessWidget {
  const _AccountStat({
    required this.label,
    required this.value,
    required this.unit,
    required this.valueColor,
  });

  final String label;
  final String value;
  final String unit;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: _StarStyles.accountLabel,
        ),
        const SizedBox(height: 9),
        _Amount(
          value: value,
          unit: unit,
          valueSize: 20,
          unitSize: 13,
          valueColor: valueColor,
          unitColor: const Color(0xFF8B8F96),
          gap: 4,
        ),
      ],
    );
  }
}

/// 「数字 + 单位」基线对齐的一行。尺寸/颜色全部由调用方给，本身不预设口径 ——
/// 概览卡上下两处的字号与颜色在小程序里就是不同的两套。
class _Amount extends StatelessWidget {
  const _Amount({
    required this.value,
    required this.unit,
    required this.valueSize,
    required this.unitSize,
    required this.valueColor,
    required this.unitColor,
    required this.gap,
  });

  final String value;
  final String unit;
  final double valueSize;
  final double unitSize;
  final Color valueColor;
  final Color unitColor;
  final double gap;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Flexible(
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: valueColor,
              fontSize: valueSize,
              fontWeight: FontWeight.w700,
              height: 1,
            ),
          ),
        ),
        SizedBox(width: gap),
        Text(
          unit,
          style: TextStyle(color: unitColor, fontSize: unitSize, height: 1),
        ),
      ],
    );
  }
}

class _RecordsEntry extends StatelessWidget {
  const _RecordsEntry({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      // 小程序 `.record-entry`：内边距 32/32/34rpx、两行文案间距 16rpx。
      child: StarCard(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 17),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.starRecordsTitle, style: _StarStyles.cardTitle),
                  const SizedBox(height: 8),
                  Text(l10n.starRecordsDesc, style: _StarStyles.label),
                ],
              ),
            ),
            const Text(
              '›',
              style: TextStyle(
                color: Color(0xFF777E88),
                fontSize: 26,
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

/// 星币消耗规则表。2026-08-13 起**只剩「服务类型 / 星币/次」两列**（两端同改）：
/// 「说明」整列去掉，服务类型吃掉剩余宽度、星币数右对齐——两列时各行数字对齐同一条边
/// 比居中好比对，也让「图生图 / 融合图-1」这类 11 字的服务类型一行就放得下。
///
/// ⚠️ **行高仍不能写死**：服务类型名由后台配置，将来出现更长的名字仍要能折行。
/// ⚠️ 接口出参的 `remark` 仍在 [StarRule] 里映射着，只是页面不画这一列 ——
/// 它是接口字段的原样落点，删掉只会让下次要放回来时再翻一遍文档。
class _RulesCard extends StatelessWidget {
  const _RulesCard({required this.rules, required this.l10n});

  final List<StarRule> rules;
  final AppL10n l10n;

  @override
  Widget build(BuildContext context) {
    // 小程序 `.rule-card`：内边距 8/32/12rpx，与记录入口同一张白卡底。
    return StarCard(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
      child: Column(
        children: [
          _RuleRow(
            name: l10n.starRuleColService,
            cost: l10n.starRuleColCost,
            head: true,
          ),
          for (final rule in rules)
            _RuleRow(name: rule.name, cost: rule.cost),
        ],
      ),
    );
  }
}

class _RuleRow extends StatelessWidget {
  const _RuleRow({required this.name, required this.cost, this.head = false});

  final String name;
  final String cost;
  final bool head;

  @override
  Widget build(BuildContext context) {
    final base = TextStyle(
      color: head ? const Color(0xFF8B8F96) : const Color(0xFF2A2D32),
      fontSize: head ? 12 : 13,
      fontWeight: head ? FontWeight.w500 : FontWeight.w400,
      height: 1.4,
    );
    return Container(
      // 小程序 `.rule-row` 上下 20rpx；表头那行不画上边线、上内边距压到 16rpx
      //（卡片自己的圆角就是分界），字重与颜色也压一档。
      padding: EdgeInsets.only(top: head ? 8 : 10, bottom: 10),
      decoration: BoxDecoration(
        border: head
            ? null
            : const Border(top: BorderSide(color: Color(0x80CFD6E0))),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 服务类型吃掉剩余宽度，右侧留 16rpx=8（小程序 `.rule-col--name`）
          Expanded(
            flex: 3,
            child: Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text(name, style: base),
            ),
          ),
          // 成本列固定占 25%（小程序 `.rule-col--cost` 的 `flex: 0 0 25%`）：
          // 够放表头「星币/次」与 1~3 位数字，右对齐让各行数字对齐同一条边。
          // 原来写死 84 —— 窄屏上占比过大、宽屏上又对不齐。
          // ⚠️ 用 flex 3:1 而不是 FractionallySizedBox：Row 给非 flex 子节点的是**无界**
          // 主轴约束，按比例取宽在那里量不出来（会直接断言）。
          Expanded(
            flex: 1,
            child: Text(
              cost,
              textAlign: TextAlign.right,
              style: head
                  ? base
                  : base.copyWith(
                      // 消耗数字是这张表里唯一要一眼看到的信息
                      color: const Color(0xFFF2621F),
                      fontWeight: FontWeight.w600,
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StarStyles {
  const _StarStyles._();

  /// 概览卡标题「我的星币」（小程序 `.account-card-title`，36rpx w600）。
  static const TextStyle accountTitle = TextStyle(
    color: Color(0xFF2A2B2B),
    fontSize: 18,
    fontWeight: FontWeight.w600,
    height: 1,
  );

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

  /// 记录入口副标题 / 空态（小程序 `.record-entry-desc` `.token-empty` 的 #9aa0a8）。
  static const TextStyle label = TextStyle(
    color: Color(0xFF9AA0A8),
    fontSize: 13,
    height: 1,
  );

  /// 概览卡里的三个标签（小程序 `.account-label` 的 #8b8f96，比上面那档深一点）。
  static const TextStyle accountLabel = TextStyle(
    color: Color(0xFF8B8F96),
    fontSize: 13,
    height: 1,
  );
}
