import 'dart:async';

import 'package:flutter/material.dart';

import '../../../network/iot/iot_api.dart';
import '../../../network/iot/iot_client.dart';
import '../../../network/iot/iot_ws.dart';
import '../../../shared/l10n/app_l10n.dart';
import '../../../shared/widgets/app_toast.dart';
import '../../../shared/widgets/figma_common.dart';
import '../wifi_l10n.dart';
import '../wifi_messages.dart';

/// WiFi 版消息中心，同步小程序 `subpackages/device/wifi-messages`（实现报告反馈第三节、对接文档第八节）。
/// 入口：WiFi 设备详情「消息中心」。
///   · 列表：IoT GET /api/notification/list，按时间倒序，每页 20 条；下拉刷新回第一页、滑到底加载下一页（按 id 去重）；
///   · 「只看未读」开关（unreadOnly=true）；文案按 type 翻译（[WifiMessages]），未知 type 显示通用文案；
///   · 点单条：未读的标记已读（POST /api/notification/read ids=[id]，失败回滚），「全部已读」ids 传空数组；
///     只看未读时点过的那条不立刻移走，下拉刷新后才消失（免得列表跳）；
///   · 实时：订阅该设备，收到 WS notification.new（只推信号）或长连接重连成功后刷新第一页与未读数（合并 500ms）。
class WifiMessagesPage extends StatefulWidget {
  const WifiMessagesPage({super.key, required this.deviceNo});

  /// 不带冒号的 deviceNo。
  final String deviceNo;

  @override
  State<WifiMessagesPage> createState() => _WifiMessagesPageState();
}

class _WifiMessagesPageState extends State<WifiMessagesPage> {
  static const int _pageSize = 20;

  final List<StreamSubscription<Object>> _subs = <StreamSubscription<Object>>[];
  Timer? _refreshTimer;
  String _ownedSubscription = '';
  int _seq = 0;
  int _page = 0;
  bool _loading = true;
  String _loadError = '';
  List<WifiMessage> _items = <WifiMessage>[];
  int _unreadCount = 0;
  bool _unreadOnly = false;
  bool _hasMore = false;
  bool _loadingMore = false;
  bool _moreError = false;
  bool _readingAll = false;

  String get _deviceNo => IotApi.plainDeviceNo(widget.deviceNo);

  @override
  void initState() {
    super.initState();
    final ws = IotWs.instance;
    _subs
      ..add(
        ws.on('notification.new').listen((event) {
          if (IotApi.plainDeviceNo(event['deviceNo']) == _deviceNo) {
            _scheduleRefresh();
          }
        }),
      )
      // 断线期间的推送会丢：重连成功补刷一次
      ..add(
        ws.states.listen((event) {
          if (event.state == 'open' && event.reconnect) {
            _scheduleRefresh();
          }
        }),
      );
    // 收推送要先订阅；详情页通常已订阅（它在栈下面），没订阅才自己订、退出时退
    if (_deviceNo.isNotEmpty && !ws.subscriptions.contains(_deviceNo)) {
      ws.subscribe(_deviceNo);
      _ownedSubscription = _deviceNo;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadFirst());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    for (final sub in _subs) {
      unawaited(sub.cancel());
    }
    if (_ownedSubscription.isNotEmpty) {
      IotWs.instance.unsubscribe(_ownedSubscription);
    }
    super.dispose();
  }

  String _errorText(AppL10n l10n, Object error) {
    if (error is IotException) {
      return error.numericCode == 403 ? l10n.wifiMsgNoPermission : error.message;
    }
    return l10n.wifiLoadFailedRetry;
  }

