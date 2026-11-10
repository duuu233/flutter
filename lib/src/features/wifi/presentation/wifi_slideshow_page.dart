import 'package:flutter/material.dart';

import '../../../device/serial_match.dart';
import '../../../network/iot/iot_api.dart';
import '../../../network/iot/iot_client.dart';
import '../../../shared/l10n/app_l10n.dart';
import '../../../shared/widgets/app_dialog.dart';
import '../../../shared/widgets/app_toast.dart';
import '../../../shared/widgets/figma_common.dart';
import '../../../shared/widgets/home_figma_common.dart';
import '../../../state.dart';
import '../wifi_l10n.dart';
import '../wifi_status.dart';
import '../wifi_strategy.dart';
import '../wifi_time_zone.dart';
import '../wifi_widgets.dart';
import 'wifi_slideshow_sheets.dart';

/// WiFi 版轮播设置，同步小程序 `subpackages/device/wifi-slideshow`（2026-10-27 起；2026-11-05 按对接文档 20261105 / 20261105-1
/// 改为服务端按配置定时推图）。入口：我的设备 WiFi 卡、WiFi 设备详情的「轮播设置」。蓝牙版仍走 [CarouselSettingsPage]，互不影响。
///   · 回显：IoT GET /api/device/strategy（只要权限，离线也能查），含 timeZone、nextRefreshAt（「下次刷新」只读一行，带卡片类型）、
///     weekday / weekend / anniversaries 高级卡片；
///   · 状态卡：轮播状态、「设置时间：yyyy-MM-dd HH:mm」、「下次刷新：MM-dd HH:mm · 卡片类型」、轮播方式（间隔 / 固定，切换不清空另一方，
///     简单模式与高级卡片共用）、时区（默认服务端回传值，没有按手机时区推断，见 [WifiTimeZones.detect]；弹层可搜索，按语种显示「国家 / 城市」）；
///   · 简单模式卡片（20261105-1）：启用开关（默认启用，关闭不提交基础字段），间隔（开始 / 结束，结束可选 24:00；间隔 10 分钟起）/
///     固定（每 N 天 1~30 + 时间点；存量 > 30 提示调整）、轮播照片（弹层选）、顺序 / 随机；「轮播后休眠」已去掉（idle 废弃）；
///     工作日 / 周末启用时出三档提示（纯文字）；
///   · 高级设置：同页展开 / 收起，进页一律收起、不持久化；工作日 / 周末（启用开关）、纪念日（可多条、只选月日、2 月最多 28 日、
///     日期不可重复、当天独占），每张卡片独立的时间、图片组、顺序；
///   · 选图：「我的相册」里这台设备的照片（老服务投屏成功记录，只取带 imgBle 的；有完整设备 ID 时带 deviceId 按设备查，
///     每页 21 张按页取完），统一用底部弹层（[pickWifiSlidePhotos]：每行 3 张、每页 21 张、滑到底显示下一页），按选择顺序提交；
///     简单模式默认不选（2026-11-06），已保存的 imgUrls=null（全部相册）回显全选、按相册顺序全选时不带 imgUrls；
///     卡片的图片组一律明确提交；最多 100 张；开启轮播必须至少选一张（简单模式与每张启用的卡片）；
///   · 保存：简单模式或任一高级卡片启用才能保存（否则按钮置灰、点了提示「至少配置一项」）；IoT POST /api/device/strategy，
///     要求设备在线（4041 时补查是休眠 / 关机 / 离线给对应提示）；下发后设备会立刻自动刷屏，**不再额外投第一张**；
///     保存成功后重新拉一次配置（时区、下次刷新、卡片以服务端为准）；未保存的编辑只在本页有效；
///   · 正在轮播时可「暂停轮播」（POST /api/device/strategy/stop）。
/// 换算、校验、卡片与选图顺序见 [WifiStrategy]。
class WifiSlideshowPage extends StatefulWidget {
  const WifiSlideshowPage({super.key, required this.state, required this.deviceId});

  final PhotoFrameState state;
  final String deviceId;

  @override
  State<WifiSlideshowPage> createState() => _WifiSlideshowPageState();
}

