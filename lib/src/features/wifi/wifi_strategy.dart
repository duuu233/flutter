import '../../network/iot/iot_client.dart';
import '../../shared/l10n/app_l10n.dart';
import 'wifi_l10n.dart';
import 'wifi_time_zone.dart';

/// WiFi 版轮播设置的简单模式（基础配置）表单（与接口字段的换算见 [WifiStrategy]）。
class WifiStrategyForm {
  const WifiStrategyForm({
    this.updateType = WifiStrategy.updateInterval,
    this.simpleEnabled = true,
    this.timeZone = '',
    this.beginTime = WifiStrategy.dayStart,
    this.endTime = WifiStrategy.dayEnd,
    this.intervalMinutes = 60,
    this.updateDays = 1,
    this.updateTimeList = const ['08:00'],
    this.mode = 1,
  });

  /// 2 = 间隔（beginTime / endTime + intervalMinutes），1 = 固定时间（updateDays + updateTimeList）。
  /// 简单模式与高级卡片共用这一个轮播方式。
  final int updateType;

  /// 简单模式启用开关（20261105-1，默认启用）：关闭 = 不提交基础字段。
  final bool simpleEnabled;

  /// IANA 时区名（间隔 / 固定共用，必传）。
  final String timeZone;
  final String beginTime;

  /// 允许 24:00。
  final String endTime;
  final int intervalMinutes;

  /// 1~30（存量 > 30 原值回显、提示调整、不让保存）。
  final int updateDays;
  final List<String> updateTimeList;

  /// 1 顺序 / 2 随机。
  final int mode;

  WifiStrategyForm copyWith({
    int? updateType,
    bool? simpleEnabled,
    String? timeZone,
    String? beginTime,
    String? endTime,
    int? intervalMinutes,
    int? updateDays,
    List<String>? updateTimeList,
    int? mode,
  }) {
    return WifiStrategyForm(
      updateType: updateType ?? this.updateType,
      simpleEnabled: simpleEnabled ?? this.simpleEnabled,
      timeZone: timeZone ?? this.timeZone,
      beginTime: beginTime ?? this.beginTime,
      endTime: endTime ?? this.endTime,
      intervalMinutes: intervalMinutes ?? this.intervalMinutes,
      updateDays: updateDays ?? this.updateDays,
      updateTimeList: updateTimeList ?? this.updateTimeList,
      mode: mode ?? this.mode,
    );
  }
}

/// 高级卡片种类：工作日 / 周末（各 0~1 张，enabled 开关）、纪念日（0~N 张，monthDay 不可重复、当天独占）。
enum WifiCardKind { weekday, weekend, anniversary }

/// 一张高级卡片（同小程序 wifi-strategy defaultCard）：两组时间参数都留着（切换轮播方式不清空），
/// [selected] 为该卡片的图片组（imgBle，按选择顺序）。
class WifiStrategyCard {
  const WifiStrategyCard({
    required this.kind,
    this.enabled = false,
    this.monthDay = '',
    this.beginTime = WifiStrategy.dayStart,
    this.endTime = WifiStrategy.dayEnd,
    this.intervalMinutes = 60,
    this.updateTimeList = const ['08:00'],
    this.mode = 1,
    this.selected = const [],
    this.hint = '',
  });

  /// 新卡片：纪念日默认启用、固定模式默认 ["00:00"]（对接文档 7.2）；工作日 / 周末默认关闭。
  factory WifiStrategyCard.initial(WifiCardKind kind, {String monthDay = ''}) => WifiStrategyCard(
    kind: kind,
    enabled: kind == WifiCardKind.anniversary,
    monthDay: kind == WifiCardKind.anniversary ? monthDay : '',
    updateTimeList: kind == WifiCardKind.anniversary ? const ['00:00'] : const ['08:00'],
  );

  final WifiCardKind kind;
  final bool enabled;

  /// MM-dd（只有纪念日有）。
  final String monthDay;
  final String beginTime;
  final String endTime;
  final int intervalMinutes;
  final List<String> updateTimeList;
  final int mode;
  final List<String> selected;

  /// 回显时的选图提示（之前选的照片被删了等），重新选过就清掉。
  final String hint;

  WifiStrategyCard copyWith({
    bool? enabled,
    String? monthDay,
    String? beginTime,
    String? endTime,
    int? intervalMinutes,
    List<String>? updateTimeList,
    int? mode,
    List<String>? selected,
    String? hint,
  }) {
    return WifiStrategyCard(
      kind: kind,
      enabled: enabled ?? this.enabled,
      monthDay: monthDay ?? this.monthDay,
      beginTime: beginTime ?? this.beginTime,
      endTime: endTime ?? this.endTime,
      intervalMinutes: intervalMinutes ?? this.intervalMinutes,
      updateTimeList: updateTimeList ?? this.updateTimeList,
      mode: mode ?? this.mode,
      selected: selected ?? this.selected,
      hint: hint ?? this.hint,
    );
  }
}

