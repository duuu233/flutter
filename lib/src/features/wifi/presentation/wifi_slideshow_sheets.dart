import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../../shared/l10n/app_l10n.dart';
import '../../../shared/widgets/app_toast.dart';
import '../wifi_l10n.dart';
import '../wifi_strategy.dart';
import '../wifi_time_zone.dart';

/// 轮播设置页的几个底部弹层（2026-11-05 同小程序 wifi-slideshow：时区、选图、多列选择器）。

/// 选图网格的一格：url = 记录的 imgBle（设备拉的就是它），thumb 缩略图。
class WifiSlideTile {
  const WifiSlideTile({required this.id, required this.url, required this.thumb});

  final String id;
  final String url;
  final String thumb;
}

const Color _accent = Color(0xFFFF6A20);

/// 多列滚轮选择（结束时间「时 / 分」、纪念日「月 / 日」）。[columnsOf] 按当前选中下标给出各列（纪念日的日列随月份变），
/// 改了前面的列时后面的列按新长度夹紧。确定返回各列下标，取消返回 null。
Future<List<int>?> pickWifiColumns(
  BuildContext context, {
  required List<int> initial,
  required List<List<String>> Function(List<int> index) columnsOf,
}) {
  return showModalBottomSheet<List<int>>(
    context: context,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
    builder: (context) => _ColumnsPicker(initial: initial, columnsOf: columnsOf),
  );
}

class _ColumnsPicker extends StatefulWidget {
  const _ColumnsPicker({required this.initial, required this.columnsOf});

  final List<int> initial;
  final List<List<String>> Function(List<int> index) columnsOf;

  @override
  State<_ColumnsPicker> createState() => _ColumnsPickerState();
}