/// 高级卡片的定位：工作日 / 周末 / 第几张纪念日。
typedef _CardRef = ({WifiCardKind kind, int index});

class _WifiSlideshowPageState extends State<WifiSlideshowPage> {
  static const TextStyle _titleStyle = TextStyle(color: Color(0xFF25282D), fontSize: 15, fontWeight: FontWeight.w700);
  static const TextStyle _subStyle = TextStyle(color: Color(0xFF8A9099), fontSize: 12, height: 1.5);
  static const TextStyle _hintStyle = TextStyle(color: Color(0xFFE5533D), fontSize: 12, height: 1.5);

  bool _loading = true;
  bool _running = false;
  bool _configured = false;
  String _updatedAt = '';
  String _nextRefresh = '';
  WifiStrategyForm _form = WifiStrategy.defaultForm;
  WifiAdvanced _advanced = WifiAdvanced.empty;
  bool _advancedOpen = false;
  List<WifiSlideTile> _tiles = const [];
  List<String> _selected = <String>[];
  String _selectionHint = '';
  bool _photosError = false;
  bool _saving = false;
  bool _stopping = false;

  DeviceItem get _device => widget.state.deviceById(widget.deviceId);

  String get _deviceNo => IotApi.plainDeviceNo(_device.serialNumber);

  List<String> get _albumUrls => [for (final tile in _tiles) tile.url];

  bool get _canSave => WifiStrategy.hasAnyConfig(_form, _advanced);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  /// 轮播配置 + 相册照片（两者并发），各自失败分别兜底。
  Future<void> _load() async {
    setState(() {
      _loading = true;
      _advancedOpen = false;
    });
    // 选图列表：有设备完整 6 字节 ID 就带 deviceId，后端按设备查（这台设备上所有人上传的都能查到）；没有不带，仍按用户查
    final serial = canonicalDeviceSerial(_device.serialNumber);
    debugPrint('[轮播选图] ${serial.isNotEmpty ? '已传 deviceId=$serial，按设备查' : '未传 deviceId（设备没有完整 6 字节 ID），按用户查'}');
    final results = await Future.wait<Object?>([
      IotApi.getStrategy(_deviceNo).then<Object?>((value) => value).catchError((Object error) {
        debugPrint('[WiFi轮播] 查询轮播配置失败 $error');
        return null;
      }),
      widget.state
          .fetchSuccessCastRecords(widget.deviceId, deviceId: serial.isNotEmpty ? serial : null)
          .then<Object?>((value) => value)
          .catchError((Object error) {
            debugPrint('[轮播选图] 拉我的相册失败 $error');
            return null;
          }),
    ]);
    if (!mounted) return;
    final config = results[0] as Map<String, dynamic>?;
    final records = results[1] as List<CastRecord>?;
    // 只有带 imgBle 的记录能进轮播（设备拉的就是它）；同一个 imgBle 只留第一条
    final tiles = <WifiSlideTile>[];
    for (final record in records ?? const <CastRecord>[]) {
      final url = record.imgBle ?? '';
      if (record.status == CastStatus.success && url.isNotEmpty && !tiles.any((tile) => tile.url == url)) {
        tiles.add(WifiSlideTile(id: record.id, url: url, thumb: record.thumbUrl ?? record.imageUrl ?? ''));
      }
    }
    if (records != null) {
      debugPrint('[轮播选图] 返回 ${records.length} 条记录，可轮播（投屏成功且带 imgBle、去重后）${tiles.length} 张');
    }
    _tiles = tiles;
    _photosError = records == null;
    _applyConfig(config);
    setState(() => _loading = false);
  }

  /// 服务端配置 → 页面（进页与保存成功后共用）：未保存的草稿一律丢弃，以服务端为准。查询失败（null）用默认值并提示。
  void _applyConfig(Map<String, dynamic>? config) {
    debugPrint('[WiFi轮播] 当前配置 $config');
    final l10n = AppL10n.of(context);
    final urls = _albumUrls;
    final picked = WifiStrategy.selectionFromStrategy(l10n, config, urls);
    setState(() {
      _selected = picked.selected;
      _advanced = WifiStrategy.advancedFromStrategy(l10n, config, urls);
      _form = WifiStrategy.formFromStrategy(config, WifiTimeZones.detect());
      _configured = config?['configured'] == true;
      _running = config?['running'] == true;
      _updatedAt = WifiStrategy.timeText(config?['updatedAt']);
      _nextRefresh = WifiStrategy.nextRefreshLine(l10n, config);
      _selectionHint = config != null ? picked.hint : l10n.wifiSlideQueryFailed;
    });
  }

