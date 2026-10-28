import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../network/dithering_api.dart';
import '../../../network/iot/iot_api.dart';
import '../../../network/iot/iot_client.dart';
import '../../../shared/l10n/app_l10n.dart';
import '../../../shared/widgets/app_toast.dart';
import '../../../shared/widgets/figma_common.dart';
import '../../../shared/widgets/home_figma_common.dart';
import '../../../state.dart';
import '../../cast/recast_download.dart';
import '../wifi_l10n.dart';
import '../wifi_projection.dart';
import '../wifi_status.dart';
import '../wifi_strategy.dart';
import '../wifi_widgets.dart';

/// 选图网格的一格：url = 记录的 imgBle（设备拉的就是它），thumb 缩略图，img 原图（保存后立即投第一张用）。
class _Tile {
  const _Tile({required this.id, required this.url, required this.thumb, required this.img});

  final String id;
  final String url;
  final String thumb;
  final String img;
}

/// WiFi 版轮播设置，同步小程序 `subpackages/device/wifi-slideshow`（V1.4 更新说明 1.5 / 第五节、实现报告反馈六、
/// 反馈追加内容第一节）。入口：我的设备 WiFi 卡、WiFi 设备详情的「轮播设置」（取代原「刷新状态」）。蓝牙版仍走
/// [CarouselSettingsPage]，互不影响。
///   · 回显：IoT GET /api/device/strategy（只要权限，离线也能查）；
///   · 模式：间隔时间（开始 / 结束 HH:mm + 间隔）/ 固定时间（每 N 天 + 若干时间点）；顺序 / 随机；轮播后是否休眠；
///   · 选图：「我的相册」里这台设备的投屏成功记录（只取带 imgBle 的），单选 / 多选 / 全选，按选择顺序作为 imgUrls 提交；
///     回显 imgUrls=null（全部相册）时全选；一张不选不让保存（空数组会回 4000）；按相册顺序全选时不带 imgUrls，
///     保持「全部相册」（之后新上传的也进轮播）；最多 100 张：显示「已选 X/100」，选满后未选的置灰、点了提示，
///     已选的仍可取消；全选时相册超过 100 张只选前 100 张并提示；超过 100 张服务端回 4000，给明确提示；
///   · 保存：IoT POST /api/device/strategy，要求设备在线（4041 时补查是休眠 / 关机 / 离线给对应提示）；
///     轮播中改选图不用先暂停，直接保存；
///   · 保存成功后立即投第一张（选中的第一张；全部相册取相册第一张）：下载这张图 → POST /api/device/play refresh=true，
///     屏幕马上切过去，不等下一个轮播周期（服务端保存轮播只下发 strategy_bin、不自动播放）。这一张不写新的相册记录；
///   · 正在轮播时可「暂停轮播」（POST /api/device/strategy/stop）。
/// 换算与选图顺序见 [WifiStrategy]。
class WifiSlideshowPage extends StatefulWidget {
  const WifiSlideshowPage({super.key, required this.state, required this.deviceId});

  final PhotoFrameState state;
  final String deviceId;

  @override
  State<WifiSlideshowPage> createState() => _WifiSlideshowPageState();
}

class _WifiSlideshowPageState extends State<WifiSlideshowPage> {
  bool _loading = true;
  bool _running = false;
  bool _configured = false;
  String _updatedAt = '';
  WifiStrategyForm _form = WifiStrategy.defaultForm;
  List<_Tile> _tiles = const [];
  List<String> _selected = <String>[];
  String _selectionHint = '';
  bool _photosError = false;
  bool _saving = false;
  String _savingText = '';
  bool _stopping = false;

  DeviceItem get _device => widget.state.deviceById(widget.deviceId);

  String get _deviceNo => IotApi.plainDeviceNo(_device.serialNumber);

