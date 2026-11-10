import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:BoltStar/src/features/wifi/wifi_messages.dart';
import 'package:BoltStar/src/features/wifi/wifi_strategy.dart';
import 'package:BoltStar/src/features/wifi/wifi_time_zone.dart';
import 'package:BoltStar/src/shared/l10n/app_l10n.dart';
import 'package:BoltStar/src/shared/tap_guard.dart';
import 'package:BoltStar/src/state.dart' show AppLanguage;

/// 2026-11-10 同步小程序 main-wifi（11-04 ~ 11-09）的纯逻辑：轮播服务端化（对接文档 20261105 / 20261105-1）、时区、
/// 消息中心带 lang 与接口文案、投屏按钮防重复点击。用例与小程序 tests/wifi-strategy、wifi-carousel-server、
/// wifi-messages、tap-guard 同口径——改一端的规则，两端的用例要一起改。
void main() {
  const l10n = AppL10n(AppLanguage.zh);
  const album = ['b1', 'b2', 'b3'];

  group('轮播回显', () {
    test('没配置过：默认 00:00~24:00、每 1 小时，时区用手机时区，简单模式启用、照片默认不选', () {
      final form = WifiStrategy.formFromStrategy({'configured': false}, 'Asia/Tokyo');
      expect(form.beginTime, '00:00');
      expect(form.endTime, '24:00');
      expect(form.intervalMinutes, 60);
      expect(form.timeZone, 'Asia/Tokyo');
      expect(form.simpleEnabled, isTrue);
      expect(WifiStrategy.selectionFromStrategy(l10n, {'configured': false}, album).selected, isEmpty);
    });

    test('服务端回传合法 IANA 时区就用它；固定偏移不算', () {
      expect(WifiStrategy.formFromStrategy({'configured': true, 'timeZone': 'Europe/Paris'}, 'Asia/Tokyo').timeZone, 'Europe/Paris');
      expect(WifiStrategy.formFromStrategy({'configured': true, 'timeZone': 'UTC+8'}, 'Asia/Tokyo').timeZone, 'Asia/Tokyo');
    });

    test('简单模式：当前模式基础字段为空即视为关闭；保存过的 imgUrls=null 才回显全选', () {
      final off = WifiStrategy.formFromStrategy({'configured': true, 'updateType': 2, 'intervalMinutes': null}, 'Asia/Shanghai');
      expect(off.simpleEnabled, isFalse);
      final saved = {'configured': true, 'updateType': 2, 'intervalMinutes': 30, 'imgUrls': null};
      expect(WifiStrategy.formFromStrategy(saved, '').simpleEnabled, isTrue);
      expect(WifiStrategy.selectionFromStrategy(l10n, saved, album).selected, album);
      final cardsOnly = {'configured': true, 'updateType': 2, 'imgUrls': null};
      expect(WifiStrategy.selectionFromStrategy(l10n, cardsOnly, album).selected, isEmpty, reason: '只配过高级卡片：默认不选');
    });

    test('间隔低于 10 分钟落到 10 分钟档；每 N 天存量 > 30 原值回显并提示', () {
      final form = WifiStrategy.formFromStrategy({'configured': true, 'updateType': 2, 'intervalMinutes': 5}, '');
      expect(form.intervalMinutes, 10);
      final days = WifiStrategy.formFromStrategy(
        {'configured': true, 'updateType': 1, 'updateDays': 90, 'updateTimeList': ['08:00']},
        '',
      );
      expect(days.updateDays, 90);
      expect(WifiStrategy.daysOverHint(l10n, days), contains('90'));
    });

    test('高级卡片：纪念日去重排序、卡片没带 imgUrls 按全部相册', () {
      final advanced = WifiStrategy.advancedFromStrategy(l10n, {
        'weekday': {'enabled': true, 'intervalMinutes': 30, 'imgUrls': ['b2']},
        'weekend': null,
        'anniversaries': [
          {'monthDay': '12-25', 'updateTimeList': ['09:00']},
          {'monthDay': '02-14'},
          {'monthDay': '02-14'},
          {'monthDay': '02-29'},
        ],
      }, album);
      expect(advanced.weekday.enabled, isTrue);
      expect(advanced.weekday.selected, ['b2']);
      expect(advanced.weekend.enabled, isFalse);
      expect(advanced.anniversaries.map((c) => c.monthDay), ['02-14', '12-25']);
      expect(advanced.anniversaries.first.selected, album);
      expect(WifiStrategy.advancedCount(advanced), 3);
    });
  });

  group('轮播保存', () {
    const form = WifiStrategyForm(timeZone: 'Asia/Shanghai', intervalMinutes: 30, updateTimeList: ['08:00']);

    test('时区必传；简单模式关闭且没有启用的卡片：至少配置一项', () {
      expect(
        WifiStrategy.buildPayload(l10n, 'AABB', form.copyWith(timeZone: ''), album, album, WifiAdvanced.empty).error,
        l10n.wifiSlideNeedTimeZone,
      );
      expect(
        WifiStrategy.buildPayload(l10n, 'AABB', form.copyWith(simpleEnabled: false), album, album, WifiAdvanced.empty).error,
        l10n.wifiSlideNeedAnyConfig,
      );
    });

    test('间隔模式：两组参数都带、带时区、不带 idle；全选不带 imgUrls', () {
      final built = WifiStrategy.buildPayload(l10n, 'AABB', form, album, album, WifiAdvanced.empty);
      final payload = built.payload!;
      expect(payload['timeZone'], 'Asia/Shanghai');
      expect(payload['timingTime'], 1800);
      expect(payload['beginTime'], '00:00');
      expect(payload['endTime'], '24:00');
      expect(payload['updateTimeList'], ['08:00']);
      expect(payload['updateDays'], 1);
      expect(payload.containsKey('idle'), isFalse);
      expect(payload.containsKey('imgUrls'), isFalse);
      expect(payload['weekday'], isNull);
      expect(payload['anniversaries'], isEmpty);
    });

    test('开始与结束相同不让存；固定模式每 N 天超过 30 不让存', () {
      expect(
        WifiStrategy.buildPayload(l10n, 'A', form.copyWith(beginTime: '08:00', endTime: '08:00'), album, album, WifiAdvanced.empty).error,
        l10n.wifiSlideSameBeginEnd,
      );
      expect(
        WifiStrategy.buildPayload(l10n, 'A', form.copyWith(updateType: 1, updateDays: 31), album, album, WifiAdvanced.empty).error,
        l10n.wifiSlideDaysRange(30),
      );
    });

    test('简单模式关闭：基础字段与 mode / imgUrls 都不带；纪念日卡片带 monthDay 与图片组', () {
      final advanced = WifiAdvanced.empty.copyWith(
        anniversaries: [WifiStrategyCard.initial(WifiCardKind.anniversary, monthDay: '05-20').copyWith(selected: ['b3'])],
      );
      final payload = WifiStrategy.buildPayload(l10n, 'A', form.copyWith(simpleEnabled: false), const [], album, advanced).payload!;
      expect(payload.containsKey('timingTime'), isFalse);
      expect(payload.containsKey('mode'), isFalse);
      expect(payload.containsKey('imgUrls'), isFalse);
      final anniv = (payload['anniversaries']! as List).single as Map;
      expect(anniv['monthDay'], '05-20');
      expect(anniv['imgUrls'], ['b3']);
    });

    test('未启用但选过照片的工作日：随 enabled=false 带上；启用的卡片没选照片不让存', () {
      final withPhotos = WifiAdvanced.empty.copyWith(weekday: WifiStrategyCard.initial(WifiCardKind.weekday).copyWith(selected: ['b1']));
      final payload = WifiStrategy.buildPayload(l10n, 'A', form, album, album, withPhotos).payload!;
      expect((payload['weekday']! as Map)['enabled'], isFalse);
      final enabledEmpty = WifiAdvanced.empty.copyWith(weekend: WifiStrategyCard.initial(WifiCardKind.weekend).copyWith(enabled: true));
      expect(
        WifiStrategy.buildPayload(l10n, 'A', form, album, album, enabledEmpty).error,
        l10n.wifiSlideCardError(l10n.wifiSlideWeekend, l10n.wifiSlideNeedPhoto),
      );
    });
  });

  group('时间与日期', () {
    test('结束时间可选 24:00，选 24 时分钟一律 00', () {
      expect(WifiStrategy.endTimeFromIndex(24, 30), '24:00');
      expect(WifiStrategy.endTimeFromIndex(9, 15), '09:15');
      expect(WifiStrategy.endTimeIndex('24:00'), [24, 0]);
    });

    test('纪念日只选月日：2 月最多 28 日，越界落到月末；默认日期跳过已占用', () {
      expect(WifiStrategy.isMonthDay('02-29'), isFalse);
      expect(WifiStrategy.monthDayFromIndex(1, 30), '02-28');
      expect(WifiStrategy.monthDayFromIndex(3, 30), '04-30');
      expect(WifiStrategy.nextFreeMonthDay(['12-31', '01-01'], '12-31'), '01-02');
    });

    test('下次刷新：MM-dd HH:mm · 卡片类型；nextRefreshAt 为空整行不显示', () {
      expect(
        WifiStrategy.nextRefreshLine(l10n, {'nextRefreshAt': '2026-11-06 08:00:00', 'nextRefreshCardType': 'base', 'intervalMinutes': 60}),
        '11-06 08:00 · 每 1 小时',
      );
      expect(
        WifiStrategy.nextRefreshLine(l10n, {'nextRefreshAt': '2026-11-06 08:00:00', 'nextRefreshCardType': 'weekend'}),
        '11-06 08:00 · 周末',
      );
      expect(
        WifiStrategy.nextRefreshLine(l10n, {'nextRefreshAt': '2026-11-06 08:00:00', 'nextRefreshCardType': 'base', 'updateType': 1, 'updateDays': null}),
        '11-06 08:00',
      );
      expect(WifiStrategy.nextRefreshLine(l10n, {'nextRefreshAt': null}), '');
      expect(WifiStrategy.timeText('2026-11-05 21:43:10'), '2026-11-05 21:43');
    });
  });

  group('时区', () {
    test('只认 IANA 名', () {
      expect(WifiTimeZones.isIana('Asia/Shanghai'), isTrue);
      expect(WifiTimeZones.isIana('Etc/GMT-8'), isTrue);
      expect(WifiTimeZones.isIana('UTC+8'), isFalse);
      expect(WifiTimeZones.isIana('中国 / 北京'), isFalse);
    });

    test('按 UTC 偏移推断手机时区：+8 固定北京，夏令时按标准偏移 + 1 小时，候选里没有用 Etc/GMT', () {
      expect(WifiTimeZones.detect(offsetMinutes: 480), 'Asia/Shanghai');
      expect(WifiTimeZones.detect(offsetMinutes: 540), 'Asia/Tokyo');
      expect(WifiTimeZones.detect(offsetMinutes: -240), 'America/New_York');
      expect(WifiTimeZones.detect(offsetMinutes: 300), 'Etc/GMT-5');
      expect(WifiTimeZones.detect(offsetMinutes: 330), WifiTimeZones.defaultZone);
    });

    test('按语种显示国家 / 城市；不在候选里的原样显示并放进「当前」组；搜索认译名', () {
      expect(WifiTimeZones.label('Asia/Tokyo', AppLanguage.zh), '日本 / 东京');
      expect(WifiTimeZones.label('Asia/Tokyo', AppLanguage.en), 'Japan / Tokyo');
      expect(WifiTimeZones.label('Asia/Kolkata', AppLanguage.zh), 'Asia/Kolkata');
      final rows = WifiTimeZones.options('', 'Asia/Kolkata', AppLanguage.zh);
      expect(rows.first.id, 'Asia/Kolkata');
      expect(rows.first.group, '当前');
      expect(WifiTimeZones.options('东京', '', AppLanguage.en).map((r) => r.id), ['Asia/Tokyo']);
    });
  });

  group('消息中心（2026-11-09）', () {
    test('lang 跟 App 语种；接口给了 title / content 就直接用，content 空串即不显示', () {
      expect(WifiMessages.notificationLang(AppLanguage.zhHant), 'zh-TW');
      final item = WifiMessages.toItem({'id': 1, 'type': 'DEVICE_ONLINE', 'title': ' 设备上线啦 ', 'content': ''});
      expect(WifiMessages.titleText(l10n, item), '设备上线啦');
      expect(WifiMessages.detailText(l10n, item), '');
    });

    test('接口没给文案：本地按 type 兜底；轮播未发送带时刻', () {
      final item = WifiMessages.toItem({'id': 2, 'type': 'CAROUSEL_NOT_SENT', 'payload': {'triggerTime': '2026-11-05 18:00:00'}});
      expect(WifiMessages.titleText(l10n, item), '轮播未发送成功');
      expect(WifiMessages.detailText(l10n, item), '18:00 的轮播图片未发送成功，请检查设备网络状态');
    });
  });

  group('防重复点击', () {
    test('执行中再点忽略，结束后冷却期内也忽略', () async {
      final owner = Object();
      var runs = 0;
      final gate = Completer<void>();
      final first = TapGuard.run(owner, 'projection', () async {
        runs++;
        await gate.future;
      });
      await TapGuard.run(owner, 'projection', () async => runs++);
      expect(runs, 1);
      gate.complete();
      await first;
      await TapGuard.run(owner, 'projection', () async => runs++);
      expect(runs, 1, reason: '冷却 500ms 内');
      await TapGuard.run(Object(), 'projection', () async => runs++);
      expect(runs, 2, reason: '不同页面互不影响');
    });
  });
}