  Future<String> _errorTip(AppL10n l10n, Object error, String fallback) async {
    if (error is IotException) {
      return error.numericCode == 4041 ? wifiOfflineTipFor(l10n, _deviceNo) : error.message;
    }
    return fallback;
  }

  Future<void> _save() async {
    if (_saving) return;
    final l10n = AppL10n.of(context);
    if (!_canSave) {
      AppToast.warn(context, l10n.wifiSlideNeedAnyConfig);
      return;
    }
    final built = WifiStrategy.buildPayload(l10n, _deviceNo, _form, _selected, _albumUrls, _advanced);
    final payload = built.payload;
    if (payload == null) {
      AppToast.warn(context, built.error);
      return;
    }
    debugPrint('[WiFi轮播] 保存 $payload');
    setState(() => _saving = true);
    // 保存前判断设备状态（2026-10-29 同小程序）：本地模式 / 离线 / 休眠 / 关机直接提示，不发请求；查不到交给接口裁决
    final blocked = await wifiQueryBlockedTip(l10n, _deviceNo);
    if (!mounted) return;
    if (blocked.isNotEmpty) {
      setState(() => _saving = false);
      AppToast.warn(context, blocked);
      return;
    }
    try {
      await IotApi.setStrategy(payload);
    } catch (error) {
      debugPrint('[WiFi轮播] 保存失败 $error');
      final special = WifiStrategy.saveErrorText(l10n, error, payload);
      final tip = special.isNotEmpty ? special : await _errorTip(l10n, error, l10n.wifiSaveFailed);
      if (mounted) {
        setState(() => _saving = false);
        AppToast.warn(context, tip);
      }
      return;
    }
    if (!mounted) return;
    // 下发轮播后设备会立刻自动刷屏，不再额外投第一张（2026-11-05）
    final urls = payload['imgUrls'];
    final saved = !_form.simpleEnabled
        ? l10n.wifiSlideSaved
        : (urls is List ? l10n.wifiSlideSavedSome(urls.length) : l10n.wifiSlideSavedAll);
    setState(() {
      _running = true;
      _configured = true;
      _selectionHint = '';
    });
    AppToast.show(context, l10n.wifiSlideSavedRefresh(saved));
    // 保存成功后重新拉一次：时区、下次刷新时间、卡片都以服务端回传为准；拉不到保留本地
    try {
      final config = await IotApi.getStrategy(_deviceNo);
      if (mounted) {
        _applyConfig(config);
      }
    } catch (error) {
      debugPrint('[WiFi轮播] 保存后查询配置失败 $error');
    }
    if (mounted) {
      setState(() => _saving = false);
    }
  }

  Future<void> _stop() async {
    if (_stopping) return;
    final l10n = AppL10n.of(context);
    setState(() => _stopping = true);
    try {
      await IotApi.stopStrategy(_deviceNo);
    } catch (error) {
      debugPrint('[WiFi轮播] 暂停失败 $error');
      final tip = await _errorTip(l10n, error, l10n.wifiSlideStopFailed);
      if (mounted) {
        setState(() => _stopping = false);
        AppToast.warn(context, tip);
      }
      return;
    }
    if (mounted) {
      setState(() {
        _stopping = false;
        _running = false;
        _nextRefresh = '';
      });
      AppToast.show(context, l10n.wifiSlideStopped);
    }
  }

  // ── 卡片读写 ─────────────────────────────────────────

  WifiStrategyCard? _card(_CardRef ref) => switch (ref.kind) {
    WifiCardKind.weekday => _advanced.weekday,
    WifiCardKind.weekend => _advanced.weekend,
    WifiCardKind.anniversary =>
      ref.index >= 0 && ref.index < _advanced.anniversaries.length ? _advanced.anniversaries[ref.index] : null,
  };

