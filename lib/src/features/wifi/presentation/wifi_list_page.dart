import 'dart:async';

import 'package:flutter/material.dart';

import '../../../device/ble_controller.dart';
import '../../../device/wifi/blufi.dart';
import '../../../device/wifi/broadcast_match.dart';
import '../../../routes/app_routes.dart';
import '../../../shared/l10n/app_l10n.dart';
import '../../../shared/widgets/figma_common.dart';
import '../../../state.dart';
import '../wifi_l10n.dart';
import '../wifi_provision.dart';
import '../wifi_widgets.dart';
import 'wifi_config_page.dart';
import 'wifi_glyphs.dart';

/// WiFi 版设备配网第一步：选择 WiFi，同步小程序 `subpackages/device/wifi-list`。
///
///   搜索页已蓝牙连上设备 → 本页让**设备**扫描附近 WiFi（BluFi 0x09，页面显示「正在搜索网络...」）
///   → 显示列表（名称 + 信号格）→ 点一行即带名称进账号密码页 → 配网状态页下发参数。
///
///   · 列表来自设备扫描，不用手机扫：iOS 拿不到附近列表、手机扫到的也不一定是设备那边收得到的；
///     本设备是双频芯片，5G、2.4G 都列出（只留 2.4G 的过滤 10-28 取消、10-29 恢复，2026-11-05 再次取消，同小程序）；
///   · 搜一个显示一个（2026-11-11，仿搜索设备页，同小程序）：设备每回一批，没显示过的按信号从强到弱逐条亮出
///     （间隔 [_revealInterval]，新行淡入）；头部「正在搜索网络...」只在一条都还没有时显示，列表出来后头部即换成
///     「重新搜索」（可随时重搜，旧一轮结果作废）；后台照旧收后续批次，最后一批后再等 5 秒才算结束，不再挂着转圈；
///   · 同名去重取信号强的、信号强的在前；隐藏网络（名称为空）不列；
///   · 这条蓝牙连接一直留着给配网状态页复用（同一会话、序号连续），离开本页（返回搜索页）才断开；
///   · 连不上设备 / 设备没回列表 / 设备报扫描失败：提示原因，给「重新搜索」；搜不到时可手动输入。
class WifiListPage extends StatefulWidget {
  const WifiListPage({super.key, required this.state});

  final PhotoFrameState state;

  @override
  State<WifiListPage> createState() => _WifiListPageState();
}

class _WifiItem {
  const _WifiItem(this.ssid, this.rssi);

  final String ssid;
  final int rssi;
}

class _WifiListPageState extends State<WifiListPage> {
  /// 等设备回 WiFi 列表的上限 60 秒；设备报错会立即结束，不必等满。
  static const Duration _scanTimeout = Duration(seconds: 60);

  /// 搜一个显示一个：每隔多久亮出下一条（2026-11-11）。
  static const Duration _revealInterval = Duration(milliseconds: 100);

  List<_WifiItem> _list = const [];
  bool _scanning = true;
  bool _connecting = true; // true 连接设备中 / false 设备扫描中
  String _tip = '';
  String _remoteId = '';

  /// 每轮搜索一个序号：列表出来后可随时重新搜索，旧一轮之后回来的批次 / 结果一律作废。
  int _scanSeq = 0;

