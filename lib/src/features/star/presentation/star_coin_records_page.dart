import 'package:flutter/material.dart';

import '../../../shared/l10n/app_l10n.dart';
import '../../../shared/widgets/app_widgets.dart';
import '../../../shared/widgets/figma_common.dart';
import '../star_coin_api.dart';

/// 购买 & 消费记录，对照小程序 `photo-album/subpackages/token/records`。
/// 顶部两个 Tab 共用一页，切换只换列表数据。
class StarCoinRecordsPage extends StatefulWidget {
  const StarCoinRecordsPage({super.key});

  @override
  State<StarCoinRecordsPage> createState() => _StarCoinRecordsPageState();
}

class _StarCoinRecordsPageState extends State<StarCoinRecordsPage> {
  final ScrollController _scroll = ScrollController();

  bool _spend = false;
  List<StarRecord> _records = const [];
  bool _loading = true;
  bool _loadFailed = false;
  bool _loadingMore = false;
  bool _hasMore = false;
  int _pageIndex = 1;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _load();
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) {
      return;
    }
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 120) {
      _loadMore();
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadFailed = false;
    });
    final spend = _spend;
    try {
      final page = await StarCoinApi.fetchRecords(spend: spend, pageIndex: 1);
      if (!mounted || _spend != spend) {
        return; // 切 Tab 期间又切走了，回来的数据不再覆盖
      }
      setState(() {
        _records = page.records;
        _pageIndex = page.pageIndex;
        _hasMore = page.hasMore;
        _loading = false;
        _loadingMore = false;
      });
    } catch (_) {
      if (!mounted || _spend != spend) {
        return;
      }
      setState(() {
        _records = const [];
        _hasMore = false;
        _loading = false;
        _loadFailed = true;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loading || _loadingMore || !_hasMore) {
      return;
    }
    final spend = _spend;
    setState(() => _loadingMore = true);
    try {
      final page = await StarCoinApi.fetchRecords(
        spend: spend,
        pageIndex: _pageIndex + 1,
      );
      if (!mounted || _spend != spend) {
        return;
      }
      setState(() {
        _records = [..._records, ...page.records];
        _pageIndex = page.pageIndex;
        _hasMore = page.hasMore;
        _loadingMore = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() => _loadingMore = false);
      }
    }
  }

  void _switchTab(bool spend) {
    if (spend == _spend) {
      return;
    }
    setState(() {
      _spend = spend;
      _records = const [];
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    return FigmaScreen(
      title: l10n.starRecordsTitle,
      scrollable: false,
      bodyPadding: EdgeInsets.zero,
      background: Image.asset('assets/images/bg02.jpg', fit: BoxFit.cover),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 4, 24, 14),
            child: Row(
              children: [
                _TabItem(
                  label: l10n.starPurchaseRecords,
                  active: !_spend,
                  onTap: () => _switchTab(false),
                ),
                const SizedBox(width: 24),
                _TabItem(
                  label: l10n.starSpendRecords,
                  active: _spend,
                  onTap: () => _switchTab(true),
                ),
              ],
            ),
          ),
          Expanded(child: _buildBody(l10n)),
        ],
      ),
    );
  }

  Widget _buildBody(AppL10n l10n) {
    if (_loading) {
      return const PageLoading();
    }
    if (_loadFailed && _records.isEmpty) {
      return PageLoadError(onRetry: _load);
    }
    if (_records.isEmpty) {
      return Center(
        child: Text(
          _spend ? l10n.starNoSpendRecords : l10n.starNoPurchaseRecords,
          style: const TextStyle(color: Color(0xFF9AA0A8), fontSize: 13),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        itemCount: _records.length + 1,
        itemBuilder: (context, index) {
          if (index == _records.length) {
            return Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                _loadingMore
                    ? l10n.galleryLoading
                    : (_hasMore ? l10n.galleryPullMore : l10n.galleryNoMore),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFF9AA0A8), fontSize: 12),
              ),
            );
          }
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _RecordCard(
              record: _records[index],
              spend: _spend,
              unit: l10n.aiTokenUnit,
              giftLabel: l10n.starGift,
            ),
          );
        },
      ),
    );
  }
}

class _TabItem extends StatelessWidget {
  const _TabItem({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              color: active ? const Color(0xFF2A2D32) : const Color(0xFF9AA0A8),
              fontSize: 15,
              fontWeight: active ? FontWeight.w600 : FontWeight.w400,
              height: 1,
            ),
          ),
          const SizedBox(height: 6),
          Container(
            width: 22,
            height: 3,
            decoration: BoxDecoration(
              color: active ? const Color(0xFFF2621F) : Colors.transparent,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ],
      ),
    );
  }
}

class _RecordCard extends StatelessWidget {
  const _RecordCard({
    required this.record,
    required this.spend,
    required this.unit,
    required this.giftLabel,
  });

  final StarRecord record;
  final bool spend;
  final String unit;
  final String giftLabel;

  @override
  Widget build(BuildContext context) {
    // 购买行要把后端下发的支付方式/订单状态翻成当前语言（后端忽略 language，恒中文），
    // 所以 l10n 从 build 传进去，别在子方法里再取一次 context。
    final l10n = AppL10n.of(context);
    return FigmaGlassCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: spend ? _buildSpend() : _buildPurchase(l10n),
    );
  }

  Widget _buildPurchase(AppL10n l10n) {
    final gift = record.gift > 0 ? ' + $giftLabel ${record.gift}' : '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(record.time, style: _RecordStyles.sub),
            ),
            Text(
              '¥${record.money.toStringAsFixed(2)}',
              style: _RecordStyles.sub,
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text('${record.amount} $unit$gift', style: _RecordStyles.main),
        const SizedBox(height: 8),
        Row(
          children: [
            // 两处都不能直接渲染后端原文：后端忽略 language，`payTypeMsg`/`orderStateMsg`
            // 恒为中文，英/日/繁用户会在这一行看到「微信支付」「已完成」。
            Expanded(
              child: Text(
                l10n.starPayChannel(record.payType, record.channel),
                style: _RecordStyles.sub,
              ),
            ),
            Text(
              l10n.starRecordStatus(record.status),
              style: _RecordStyles.sub,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSpend() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(record.time, style: _RecordStyles.sub),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: Text(record.scene, style: _RecordStyles.main)),
            Text(
              '-${record.amount} $unit',
              style: _RecordStyles.main.copyWith(
                color: const Color(0xFFF2621F),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _RecordStyles {
  const _RecordStyles._();

  static const TextStyle main = TextStyle(
    color: Color(0xFF2A2D32),
    fontSize: 15,
    height: 1.3,
  );

  static const TextStyle sub = TextStyle(
    color: Color(0xFF9AA0A8),
    fontSize: 12,
    height: 1.3,
  );
}