  void _patchCard(_CardRef ref, WifiStrategyCard Function(WifiStrategyCard card) patch) {
    final card = _card(ref);
    if (card == null) {
      return;
    }
    setState(() {
      _advanced = switch (ref.kind) {
        WifiCardKind.weekday => _advanced.copyWith(weekday: patch(card)),
        WifiCardKind.weekend => _advanced.copyWith(weekend: patch(card)),
        WifiCardKind.anniversary => _advanced.copyWith(
          anniversaries: [
            for (var i = 0; i < _advanced.anniversaries.length; i++)
              i == ref.index ? patch(card) : _advanced.anniversaries[i],
          ],
        ),
      };
    });
  }

  // ── 选择器 ─────────────────────────────────────────

  /// 往时间点列表里加一个：重复 / 超上限给提示，返回新列表或 null。
  Future<List<String>?> _appendTime(List<String> list) async {
    final l10n = AppL10n.of(context);
    final value = await pickWifiTime(context, '12:00');
    if (value == null || !mounted) return null;
    if (list.contains(value)) {
      AppToast.warn(context, l10n.wifiSlideTimeExists);
      return null;
    }
    if (list.length >= WifiStrategy.maxTimePoints) {
      AppToast.warn(context, l10n.wifiSlideTimeMax(WifiStrategy.maxTimePoints));
      return null;
    }
    return WifiStrategy.normalizeTimes([...list, value]);
  }

  /// 结束时间：两列（时 00~24 / 分），选 24 时一律 24:00。
  Future<String?> _pickEndTime(String current) async {
    final index = await pickWifiColumns(
      context,
      initial: WifiStrategy.endTimeIndex(current),
      columnsOf: (_) => [WifiStrategy.endHourLabels, WifiStrategy.minuteLabels],
    );
    return index == null ? null : WifiStrategy.endTimeFromIndex(index[0], index[1]);
  }

  Future<int?> _pickInterval(AppL10n l10n, int minutes) async {
    final labels = [for (final m in WifiStrategy.intervalOptions) WifiStrategy.intervalLabel(l10n, m)];
    final index = await pickWifiOption(context, labels, WifiStrategy.intervalIndexOf(minutes));
    return index == null ? null : WifiStrategy.intervalOptions[index];
  }

  Future<void> _pickTimeZone() async {
    final id = await pickWifiTimeZone(context, _form.timeZone);
    if (id != null && id.isNotEmpty && mounted) {
      setState(() => _form = _form.copyWith(timeZone: id));
    }
  }

  /// 纪念日日期选择器（月 / 日两列，不选年）：日这一列随月份变（2 月 28 天，4 / 6 / 9 / 11 月 30 天）；与其他纪念日重复时拦下。
  Future<void> _pickAnnivDate(int index) async {
    final l10n = AppL10n.of(context);
    final card = _card((kind: WifiCardKind.anniversary, index: index));
    if (card == null) return;
    final md = card.monthDay;
    final initial = WifiStrategy.isMonthDay(md)
        ? [int.parse(md.substring(0, 2)) - 1, int.parse(md.substring(3, 5)) - 1]
        : [0, 0];
    final picked = await pickWifiColumns(
      context,
      initial: initial,
      columnsOf: (selected) => [
        [for (var m = 1; m <= 12; m++) l10n.wifiSlideMonthLabel(m)],
        [for (var d = 1; d <= WifiStrategy.monthDays[selected[0].clamp(0, 11)]; d++) l10n.wifiSlideDayLabel(d)],
      ],
    );
    if (picked == null || !mounted) return;
    final monthDay = WifiStrategy.monthDayFromIndex(picked[0], picked[1]);
    final taken = [
      for (var i = 0; i < _advanced.anniversaries.length; i++)
        if (i != index) _advanced.anniversaries[i].monthDay,
    ].contains(monthDay);
    if (taken) {
      AppToast.warn(context, l10n.wifiSlideAnnivTaken);
      return;
    }
    _patchCard((kind: WifiCardKind.anniversary, index: index), (c) => c.copyWith(monthDay: monthDay));
  }

