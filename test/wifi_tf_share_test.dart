import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:BoltStar/src/features/wifi/wifi_l10n.dart';
import 'package:BoltStar/src/features/wifi/wifi_share.dart';
import 'package:BoltStar/src/features/wifi/wifi_status.dart';
import 'package:BoltStar/src/features/wifi/wifi_tf.dart';
import 'package:BoltStar/src/network/iot/iot_client.dart';
import 'package:BoltStar/src/shared/l10n/app_l10n.dart';
import 'package:BoltStar/src/state.dart' show AppLanguage;

/// WiFi 版 TF 卡本地模式、详情改版与简化版分享（2026-10-29 同步小程序 main-wifi）的纯逻辑，用例与小程序
/// `tests/wifi-tf-local-mode.test.js`、`tests/wifi-share.test.js` 同口径——改一端的规则，两端的用例要一起改。
void main() {
  const l10n = AppL10n(AppLanguage.zh);

  group('本地模式状态', () {
    test('LOCAL_TF → 本地模式；不认识的状态按未知；缺 status 仍按 online 回退', () {
      expect(wifiDeviceState({'online': false, 'status': 'LOCAL_TF'}), WifiOnlineStatus.local);
      expect(wifiDeviceState({'online': true, 'status': 'NEW_ONE'}), WifiOnlineStatus.unknown);
      expect(wifiDeviceState({'online': true}), WifiOnlineStatus.online);
      expect(wifiDeviceState({'online': false}), WifiOnlineStatus.offline);
      expect(wifiBlockedTip(l10n, WifiOnlineStatus.local), '当前设备状态：本地模式，请恢复设备网络再试');
      final local = WifiDeviceStatus.fromInfo({
        'online': false,
        'status': 'LOCAL_TF',
        'shadow': {'battery': 80, 'wifiRssi': -40},
      });
      expect(local.text(l10n), '本地模式');
      expect(local.battery, isNull, reason: '本地模式影子冻结，不显示电量');
    });
  });

  group('TF 卡', () {
    test('未插卡 / 已用/总量 / 没上报', () {
      expect(wifiTfState(l10n, {'tfStatus': 'absent'}).state, WifiTfState.absent);
      expect(wifiTfState(l10n, {'tfStatus': 'absent'}).text, '未插卡');
      expect(wifiTfState(l10n, {'tfStatus': 'present', 'tfUsed': 512, 'tfTotal': 30720}).text, '512MB/30GB');
      expect(wifiTfState(l10n, {'tfStatus': 'present', 'tfTotal': 0}).text, '已插卡');
      expect(wifiTfState(l10n, const {}).state, WifiTfState.unknown);
      expect(wifiTfSizeText(1536), '1.5GB');
    });

    test('play-tf 错误码提示', () {
      IotException error(int code) => IotException(code: code, message: 'x', action: IotErrorAction.none);
      expect(wifiPlayTfErrorText(l10n, error(4000)), '设备未插TF卡，无法开启');
      expect(wifiPlayTfErrorText(l10n, error(4041)), '设备不在线，无法开启');
      expect(wifiPlayTfErrorText(l10n, error(4045)), '设备升级中，请稍后');
    });

    test('command.result：推送早于响应也认，按设备 + msgid 匹配，超时', () async {
      final controller = StreamController<Map<String, dynamic>>.broadcast();
      final early = WifiCommandResultWaiter(controller.stream, 'D0:CF:13', 'play_tf');
      controller.add({'deviceNo': 'D0CF13', 'action': 'play_tf', 'msgid': '9', 'success': true, 'result': 0});
      await Future<void>.delayed(Duration.zero);
      final first = await early.wait('9');
      expect(first.success, isTrue);
      early.dispose();

      final lateWaiter = WifiCommandResultWaiter(controller.stream, 'D0CF13', 'play_tf');
      final waiting = lateWaiter.wait('10');
      controller.add({'deviceNo': 'OTHER', 'action': 'play_tf', 'msgid': '10', 'success': true});
      controller.add({'deviceNo': 'D0CF13', 'action': 'play_tf', 'msgid': '10', 'success': false, 'result': 112});
      final second = await waiting;
      expect(second.success, isFalse);
      expect(second.result, 112);
      lateWaiter.dispose();

      final slow = WifiCommandResultWaiter(controller.stream, 'D0CF13', 'play_tf');
      expect((await slow.wait('12', timeout: const Duration(milliseconds: 5))).timeout, isTrue);
      slow.dispose();
      await controller.close();
    });

    test('消息类型 TF_LOCAL_MODE 有文案', () {
      expect(l10n.wifiMessageTitle('TF_LOCAL_MODE'), '设备已进入本地模式');
    });
  });

  group('分享', () {
    test('所有者判定：isToHave=1 是；带分享者的是成员；老记录按所有者', () {
      expect(wifiIsOwner({'isToHave': 1}), isTrue);
      expect(wifiIsOwner({'isToHave': 0, 'shareUserId': 5}), isFalse);
      expect(wifiIsOwner(const {}), isTrue);
    });

    test('所有者固定第一栏；列表没有所有者用当前用户兜底', () {
      final split = wifiSplitMembers([
        {'userProductId': 2, 'userName': 'B', 'isToHave': 0},
        {'userProductId': 1, 'userName': 'A', 'isToHave': 1},
      ], null);
      expect(split.owner?.name, 'A');
      expect(split.members.map((m) => m.name), ['B']);
      const me = WifiShareMember(id: '1', name: '我', avatar: '', joinedAt: '');
      expect(wifiSplitMembers(const [], me).owner?.name, '我');
    });

    test('卡片路径与小程序接受页同格式', () {
      final path = WifiShareLink.acceptPath(
        deviceId: 'E3:48:C2:1E:D4:28',
        productId: 12,
        ownerUserId: '34',
        deviceName: '客厅 相框',
      );
      expect(path, '/subpackages/device/wifi-share-accept/wifi-share-accept?d=E3%3A48%3AC2%3A1E%3AD4%3A28&p=12&u=34&n=%E5%AE%A2%E5%8E%85%20%E7%9B%B8%E6%A1%86');
    });
  });
}
