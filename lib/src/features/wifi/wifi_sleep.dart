import '../../shared/l10n/app_l10n.dart';
import 'wifi_l10n.dart';

/// 休眠设置表单。
class WifiSleepForm {
  const WifiSleepForm({
    required this.mode,
    required this.sleepTime,
    required this.wakeTime,
    required this.beginDate,
    required this.beginTime,
    required this.endDate,
    required this.endTime,
  });

  /// 0 关闭 / 1 一次性 / 2 周期。
  final int mode;
  final String sleepTime;
  final String wakeTime;
  final String beginDate;
  final String beginTime;
  final String endDate;
  final String endTime;

  /// 周期模式唤醒早于休眠 = 跨午夜，次日唤醒。
  bool get crossDay => wakeTime.compareTo(sleepTime) < 0;

  WifiSleepForm copyWith({
    int? mode,
    String? sleepTime,
    String? wakeTime,
    String? beginDate,
    String? beginTime,
    String? endDate,
    String? endTime,
  }) {
    return WifiSleepForm(
      mode: mode ?? this.mode,
      sleepTime: sleepTime ?? this.sleepTime,
      wakeTime: wakeTime ?? this.wakeTime,
      beginDate: beginDate ?? this.beginDate,
      beginTime: beginTime ?? this.beginTime,
      endDate: endDate ?? this.endDate,
      endTime: endTime ?? this.endTime,
    );
  }
}

/// WiFi 版休眠设置的纯逻辑，同步小程序 `utils/wifi-sleep.js`（实现报告反馈第二节、V1.4 更新说明第四节）。
/// 页面 [WifiSleepPage] 只管交互，回显 ↔ 表单 ↔ 提交参数的换算与校验都在这里。
///   · mode 0 关闭；1 一次性（beginTime / endTime：yyyy-MM-dd HH:mm）；2 周期（sleepTime / wakeTime：HH:mm，可跨午夜）；
///   · 时间一律本地时间，不转 UTC（服务端转）。
abstract final class WifiSleep {
  static const int modeOff = 0;
  static const int modeOnce = 1;
  static const int modeDaily = 2;

  static String _pad(int n) => n.toString().padLeft(2, '0');

  static String dateText(DateTime date) => '${date.year}-${_pad(date.month)}-${_pad(date.day)}';

  static bool isTime(Object? value) => RegExp(r'^([01]\d|2[0-3]):[0-5]\d$').hasMatch('${value ?? ''}');

  static bool isDate(Object? value) => RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch('${value ?? ''}');

  /// 'yyyy-MM-dd HH:mm' → (date, time)。
  static ({String date, String time})? splitDateTime(Object? value) {
    final match = RegExp(r'^(\d{4}-\d{2}-\d{2})\s+(\d{2}:\d{2})').firstMatch('${value ?? ''}');
    return match == null ? null : (date: match.group(1)!, time: match.group(2)!);
  }

  /// GET /api/device/sleep → 表单。一次性默认今晚 22:00 → 明早 07:00。
  static WifiSleepForm formFromSleep(Map<String, dynamic>? plan, [DateTime? now]) {
    final today = now ?? DateTime.now();
    var form = WifiSleepForm(
      mode: modeOff,
      sleepTime: '22:00',
      wakeTime: '07:00',
      beginDate: dateText(today),
      beginTime: '22:00',
      endDate: dateText(today.add(const Duration(days: 1))),
      endTime: '07:00',
    );
    final p = plan ?? const <String, dynamic>{};
    if (p['configured'] != true) {
      return form;
    }
    final mode = num.tryParse('${p['mode']}');
    form = form.copyWith(mode: mode == modeOnce || mode == modeDaily ? mode!.toInt() : modeOff);
    if (isTime(p['sleepTime'])) form = form.copyWith(sleepTime: '${p['sleepTime']}');
    if (isTime(p['wakeTime'])) form = form.copyWith(wakeTime: '${p['wakeTime']}');
    final begin = splitDateTime(p['beginTime']);
    final end = splitDateTime(p['endTime']);
    if (begin != null) form = form.copyWith(beginDate: begin.date, beginTime: begin.time);
    if (end != null) form = form.copyWith(endDate: end.date, endTime: end.time);
    return form;
  }

  /// 当前计划的一行说明（页面顶部「当前设置」）。
  static String summary(AppL10n l10n, Map<String, dynamic> plan) {
    if (plan['configured'] != true) {
      return l10n.wifiSleepNotSet;
    }
    final mode = num.tryParse('${plan['mode']}');
    String text(Object? value) => '${value ?? ''}'.isNotEmpty ? '$value' : '--';
    if (mode == modeDaily) {
      final cross = isTime(plan['sleepTime']) &&
          isTime(plan['wakeTime']) &&
          '${plan['wakeTime']}'.compareTo('${plan['sleepTime']}') < 0;
      return l10n.wifiSleepDailySummary(text(plan['sleepTime']), text(plan['wakeTime']), cross);
    }
    if (mode == modeOnce) {
      return l10n.wifiSleepOnceSummary(text(plan['beginTime']), text(plan['endTime']));
    }
    return l10n.wifiSleepClosed;
  }

  /// 表单 → POST /api/device/sleep 的 body。返回 payload 或 error（给用户看的文案）。
  static ({Map<String, Object?>? payload, String error}) buildPayload(
    AppL10n l10n,
    String deviceNo,
    WifiSleepForm form, [
    DateTime? now,
  ]) {
    if (form.mode == modeDaily) {
      if (!isTime(form.sleepTime) || !isTime(form.wakeTime)) {
        return (payload: null, error: l10n.wifiSleepNeedTimes);
      }
      if (form.sleepTime == form.wakeTime) {
        return (payload: null, error: l10n.wifiSleepSameTime);
      }
      return (
        payload: {'deviceNo': deviceNo, 'mode': modeDaily, 'sleepTime': form.sleepTime, 'wakeTime': form.wakeTime},
        error: '',
      );
    }
    if (form.mode == modeOnce) {
      if (!isDate(form.beginDate) || !isTime(form.beginTime) || !isDate(form.endDate) || !isTime(form.endTime)) {
        return (payload: null, error: l10n.wifiSleepNeedDateTimes);
      }
      final beginTime = '${form.beginDate} ${form.beginTime}';
      final endTime = '${form.endDate} ${form.endTime}';
      if (beginTime.compareTo(endTime) >= 0) {
        return (payload: null, error: l10n.wifiSleepBeginBeforeEnd);
      }
      final current = now ?? DateTime.now();
      if (endTime.compareTo('${dateText(current)} ${_pad(current.hour)}:${_pad(current.minute)}') <= 0) {
        return (payload: null, error: l10n.wifiSleepEndPassed);
      }
      return (payload: {'deviceNo': deviceNo, 'mode': modeOnce, 'beginTime': beginTime, 'endTime': endTime}, error: '');
    }
    return (payload: {'deviceNo': deviceNo, 'mode': modeOff}, error: '');
  }
}