  void _addAnniversary() {
    final now = DateTime.now();
    final today = '${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final monthDay = WifiStrategy.nextFreeMonthDay([for (final card in _advanced.anniversaries) card.monthDay], today);
    if (monthDay.isEmpty) return;
    setState(() {
      _advanced = _advanced.copyWith(
        anniversaries: [..._advanced.anniversaries, WifiStrategyCard.initial(WifiCardKind.anniversary, monthDay: monthDay)],
      );
    });
  }

  Future<void> _removeAnniversary(int index) async {
    final l10n = AppL10n.of(context);
    final card = _card((kind: WifiCardKind.anniversary, index: index));
    if (card == null) return;
    final ok = await showAppConfirmDialog(
      context,
      title: l10n.wifiSlideDeleteAnnivTitle,
      message: l10n.wifiSlideDeleteAnnivMessage(WifiStrategy.monthDayLabel(l10n, card.monthDay)),
      icon: Icons.delete_outline_rounded,
      confirmLabel: l10n.wifiSlideDelete,
    );
    if (ok != true || !mounted) return;
    setState(() {
      _advanced = _advanced.copyWith(
        anniversaries: [
          for (var i = 0; i < _advanced.anniversaries.length; i++)
            if (i != index) _advanced.anniversaries[i],
        ],
      );
    });
  }

  /// 打开选图弹层；确定后由 [apply] 写回。
  Future<void> _openPhotos(String title, List<String> selected, void Function(List<String> picked) apply) async {
    final l10n = AppL10n.of(context);
    if (_tiles.isEmpty) {
      AppToast.show(context, _photosError ? l10n.wifiSlidePhotosFailed : l10n.wifiSlidePhotosEmpty);
      return;
    }
    final picked = await pickWifiSlidePhotos(
      context,
      title: l10n.wifiSlideSheetTitle(title),
      tiles: _tiles,
      selected: selected,
    );
    if (picked != null && mounted) {
      apply(picked);
    }
  }

  // ── 视图 ─────────────────────────────────────────