  List<String> get _albumUrls => [for (final tile in _tiles) tile.url];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  /// 轮播配置 + 相册照片（两者并发），各自失败分别兜底。
  Future<void> _load() async {
    final l10n = AppL10n.of(context);
    final results = await Future.wait<Object?>([
      IotApi.getStrategy(_deviceNo).then<Object?>((value) => value).catchError((Object error) {
        debugPrint('[WiFi轮播] 查询轮播配置失败 $error');
        return null;
      }),
      widget.state.fetchSuccessCastRecords(widget.deviceId).then<Object?>((value) => value).catchError((Object error) {
        debugPrint('[WiFi轮播] 拉我的相册失败 $error');
        return null;
      }),
    ]);
    if (!mounted) return;
    final config = results[0] as Map<String, dynamic>?;
    final records = results[1] as List<CastRecord>?;
    debugPrint('[WiFi轮播] 当前配置 $config');
    // 只有带 imgBle 的记录能进轮播（设备拉的就是它）；同一个 imgBle 只留第一条
    final tiles = <_Tile>[];
    for (final record in records ?? const <CastRecord>[]) {
      final url = record.imgBle ?? '';
      if (record.status == CastStatus.success && url.isNotEmpty && !tiles.any((tile) => tile.url == url)) {
        tiles.add(
          _Tile(
            id: record.id,
            url: url,
            thumb: record.thumbUrl ?? record.imageUrl ?? '',
            img: record.imageUrl ?? record.thumbUrl ?? '',
          ),
        );
      }
    }
    final albumUrls = [for (final tile in tiles) tile.url];
    final picked = WifiStrategy.selectionFromStrategy(l10n, config, albumUrls);
    setState(() {
      _tiles = tiles;
      _selected = picked.selected;
      _form = WifiStrategy.formFromStrategy(config);
      _configured = config?['configured'] == true;
      _running = config?['running'] == true;
      _updatedAt = '${config?['updatedAt'] ?? ''}';
      _selectionHint = config != null ? picked.hint : l10n.wifiSlideQueryFailed;
      _photosError = records == null;
      _loading = false;
    });
  }

  void _toggleTile(String url) {
    final next = WifiStrategy.toggleSelection(_selected, url);
    if (next.overflow) {
      AppToast.warn(context, AppL10n.of(context).wifiSlideFull(WifiStrategy.maxImgUrls));
      return;
    }
    setState(() => _selected = next.selected);
  }

  void _toggleAll() {
    final urls = _albumUrls;
    if (urls.isEmpty) return;
    setState(() => _selected = WifiStrategy.toggleAll(_selected, urls));
    if (urls.length > WifiStrategy.maxImgUrls && _selected.isNotEmpty) {
      AppToast.show(context, AppL10n.of(context).wifiSlideMax(WifiStrategy.maxImgUrls));
    }
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
    final albumUrls = _albumUrls;
    final built = WifiStrategy.buildPayload(l10n, _deviceNo, _form, _selected, albumUrls);
    final payload = built.payload;
    if (payload == null) {
      AppToast.warn(context, built.error);
      return;
    }
    debugPrint('[WiFi轮播] 保存 $payload');
    setState(() => _saving = true);
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
    setState(() {
      _running = true;
      _configured = true;
      _selectionHint = '';
    });
    final urls = payload['imgUrls'];
    final saved = urls is List ? l10n.wifiSlideSavedSome(urls.length) : l10n.wifiSlideSavedAll;
    final played = await _playFirst(l10n, WifiStrategy.firstImageUrl(payload, albumUrls));
    if (!mounted) return;
    setState(() => _saving = false);
    AppToast.show(context, played.isEmpty ? l10n.wifiSlideSavedPlaying(saved) : '$saved；$played');
  }