  /// 逐条亮出：最新整理好的完整列表、已亮出的名称、下一拍定时器。
  List<_WifiItem> _revealAll = const [];
  final Set<String> _revealShown = <String>{};
  Timer? _revealTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scan());
  }

  @override
  void dispose() {
    _revealTimer?.cancel();
    // 返回搜索页（或整个配网流程结束）时断开蓝牙；往后跳到账号密码页时本页不销毁，连接保留给配网复用
    if (_remoteId.isNotEmpty) {
      unawaited(Blufi.release(_remoteId));
    }
    super.dispose();
  }

  /// 设备回的列表整理成页面数据：去掉名称为空的隐藏网络、同名取信号强的、按信号排序。
  /// 不按频段过滤（2026-11-05 再次取消只留 2.4G，5G、2.4G 都显示）。
  static List<_WifiItem> _toList(List<BlufiWifi> list) {
    final best = <String, BlufiWifi>{};
    for (final item in list) {
      final ssid = item.ssid.trim();
      if (ssid.isEmpty) {
        continue;
      }
      final current = best[ssid];
      if (current == null || item.rssi > current.rssi) {
        best[ssid] = item;
      }
    }
    return best.entries.map((e) => _WifiItem(e.key, e.value.rssi)).toList()
      ..sort((a, b) => b.rssi.compareTo(a.rssi));
  }

  /// 搜一个显示一个：[all] 是最新整理好的完整列表（去重、按信号排序）。已亮出的跟着刷新信号与位置，
  /// 没亮出的立即亮一条（定时器空闲时），其余每隔 [_revealInterval] 按信号从强到弱再亮一条。
  void _reveal(List<_WifiItem> all) {
    _revealAll = all;
    if (_revealTimer != null) {
      _renderRevealed();
      return;
    }
    _revealNext();
  }

  void _revealNext() {
    _revealTimer = null;
    if (!mounted) {
      return;
    }
    final pending = _revealAll.where((item) => !_revealShown.contains(item.ssid)).toList();
    if (pending.isEmpty) {
      return;
    }
    _revealShown.add(pending.first.ssid);
    _renderRevealed();
    if (pending.length > 1) {
      _revealTimer = Timer(_revealInterval, _revealNext);
    }
  }

  void _renderRevealed() {
    if (mounted) {
      setState(() => _list = _revealAll.where((item) => _revealShown.contains(item.ssid)).toList());
    }
  }

  void _resetReveal() {
    _revealTimer?.cancel();
    _revealTimer = null;
    _revealAll = const [];
    _revealShown.clear();
  }

  /// 列表出来后即可重新搜索（不必等后台收尾）；连接设备、一条都没出来时不响应。
  void _rescan() {
    if (!_scanning || _list.isNotEmpty) {
      unawaited(_scan());
    }
  }

  Future<void> _scan() async {
    final l10n = AppL10n.of(context);
    final seq = ++_scanSeq;
    bool current() => mounted && _scanSeq == seq;
    _resetReveal();
    final target = WifiProvision.target;
    if (target == null || target.bleRemoteId.isEmpty) {
      setState(() {
        _scanning = false;
        _list = const [];
        _tip = l10n.wifiTargetExpired;
      });
      return;
    }
    _remoteId = target.bleRemoteId;
    // ① 蓝牙连接设备（从搜索页进来时已连上，这里直接复用；断了就重连）
    setState(() {
      _scanning = true;
      _connecting = true;
      _tip = '';
      _list = const [];
    });
    BlufiSession session;
    try {
      await BleController.instance.stopScan();
      session = await Blufi.connect(target.bleRemoteId);
    } catch (error) {
      debugPrint('[WiFi列表] 蓝牙连接设备失败 $error');
      if (current()) {
        setState(() {
          _scanning = false;
          _tip = l10n.wifiListConnectFailed;
        });
      }
      return;
    }
    if (!current()) {
      return;
    }

    // ② 设备扫描附近 WiFi：每回一批就交给逐条显示（搜一个显示一个），扫描结束前头部不再挂转圈
    setState(() => _connecting = false);
    // 耗时日志（2026-11-11）：发出扫描指令到每一批回来各用了多久，真机日志据此区分慢在设备扫描还是别处
    final watch = Stopwatch()..start();
    var batches = 0;
    List<BlufiWifi>? list;
    try {
      list = await session.scanWifi(
        _scanTimeout,
        onBatch: (all) {
          if (!current()) {
            return;
          }
          batches++;
          debugPrint('[WiFi列表] 第 $batches 批，累计 ${all.length} 条，距发出扫描 ${watch.elapsedMilliseconds}ms');
          _reveal(_toList(all));
        },
      );
    } on BlufiException catch (error) {
      debugPrint('[WiFi列表] 设备扫描失败 $error，距发出扫描 ${watch.elapsedMilliseconds}ms');
      if (current()) {
        // 设备报的错（带 code：扫描失败、要求加密、断开等）告诉用户；写指令本身失败给通用提示
        setState(() {
          _scanning = false;
          _tip = error.code != null ? l10n.wifiScanDeviceError(error.message) : l10n.wifiScanSendFailed;
        });
      }
      return;
    } catch (error) {
      debugPrint('[WiFi列表] 发送扫描指令失败 $error');
      if (current()) {
        setState(() {
          _scanning = false;
          _tip = l10n.wifiScanSendFailed;
        });
      }
      return;
    }
    if (!current()) {
      return;
    }
    if (list == null) {
      debugPrint('[WiFi列表] 设备未返回 WiFi 列表，等了 ${watch.elapsedMilliseconds}ms');
      _resetReveal();
      setState(() {
        _scanning = false;
        _tip = l10n.wifiScanNoList;
      });
      return;
    }
    final items = _toList(list);
    debugPrint('[WiFi列表] 设备返回 ${list.length} 条（$batches 批），显示 ${items.length} 条，含收尾等待共 ${watch.elapsedMilliseconds}ms');
    // 收尾：还没逐条亮出的一次补齐（最后一批后已等 5 秒，正常早已亮完）
    _resetReveal();
    setState(() {
      _scanning = false;
      _list = items;
      _tip = items.isEmpty ? l10n.wifiScanNo24G : '';
    });
  }

  void _goConfig(String ssid) {
    Navigator.of(context).push<void>(
      AppPageRoute(builder: (_) => WifiConfigPage(state: widget.state, initialSsid: ssid)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    return FigmaScreen(
      title: l10n.wifiListTitle,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 16),
          // 顶部「设备仅支持 2.4G WiFi 配网」提示条：10-27 去掉、10-29 恢复，2026-11-05 再次去掉（同小程序）
          // 搜不到时的手动入口：灰字，点击进账号密码页手动填名称
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _goConfig(''),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text(
                l10n.wifiManualHint,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFF8B9098), fontSize: 13),
              ),
            ),
          ),
          FigmaGlassCard(
            borderRadius: 16,
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        l10n.wifiListHead,
                        style: const TextStyle(
                          color: Color(0xFF2A2D32),
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    // 列表出来后头部即换成「重新搜索」，不再挂着转圈（2026-11-11）
                    if (!_scanning || _list.isNotEmpty)
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: _rescan,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            children: [
                              Image.asset(
                                'assets/images/refresh-icon.png',
                                width: 16,
                                height: 16,
                                errorBuilder: (context, error, stackTrace) => const Icon(
                                  Icons.refresh_rounded,
                                  size: 16,
                                  color: Color(0xFFFF6A24),
                                ),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                l10n.wifiRescan,
                                style: const TextStyle(color: Color(0xFFFF6A24), fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                // 只在一条都还没收到时转圈；收到后由下面的列表逐条亮出（搜一个显示一个）
                if (_scanning && _list.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const WifiMiniSpinner(size: 14),
                        const SizedBox(width: 8),
                        Text(
                          _connecting ? l10n.wifiConnectingDevice : l10n.wifiSearchingNetwork,
                          style: const TextStyle(color: Color(0xFF8B9098), fontSize: 13),
                        ),
                      ],
                    ),
                  )
                else if (!_scanning && _tip.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Text(
                      _tip,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Color(0xFF8B9098), fontSize: 13, height: 1.4),
                    ),
                  ),
                // 点一行即选中该网络，直接进账号密码页。每行按 ssid 保留状态：新出现的行淡入一次，
                // 已显示的行刷新信号 / 排序时不重播（2026-11-11）
                for (var i = 0; i < _list.length; i++)
                  _WifiRowFadeIn(
                    key: ValueKey<String>(_list[i].ssid),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (i > 0) const Divider(height: 1, color: Color(0x14000000)),
                        InkWell(
                          onTap: () => _goConfig(_list[i].ssid),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            child: Row(
                              children: [
                                // 与小程序同一枚图标（badge-wifi.svg，见 wifi_glyphs.dart）
                                const WifiBadgeGlyph(size: 20),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    _list[i].ssid,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(color: Color(0xFF2A2D32), fontSize: 15),
                                  ),
                                ),
                                // 信号强度：信号格（与搜索设备列表同一组件）
                                SignalBars(level: rssiToBars(_list[i].rssi), small: false),
                                const SizedBox(width: 8),
                                const Icon(Icons.chevron_right_rounded, size: 18, color: Color(0xFFB7BBC0)),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                // 手动输入：橙字居中，列表下方；列表出来即显示（2026-11-11）
                if (!_scanning || _list.isNotEmpty)
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _goConfig(''),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      child: Text(
                        l10n.wifiManualInput,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Color(0xFFFF6A24),
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

/// 新出现的 WiFi 行淡入下滑一次（2026-11-11 搜一个显示一个，同小程序 `.wifi-item` 的 wifiItemIn）。
/// 行按 ssid 作 key：已显示的行刷新信号 / 排序时保留状态，不重播。
class _WifiRowFadeIn extends StatelessWidget {
  const _WifiRowFadeIn({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOut,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset(0, -6 * (1 - t)), child: child),
      ),
      child: child,
    );
  }
}

/// 「i 设备仅支持 2.4G WiFi 配网」提示行（选择 WiFi / 账号密码两页共用）。
class WifiTipRow extends StatelessWidget {
  const WifiTipRow({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 14,
          height: 14,
          alignment: Alignment.center,
          decoration: const BoxDecoration(color: Color(0xFFFF8A3D), shape: BoxShape.circle),
          child: const Text(
            'i',
            style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700, height: 1),
          ),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            text,
            style: const TextStyle(color: Color(0xFF5E6470), fontSize: 13),
          ),
        ),
      ],
    );
  }
}
