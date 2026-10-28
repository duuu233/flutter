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

/// WiFi 版设备配网第一步：选择 WiFi，同步小程序 `subpackages/device/wifi-list`。
///
///   搜索页已蓝牙连上设备 → 本页让**设备**扫描附近 WiFi（BluFi 0x09，页面显示「正在搜索网络...」）
///   → 显示列表（名称 + 信号格）→ 点一行即带名称进账号密码页 → 配网状态页下发参数。
///
///   · 列表来自设备扫描，不用手机扫：iOS 拿不到附近列表、手机扫到的也不一定是设备那边收得到的；
///     本设备是双频芯片，按回包里的信道只留 2.4G（ch 1~14）；没回信道（乐鑫标准格式）时照常列出；
///   · 设备分批回就边收边显示，最后一批后再等 5 秒才结束转圈；同名去重取信号强的、信号强的在前；
///     隐藏网络（名称为空）不列；
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

  List<_WifiItem> _list = const [];
  bool _scanning = true;
  bool _connecting = true; // true 连接设备中 / false 设备扫描中
  String _tip = '';
  String _remoteId = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scan());
  }

  @override
  void dispose() {
    // 返回搜索页（或整个配网流程结束）时断开蓝牙；往后跳到账号密码页时本页不销毁，连接保留给配网复用
    if (_remoteId.isNotEmpty) {
      unawaited(Blufi.release(_remoteId));
    }
    super.dispose();
  }

  /// 设备回的列表整理成页面数据：只留 2.4G、去掉名称为空的隐藏网络、同名取信号强的、按信号排序。
  static List<_WifiItem> _toList(List<BlufiWifi> list) {
    final best = <String, BlufiWifi>{};
    for (final item in list) {
      final ssid = item.ssid.trim();
      if (ssid.isEmpty || Blufi.is24GChannel(item.channel) == false) {
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

  Future<void> _scan() async {
    final l10n = AppL10n.of(context);
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
    });
    BlufiSession session;
    try {
      await BleController.instance.stopScan();
      session = await Blufi.connect(target.bleRemoteId);
    } catch (error) {
      debugPrint('[WiFi列表] 蓝牙连接设备失败 $error');
      if (mounted) {
        setState(() {
          _scanning = false;
          _tip = l10n.wifiListConnectFailed;
        });
      }
      return;
    }
    if (!mounted) {
      return;
    }

    // ② 设备扫描附近 WiFi：每回一批就先显示出来（边扫边显示），转圈保持到扫描结束
    setState(() => _connecting = false);
    List<BlufiWifi>? list;
    try {
      list = await session.scanWifi(
        _scanTimeout,
        onBatch: (all) {
          if (mounted) {
            setState(() => _list = _toList(all));
          }
        },
      );
    } on BlufiException catch (error) {
      debugPrint('[WiFi列表] 设备扫描失败 $error');
      if (mounted) {
        // 设备报的错（带 code：扫描失败、要求加密、断开等）告诉用户；写指令本身失败给通用提示
        setState(() {
          _scanning = false;
          _tip = error.code != null ? l10n.wifiScanDeviceError(error.message) : l10n.wifiScanSendFailed;
        });
      }
      return;
    } catch (error) {
      debugPrint('[WiFi列表] 发送扫描指令失败 $error');
      if (mounted) {
        setState(() {
          _scanning = false;
          _tip = l10n.wifiScanSendFailed;
        });
      }
      return;
    }
    if (!mounted) {
      return;
    }
    if (list == null) {
      setState(() {
        _scanning = false;
        _tip = l10n.wifiScanNoList;
      });
      return;
    }
    final items = _toList(list);
    debugPrint('[WiFi列表] 设备返回 ${list.length} 条，显示 2.4G ${items.length} 条');
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
          // 顶部「设备仅支持 2.4G WiFi 配网」提示条已去掉（同小程序 2026-10-27）；列表仍只留 2.4G
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
                    if (!_scanning)
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: _scan,
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
                if (_scanning)
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
                else if (_tip.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Text(
                      _tip,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Color(0xFF8B9098), fontSize: 13, height: 1.4),
                    ),
                  ),
                // 点一行即选中该网络，直接进账号密码页
                for (var i = 0; i < _list.length; i++) ...[
                  if (i > 0) const Divider(height: 1, color: Color(0x14000000)),
                  InkWell(
                    onTap: () => _goConfig(_list[i].ssid),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      child: Row(
                        children: [
                          const Icon(Icons.wifi_rounded, size: 18, color: kWifiGreen),
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
                // 手动输入：橙字居中，列表下方
                if (!_scanning)
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