/// 全部高级卡片。
class WifiAdvanced {
  const WifiAdvanced({required this.weekday, required this.weekend, this.anniversaries = const []});

  static const WifiAdvanced empty = WifiAdvanced(
    weekday: WifiStrategyCard(kind: WifiCardKind.weekday),
    weekend: WifiStrategyCard(kind: WifiCardKind.weekend),
  );

  final WifiStrategyCard weekday;
  final WifiStrategyCard weekend;
  final List<WifiStrategyCard> anniversaries;

  WifiAdvanced copyWith({WifiStrategyCard? weekday, WifiStrategyCard? weekend, List<WifiStrategyCard>? anniversaries}) {
    return WifiAdvanced(
      weekday: weekday ?? this.weekday,
      weekend: weekend ?? this.weekend,
      anniversaries: anniversaries ?? this.anniversaries,
    );
  }
}

/// WiFi 版轮播设置的纯逻辑，同步小程序 `utils/wifi-strategy.js`。页面 [WifiSlideshowPage] 只管交互，
/// 表单 ↔ 接口字段的换算、选图顺序、高级卡片都在这里。
///
/// 2026-11-05 起按对接文档 20261105（轮播服务端化）：服务端按配置定时推图，设备不再自己按 strategy 拉图。
///   · 时区 timeZone 必传（IANA 名，间隔 / 固定共用，见 [WifiTimeZones]）；
///   · 间隔 timingTime 600~86400 秒，档位 10 分钟起（去掉 1 / 5 分钟）；beginTime / endTime 默认 00:00~24:00，endTime 允许 24:00，
///     beginTime > endTime 视为跨天；
///   · 固定 updateDays + updateTimeList HH:mm[]（至少 1 个）；mode 1 顺序 / 2 随机；
///   · idle 已废弃（不再传，页面去掉「轮播后休眠」）；
///   · 间隔 / 固定二选一，切换不清空另一方：两组参数都带上（当前模式的校验过，另一方合法才带），服务端只取当前模式那组；
///   · 高级设置：weekday / weekend（各 0~1 张，enabled 开关）+ anniversaries（0~N 张，monthDay MM-dd 不可重复），
///     每张卡片独立的时间设置、图片组、顺序；每天只有一种卡片生效（纪念日 > 周末 / 工作日 > 基础配置），不做跨卡片时间重叠校验；
///   · 保存后不再额外 /api/device/play 投第一张（下发轮播后设备会立刻自动刷屏）。
///
/// 2026-11-05 修订版 20261105-1（与上一版冲突以它为准）：
///   · 基础配置做成「简单模式」卡片，带启用开关（默认启用）。关闭 = 不提交基础字段：间隔的 timingTime / beginTime / endTime、
///     固定的 updateDays / updateTimeList，以及基础的 mode / imgUrls；回显时当前模式的基础字段为空即视为关闭；
///   · 保存条件：简单模式启用，或至少一张高级卡片启用（工作日 / 周末 enabled、任一纪念日），否则「至少配置一项」、保存按钮置灰；
///   · 固定模式每 N 天 1~30（原 1~365）；updateDays 只在 updateTimeList 非空时才带。存量 > 30 的照样回显，提示调整、不让保存；
///   · 纪念日只选月日，2 月最多 28 日（服务端拒绝 02-29），4 / 6 / 9 / 11 月 30 日；
///   · 「下次刷新：MM-dd HH:mm · 卡片类型」（nextRefreshCardType），nextRefreshAt 为 null 整行不显示。
///
/// 选图：
///   · imgUrls：「我的相册」里选中照片的 imgBle，按选择顺序，最多 100；不传 = 轮播全部相册；**不能传空数组**（服务端回 4000）；
///   · 开启轮播必须至少选一张：简单模式与每张启用的卡片都要选；
///   · 简单模式按相册顺序全选时不带 imgUrls（= 全部相册，之后新上传的也进轮播）；卡片的图片组一律按所选明确提交；
///   · 回显 imgUrls：null = 简单模式保存过时是「全部相册」（全选；相册超过 100 张只选前 100 张），没配置过 / 简单模式没保存时
///     默认不选（2026-11-06）；[] = 选过但照片都删了（提示重新选择）。
abstract final class WifiStrategy {
  static const int updateInterval = 2;
  static const int updateFixed = 1;
  static const int maxImgUrls = 100;
  static const int maxUpdateDays = 30;
  static const int maxTimePoints = 24;
  static const int minTimingSeconds = 600;
  static const int maxTimingSeconds = 86400;
  static const String dayStart = '00:00';
  static const String dayEnd = '24:00';

