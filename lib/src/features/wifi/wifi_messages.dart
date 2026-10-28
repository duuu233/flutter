import 'dart:convert';

import '../../shared/l10n/app_l10n.dart';
import 'wifi_l10n.dart';

/// 消息中心的一条。
class WifiMessage {
  WifiMessage({
    required this.id,
    required this.rawId,
    required this.type,
    required this.category,
    required this.payload,
    required this.read,
    required this.createdAt,
  });

  final String id;

  /// 标记已读原样回传（Long 型 ID 可能按字符串返回，不转数字）。
  final Object rawId;
  final String type;
  final String category;
  final Map<String, dynamic> payload;
  bool read;
  final String createdAt;
}

/// WiFi 版消息中心的纯逻辑，同步小程序 `utils/wifi-messages.js`（实现报告反馈第三节、对接文档第八节、V1.4 更新说明 2.2）。
/// 服务端只给短码 type + payload，文案由 App 维护（见 [WifiL10n.wifiMessageTitle]）；未知 type 显示通用文案。
abstract final class WifiMessages {
  static Map<String, dynamic> _parsePayload(Object? payload) {
    if (payload is Map) {
      return payload.map((k, v) => MapEntry(k.toString(), v));
    }
    try {
      final value = jsonDecode('${payload ?? ''}');
      return value is Map ? value.map((k, v) => MapEntry(k.toString(), v)) : <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  static bool _has(Object? value) => value != null && '$value'.isNotEmpty;

  /// payload 里值得给用户看的参数，拼成一行；看不懂的字段不展示。
  static String detailText(AppL10n l10n, WifiMessage message) {
    final p = message.payload;
    final parts = <String>[];
    if (_has(p['level'])) {
      parts.add(message.type == 'WIFI_WEAK' ? l10n.wifiMsgSignalLevel('${p['level']}') : l10n.wifiMsgBatteryLevel('${p['level']}'));
    }
    if (_has(p['battery'])) {
      parts.add(l10n.wifiMsgBattery('${p['battery']}'));
    }
    if (_has(p['rssi'])) {
      parts.add(l10n.wifiMsgRssi('${p['rssi']}'));
    }
    if (_has(p['reason'])) {
      parts.add('${p['reason']}');
    }
    if (_has(p['result']) && message.type.startsWith('PLAY_')) {
      parts.add(l10n.wifiMsgResultCode('${p['result']}'));
    }
    if (p['corrected'] == true) {
      parts.add(l10n.wifiMsgCorrected);
    }
    return parts.join(l10n.wifiMsgSeparator);
  }

  /// 列表项 → 页面行。
  static WifiMessage toItem(Object? raw) {
    final r = raw is Map ? raw : const {};
    return WifiMessage(
      id: '${r['id']}',
      rawId: r['id'] ?? '',
      type: '${r['type'] ?? ''}',
      category: '${r['category'] ?? ''}',
      payload: _parsePayload(r['payload']),
      read: r['read'] == true,
      createdAt: '${r['createdAt'] ?? ''}',
    );
  }

  /// 分页合并：按 id 去重，保持先来后到（服务端按时间倒序），翻页时新增的消息把旧页往后挤也不会重复。
  static List<WifiMessage> mergePage(List<WifiMessage> existing, List<Object?> rawList) {
    final list = List<WifiMessage>.of(existing);
    final seen = {for (final item in list) item.id};
    for (final raw in rawList) {
      final item = toItem(raw);
      if (seen.add(item.id)) {
        list.add(item);
      }
    }
    return list;
  }
}
