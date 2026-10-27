import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:BoltStar/src/device/wifi/blufi.dart';
import 'package:BoltStar/src/device/wifi/broadcast_match.dart';
import 'package:BoltStar/src/features/wifi/wifi_status.dart';
import 'package:BoltStar/src/network/boltfox_api.dart';
import 'package:BoltStar/src/network/iot/iot_client.dart';
import 'package:BoltStar/src/shared/l10n/app_l10n.dart';
import 'package:BoltStar/src/state.dart' show AppLanguage;

/// WiFi 版接入（2026-10-27 同步小程序 main-wifi）的纯逻辑，用例与小程序 `tests/wifi-search.test.js`、
/// `tests/blufi.test.js`、`tests/iot-foundation.test.js`、`tests/wifi-product-lookup.test.js`、
/// `tests/device-list-wifi-group.test.js` 同口径——改一端的规则，两端的用例要一起改。
void main() {
  group('广播名匹配（broadcast-match）', () {
    test('IJ_* / IJ_*ABC 命中并取出中间 12 位 deviceNo，大小写不敏感', () {
      expect(BroadcastMatch.wifiMatch(['IJ_E348C21ED428'], ['IJ_*'])?.wifiDeviceNo, 'E348C21ED428');
      expect(BroadcastMatch.wifiMatch(['IJ_E348C21ED428ABC'], ['IJ_*ABC'])?.wifiDeviceNo, 'E348C21ED428');
      expect(BroadcastMatch.wifiMatch(['ij_e348c21ed428'], ['IJ_*'])?.wifiDeviceNo, 'E348C21ED428');
      expect(BroadcastMatch.wifiMatch(['', 'IJ_D0CF13F02FF8'], ['IJ_*'])?.wifiDeviceNo, 'D0CF13F02FF8');
    });

    test('中间不是 12 位 / 前后缀对不上 / 多个 * 都不命中', () {
      for (final name in ['IJ_E348C21ED42', 'IJ_E348C21ED4281', 'IJ_', 'XIJ_E348C21ED428', 'IJ_E348C21ED42!']) {
        expect(BroadcastMatch.matchWildcard(name, 'IJ_*'), '', reason: name);
      }
      expect(BroadcastMatch.matchWildcard('IJ_E348C21ED428', 'IJ_*ABC'), '');
      expect(BroadcastMatch.matchWildcard('IJ_E348C21ED428', 'IJ_**'), '');
    });

    test('后台把广播 ID 写成 IJ_（不带 *）也按内置模板认作 WiFi 版', () {
      expect(BroadcastMatch.wifiMatch(['IJ_E348C21ED428'], ['EF6-370', 'IJ_'])?.wifiDeviceNo, 'E348C21ED428');
      expect(BroadcastMatch.wifiMatch(['EF6-370'], ['EF6-370', 'IJ_*']), isNull);
    });

    test('已绑定记录按产品广播 ID 认 WiFi 版', () {
      expect(BroadcastMatch.isWifiBroadcastId('IJ_*'), isTrue);
      expect(BroadcastMatch.isWifiBroadcastId('ij_*abc'), isTrue);
      expect(BroadcastMatch.isWifiBroadcastId('IJ_'), isTrue);
      expect(BroadcastMatch.isWifiBroadcastId('EF6-370'), isFalse);
      expect(BroadcastMatch.isWifiBroadcastId('EB-169'), isFalse);
      expect(BroadcastMatch.isWifiBroadcastId(''), isFalse);
    });

    test('信号格：≥-55 四格、≥-67 三格、≥-78 两格、更弱一格、未知 0 格', () {
      expect([-27, -55, -56, -67, -68, -78, -79, -95].map(rssiToBars), [4, 4, 3, 3, 2, 2, 1, 1]);
      expect([0, null, 5].map(rssiToBars), [0, 0, 0]);
    });
  });

  group('BluFi 帧', () {
    test('控制帧 / 数据帧头部与序号', () {
      expect(Blufi.encodeFrames(false, Blufi.ctrlSetOpmode, [Blufi.opmodeSta], 0).single, [0x08, 0x00, 0x00, 0x01, 0x01]);
      expect(Blufi.encodeFrames(true, Blufi.dataStaSsid, utf8.encode('Home'), 1).single,
          [0x09, 0x00, 0x01, 0x04, 0x48, 0x6f, 0x6d, 0x65]);
      expect(Blufi.encodeFrames(false, Blufi.ctrlConnectWifi, const [], 0xff).single, [0x0c, 0x00, 0xff, 0x00]);
      expect(Blufi.encodeFrames(false, Blufi.ctrlGetWifiList, const [], 3).single, [0x24, 0x00, 0x03, 0x00]);
    });

    test('40 字节分片：首片 2+14、次片 2+14、末片 12，拼回原文', () {
      final payload = List<int>.generate(40, (i) => i + 1);
      final frames = Blufi.encodeFrames(true, Blufi.dataStaPassword, payload, 5, 20);
      expect(frames.length, 3);
      expect(frames.map((f) => f[2]), [5, 6, 7]);
      expect(frames.map((f) => f[1]), [0x10, 0x10, 0x00]);
      expect(frames[0].sublist(4, 6), [40, 0]);
      expect(frames[1].sublist(4, 6), [26, 0]);
      expect(frames[2][3], 12);
      expect(frames.every((f) => f.length <= 20), isTrue);
      expect([...frames[0].sublist(6), ...frames[1].sublist(6), ...frames[2].sublist(4)], payload);
      expect(Blufi.encodeFrames(true, Blufi.dataStaPassword, payload.sublist(0, 16), 0, 20).length, 1);
    });

    test('带密码的帧不出 hex', () {
      final bytes = utf8.encode('secret');
      expect(Blufi.txFrameHex(true, Blufi.dataStaPassword, bytes), '');
      expect(Blufi.txFrameHex(true, Blufi.dataCustom, bytes), '');
      expect(Blufi.txFrameHex(true, Blufi.dataStaSsid, utf8.encode('Home')), isNotEmpty);
    });

    test('乐鑫标准 WiFi 列表：RSSI 有符号，长度不足的残尾丢弃', () {
      final home = utf8.encode('Home');
      final mine = utf8.encode('我家');
      final payload = [home.length + 1, 0xD3, ...home, mine.length + 1, 0xB0, ...mine, 0x09, 0xC0];
      final list = Blufi.parseWifiList(payload);
      expect(list.map((w) => [w.ssid, w.rssi]), [['Home', -45], ['我家', -80]]);
      expect(list.every((w) => w.channel == null), isTrue);
    });

    test('本设备自定义文本 WiFi 列表：名称可空、可带中文和逗号，认不出的行忽略', () {
      final text = [
        'ssid:starhc520,rssi:-27,ch:1',
        'ssid:,rssi:-28,ch:1',
        'ssid:starhc520_5G,rssi:-29,ch:48',
        'ssid:Zheng房间,rssi:-79,ch:1',
        'ssid:a,b,rssi:-50,ch:6',
        'ssid:1308_5G,rssi:-60,ch:157',
        'ssid:EricRachel,rssi:-84,ch:13',
        'garbage line',
      ].join('\n');
      expect(Blufi.parseCustomWifiList(text).map((w) => [w.ssid, w.rssi, w.channel]), [
        ['starhc520', -27, 1],
        ['', -28, 1],
        ['starhc520_5G', -29, 48],
        ['Zheng房间', -79, 1],
        ['a,b', -50, 6],
        ['1308_5G', -60, 157],
        ['EricRachel', -84, 13],
      ]);
      expect(Blufi.parseCustomWifiList('ssid:x,rssi:-1,ch:1\r\nssid:y,rssi:-2,ch:6').length, 2);
      expect([1, 6, 13, 14, 36, 48, 157].map(Blufi.is24GChannel), [true, true, true, true, false, false, false]);
      expect(Blufi.is24GChannel(null), isNull);
      expect([1, 13, 14, 36, 157].map(Blufi.channelFrequency), [2412, 2472, 2484, 5180, 5785]);
    });

    test('自定义 JSON 应答：data / date 两种写法都认', () {
      final ack = Blufi.parseCustom(utf8.encode(jsonEncode({
        'action': 'mqtt_config_ack',
        'data': {'result': 0, 'ack_msgid': '1756108400173'},
      })));
      expect(ack.action, 'mqtt_config_ack');
      expect(ack.body['result'], 0);
      expect(ack.ackMsgid, '1756108400173');
      final typo = Blufi.parseCustom(utf8.encode('{"action":"mqtt_config_ack","date":{"result":3,"ack_msgid":"9"}}'));
      expect(typo.body['result'], 3);
      expect(Blufi.parseCustom(utf8.encode('not json')).action, '');
    });

    test('WiFi 状态报告与 msgid', () {
      final ssid = utf8.encode('Home');
      final state = Blufi.parseWifiState([0x01, 0x00, 0x00, Blufi.dataStaSsid, ssid.length, ...ssid]);
      expect(state.staState, 0);
      expect(state.ssid, 'Home');
      final ids = List.generate(5, (_) => Blufi.newMsgid());
      expect(ids.every((id) => RegExp(r'^\d{16}$').hasMatch(id)), isTrue);
      expect(Blufi.errorText(11), 'WiFi 扫描失败');
      expect(Blufi.errorText(99), '未知错误');
    });
  });

  group('IoT 错误码', () {
    const l10n = AppL10n(AppLanguage.zh);
    IotException errorOf(int status, Object? body) {
      try {
        parseIotResponse(status, body, l10n: l10n);
      } on IotException catch (error) {
        return error;
      }
      fail('应当抛 IotException');
    }

    test('code=0 解出 data；HTTP 200 + body.code 以 body.code 为准', () {
      expect(parseIotResponse(200, {'code': 0, 'data': {'online': true}}, l10n: l10n), {'online': true});
      final offline = errorOf(200, {'code': 4041, 'msg': 'offline'});
      expect(offline.code, 4041);
      expect(offline.message, '设备已离线，请检查设备网络');
    });

    test('401 要重登，503 只重试、不登出', () {
      expect(errorOf(401, {'code': 401}).isRelogin, isTrue);
      final unavailable = errorOf(503, {'code': 503});
      expect(unavailable.isRelogin, isFalse);
      expect(unavailable.isRetryable, isTrue);
    });

    test('码表外的 5xx 按服务异常可重试；其余退回服务端 msg', () {
      expect(errorOf(502, '<html>').isRetryable, isTrue);
      expect(errorOf(200, {'code': 4999, 'msg': '自定义错误'}).message, '自定义错误');
    });

    test('429 读 retryAfter', () {
      expect(errorOf(200, {'code': 429, 'data': {'retryAfter': 5}}).retryAfter, 5);
    });
  });

  group('WiFi 产品规格归一（getProductByDevice）', () {
    test('有产品 ID 或产品名才算查到；空壳记录算查不到', () {
      expect(BoltFoxApi.normalizeWifiProduct({'productId': 17, 'sizeModel': '13.3寸'})?['sizeModel'], '13.3寸');
      expect(BoltFoxApi.normalizeWifiProduct([{'productName': 'WiFi相框'}])?['productName'], 'WiFi相框');
      expect(BoltFoxApi.normalizeWifiProduct({'pageData': [{'productId': '9'}]})?['productId'], '9');
      expect(BoltFoxApi.normalizeWifiProduct({'product': {'productId': 3}})?['productId'], '3');
      expect(BoltFoxApi.normalizeWifiProduct({'productId': 0, 'productName': null, 'sizeModel': '5寸'}), isNull);
      expect(BoltFoxApi.normalizeWifiProduct(<String, dynamic>{}), isNull);
      expect(BoltFoxApi.normalizeWifiProduct(null), isNull);
    });
  });

  group('WiFi 云端状态', () {
    test('在线带信号格与电量；离线都不显示', () {
      final online = WifiDeviceStatus.fromInfo({
        'online': true,
        'shadow': {'wifiRssi': -60, 'battery': 87},
      });
      expect(online.status, WifiOnlineStatus.online);
      expect(online.signalBars, 3);
      expect(online.battery, 87);
      final offline = WifiDeviceStatus.fromInfo({
        'online': false,
        'shadow': {'wifiRssi': -60, 'battery': 87},
      });
      expect(offline.status, WifiOnlineStatus.offline);
      expect(offline.signalBars, 0);
      expect(offline.battery, isNull);
      expect(WifiDeviceStatus.normalizeBattery(0), 0);
      expect(WifiDeviceStatus.normalizeBattery(101), isNull);
    });
  });
}