  /// 间隔可选档位（分钟），对接文档 5.1 建议候选：10 分钟起，最大 24 小时。
  static const List<int> intervalOptions = [10, 15, 30, 60, 120, 180, 360, 720, 1440];
  static const WifiStrategyForm defaultForm = WifiStrategyForm();

  /// 2 月最多 28 日（服务端拒绝 02-29）。
  static const List<int> monthDays = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];

  static String _two(int n) => n.toString().padLeft(2, '0');

  static bool isTime(Object? value) => RegExp(r'^([01]\d|2[0-3]):[0-5]\d$').hasMatch('${value ?? ''}');

  /// 窗口结束额外允许 24:00。
  static bool isEndTime(Object? value) => isTime(value) || '${value ?? ''}' == dayEnd;

  /// 时间点去重、去非法、按时刻排序。
  static List<String> normalizeTimes(Iterable<Object?>? list) {
    final out = <String>[];
    for (final item in list ?? const <Object?>[]) {
      final value = '${item ?? ''}'.trim();
      if (isTime(value) && !out.contains(value)) {
        out.add(value);
      }
    }
    return out..sort();
  }

  static List<String> _times(Object? raw) => normalizeTimes(raw is List ? raw : null);

  /// 最接近的间隔档位下标（回显用：服务端可能存了不在档位里的分钟数，低于 10 分钟的落到 10 分钟）。
  static int intervalIndexOf(num? minutes) {
    final value = minutes ?? 0;
    if (value <= 0) {
      return intervalOptions.indexOf(defaultForm.intervalMinutes);
    }
    var best = 0;
    for (var i = 0; i < intervalOptions.length; i++) {
      if ((intervalOptions[i] - value).abs() < (intervalOptions[best] - value).abs()) {
        best = i;
      }
    }
    return best;
  }

  static String intervalLabel(AppL10n l10n, int minutes) =>
      minutes >= 60 && minutes % 60 == 0 ? l10n.wifiHours(minutes ~/ 60) : l10n.wifiMinutes(minutes);

  /// 回显的间隔分钟：intervalMinutes 优先，没有就按 timingTime 秒换算；再落到最近档位。
  static int _minutesOf(Map<String, dynamic> raw) {
    final minutes = num.tryParse('${raw['intervalMinutes']}') ?? 0;
    final timing = num.tryParse('${raw['timingTime']}') ?? 0;
    final value = minutes > 0 ? minutes : (timing > 0 ? (timing / 60).ceil() : 0);
    return intervalOptions[intervalIndexOf(value)];
  }

  /// 回显：当前模式的基础字段有值才算简单模式启用（关闭时服务端不存基础字段，intervalMinutes / updateDays 回 null）。
  static bool hasBaseConfig(Map<String, dynamic>? raw, int updateType) {
    final r = raw ?? const <String, dynamic>{};
    if (updateType == updateFixed) {
      return _times(r['updateTimeList']).isNotEmpty;
    }
    return (num.tryParse('${r['intervalMinutes']}') ?? 0) > 0 || (num.tryParse('${r['timingTime']}') ?? 0) > 0;
  }

  static int _typeOf(Map<String, dynamic>? s) =>
      num.tryParse('${s?['updateType']}') == updateFixed ? updateFixed : updateInterval;

  /// GET /api/device/strategy → 简单模式表单。没配置过（configured=false）用默认值；
  /// 时区：服务端回传了合法 IANA 名就用它，否则用 [fallbackZone]（手机时区）。
  /// 每 N 天：存量配置可能 > 30，原值回显（页面提示调整，保存时拦下），不悄悄改成别的天数。
  static WifiStrategyForm formFromStrategy(Map<String, dynamic>? strategy, String fallbackZone) {
    final s = strategy ?? const <String, dynamic>{};
    final zone = WifiTimeZones.isIana(s['timeZone'])
        ? '${s['timeZone']}'.trim()
        : (fallbackZone.isNotEmpty ? fallbackZone : WifiTimeZones.defaultZone);
    if (s['configured'] != true) {
      return defaultForm.copyWith(timeZone: zone);
    }
    final updateType = _typeOf(s);
    final days = num.tryParse('${s['updateDays']}') ?? 0;
    final times = _times(s['updateTimeList']);
    return WifiStrategyForm(
      updateType: updateType,
      simpleEnabled: hasBaseConfig(s, updateType),
      timeZone: zone,
      beginTime: isTime(s['beginTime']) ? '${s['beginTime']}' : dayStart,
      endTime: isEndTime(s['endTime']) ? '${s['endTime']}' : dayEnd,
      intervalMinutes: _minutesOf(s),
      updateDays: days >= 1 ? days.floor() : defaultForm.updateDays,
      updateTimeList: times.isNotEmpty ? times : defaultForm.updateTimeList,
      mode: num.tryParse('${s['mode']}') == 2 ? 2 : 1,
    );
  }

  /// 回显的 imgUrls 与当前相册对一下：只留相册里还在的、保持原顺序。
  static ({List<String> selected, String hint}) _pickFromAlbum(AppL10n l10n, List<String> urls, List<String> album) {
    final selected = <String>[];
    for (final url in urls) {
      if (album.contains(url) && !selected.contains(url) && selected.length < maxImgUrls) {
        selected.add(url);
      }
    }
    if (urls.isEmpty) {
      return (selected: selected, hint: l10n.wifiSlideAllDeleted);
    }
    if (selected.isEmpty) {
      return (selected: selected, hint: l10n.wifiSlideNotInAlbum);
    }
    if (selected.length < urls.length) {
      return (selected: selected, hint: l10n.wifiSlideSomeDeleted(urls.length - selected.length));
    }
    return (selected: selected, hint: '');
  }

  /// 全部相册：按相册顺序全选，超过上限只选前 [maxImgUrls] 张并说明。
  static ({List<String> selected, String hint}) _wholeAlbum(AppL10n l10n, List<String> album) {
    if (album.length > maxImgUrls) {
      return (selected: album.sublist(0, maxImgUrls), hint: l10n.wifiSlideWholeAlbumOverLimit(maxImgUrls));
    }
    return (selected: List<String>.of(album), hint: '');
  }

  /// 简单模式的回显选择。查询失败（strategy 为空）不选。imgUrls 为 null 时（2026-11-06 起「默认不选」）：
  /// 只有简单模式确实保存过（configured 且基础字段在）才是用户选的「全部相册」，按相册顺序全选；
  /// 没配置过、或只配过高级卡片一律不选，由用户自己挑。
  static ({List<String> selected, String hint}) selectionFromStrategy(
    AppL10n l10n,
    Map<String, dynamic>? strategy,
    List<String> albumUrls,
  ) {
    if (strategy == null) {
      return (selected: <String>[], hint: '');
    }
    final raw = strategy['imgUrls'];
    if (raw is! List) {
      final savedWhole = strategy['configured'] == true && hasBaseConfig(strategy, _typeOf(strategy));
      return savedWhole ? _wholeAlbum(l10n, albumUrls) : (selected: <String>[], hint: '');
    }
    return _pickFromAlbum(l10n, [for (final item in raw) '$item'], albumUrls);
  }

  /// 卡片的回显选择：卡片对象里没有 imgUrls（null / 缺）按全部相册全选，与简单模式同口径。
  static ({List<String> selected, String hint}) selectionFromCard(AppL10n l10n, Object? imgUrls, List<String> albumUrls) =>
      imgUrls is List ? _pickFromAlbum(l10n, [for (final item in imgUrls) '$item'], albumUrls) : _wholeAlbum(l10n, albumUrls);

  /// 点一张：选中追加到末尾（顺序 = 轮播顺序），再点取消。已选满上限时返回 overflow=true 不改（已选的仍可取消）。
  static ({List<String> selected, bool overflow}) toggleSelection(List<String> selected, String url) {
    final list = List<String>.of(selected);
    if (list.remove(url)) {
      return (selected: list, overflow: false);
    }
    if (list.length >= maxImgUrls) {
      return (selected: list, overflow: true);
    }
    list.add(url);
    return (selected: list, overflow: false);
  }

  /// 已选满上限（未选的置灰、点了只提示）。
  static bool isFull(List<String> selected) => selected.length >= maxImgUrls;

  /// 全选按钮的状态：相册全选了，或已选满上限（相册超过上限时选不全，此时按钮给「取消全选」）。
  static bool isAllSelected(List<String> selected, List<String> albumUrls) =>
      albumUrls.isNotEmpty && (isFull(selected) || albumUrls.every(selected.contains));

  /// 全选 / 取消全选：已全选（或已选满）则清空；否则保留已选顺序，把没选的按网格顺序追加（截到上限）。
  static List<String> toggleAll(List<String> selected, List<String> albumUrls) {
    final list = List<String>.of(selected);
    if (isAllSelected(list, albumUrls)) {
      return <String>[];
    }
    for (final url in albumUrls) {
      if (!list.contains(url) && list.length < maxImgUrls) {
        list.add(url);
      }
    }
    return list;
  }

  /// 是否「按相册顺序全选」：是则不带 imgUrls，保持「全部相册」语义。
  static bool isWholeAlbum(List<String> selected, List<String> albumUrls) {
    if (albumUrls.isEmpty || selected.length != albumUrls.length) {
      return false;
    }
    for (var i = 0; i < albumUrls.length; i++) {
      if (selected[i] != albumUrls[i]) {
        return false;
      }
    }
    return true;
  }

  // ── 结束时间（两列：时 00~24、分 00~59，选 24 时分钟只能是 00）──

  static List<String> get endHourLabels => [for (var i = 0; i <= 24; i++) _two(i)];
  static List<String> get minuteLabels => [for (var i = 0; i < 60; i++) _two(i)];

  static List<int> endTimeIndex(String value) {
    final text = isEndTime(value) ? value : dayEnd;
    return [int.parse(text.substring(0, 2)), int.parse(text.substring(3, 5))];
  }

  static String endTimeFromIndex(int hourIndex, int minuteIndex) {
    final hour = hourIndex.clamp(0, 24);
    final minute = hour == 24 ? 0 : minuteIndex.clamp(0, 59);
    return '${_two(hour)}:${_two(minute)}';
  }

  // ── 纪念日日期 ──

  static bool isMonthDay(Object? value) {
    final m = RegExp(r'^(\d{2})-(\d{2})$').firstMatch('${value ?? ''}');
    if (m == null) {
      return false;
    }
    final month = int.parse(m.group(1)!);
    final day = int.parse(m.group(2)!);
    return month >= 1 && month <= 12 && day >= 1 && day <= monthDays[month - 1];
  }

  static String monthDayLabel(AppL10n l10n, String value) =>
      isMonthDay(value) ? l10n.wifiSlideMonthDay(int.parse(value.substring(0, 2)), int.parse(value.substring(3, 5))) : '';

  /// 下标 [月, 日]（0 起）→ MM-dd；日超过该月天数时落到月末。
  static String monthDayFromIndex(int monthIndex, int dayIndex) {
    final month = (monthIndex + 1).clamp(1, 12);
    final day = (dayIndex + 1).clamp(1, monthDays[month - 1]);
    return '${_two(month)}-${_two(day)}';
  }

  /// 新增纪念日的默认日期：从 [start]（MM-dd，默认 01-01）起找第一个没被占用的日子。
  static String nextFreeMonthDay(List<String> taken, String start) {
    var month = 1;
    var day = 1;
    if (isMonthDay(start)) {
      month = int.parse(start.substring(0, 2));
      day = int.parse(start.substring(3, 5));
    }
    for (var n = 0; n < 366; n++) {
      final value = '${_two(month)}-${_two(day)}';
      if (!taken.contains(value)) {
        return value;
      }
      day++;
      if (day > monthDays[month - 1]) {
        day = 1;
        month = month == 12 ? 1 : month + 1;
      }
    }
    return '';
  }

  // ── 高级卡片 ──

  /// 接口里的卡片对象 → 卡片表单。raw 为空（null / 不传）→ 未启用的默认卡片。
  static WifiStrategyCard cardFromStrategy(AppL10n l10n, Object? raw, WifiCardKind kind, List<String> albumUrls) {
    if (raw is! Map) {
      return WifiStrategyCard.initial(kind);
    }
    final r = raw.map((k, v) => MapEntry(k.toString(), v));
    final card = WifiStrategyCard.initial(kind, monthDay: '${r['monthDay'] ?? ''}');
    final times = _times(r['updateTimeList']);
    final picked = selectionFromCard(l10n, r['imgUrls'], albumUrls);
    return card.copyWith(
      enabled: kind == WifiCardKind.anniversary ? true : r['enabled'] == true,
      beginTime: isTime(r['beginTime']) ? '${r['beginTime']}' : dayStart,
      endTime: isEndTime(r['endTime']) ? '${r['endTime']}' : dayEnd,
      intervalMinutes: _minutesOf(r),
      updateTimeList: times.isNotEmpty ? times : card.updateTimeList,
      mode: num.tryParse('${r['mode']}') == 2 ? 2 : 1,
      selected: picked.selected,
      hint: picked.hint,
    );
  }

  /// 回显全部高级卡片；纪念日去掉日期非法 / 重复的，按日期排序。
  static WifiAdvanced advancedFromStrategy(AppL10n l10n, Map<String, dynamic>? strategy, List<String> albumUrls) {
    final s = strategy ?? const <String, dynamic>{};
    final anniversaries = <WifiStrategyCard>[];
    final seen = <String>{};
    final rawList = s['anniversaries'];
    for (final raw in rawList is List ? rawList : const []) {
      final monthDay = raw is Map ? '${raw['monthDay'] ?? ''}' : '';
      if (isMonthDay(monthDay) && seen.add(monthDay)) {
        anniversaries.add(cardFromStrategy(l10n, raw, WifiCardKind.anniversary, albumUrls));
      }
    }
    anniversaries.sort((a, b) => a.monthDay.compareTo(b.monthDay));
    return WifiAdvanced(
      weekday: cardFromStrategy(l10n, s['weekday'], WifiCardKind.weekday, albumUrls),
      weekend: cardFromStrategy(l10n, s['weekend'], WifiCardKind.weekend, albumUrls),
      anniversaries: anniversaries,
    );
  }

  /// 「高级设置（N 项）」：启用的工作日 / 周末 + 纪念日条数。
  static int advancedCount(WifiAdvanced advanced) =>
      (advanced.weekday.enabled ? 1 : 0) + (advanced.weekend.enabled ? 1 : 0) + advanced.anniversaries.length;

  /// 简单模式旁的提示（对接文档 4.2）：只看工作日 / 周末是否启用，纯文字、不阻断保存。
  static String baseHint(AppL10n l10n, WifiAdvanced advanced) {
    final weekday = advanced.weekday.enabled;
    final weekend = advanced.weekend.enabled;
    if (weekday && weekend) {
      return l10n.wifiSlideBaseHintBoth;
    }
    if (weekday) {
      return l10n.wifiSlideBaseHintWeekday;
    }
    if (weekend) {
      return l10n.wifiSlideBaseHintWeekend;
    }
    return '';
  }

  /// 是否有可保存的配置：简单模式启用，或任一高级卡片启用（工作日 / 周末 enabled、任一纪念日）。
  static bool hasAnyConfig(WifiStrategyForm form, WifiAdvanced advanced) =>
      form.simpleEnabled || advanced.weekday.enabled || advanced.weekend.enabled || advanced.anniversaries.isNotEmpty;

  static bool isUpdateDays(int value) => value >= 1 && value <= maxUpdateDays;

  /// 存量配置每 N 天 > 30 时的提示（服务端照旧按原值跑，但改任何设置都存不了）：只在简单模式启用时给。
  static String daysOverHint(AppL10n l10n, WifiStrategyForm form) =>
      !form.simpleEnabled || form.updateDays <= maxUpdateDays ? '' : l10n.wifiSlideDaysOver(form.updateDays, maxUpdateDays);

  static String cardTitle(AppL10n l10n, WifiStrategyCard card) => switch (card.kind) {
    WifiCardKind.weekday => l10n.wifiSlideWeekday,
    WifiCardKind.weekend => l10n.wifiSlideWeekend,
    WifiCardKind.anniversary => '${l10n.wifiSlideAnniversary} ${monthDayLabel(l10n, card.monthDay)}'.trim(),
  };

  // ── 保存 ──

  /// 间隔参数：合法返回 value，否则 error。
  static ({Map<String, Object?>? value, String error}) _intervalGroup(
    AppL10n l10n,
    String beginTime,
    String endTime,
    int intervalMinutes,
  ) {
    if (!isTime(beginTime) || !isEndTime(endTime)) {
      return (value: null, error: l10n.wifiSlideNeedTimes);
    }
    if (beginTime == endTime) {
      return (value: null, error: l10n.wifiSlideSameBeginEnd);
    }
    final seconds = intervalMinutes * 60;
    if (seconds < minTimingSeconds || seconds > maxTimingSeconds) {
      return (value: null, error: l10n.wifiSlideIntervalRange);
    }
    return (value: {'beginTime': beginTime, 'endTime': endTime, 'timingTime': seconds}, error: '');
  }

  /// 固定时间点：合法返回 value，否则 error。
  static ({Map<String, Object?>? value, String error}) _fixedGroup(AppL10n l10n, List<String> updateTimeList) {
    final times = normalizeTimes(updateTimeList);
    if (times.isEmpty) {
      return (value: null, error: l10n.wifiSlideNeedTimePoint);
    }
    return (value: {'updateTimeList': times}, error: '');
  }

  /// 两组参数都带上：当前模式那组出错直接返回错误，另一方合法才带（切换模式不清空另一方）。
  static ({Map<String, Object?>? value, String error}) _bothGroups(
    AppL10n l10n,
    int updateType, {
    required String beginTime,
    required String endTime,
    required int intervalMinutes,
    required List<String> updateTimeList,
  }) {
    final interval = _intervalGroup(l10n, beginTime, endTime, intervalMinutes);
    final fixed = _fixedGroup(l10n, updateTimeList);
    final current = updateType == updateFixed ? fixed : interval;
    if (current.value == null) {
      return (value: null, error: current.error);
    }
    return (value: {...?interval.value, ...?fixed.value}, error: '');
  }

  static String _photoError(AppL10n l10n, List<String> urls) {
    if (urls.isEmpty) {
      return l10n.wifiSlideNeedPhoto;
    }
    if (urls.length > maxImgUrls) {
      return l10n.wifiSlideOverLimit(maxImgUrls);
    }
    return '';
  }

  /// 卡片 → 接口对象。返回 value（未配置的工作日 / 周末为 null）或 error。
  static ({Map<String, Object?>? value, String error}) cardPayload(AppL10n l10n, WifiStrategyCard card, int updateType) {
    final name = cardTitle(l10n, card);
    final urls = card.selected.where((url) => url.isNotEmpty).toList();
    final mode = card.mode == 2 ? 2 : 1;
    if (card.kind != WifiCardKind.anniversary && !card.enabled) {
      // 未启用：选过照片的把参数随 enabled=false 带上（下次启用不用重填），没选过照片的按未配置传 null
      if (urls.isEmpty || urls.length > maxImgUrls) {
        return (value: null, error: '');
      }
      final interval = _intervalGroup(l10n, card.beginTime, card.endTime, card.intervalMinutes);
      final fixed = _fixedGroup(l10n, card.updateTimeList);
      return (value: {'enabled': false, 'mode': mode, ...?interval.value, ...?fixed.value, 'imgUrls': urls}, error: '');
    }
    if (card.kind == WifiCardKind.anniversary && !isMonthDay(card.monthDay)) {
      return (value: null, error: l10n.wifiSlideAnnivNeedDate);
    }
    final groups = _bothGroups(
      l10n,
      updateType,
      beginTime: card.beginTime,
      endTime: card.endTime,
      intervalMinutes: card.intervalMinutes,
      updateTimeList: card.updateTimeList,
    );
    if (groups.value == null) {
      return (value: null, error: l10n.wifiSlideCardError(name, groups.error));
    }
    final photos = _photoError(l10n, urls);
    if (photos.isNotEmpty) {
      return (value: null, error: l10n.wifiSlideCardError(name, photos));
    }
    final value = {...groups.value!, 'mode': mode, 'imgUrls': urls};
    if (card.kind == WifiCardKind.anniversary) {
      return (value: {'monthDay': card.monthDay, ...value}, error: '');
    }
    return (value: {'enabled': true, ...value}, error: '');
  }

  /// 表单 + 已选 + 高级卡片 → POST /api/device/strategy 的 body。返回 payload 或 error（给用户看的文案）。
  /// [albumUrls] 传相册里可选的全部照片（网格顺序），用来判断「全部相册」。
  /// 简单模式关闭时基础字段、基础 mode / imgUrls 一律不带，此时至少要启用一张高级卡片。
  static ({Map<String, Object?>? payload, String error}) buildPayload(
    AppL10n l10n,
    String deviceNo,
    WifiStrategyForm form,
    List<String> selected,
    List<String> albumUrls,
    WifiAdvanced advanced,
  ) {
    final updateType = form.updateType == updateFixed ? updateFixed : updateInterval;
    if (!WifiTimeZones.isIana(form.timeZone)) {
      return (payload: null, error: l10n.wifiSlideNeedTimeZone);
    }
    if (!hasAnyConfig(form, advanced)) {
      return (payload: null, error: l10n.wifiSlideNeedAnyConfig);
    }
    final payload = <String, Object?>{'deviceNo': deviceNo, 'updateType': updateType, 'timeZone': form.timeZone};
    if (form.simpleEnabled) {
      final daysOk = isUpdateDays(form.updateDays);
      if (updateType == updateFixed && !daysOk) {
        return (payload: null, error: l10n.wifiSlideDaysRange(maxUpdateDays));
      }
      final groups = _bothGroups(
        l10n,
        updateType,
        beginTime: form.beginTime,
        endTime: form.endTime,
        intervalMinutes: form.intervalMinutes,
        updateTimeList: form.updateTimeList,
      );
      if (groups.value == null) {
        return (payload: null, error: groups.error);
      }
      final value = Map<String, Object?>.of(groups.value!);
      // updateDays 只跟着 updateTimeList 走；天数不合法时固定那组整组不带（间隔模式下）
      if (value['updateTimeList'] != null && daysOk) {
        value['updateDays'] = form.updateDays;
      } else {
        value.remove('updateTimeList');
      }
      final urls = selected.where((url) => url.isNotEmpty).toList();
      final photos = _photoError(l10n, urls);
      if (photos.isNotEmpty) {
        return (payload: null, error: photos);
      }
      payload
        ..['mode'] = form.mode == 2 ? 2 : 1
        ..addAll(value);
      if (!isWholeAlbum(urls, albumUrls)) {
        payload['imgUrls'] = urls;
      }
    }
    final weekday = cardPayload(l10n, advanced.weekday, updateType);
    if (weekday.error.isNotEmpty) {
      return (payload: null, error: weekday.error);
    }
    final weekend = cardPayload(l10n, advanced.weekend, updateType);
    if (weekend.error.isNotEmpty) {
      return (payload: null, error: weekend.error);
    }
    final anniversaries = <Map<String, Object?>>[];
    final seen = <String>{};
    for (final card in advanced.anniversaries) {
      if (!seen.add(card.monthDay)) {
        return (payload: null, error: l10n.wifiSlideAnnivDuplicate(monthDayLabel(l10n, card.monthDay)));
      }
      final built = cardPayload(l10n, card, updateType);
      final value = built.value;
      if (built.error.isNotEmpty || value == null) {
        return (payload: null, error: built.error);
      }
      anniversaries.add(value);
    }
    payload
      ..['weekday'] = weekday.value
      ..['weekend'] = weekend.value
      ..['anniversaries'] = anniversaries;
    return (payload: payload, error: '');
  }

  /// 时间文案：yyyy-MM-dd HH:mm:ss → 'MM-dd HH:mm'（[short]）或 'yyyy-MM-dd HH:mm'；认不出原样返回，空返回 ''。
  static String timeText(Object? value, {bool short = false}) {
    final text = '${value ?? ''}'.trim();
    if (text.isEmpty || text == 'null') {
      return '';
    }
    final m = RegExp(r'^(\d{4})-(\d{2}-\d{2})[ T](\d{2}:\d{2})').firstMatch(text);
    if (m == null) {
      return text;
    }
    return short ? '${m.group(2)} ${m.group(3)}' : '${m.group(1)}-${m.group(2)} ${m.group(3)}';
  }

  /// 「下次刷新」后面的卡片类型（20261105-1 第 5 条 / 3.3）。base 按当前轮播方式：
  /// 间隔取 intervalMinutes「每 N 分钟 / 每 N 小时」，固定取 updateDays「每天 / 每 N 天」；对应字段为 null 不带后缀。
  static String nextRefreshCardText(AppL10n l10n, Map<String, dynamic>? config) {
    final c = config ?? const <String, dynamic>{};
    switch ('${c['nextRefreshCardType'] ?? ''}') {
      case 'weekday':
        return l10n.wifiSlideWeekday;
      case 'weekend':
        return l10n.wifiSlideWeekend;
      case 'anniversary':
        return l10n.wifiSlideAnniversary;
      case 'base':
        break;
      default:
        return '';
    }
    if (_typeOf(c) == updateFixed) {
      final days = num.tryParse('${c['updateDays']}');
      if (days == null || days < 1) {
        return '';
      }
      return days == 1 ? l10n.wifiSlideEveryDay : l10n.wifiSlideEveryNDays(days.floor());
    }
    final minutes = num.tryParse('${c['intervalMinutes']}');
    if (minutes == null || minutes <= 0) {
      return '';
    }
    final value = minutes.floor();
    return value >= 60 && value % 60 == 0 ? l10n.wifiSlideEveryNHours(value ~/ 60) : l10n.wifiSlideEveryNMinutes(value);
  }

  /// 「下次刷新：11-06 08:00 · 工作日」冒号后的部分；nextRefreshAt 为 null 返回 ''（整行不显示）。
  static String nextRefreshLine(AppL10n l10n, Map<String, dynamic>? config) {
    final time = timeText(config?['nextRefreshAt'], short: true);
    if (time.isEmpty) {
      return '';
    }
    final card = nextRefreshCardText(l10n, config);
    return card.isNotEmpty ? '$time · $card' : time;
  }

  /// 保存失败的提示：4000（参数错误，含超过 100 张）给明确文案，其余返回空串由页面按通用错误处理。
  static String saveErrorText(AppL10n l10n, Object error, Map<String, Object?> payload) {
    if (error is! IotException || error.numericCode != 4000) {
      return '';
    }
    final urls = payload['imgUrls'];
    final count = urls is List ? urls.length : 0;
    if (count >= maxImgUrls) {
      return l10n.wifiSlideSaveOverLimit(maxImgUrls);
    }
    final server = error.serverMessage.trim();
    return server.isNotEmpty ? l10n.wifiSaveFailedWith(server) : l10n.wifiSlideSaveInvalid;
  }
}