  void _scheduleRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer(const Duration(milliseconds: 500), () {
      if (mounted) {
        debugPrint('[WiFi消息] 收到新消息推送，刷新列表');
        _loadFirst();
      }
    });
  }

  bool _computeHasMore(List<Object?> list, int itemCount, Map<String, dynamic> res) =>
      list.length >= _pageSize && itemCount < (num.tryParse('${res['total'] ?? 0}') ?? 0);

  /// 第一页（进页、下拉、切「只看未读」、推送）：整页替换，带序号防旧请求覆盖。
  Future<void> _loadFirst() async {
    final seq = ++_seq;
    if (_items.isEmpty) {
      setState(() {
        _loading = true;
        _loadError = '';
      });
    }
    Map<String, dynamic> res;
    try {
      res = await IotApi.getNotifications(_deviceNo, page: 1, size: _pageSize, unreadOnly: _unreadOnly);
    } catch (error) {
      if (!mounted || seq != _seq) return;
      debugPrint('[WiFi消息] 列表加载失败 $error');
      final l10n = AppL10n.of(context);
      if (_items.isNotEmpty) {
        AppToast.warn(context, _errorText(l10n, error));
        setState(() => _loading = false);
      } else {
        setState(() {
          _loading = false;
          _loadError = _errorText(l10n, error);
        });
      }
      return;
    }
    if (!mounted || seq != _seq) return;
    final raw = res['list'];
    final list = raw is List ? raw : const <Object?>[];
    final items = WifiMessages.mergePage(const [], list);
    _page = 1;
    setState(() {
      _loading = false;
      _loadError = '';
      _items = items;
      _unreadCount = (num.tryParse('${res['unreadCount'] ?? 0}') ?? 0).toInt();
      _hasMore = _computeHasMore(list, items.length, res);
      _moreError = false;
    });
  }

  Future<void> _loadMore() async {
    if (_loading || _loadingMore || !_hasMore) {
      return;
    }
    final seq = _seq;
    setState(() {
      _loadingMore = true;
      _moreError = false;
    });
    Map<String, dynamic> res;
    try {
      res = await IotApi.getNotifications(_deviceNo, page: _page + 1, size: _pageSize, unreadOnly: _unreadOnly);
    } catch (_) {
      if (mounted && seq == _seq) {
        setState(() {
          _loadingMore = false;
          _moreError = true;
        });
      }
      return;
    }
    if (!mounted || seq != _seq) return;
    final raw = res['list'];
    final list = raw is List ? raw : const <Object?>[];
    final items = WifiMessages.mergePage(_items, list);
    _page += 1;
    setState(() {
      _loadingMore = false;
      _items = items;
      final unread = (num.tryParse('${res['unreadCount'] ?? ''}') ?? 0).toInt();
      if (unread > 0) _unreadCount = unread;
      _hasMore = _computeHasMore(list, items.length, res);
    });
  }

  /// 点单条：未读的标记已读，失败回滚。
  Future<void> _tapItem(WifiMessage item) async {
    if (item.read) {
      return;
    }
    setState(() {
      item.read = true;
      _unreadCount = _unreadCount > 0 ? _unreadCount - 1 : 0;
    });
    try {
      await IotApi.markNotificationsRead(_deviceNo, [item.rawId]);
    } catch (error) {
      debugPrint('[WiFi消息] 标记已读失败 $error');
      if (mounted) {
        setState(() {
          item.read = false;
          _unreadCount += 1;
        });
        AppToast.warn(context, _errorText(AppL10n.of(context), error));
      }
    }
  }

  Future<void> _readAll() async {
    if (_unreadCount <= 0 || _readingAll) {
      return;
    }
    _readingAll = true;
    try {
      await IotApi.markNotificationsRead(_deviceNo, const []);
      if (mounted) {
        setState(() {
          for (final item in _items) {
            item.read = true;
          }
          _unreadCount = 0;
        });
        AppToast.show(context, AppL10n.of(context).wifiMsgAllRead);
      }
    } catch (error) {
      if (mounted) {
        AppToast.warn(context, _errorText(AppL10n.of(context), error));
      }
    } finally {
      _readingAll = false;
    }
  }

  Color _tagColor(String category) => switch (category) {
    'ALARM' => const Color(0xFFE5533D),
    'EXCEPTION' => const Color(0xFFB7791F),
    'BUSINESS' => const Color(0xFFFF6A20),
    _ => const Color(0xFF0E9F87),
  };

  Widget _buildItem(AppL10n l10n, WifiMessage item) {
    final detail = WifiMessages.detailText(l10n, item);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _tapItem(item),
        child: Opacity(
          opacity: item.read ? 0.7 : 1,
          child: FigmaGlassCard(
            borderRadius: 14,
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (!item.read) ...[
                      Container(
                        width: 7,
                        height: 7,
                        decoration: const BoxDecoration(color: Color(0xFFE5533D), shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 6),
                    ],
                    Expanded(
                      child: Text(
                        l10n.wifiMessageTitle(item.type),
                        style: TextStyle(
                          color: const Color(0xFF25282D),
                          fontSize: 14,
                          fontWeight: item.read ? FontWeight.w500 : FontWeight.w700,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: _tagColor(item.category).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        l10n.wifiMessageCategory(item.category),
                        style: TextStyle(color: _tagColor(item.category), fontSize: 11),
                      ),
                    ),
                  ],
                ),
                if (detail.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(detail, style: const TextStyle(color: Color(0xFF5E6470), fontSize: 12, height: 1.4)),
                ],
                const SizedBox(height: 6),
                Text(item.createdAt, style: const TextStyle(color: Color(0xFF9BA2AD), fontSize: 11)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildState(String title, String desc, {VoidCallback? onRetry}) {
    final l10n = AppL10n.of(context);
    return FigmaGlassCard(
      borderRadius: 16,
      padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 18),
      child: Column(
        children: [
          Text(title, style: const TextStyle(color: Color(0xFF25282D), fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(desc, textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFF7E858F), fontSize: 13)),
          if (onRetry != null) ...[
            const SizedBox(height: 14),
            GestureDetector(
              onTap: onRetry,
              child: Text(l10n.wifiReload, style: const TextStyle(color: Color(0xFFFF6A20), fontSize: 14)),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    Widget content;
    if (_loading) {
      content = const Center(child: CircularProgressIndicator());
    } else if (_loadError.isNotEmpty) {
      content = ListView(children: [_buildState(l10n.wifiLoadFailed, _loadError, onRetry: _loadFirst)]);
    } else if (_items.isEmpty) {
      content = ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [_buildState(_unreadOnly ? l10n.wifiMsgNoUnread : l10n.wifiMsgEmpty, l10n.wifiMsgEmptyDesc)],
      );
    } else {
      final moreText = _loadingMore
          ? l10n.wifiLoadingMore
          : _moreError
          ? l10n.wifiLoadMoreFailed
          : _hasMore
          ? l10n.wifiPullUpMore
          : l10n.wifiNoMore;
      content = NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (notification.metrics.extentAfter < 80) {
            _loadMore();
          }
          return false;
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            for (final item in _items) _buildItem(l10n, item),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _loadMore,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Center(child: Text(moreText, style: const TextStyle(color: Color(0xFF8B9098), fontSize: 12))),
              ),
            ),
          ],
        ),
      );
    }
    return FigmaScreen(
      title: l10n.wifiMessageCenter,
      scrollable: false,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 16),
          FigmaGlassCard(
            borderRadius: 14,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            child: Row(
              children: [
                Text(l10n.wifiMsgUnreadOnly, style: const TextStyle(color: Color(0xFF33373D), fontSize: 14)),
                Transform.scale(
                  scale: 0.8,
                  child: Switch(
                    value: _unreadOnly,
                    activeTrackColor: const Color(0xFFFF6A20),
                    onChanged: (value) {
                      setState(() {
                        _unreadOnly = value;
                        _items = <WifiMessage>[];
                      });
                      _loadFirst();
                    },
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _readAll,
                  child: Text(
                    l10n.wifiMsgReadAll(_unreadCount),
                    style: TextStyle(
                      color: _unreadCount > 0 ? const Color(0xFFFF6A20) : const Color(0xFFB8BDC6),
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: RefreshIndicator(
              color: const Color(0xFFEB5F1B),
              onRefresh: _loadFirst,
              child: content,
            ),
          ),
        ],
      ),
    );
  }
}