class _ColumnsPickerState extends State<_ColumnsPicker> {
  late List<int> _index = List<int>.of(widget.initial);
  late final List<FixedExtentScrollController> _controllers = [
    for (final value in widget.initial) FixedExtentScrollController(initialItem: value),
  ];

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  void _onChanged(int column, int value) {
    final next = List<int>.of(_index)..[column] = value;
    final columns = widget.columnsOf(next);
    for (var i = column + 1; i < next.length; i++) {
      final max = columns[i].length - 1;
      if (next[i] > max) {
        next[i] = max;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _controllers[i].hasClients) {
            _controllers[i].jumpToItem(max);
          }
        });
      }
    }
    setState(() => _index = next);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final columns = widget.columnsOf(_index);
    return SafeArea(
      child: SizedBox(
        height: 300,
        child: Column(
          children: [
            Row(
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(l10n.cancel, style: const TextStyle(color: Color(0xFF6F6B66))),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(_index),
                  child: Text(l10n.devConfirm, style: const TextStyle(color: _accent, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
            Expanded(
              child: Row(
                children: [
                  for (var c = 0; c < columns.length; c++)
                    Expanded(
                      child: CupertinoPicker(
                        scrollController: _controllers[c],
                        itemExtent: 40,
                        onSelectedItemChanged: (value) => _onChanged(c, value),
                        children: [
                          for (final label in columns[c])
                            Center(child: Text(label, style: const TextStyle(fontSize: 17, color: Color(0xFF2A2D32)))),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 时区选择：分组列表 + 搜索；每行只有一段按语种的文字（20261105-1 第 2 条），返回 IANA 名，取消返回 null。
Future<String?> pickWifiTimeZone(BuildContext context, String current) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
    builder: (context) => _TimeZoneSheet(current: current),
  );
}

class _TimeZoneSheet extends StatefulWidget {
  const _TimeZoneSheet({required this.current});

  final String current;

  @override
  State<_TimeZoneSheet> createState() => _TimeZoneSheetState();
}

class _TimeZoneSheetState extends State<_TimeZoneSheet> {
  String _keyword = '';

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final media = MediaQuery.of(context);
    final rows = WifiTimeZones.options(_keyword, widget.current, l10n.language);
    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: SizedBox(
        height: media.size.height * 0.7,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
              child: Row(
                children: [
                  Text(
                    l10n.wifiSlideTimeZoneTitle,
                    style: const TextStyle(color: Color(0xFF25282D), fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(l10n.wifiSlideClose, style: const TextStyle(color: Color(0xFF6F6B66))),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: TextField(
                onChanged: (value) => setState(() => _keyword = value),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: l10n.wifiSlideTimeZoneSearch,
                  prefixIcon: const Icon(Icons.search_rounded, size: 20),
                  filled: true,
                  fillColor: const Color(0xFFF3F4F6),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: rows.isEmpty
                  ? Center(
                      child: Text(l10n.wifiSlideTimeZoneEmpty, style: const TextStyle(color: Color(0xFF8A9099), fontSize: 13)),
                    )
                  : ListView.builder(
                      itemCount: rows.length,
                      itemBuilder: (context, index) {
                        final row = rows[index];
                        final active = row.id == widget.current;
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (row.showGroup)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                                child: Text(row.group, style: const TextStyle(color: Color(0xFF8A9099), fontSize: 12)),
                              ),
                            InkWell(
                              onTap: () => Navigator.of(context).pop(row.id),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                child: Text(
                                  row.label,
                                  style: TextStyle(
                                    color: active ? _accent : const Color(0xFF2A2D32),
                                    fontSize: 15,
                                    fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 选图弹层（简单模式与高级卡片共用，20261105-1 第 1 条）：从下往上滑入；每行 3 张（同「我的相册」样式），
/// 每页 21 张、滑到底显示下一页；按点选顺序轮播，最多 100 张。确定返回所选（imgBle，按选择顺序），取消返回 null。
Future<List<String>?> pickWifiSlidePhotos(
  BuildContext context, {
  required String title,
  required List<WifiSlideTile> tiles,
  required List<String> selected,
}) {
  return showModalBottomSheet<List<String>>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
    builder: (context) => _PhotoSheet(title: title, tiles: tiles, selected: selected),
  );
}

class _PhotoSheet extends StatefulWidget {
  const _PhotoSheet({required this.title, required this.tiles, required this.selected});

  final String title;
  final List<WifiSlideTile> tiles;
  final List<String> selected;

  @override
  State<_PhotoSheet> createState() => _PhotoSheetState();
}

class _PhotoSheetState extends State<_PhotoSheet> {
  static const int _pageSize = 21;

  late List<String> _selected = List<String>.of(widget.selected);
  int _limit = _pageSize;

  List<String> get _albumUrls => [for (final tile in widget.tiles) tile.url];

  void _toggle(String url) {
    final next = WifiStrategy.toggleSelection(_selected, url);
    if (next.overflow) {
      AppToast.warn(context, AppL10n.of(context).wifiSlideFull(WifiStrategy.maxImgUrls));
      return;
    }
    setState(() => _selected = next.selected);
  }

  void _toggleAll() {
    final urls = _albumUrls;
    setState(() => _selected = WifiStrategy.toggleAll(_selected, urls));
    if (urls.length > WifiStrategy.maxImgUrls && _selected.isNotEmpty) {
      AppToast.show(context, AppL10n.of(context).wifiSlideMax(WifiStrategy.maxImgUrls));
    }
  }

  void _loadMore() {
    if (_limit < widget.tiles.length) {
      setState(() => _limit += _pageSize);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final media = MediaQuery.of(context);
    final full = WifiStrategy.isFull(_selected);
    final allSelected = WifiStrategy.isAllSelected(_selected, _albumUrls);
    final shown = widget.tiles.length < _limit ? widget.tiles.length : _limit;
    return SizedBox(
      height: media.size.height * 0.8,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Color(0xFF25282D), fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _toggleAll,
                  child: Text(
                    allSelected ? l10n.wifiSlideUnselectAll : l10n.wifiSlideSelectAll,
                    style: const TextStyle(color: _accent, fontSize: 14),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
            child: Text(
              l10n.wifiSlideSheetCount(_selected.length, WifiStrategy.maxImgUrls),
              style: TextStyle(color: full ? _accent : const Color(0xFF5E6470), fontSize: 12),
            ),
          ),
          Expanded(
            child: NotificationListener<ScrollNotification>(
              onNotification: (notification) {
                if (notification.metrics.extentAfter < 120) {
                  _loadMore();
                }
                return false;
              },
              child: CustomScrollView(
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    sliver: SliverGrid(
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        mainAxisSpacing: 7,
                        crossAxisSpacing: 7,
                      ),
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final tile = widget.tiles[index];
                          final order = _selected.indexOf(tile.url) + 1;
                          return _buildTile(tile, order, full);
                        },
                        childCount: shown,
                      ),
                    ),
                  ),
                  // 分页尾：只有一页时不显示
                  if (widget.tiles.length > _pageSize)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        child: Text(
                          shown < widget.tiles.length ? l10n.wifiPullUpMore : l10n.wifiNoMore,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Color(0xFF8B9098), fontSize: 12),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(l10n.cancel, style: const TextStyle(color: Color(0xFF6F6B66), fontSize: 15)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: _accent, shape: const StadiumBorder()),
                      onPressed: () => Navigator.of(context).pop(List<String>.of(_selected)),
                      child: Text(l10n.devConfirm, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTile(WifiSlideTile tile, int order, bool full) {
    final selected = order > 0;
    return GestureDetector(
      onTap: () => _toggle(tile.url),
      // 选满 100 张后未选的置灰（点了提示先取消部分照片）
      child: Opacity(
        opacity: full && !selected ? 0.4 : 1,
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFFF3F4F6),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: selected ? _accent : Colors.transparent, width: 2),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (tile.thumb.isNotEmpty)
                  CachedNetworkImage(
                    imageUrl: tile.thumb,
                    fit: BoxFit.contain,
                    errorWidget: (context, url, error) => const SizedBox.shrink(),
                  ),
                // 右上角圆圈：选中后显示选择顺序（= 轮播顺序）
                Positioned(
                  top: 4,
                  right: 4,
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 18),
                    height: 18,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: selected ? _accent : Colors.black.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: Colors.white),
                    ),
                    child: Text(selected ? '$order' : '', style: const TextStyle(color: Colors.white, fontSize: 11, height: 1)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
