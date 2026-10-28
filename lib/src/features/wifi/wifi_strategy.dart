import '../../network/iot/iot_client.dart';
import '../../shared/l10n/app_l10n.dart';
import 'wifi_l10n.dart';

/// WiFi 版轮播设置的表单（与接口字段的换算见 [WifiStrategy]）。
class WifiStrategyForm {
  const WifiStrategyForm({
    this.updateType = WifiStrategy.updateInterval,
    this.beginTime = '08:00',
    this.endTime = '22:00',
    this.intervalMinutes = 60,
    this.updateDays = 1,
    this.updateTimeList = const ['08:00'],
    this.mode = 1,
    this.idle = 1,
  });

  /// 2 = 间隔（beginTime / endTime + intervalMinutes），1 = 固定时间（updateDays + updateTimeList）。
  final int updateType;
  final String beginTime;
  final String endTime;
  final int intervalMinutes;
  final int updateDays;
  final List<String> updateTimeList;

  /// 1 顺序 / 2 随机。
  final int mode;

  /// 0 轮播后休眠 / 1 不休眠。
  final int idle;

  WifiStrategyForm copyWith({
    int? updateType,
    String? beginTime,
    String? endTime,
    int? intervalMinutes,
    int? updateDays,
    List<String>? updateTimeList,
    int? mode,
    int? idle,
  }) {
    return WifiStrategyForm(
      updateType: updateType ?? this.updateType,
      beginTime: beginTime ?? this.beginTime,
      endTime: endTime ?? this.endTime,
      intervalMinutes: intervalMinutes ?? this.intervalMinutes,
      updateDays: updateDays ?? this.updateDays,
      updateTimeList: updateTimeList ?? this.updateTimeList,
      mode: mode ?? this.mode,
      idle: idle ?? this.idle,
    );
  }
}

/// WiFi 版轮播设置的纯逻辑，同步小程序 `utils/wifi-strategy.js`（V1.4 更新说明 1.5 / 第五节、实现报告反馈六、
/// 反馈追加内容第一节）。页面 [WifiSlideshowPage] 只管交互，表单 ↔ 接口字段的换算、选图顺序都在这里。
///
/// 接口：GET /api/device/strategy 回显，POST /api/device/strategy 保存。
///   · updateType 2 = 间隔（beginTime / endTime HH:mm + timingTime 秒），1 = 固定时间（updateDays 1~365 + updateTimeList HH:mm[]）；
///   · mode 1 顺序 / 2 随机；idle 0 轮播后休眠 / 1 不休眠；
///   · imgUrls：「我的相册」里选中照片的 imgBle，按选择顺序，最多 100（原 200）；不传 = 轮播全部相册；
///     **不能传空数组**（服务端回 4000）：一张都没选时不让保存；
///     按相册顺序全选时不带 imgUrls（= 全部相册，之后新上传的照片也会进轮播）。
///   · 回显 imgUrls：null = 没选过（全部相册，页面上全选；相册超过 100 张只选前 100 张）；[] = 选过但照片都删了（提示重新选择）。
///   · 超过 100 张服务端回 4000：前端选满即拦截，保存时再挡一次，4000 给明确提示（[saveErrorText]）。
abstract final class WifiStrategy {
  static const int updateInterval = 2;
  static const int updateFixed = 1;
  static const int maxImgUrls = 100;
  static const int maxTimePoints = 24;

  /// 间隔可选档位（分钟）；服务端按分钟取整，最小 1 分钟。
  static const List<int> intervalOptions = [1, 5, 10, 15, 30, 60, 120, 180, 360, 720, 1440];
  static const WifiStrategyForm defaultForm = WifiStrategyForm();

  static bool isTime(Object? value) => RegExp(r'^([01]\d|2[0-3]):[0-5]\d$').hasMatch('${value ?? ''}');

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

  /// 最接近的间隔档位下标（回显用：服务端可能存了不在档位里的分钟数）。
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