  Widget _chip(String text, VoidCallback onTap, {bool accent = false}) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: accent ? const Color(0x1AFF6A20) : Colors.white.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          text,
          style: TextStyle(color: accent ? const Color(0xFFFF6A20) : const Color(0xFF2A2D32), fontSize: 13),
        ),
      ),
    );
  }

  Widget _timesRow(AppL10n l10n, List<String> times, ValueChanged<List<String>> onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.wifiSlidePlayTime, style: const TextStyle(color: Color(0xFF33373D), fontSize: 14)),
          const SizedBox(width: 16),
          Expanded(
            child: Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final time in times) _chip('$time ×', () => onChanged(times.where((item) => item != time).toList())),
                _chip(l10n.wifiSlideAddTime, () async {
                  final next = await _appendTime(times);
                  if (next != null && mounted) {
                    onChanged(next);
                  }
                }, accent: true),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _orderSegment(AppL10n l10n, int mode, ValueChanged<int> onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 10),
        Text(l10n.wifiSlideOrder, style: _titleStyle),
        const SizedBox(height: 10),
        WifiSegment<int>(
          value: mode,
          items: [(1, l10n.wifiSlideSequential), (2, l10n.wifiSlideRandom)],
          onChanged: onChanged,
        ),
      ],
    );
  }

  Widget _photosRow(AppL10n l10n, int count, VoidCallback onTap) => WifiFormRow(
    label: l10n.wifiSlidePhotos,
    value: count > 0 ? l10n.wifiSlidePickedCount(count) : l10n.wifiSlidePickPhotos,
    onTap: onTap,
  );

  Widget _buildStateCard(AppL10n l10n) {
    final stateText = _running
        ? l10n.wifiSlideRunning
        : _configured
        ? l10n.wifiSlidePaused
        : l10n.wifiSlideNotSet;
    return FigmaGlassCard(
      borderRadius: 16,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(l10n.wifiSlideState, style: _titleStyle),
              const Spacer(),
              Text(stateText, style: TextStyle(color: _running ? kWifiGreen : const Color(0xFF8B9098), fontSize: 13)),
            ],
          ),
          // 「设置时间：」与「下次刷新：」同一格式（20261105-1 第 4 条）；下次刷新带卡片类型，nextRefreshAt 为空整行不显示
          if (_updatedAt.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(l10n.wifiSlideSetAt(_updatedAt), style: _subStyle),
          ],
          if (_running && _nextRefresh.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(l10n.wifiSlideNextRefresh(_nextRefresh), style: _subStyle.copyWith(color: kWifiGreen)),
          ],
          const SizedBox(height: 16),
          Text(l10n.wifiSlideMode, style: _titleStyle),
          const SizedBox(height: 10),
          WifiSegment<int>(
            value: _form.updateType,
            items: [
              (WifiStrategy.updateInterval, l10n.wifiSlideInterval),
              (WifiStrategy.updateFixed, l10n.wifiSlideFixed),
            ],
            onChanged: (value) => setState(() => _form = _form.copyWith(updateType: value)),
          ),
          WifiFormRow(
            label: l10n.wifiSlideTimeZone,
            value: WifiTimeZones.label(_form.timeZone, l10n.language),
            onTap: _pickTimeZone,
          ),
        ],
      ),
    );
  }

  Widget _switchHead(String title, bool value, ValueChanged<bool> onChanged) {
    return SizedBox(
      height: 32,
      child: Row(
        children: [
          Text(title, style: _titleStyle),
          const Spacer(),
          Switch(value: value, activeTrackColor: const Color(0xFFFF6A20), onChanged: onChanged),
        ],
      ),
    );
  }

  /// 简单模式（20261105-1 第 9 条）：原基础配置做成卡片，带启用开关，默认启用并展开；关闭后基础字段不提交。
  Widget _buildSimpleCard(AppL10n l10n) {
    final baseHint = WifiStrategy.baseHint(l10n, _advanced);
    final daysHint = WifiStrategy.daysOverHint(l10n, _form);
    final interval = _form.updateType == WifiStrategy.updateInterval;
    return FigmaGlassCard(
      borderRadius: 16,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _switchHead(
            l10n.wifiSlideSimple,
            _form.simpleEnabled,
            (value) => setState(() => _form = _form.copyWith(simpleEnabled: value)),
          ),
          if (!_form.simpleEnabled) ...[
            const SizedBox(height: 6),
            Text(l10n.wifiSlideSimpleOff, style: _subStyle),
          ] else ...[
            // 工作日 / 周末启用了独立配置时的提示（纯文字，不阻断保存）
            if (baseHint.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(baseHint, style: _subStyle.copyWith(color: const Color(0xFFFF6A20))),
            ],
            if (interval) ...[
              WifiFormRow(
                label: l10n.wifiSlideBegin,
                value: _form.beginTime,
                onTap: () async {
                  final value = await pickWifiTime(context, _form.beginTime);
                  if (value != null && mounted) setState(() => _form = _form.copyWith(beginTime: value));
                },
              ),
              WifiFormRow(
                label: l10n.wifiSlideEnd,
                value: _form.endTime,
                onTap: () async {
                  final value = await _pickEndTime(_form.endTime);
                  if (value != null && mounted) setState(() => _form = _form.copyWith(endTime: value));
                },
              ),
              WifiFormRow(
                label: l10n.wifiSlideEvery,
                value: l10n.wifiSlideEveryValue(WifiStrategy.intervalLabel(l10n, _form.intervalMinutes)),
                onTap: () async {
                  final value = await _pickInterval(l10n, _form.intervalMinutes);
                  if (value != null && mounted) setState(() => _form = _form.copyWith(intervalMinutes: value));
                },
              ),
            ] else ...[
              // 每 N 天 1~30（20261105-1 第 6 条）；存量 > 30 原值显示并提示调整
              WifiFormRow(
                label: l10n.wifiSlidePlayFreq,
                value: _form.updateDays == 1 ? l10n.wifiSlideEveryDay : l10n.wifiSlideEveryNDays(_form.updateDays),
                onTap: () async {
                  final options = [
                    for (var d = 1; d <= WifiStrategy.maxUpdateDays; d++)
                      d == 1 ? l10n.wifiSlideEveryDay : l10n.wifiSlideEveryNDays(d),
                  ];
                  final index = await pickWifiOption(context, options, (_form.updateDays - 1).clamp(0, options.length - 1));
                  if (index != null && mounted) setState(() => _form = _form.copyWith(updateDays: index + 1));
                },
              ),
              if (daysHint.isNotEmpty) Text(daysHint, style: _hintStyle),
              _timesRow(
                l10n,
                _form.updateTimeList,
                (next) => setState(() => _form = _form.copyWith(updateTimeList: next)),
              ),
            ],
            // 轮播照片（20261105-1 第 1 条）：不再在页面里铺开，与高级卡片同一个选图弹层
            _photosRow(
              l10n,
              _selected.length,
              () => _openPhotos(l10n.wifiSlideSimple, _selected, (picked) {
                setState(() {
                  _selected = picked;
                  _selectionHint = '';
                });
              }),
            ),
            if (_photosError)
              Text(l10n.wifiSlidePhotosFailed, style: _hintStyle)
            else if (_tiles.isEmpty)
              Text(l10n.wifiSlidePhotosEmpty, style: _hintStyle),
            if (_selectionHint.isNotEmpty) Text(_selectionHint, style: _hintStyle),
            _orderSegment(l10n, _form.mode, (value) => setState(() => _form = _form.copyWith(mode: value))),
          ],
        ],
      ),
    );
  }

  /// 高级卡片的时间 / 照片 / 顺序：时间参数跟随上面的轮播方式（间隔 / 固定），两组都保留。
  Widget _cardBody(AppL10n l10n, _CardRef ref, WifiStrategyCard card) {
    final interval = _form.updateType == WifiStrategy.updateInterval;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (interval) ...[
          WifiFormRow(
            label: l10n.wifiSlideBegin,
            value: card.beginTime,
            onTap: () async {
              final value = await pickWifiTime(context, card.beginTime);
              if (value != null && mounted) _patchCard(ref, (c) => c.copyWith(beginTime: value));
            },
          ),
          WifiFormRow(
            label: l10n.wifiSlideEnd,
            value: card.endTime,
            onTap: () async {
              final value = await _pickEndTime(card.endTime);
              if (value != null && mounted) _patchCard(ref, (c) => c.copyWith(endTime: value));
            },
          ),
          WifiFormRow(
            label: l10n.wifiSlideEvery,
            value: l10n.wifiSlideEveryValue(WifiStrategy.intervalLabel(l10n, card.intervalMinutes)),
            onTap: () async {
              final value = await _pickInterval(l10n, card.intervalMinutes);
              if (value != null && mounted) _patchCard(ref, (c) => c.copyWith(intervalMinutes: value));
            },
          ),
        ] else
          _timesRow(l10n, card.updateTimeList, (next) => _patchCard(ref, (c) => c.copyWith(updateTimeList: next))),
        _photosRow(
          l10n,
          card.selected.length,
          () => _openPhotos(
            WifiStrategy.cardTitle(l10n, card),
            card.selected,
            (picked) => _patchCard(ref, (c) => c.copyWith(selected: picked, hint: '')),
          ),
        ),
        if (card.hint.isNotEmpty) Text(card.hint, style: _hintStyle),
        _orderSegment(l10n, card.mode, (value) => _patchCard(ref, (c) => c.copyWith(mode: value))),
      ],
    );
  }

  Widget _buildToggleCard(AppL10n l10n, WifiCardKind kind) {
    final _CardRef ref = (kind: kind, index: 0);
    final card = kind == WifiCardKind.weekday ? _advanced.weekday : _advanced.weekend;
    return FigmaGlassCard(
      borderRadius: 16,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _switchHead(
            kind == WifiCardKind.weekday ? l10n.wifiSlideWeekday : l10n.wifiSlideWeekend,
            card.enabled,
            (value) => _patchCard(ref, (c) => c.copyWith(enabled: value)),
          ),
          const SizedBox(height: 4),
          Text(kind == WifiCardKind.weekday ? l10n.wifiSlideWeekdayDesc : l10n.wifiSlideWeekendDesc, style: _subStyle),
          if (card.enabled) _cardBody(l10n, ref, card),
        ],
      ),
    );
  }

  Widget _buildAnniversaryCard(AppL10n l10n) {
    return FigmaGlassCard(
      borderRadius: 16,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(l10n.wifiSlideAnniversary, style: _titleStyle),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(color: const Color(0x1AFF6A20), borderRadius: BorderRadius.circular(999)),
                child: Text(l10n.wifiSlideAnnivTag, style: const TextStyle(color: Color(0xFFFF6A20), fontSize: 11)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(l10n.wifiSlideAnnivDesc, style: _subStyle),
          for (var i = 0; i < _advanced.anniversaries.length; i++)
            Container(
              key: ValueKey('wifi-anniv-${_advanced.anniversaries[i].monthDay}'),
              margin: const EdgeInsets.only(top: 12),
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      // 只选月 / 日（20261105-1 第 7 条）：日这一列随月份变，2 月最多 28 日
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => _pickAnnivDate(i),
                        child: Text(
                          '${WifiStrategy.monthDayLabel(l10n, _advanced.anniversaries[i].monthDay)} ▾',
                          style: const TextStyle(color: Color(0xFF25282D), fontSize: 15, fontWeight: FontWeight.w600),
                        ),
                      ),
                      const Spacer(),
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => _removeAnniversary(i),
                        child: Text(l10n.wifiSlideDelete, style: const TextStyle(color: Color(0xFFE5533D), fontSize: 13)),
                      ),
                    ],
                  ),
                  _cardBody(l10n, (kind: WifiCardKind.anniversary, index: i), _advanced.anniversaries[i]),
                ],
              ),
            ),
          const SizedBox(height: 12),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _addAnniversary,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(l10n.wifiSlideAddAnniversary, style: const TextStyle(color: Color(0xFFFF6A20), fontSize: 14)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final count = WifiStrategy.advancedCount(_advanced);
    return FigmaScreen(
      title: l10n.wifiSlideshowSettings,
      body: _loading
          ? const Padding(padding: EdgeInsets.only(top: 120), child: Center(child: CircularProgressIndicator()))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 16),
                _buildStateCard(l10n),
                const SizedBox(height: 14),
                _buildSimpleCard(l10n),
                // 高级设置：同页展开 / 收起（进页默认收起、不持久化），收起时数据保留
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => setState(() => _advancedOpen = !_advancedOpen),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    child: Center(
                      child: Text(
                        _advancedOpen
                            ? '${l10n.wifiSlideAdvancedCollapse} ▴'
                            : '${count > 0 ? l10n.wifiSlideAdvancedCount(count) : l10n.wifiSlideAdvanced} ▾',
                        style: const TextStyle(color: Color(0xFFFF6A20), fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ),
                if (_advancedOpen) ...[
                  _buildToggleCard(l10n, WifiCardKind.weekday),
                  const SizedBox(height: 14),
                  _buildToggleCard(l10n, WifiCardKind.weekend),
                  const SizedBox(height: 14),
                  _buildAnniversaryCard(l10n),
                ],
                const SizedBox(height: 24),
              ],
            ),
      bottom: _loading
          ? null
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_running)
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _stop,
                    child: SizedBox(
                      height: 40,
                      child: Center(
                        child: Text(
                          _stopping ? l10n.wifiSlideStopping : l10n.wifiSlideStop,
                          style: const TextStyle(color: Color(0xFFFF621F), fontSize: 15),
                        ),
                      ),
                    ),
                  ),
                // 简单模式与高级卡片都没启用时置灰（20261105-1 第 8 条），点了提示「至少配置一项」
                Opacity(
                  opacity: _canSave ? 1 : 0.5,
                  child: FigmaHomePrimaryButton(
                    label: _saving ? l10n.wifiSaving : l10n.wifiSlideSaveStart,
                    fontWeight: FontWeight.w700,
                    onPressed: _saving ? null : _save,
                  ),
                ),
              ],
            ),
    );
  }
}
