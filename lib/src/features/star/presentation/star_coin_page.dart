import 'package:flutter/material.dart';

import '../../../routes/app_routes.dart';
import '../../../shared/l10n/app_l10n.dart';
import '../../../shared/widgets/app_widgets.dart';
import '../../../shared/widgets/figma_common.dart';
import '../star_coin_api.dart';
import 'star_coin_records_page.dart';

/// 星币管理，对照微信小程序 `photo-album/subpackages/token/index`
/// （2026-08-12 App 侧补齐；小程序那边叫「星币管理」，原「Token 管理」）。
///
/// ⚠️ **与小程序有意不同：App 侧没有「立即购买」**。购买链路在小程序走微信虚拟支付，
/// App 对应的是 Apple IAP / Android 内购，**尚未接入** —— 与其画一颗点了没反应（或者更糟：
/// 在后台留下一串永远付不掉的待支付单）的按钮，不如如实告诉用户「先去小程序买」。
/// IAP 接上后：把 [_PurchaseHint] 换成套餐卡 + 下单按钮即可，其余不动。
class StarCoinPage extends StatefulWidget {
  const StarCoinPage({super.key});

  @override
  State<StarCoinPage> createState() => _StarCoinPageState();
}

class _StarCoinPageState extends State<StarCoinPage> {
  StarAccount? _account;
  List<StarRule> _rules = const [];
  bool _loading = true;
  bool _loadFailed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadFailed = false;
    });
    StarAccount? account;
    var failed = false;
    try {
      account = await StarCoinApi.fetchAccount();
    } catch (_) {
      failed = true;
    }
    // 规则表**静默失败**：它是说明性内容，拉不到就整块不渲染，
    // 不该把「看余额」这件正事也一起挡在错误页后面。
    List<StarRule> rules = const [];
    try {
      rules = await StarCoinApi.fetchRules();
    } catch (_) {
      rules = const [];
    }
    if (!mounted) {
      return;
    }
    setState(() {
      if (account != null) {
        _account = account;
      }
      _rules = rules;
      _loading = false;
      // 账户读失败且此前没有过成功值才算整页失败（弱网回到本页不该把余额清零）
      _loadFailed = failed && _account == null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    return FigmaScreen(
      title: l10n.starCoinTitle,
      background: Image.asset('assets/images/bg02.jpg', fit: BoxFit.cover),
      body: _loading
          ? const SizedBox(height: 320, child: PageLoading())
          : _loadFailed
          ? SizedBox(height: 320, child: PageLoadError(onRetry: _load))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 8),
                _AccountCard(account: _account, l10n: l10n),
                const SizedBox(height: 20),
                _RecordsEntry(
                  onTap: () => Navigator.of(context).push(
                    AppPageRoute<void>(
                      builder: (_) => const StarCoinRecordsPage(),
                    ),
                  ),
                ),
                if (_rules.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  Text(l10n.starRulesTitle, style: _StarStyles.sectionTitle),
                  const SizedBox(height: 10),
                  _RulesCard(rules: _rules, l10n: l10n),
                ],
                const SizedBox(height: 20),
                const _PurchaseHint(),
                const SizedBox(height: 28),
              ],
            ),
    );
  }
}

class _AccountCard extends StatelessWidget {
  const _AccountCard({required this.account, required this.l10n});

  final StarAccount? account;
  final AppL10n l10n;

  @override
  Widget build(BuildContext context) {
    final balance = account?.balance ?? 0;
    final purchased = account?.totalPurchased ?? 0;
    final spent = account?.totalSpent ?? 0;
    return FigmaGlassCard(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.starMyBalance, style: _StarStyles.cardTitle),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l10n.starAvailable, style: _StarStyles.label),
                    const SizedBox(height: 8),
                    _Amount(value: '$balance', unit: l10n.aiTokenUnit, big: true),
                  ],
                ),
              ),
              Image.asset(
                'assets/images/token-coin.png',
                width: 54,
                height: 54,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) => const Icon(
                  Icons.toll_rounded,
                  size: 44,
                  color: Color(0xFFFF8338),
                ),
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Divider(height: 1, color: Color(0x33CFD6E0)),
          ),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l10n.starTotalPurchased, style: _StarStyles.label),
                    const SizedBox(height: 7),
                    _Amount(
                      value: '$purchased',
                      unit: l10n.aiTokenUnit,
                      color: const Color(0xFFF2621F),
                    ),
                  ],
                ),
              ),
              Container(width: 1, height: 28, color: const Color(0x33CFD6E0)),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(left: 18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l10n.starTotalSpent, style: _StarStyles.label),
                      const SizedBox(height: 7),
                      _Amount(value: '$spent', unit: l10n.aiTokenUnit),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Amount extends StatelessWidget {
  const _Amount({
    required this.value,
    required this.unit,
    this.big = false,
    this.color,
  });

  final String value;
  final String unit;
  final bool big;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          value,
          style: TextStyle(
            color: color ?? const Color(0xFF2A2D32),
            fontSize: big ? 32 : 20,
            fontWeight: FontWeight.w700,
            height: 1,
          ),
        ),
        const SizedBox(width: 5),
        Text(
          unit,
          style: TextStyle(
            color: const Color(0xFF7C828A),
            fontSize: big ? 15 : 12,
            height: 1,
          ),
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
      child: FigmaGlassCard(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 17),
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
    return FigmaGlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
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
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        border: head
            ? null
            : const Border(top: BorderSide(color: Color(0x80CFD6E0))),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 服务类型吃掉剩余宽度（原来是写死 36%，长名字必折两行）
          Expanded(child: Text(name, style: base)),
          const SizedBox(width: 12),
          SizedBox(
            width: 84,
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

/// 购买入口的替代说明（见本页文件头：App 侧 IAP 未接）。
/// ⚠️ 不用 [FigmaInfoTip]：那个是单行 Row，这句话长，会溢出。
class _PurchaseHint extends StatelessWidget {
  const _PurchaseHint();

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Text(
        l10n.starPurchaseUnavailable,
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

class _StarStyles {
  const _StarStyles._();

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