  /// 保存后立即投第一张：成功返回空串，失败返回给用户看的原因。
  Future<String> _playFirst(AppL10n l10n, String url) async {
    final matches = _tiles.where((tile) => tile.url == url);
    final tile = matches.isEmpty ? null : matches.first;
    if (tile == null || tile.img.isEmpty) {
      return l10n.wifiSlideFirstNoImage;
    }
    setState(() => _savingText = l10n.wifiSlideSwitching);
    String outcome;
    final filePath = await RecastDownload.toTempFile(tile.img);
    if (filePath == null) {
      outcome = l10n.wifiSlideFirstDownloadFailed;
    } else {
      final device = _device;
      final result = await WifiProjection.projectOne(
        l10n: l10n,
        deviceNo: _deviceNo,
        filePath: filePath,
        type: DitheringApi.typeForDevice(device.screenWidth, device.screenHeight),
        refresh: true,
        onStage: (_, _) {},
        isCancelled: () => !mounted,
      );
      outcome = result.status == 'SENT'
          ? ''
          : l10n.wifiSlideFirstFailed(result.message.isNotEmpty ? result.message : l10n.wifiCastStage('FAILED'));
    }
    if (mounted) {
      setState(() => _savingText = '');
    }
    return outcome;
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
      });
      AppToast.show(context, l10n.wifiSlideStopped);
    }
  }

  Future<void> _pickTime(String current, WifiStrategyForm Function(String value) apply) async {
    final value = await pickWifiTime(context, current);
    if (value != null && mounted) {
      setState(() => _form = apply(value));
    }
  }

  Future<void> _addTimePoint() async {
    final l10n = AppL10n.of(context);
    final value = await pickWifiTime(context, '12:00');
    if (value == null || !mounted) return;
    final list = _form.updateTimeList;
    if (list.contains(value)) {
      AppToast.warn(context, l10n.wifiSlideTimeExists);
      return;
    }
    if (list.length >= WifiStrategy.maxTimePoints) {
      AppToast.warn(context, l10n.wifiSlideTimeMax(WifiStrategy.maxTimePoints));
      return;
    }
    setState(() => _form = _form.copyWith(updateTimeList: WifiStrategy.normalizeTimes([...list, value])));
  }

  Widget _buildModeCard(AppL10n l10n) {
    const titleStyle = TextStyle(color: Color(0xFF25282D), fontSize: 15, fontWeight: FontWeight.w700);
    final intervalLabels = [for (final m in WifiStrategy.intervalOptions) WifiStrategy.intervalLabel(l10n, m)];
    final intervalIndex = WifiStrategy.intervalIndexOf(_form.intervalMinutes);
    final stateText = _running
        ? l10n.wifiSlideRunning
        : _configured
        ? l10n.wifiSlidePaused
        : l10n.wifiSlideNotSet;
    return FigmaGlassCard(
      borderRadius: 16,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(l10n.wifiSlideState, style: titleStyle),
              const Spacer(),
              Text(
                stateText,
                style: TextStyle(color: _running ? kWifiGreen : const Color(0xFF8B9098), fontSize: 13),
              ),
            ],
          ),
          if (_updatedAt.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(l10n.wifiLastSet(_updatedAt), style: const TextStyle(color: Color(0xFF8A9099), fontSize: 12)),
          ],
          const SizedBox(height: 16),
          Text(l10n.wifiSlideMode, style: titleStyle),
          const SizedBox(height: 10),
          WifiSegment<int>(
            value: _form.updateType,
            items: [
              (WifiStrategy.updateInterval, l10n.wifiSlideInterval),
              (WifiStrategy.updateFixed, l10n.wifiSlideFixed),
            ],
            onChanged: (value) => setState(() => _form = _form.copyWith(updateType: value)),
          ),
          if (_form.updateType == WifiStrategy.updateInterval) ...[
            WifiFormRow(
              label: l10n.wifiSlideBegin,
              value: _form.beginTime,
              onTap: () => _pickTime(_form.beginTime, (value) => _form.copyWith(beginTime: value)),
            ),
            WifiFormRow(
              label: l10n.wifiSlideEnd,
              value: _form.endTime,
              onTap: () => _pickTime(_form.endTime, (value) => _form.copyWith(endTime: value)),
            ),
            WifiFormRow(
              label: l10n.wifiSlideEvery,
              value: l10n.wifiSlideEveryValue(intervalLabels[intervalIndex]),
              onTap: () async {
                final index = await pickWifiOption(context, intervalLabels, intervalIndex);
                if (index != null && mounted) {
                  setState(() => _form = _form.copyWith(intervalMinutes: WifiStrategy.intervalOptions[index]));
                }
              },
            ),
          ] else ...[
            WifiFormRow(
              label: l10n.wifiSlideEvery,
              value: l10n.wifiDays(_form.updateDays),
              onTap: () async {
                final index = await pickWifiOption(
                  context,
                  [for (var d = 1; d <= 365; d++) l10n.wifiDays(d)],
                  _form.updateDays - 1,
                );
                if (index != null && mounted) {
                  setState(() => _form = _form.copyWith(updateDays: index + 1));
                }
              },
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.wifiSlideUpdateTime, style: const TextStyle(color: Color(0xFF33373D), fontSize: 14)),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Wrap(
                      alignment: WrapAlignment.end,
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final time in _form.updateTimeList)
                          _chip(
                            '$time ×',
                            () => setState(
                              () => _form = _form.copyWith(
                                updateTimeList: _form.updateTimeList.where((item) => item != time).toList(),
                              ),
                            ),
                          ),
                        _chip(l10n.wifiSlideAddTime, _addTimePoint, accent: true),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 10),
          Text(l10n.wifiSlideOrder, style: titleStyle),
          const SizedBox(height: 10),
          WifiSegment<int>(
            value: _form.mode,
            items: [(1, l10n.wifiSlideSequential), (2, l10n.wifiSlideRandom)],
            onChanged: (value) => setState(() => _form = _form.copyWith(mode: value)),
          ),
          SizedBox(
            height: 48,
            child: Row(
              children: [
                Text(l10n.wifiSlideIdle, style: const TextStyle(color: Color(0xFF33373D), fontSize: 14)),
                const Spacer(),
                // 开关打开 = 轮播后休眠（idle 0）
                Switch(
                  value: _form.idle == 0,
                  activeTrackColor: const Color(0xFFFF6A20),
                  onChanged: (value) => setState(() => _form = _form.copyWith(idle: value ? 0 : 1)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

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

  Widget _buildPhotosCard(AppL10n l10n) {
    final full = WifiStrategy.isFull(_selected);
    final allSelected = WifiStrategy.isAllSelected(_selected, _albumUrls);
    return FigmaGlassCard(
      borderRadius: 16,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                l10n.wifiSlidePhotos,
                style: const TextStyle(color: Color(0xFF25282D), fontSize: 15, fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              if (_tiles.isNotEmpty)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _toggleAll,
                  child: Text(
                    allSelected ? l10n.wifiSlideUnselectAll : l10n.wifiSlideSelectAll,
                    style: const TextStyle(color: Color(0xFFFF6A20), fontSize: 13),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            l10n.wifiSlidePhotosDesc(WifiStrategy.maxImgUrls),
            style: const TextStyle(color: Color(0xFF8A9099), fontSize: 12, height: 1.5),
          ),
          const SizedBox(height: 4),
          Text(
            l10n.wifiSlideSelectedCount(_selected.length, WifiStrategy.maxImgUrls),
            style: TextStyle(
              color: full ? const Color(0xFFFF6A20) : const Color(0xFF25282D),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (_selectionHint.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(_selectionHint, style: const TextStyle(color: Color(0xFFE5533D), fontSize: 12, height: 1.5)),
          ],
          const SizedBox(height: 12),
          if (_photosError)
            Text(l10n.wifiSlidePhotosFailed, style: const TextStyle(color: Color(0xFF8A9099), fontSize: 13))
          else if (_tiles.isEmpty)
            Text(l10n.wifiSlidePhotosEmpty, style: const TextStyle(color: Color(0xFF8A9099), fontSize: 13))
          else
            GridView.count(
              crossAxisCount: 4,
              mainAxisSpacing: 7,
              crossAxisSpacing: 7,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                for (final tile in _tiles) _buildTile(tile, _selected.indexOf(tile.url) + 1, full),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildTile(_Tile tile, int order, bool full) {
    final selected = order > 0;
    return GestureDetector(
      onTap: () => _toggleTile(tile.url),
      // 选满 100 张后未选的置灰（点了提示先取消部分照片）
      child: Opacity(
        opacity: full && !selected ? 0.4 : 1,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: selected ? const Color(0xFFFF6A20) : Colors.transparent, width: 2),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (tile.thumb.isNotEmpty)
                  CachedNetworkImage(
                    imageUrl: tile.thumb,
                    fit: BoxFit.cover,
                    errorWidget: (context, url, error) => const SizedBox.shrink(),
                  ),
                // 右上角圆圈：选中后显示选择顺序（= 轮播顺序）
                Positioned(
                  top: 4,
                  right: 4,
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 18),
                    height: 18,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: selected ? const Color(0xFFFF6A20) : Colors.black.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: Colors.white),
                    ),
                    child: Text(
                      selected ? '$order' : '',
                      style: const TextStyle(color: Colors.white, fontSize: 11, height: 1),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    return FigmaScreen(
      title: l10n.wifiSlideshowSettings,
      body: _loading
          ? const Padding(padding: EdgeInsets.only(top: 120), child: Center(child: CircularProgressIndicator()))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 16),
                _buildModeCard(l10n),
                const SizedBox(height: 14),
                _buildPhotosCard(l10n),
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
                FigmaHomePrimaryButton(
                  label: _saving ? (_savingText.isNotEmpty ? _savingText : l10n.wifiSaving) : l10n.wifiSlideSaveStart,
                  fontWeight: FontWeight.w700,
                  onPressed: _saving ? null : _save,
                ),
              ],
            ),
    );
  }
}
