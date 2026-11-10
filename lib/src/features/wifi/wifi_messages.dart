import 'dart:convert';

import '../../shared/l10n/app_l10n.dart';
import '../../state.dart' show AppLanguage;
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
    this.serverTitle,
    this.serverContent,
  });

  final String id;

  /// 标记已读原样回传（Long 型 ID 可能按字符串返回，不转数字）。
  final Object rawId;
  final String type;
  final String category;
  final Map<String, dynamic> payload;
  bool read;
  final String createdAt;

  /// 服务端按 lang 翻译好的标题 / 正文（2026-11-09 列表接口新增，同小程序）：字段是字符串就收（去首尾空白），
  /// 没有这个字段为 null，交给本地按 type 兜底。
  final String? serverTitle;
  final String? serverContent;
}

/// WiFi 版消息中心的纯逻辑，同步小程序 `utils/wifi-messages.js`（实现报告反馈第三节、对接文档第八节、V1.4 更新说明 2.2）。
/// 2026-11-09 起列表接口带 lang，返回服务端翻译好的 title / content，**有就直接显示**（[titleText] / [detailText]）；
/// 按 type + payload 拼的本地文案（[WifiL10n.wifiMessageTitle]）只在接口没给时兜底，未知 type 显示通用文案。
abstract final class WifiMessages {
  /// 列表接口的 lang（2026-11-09）：按 App 当前语种传（接口可选 zh-CN / zh-TW / en / ja，不传按简中）。
  /// 小程序语种入口已隐藏、固定传 zh-CN；App 有语种设置，跟着走。
  static String notificationLang(AppLanguage language) => switch (language) {
    AppLanguage.zh => 'zh-CN',
    AppLanguage.zhHant => 'zh-TW',
    AppLanguage.en => 'en',
    AppLanguage.ja => 'ja',
  };

  static String? _serverText(Object? value) => value is String ? value.trim() : null;

  /// 标题：服务端 title 非空用它，否则本地按 type 翻译。
  static String titleText(AppL10n l10n, WifiMessage message) {
    final title = message.serverTitle;
    return title != null && title.isNotEmpty ? title : l10n.wifiMessageTitle(message.type);
  }

  /// 轮播未发送的那个时刻（HH:mm）：time / triggerTime / scheduledAt / planTime / triggerAt，带日期的只取时分（同小程序 carouselTime）。
  static String carouselTime(Map<String, dynamic> p) {
    final raw = '${p['time'] ?? p['triggerTime'] ?? p['scheduledAt'] ?? p['planTime'] ?? p['triggerAt'] ?? ''}'.trim();
    final m = RegExp(r'(\d{1,2}:\d{2})(:\d{2})?\s*$').firstMatch(raw) ?? RegExp(r'(\d{1,2}:\d{2})').firstMatch(raw);
    return m?.group(1) ?? '';
  }

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

  /// 正文：服务端给了 content 就用它（空串即不显示），没给才按 payload 本地拼一行；看不懂的字段不展示。
  static String detailText(AppL10n l10n, WifiMessage message) {
    final content = message.serverContent;
    if (content != null) {
      return content;
    }
    final p = message.payload;
    final parts = <String>[];
    // 轮播未发送（2026-11-05 对接文档 10.2，同小程序）：「18:00 的轮播图片未发送成功，请检查设备网络状态」；取不到时刻只给后半句
    if (message.type == 'CAROUSEL_NOT_SENT') {
      return l10n.wifiMsgCarouselNotSent(carouselTime(p));
    }
    // 固件升级通知（2026-11-02 同小程序）：版本变化一行；reason 是短码（timeout 超时），翻成文案
    if (message.type.startsWith('OTA_')) {
      if (_has(p['baseVersion']) && _has(p['version'])) {
        parts.add(l10n.wifiOtaVersionChange('${p['baseVersion']}', '${p['version']}'));
      } else if (_has(p['version'])) {
        parts.add(l10n.wifiOtaTargetVersion('${p['version']}'));
      }
      if (p['reason'] == 'timeout') {
        parts.add(l10n.wifiOtaTimeout);
      }
      return parts.join(l10n.wifiMsgSeparator);
    }
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
      serverTitle: _serverText(r['title']),
      serverContent: _serverText(r['content']),
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