  /// GET /api/device/strategy → 表单。没配置过（configured=false）用默认值。
  static WifiStrategyForm formFromStrategy(Map<String, dynamic>? strategy) {
    final s = strategy ?? const <String, dynamic>{};
    if (s['configured'] != true) {
      return defaultForm;
    }
    final updateType = num.tryParse('${s['updateType']}') == updateFixed ? updateFixed : updateInterval;
    final days = num.tryParse('${s['updateDays']}') ?? 0;
    final rawTimes = s['updateTimeList'];
    final times = normalizeTimes(rawTimes is List ? rawTimes : null);
    final timing = num.tryParse('${s['timingTime']}') ?? 0;
    final minutes = num.tryParse('${s['intervalMinutes']}') ?? (timing > 0 ? (timing / 60).ceil() : 0);
    return WifiStrategyForm(
      updateType: updateType,
      beginTime: isTime(s['beginTime']) ? '${s['beginTime']}' : defaultForm.beginTime,
      endTime: isTime(s['endTime']) ? '${s['endTime']}' : defaultForm.endTime,
      intervalMinutes: intervalOptions[intervalIndexOf(minutes)],
      updateDays: days >= 1 && days <= 365 ? days.floor() : defaultForm.updateDays,
      updateTimeList: times.isNotEmpty ? times : defaultForm.updateTimeList,
      mode: num.tryParse('${s['mode']}') == 2 ? 2 : 1,
      idle: num.tryParse('${s['idle']}') == 0 ? 0 : 1,
    );
  }

  /// 回显的 imgUrls 与当前相册对一下：只留相册里还在的、保持原顺序（截到上限）。
  /// imgUrls=null（没选过 = 全部相册）按相册顺序全选，超过上限只选前 [maxImgUrls] 张并说明；查询失败（strategy 为空）不选。
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
      if (albumUrls.length > maxImgUrls) {
        return (selected: albumUrls.sublist(0, maxImgUrls), hint: l10n.wifiSlideWholeAlbumOverLimit(maxImgUrls));
      }
      return (selected: List<String>.of(albumUrls), hint: '');
    }
    final urls = [for (final item in raw) '$item'];
    final selected = <String>[];
    for (final url in urls) {
      if (albumUrls.contains(url) && !selected.contains(url) && selected.length < maxImgUrls) {
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

  /// 表单 + 已选 → POST /api/device/strategy 的 body。返回 payload 或 error（给用户看的文案）。
  /// [albumUrls] 传相册里可选的全部照片（网格顺序），用来判断「全部相册」。
  static ({Map<String, Object?>? payload, String error}) buildPayload(
    AppL10n l10n,
    String deviceNo,
    WifiStrategyForm form,
    List<String> selected,
    List<String> albumUrls,
  ) {
    final payload = <String, Object?>{
      'deviceNo': deviceNo,
      'updateType': form.updateType == updateFixed ? updateFixed : updateInterval,
      'mode': form.mode == 2 ? 2 : 1,
      'idle': form.idle == 0 ? 0 : 1,
    };
    if (payload['updateType'] == updateInterval) {
      if (!isTime(form.beginTime) || !isTime(form.endTime)) {
        return (payload: null, error: l10n.wifiSlideNeedTimes);
      }
      if (form.intervalMinutes < 1) {
        return (payload: null, error: l10n.wifiSlideNeedInterval);
      }
      payload['beginTime'] = form.beginTime;
      payload['endTime'] = form.endTime;
      payload['timingTime'] = form.intervalMinutes * 60;
    } else {
      if (form.updateDays < 1 || form.updateDays > 365) {
        return (payload: null, error: l10n.wifiSlideDaysRange);
      }
      final times = normalizeTimes(form.updateTimeList);
      if (times.isEmpty) {
        return (payload: null, error: l10n.wifiSlideNeedTimePoint);
      }
      payload['updateDays'] = form.updateDays;
      payload['updateTimeList'] = times;
    }
    final urls = selected.where((url) => url.isNotEmpty).toList();
    if (urls.isEmpty) {
      return (payload: null, error: l10n.wifiSlideNeedPhoto);
    }
    if (urls.length > maxImgUrls) {
      return (payload: null, error: l10n.wifiSlideOverLimit(maxImgUrls));
    }
    if (!isWholeAlbum(urls, albumUrls)) {
      payload['imgUrls'] = urls;
    }
    return (payload: payload, error: '');
  }

  /// 保存后立即播放的那张：选了照片取第一张选中的；全部相册取相册顺序第一张（实现报告反馈六）。
  static String firstImageUrl(Map<String, Object?> payload, List<String> albumUrls) {
    final urls = payload['imgUrls'];
    if (urls is List && urls.isNotEmpty) {
      return '${urls.first}';
    }
    return albumUrls.isNotEmpty ? albumUrls.first : '';
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
