import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint, kReleaseMode;
import 'package:flutter/material.dart';

import '../../../network/boltfox_api.dart';
import '../../../network/iot/iot_client.dart';
import '../../../routes/app_routes.dart';
import '../../../shared/l10n/app_l10n.dart';
import '../../../shared/widgets/app_toast.dart';
import '../../../shared/widgets/figma_common.dart';
import '../../../shared/widgets/home_figma_common.dart';
import '../../../state.dart';
import '../../cast/cast_photo_picker.dart';
import '../../cast/presentation/cast_preview_page.dart';
import '../wifi_l10n.dart';
import '../wifi_projection.dart';
import '../wifi_widgets.dart';
import 'wifi_provision_page.dart';

/// WiFi 版投屏结果页，同步小程序 `subpackages/projection/wifi-result`：预览页构图导出后 pushReplacement 到这里
/// （蓝牙版去 [CastingProgressPage]）。
///
/// 逐张调 [WifiProjection.projectOne]：图片上传中 → 图片处理中（两段合占进度条 0~99%）→ 接口返回成功才到 100%（2026-10-29）。
/// V1.4 起不再等设备 ack：返回 SENT 就提示「已发送，屏幕即将刷新」，设备真正的成功 / 失败由服务端写消息通知。
/// 多张按顺序一张一张传：本轮最后一张 refresh=true（刷屏），前面的 refresh=false（只上传、返回 UPLOADED、不刷屏），
/// 整批只刷一次屏（更新说明 2.4）。重试时同样按「本轮最后一张刷屏」。
/// 每张拿到 binUrl 后写老服务相册记录（[BoltFoxApi.addWifiAlbumRecord]，img + imgBle），「我的相册」、轮播选图、
/// 删除都靠它；写记录失败不算投屏失败，只在这一张的文案后注明「未存入我的上传」并记日志。
/// 同时加入轮播（实现报告反馈追加内容第二节）：预览页打开了「同时加入轮播」时 [addToCarousel]=true，每张（含只上传的）
/// 都带 addToCarousel=true；有任何一张成功投出但 carouselUpdated=false，结束后在结果下方追加
/// 「未成功加入轮播，请前往轮播设置添加」；true / null 不额外提示。
/// 记录的 img 存原图（2026-11-06 同小程序）：投屏用的那张是预览页按设备 verticalRotation / rotationDegree 转过的成品，
/// 竖向 180° 的机型（如 IJ_101）存进去，「我的相册」和轮播选图就是倒的；与蓝牙版（[CastingProgressPage.originalPaths]）同口径，
/// 改存进预览页前的原图 [originalPaths]（选图时已按 [CastPhotoPicker] 降到长边 1920，不再另缩）；缺原图时退回投屏图。
/// 逐张列表缩略图同样用原图；列表文案跟着进度条阶段走（上传中 / 处理中，2026-11-06），最多露 4 行、可上下滑，
/// 投到第几张就滚到那一行（2026-11-06）。
/// 结束后两个按钮，与蓝牙版结果页一致（2026-11-05 对接文档 20261105 第一节第 10 项，同小程序）：
///   全部成功 →「继续投屏」（本页弹拍照 / 相册，选图后同一台设备进预览页）+「返回首页」；
///   有失败 →「重试未成功的」+「返回首页」。
/// 投屏日志：2026-11-12 起去掉页面下方的黑底日志面板（同小程序），过程只打控制台 [WiFi投屏]（联调日志浮窗可看）。
/// 投屏步骤（2026-11-12 同小程序）：进度条下方四步，对应进度文案「准备投屏 → 图片上传中 → 图片处理中 → 已发送，屏幕即将刷新」，
/// 样式与交互同配网状态页（[WifiStepIcon]：未开始序号、进行中转圈、通过打勾、失败在当时那一步打叉、后续不再执行）。
/// 准备投屏 = 取产品屏幕方向 / 渲染模式；多张时步骤跟着正在投的那一张走（每张从「图片上传中」重新开始），
/// 结束后全部成功四步全勾，有失败按最后一张失败的那一步打叉。
/// type / renderMode（2026-10-28 同小程序）：首轮投屏前按设备取一次后台产品配置的屏幕方向 screenType 与渲染模式 renderMode
/// （[PhotoFrameState.resolveScreenType] / [PhotoFrameState.resolveRenderMode]），每张原样带上，重试复用；screenType 没配才用 [type]
/// （按分辨率的旧口径），renderMode 没配不传。
class WifiCastResultPage extends StatefulWidget {
  const WifiCastResultPage({
    super.key,
    required this.state,
    required this.device,
    required this.imagePaths,
    required this.type,
    this.addToCarousel = false,
    this.originalPaths = const [],
  });

  /// 预览页的 state 可空（CastPreviewPage.state）；为空时屏幕方向、渲染模式都按「产品未配置」处理。
  final PhotoFrameState? state;
  final DeviceItem device;

  /// 预览页导出的本地图（设备物理分辨率）。
  final List<String> imagePaths;

  /// 与 [imagePaths] 逐张对应的原图（进预览页前、未按设备旋转角转过）：写相册记录与列表缩略图用；缺项退回投屏图。
  final List<String> originalPaths;

  /// 产品没配屏幕方向时的回退 type：与蓝牙版抖动出帧旧口径相同，480×720 传 '1'，其余 '0'（评审回复 8.1）。
  final String type;

  /// 预览页「同时加入轮播」：只有设备正在轮播且用户打开了开关才为 true。
  final bool addToCarousel;

  @override
  State<WifiCastResultPage> createState() => _WifiCastResultPageState();
}

class _Item {
  _Item(this.path, String original) : original = original.isNotEmpty ? original : path;

  final String path;

  /// 原图（相册记录 / 缩略图用）；没有时同 [path]。
  final String original;

  /// pending / running / SENT / UPLOADED / FAILED
  String status = 'pending';
  String text = '';

  /// 这张投出去了但没加进轮播（只认 carouselUpdated=false）。
  bool carouselFailed = false;

  /// 没投成时停在哪一步（步骤卡打叉用，1 = 图片上传中、2 = 图片处理中）；成功为 -1。
  int failStep = -1;

  bool get sent => status == 'SENT' || status == 'UPLOADED';
}

class _WifiCastResultPageState extends State<WifiCastResultPage> {
  late final List<_Item> _items = [
    for (var i = 0; i < widget.imagePaths.length; i++)
      _Item(widget.imagePaths[i], i < widget.originalPaths.length ? widget.originalPaths[i] : ''),
  ];

  /// 幂等键（2026-11-13，规则见 [WifiProjection.newPlayKey]）：本页每张图按「序号 + 是否刷屏」各记一个键（批量投屏每张一个新键，不共用），
  /// 「重试未成功的」复用；新进入本页（含继续投屏 pushReplacement 回来）是新操作，键全部重新生成。
  final Map<String, String> _playKeys = {};

  /// 逐张列表（最多露 4 行）：投到第几张就滚到那一行。
  final ScrollController _listScroll = ScrollController();
  static const double _rowHeight = 52;
  static const int _visibleRows = 4;
  bool _picking = false;

  /// 非正式包才记每张图的文件大小（要多读一次文件）。
  final bool _verbose = !kReleaseMode;
  bool _running = true;
  bool _disposed = false;
  int _current = 0;

  /// 本次进页查到的 type / renderMode（null = 还没查，查一次后重试复用）。
  String? _typeValue;
  String? _renderMode;
  int _progress = 0;
  String _stageText = '';
  String _carouselTip = '';

  /// 步骤卡：当前那一步（0~3）与它的状态 running / done / fail（见类注释）。
  int _step = 0;
  String _stepState = 'running';

  static const int _stepUploading = 1;
  static const int _stepProcessing = 2;
  static const int _stepSent = 3;

  int get _successCount => _items.where((item) => item.sent).length;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final l10n = AppL10n.of(context);
      if (_items.isEmpty) {
        _appendLog('投屏信息已失效：没有图片');
        setState(() {
          _running = false;
          _step = 0;
          _stepState = 'fail';
          _stageText = l10n.wifiCastInfoExpired;
        });
        return;
      }
      final d = widget.device;
      _appendLog('IoT 服务 ${IotConfig.baseUrl}，共 ${_items.length} 张${widget.addToCarousel ? '，同时加入轮播' : ''}');
      _appendLog(
        '设备：${d.name.isNotEmpty ? d.name : '-'}，deviceNo ${d.serialNumber.isNotEmpty ? d.serialNumber : '-'}，'
        'broadcastId ${d.broadcastId.isNotEmpty ? d.broadcastId : '-'}，尺寸 ${d.sizeModel.isNotEmpty ? d.sizeModel : '-'}，'
        '接口宽高 ${d.screenWidth}×${d.screenHeight}，rotationDegree ${d.rotationDegree}，verticalRotation ${d.verticalRotation}',
      );
      _run([for (var i = 0; i < _items.length; i++) i]);
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _listScroll.dispose();
    super.dispose();
  }

  /// 投屏日志只打控制台（2026-11-12 去掉页面日志面板）；联调日志浮窗能看到。
  void _appendLog(String text) => debugPrint('[WiFi投屏] $text');

  /// 步骤卡第 [i] 步的展示状态（pending / loading / done / fail，同 [WifiStepIcon]）。
  String _stepStatus(int i) => i < _step
      ? 'done'
      : i > _step
      ? 'pending'
      : _stepState == 'running'
      ? 'loading'
      : _stepState;

  /// 逐张列表文案跟着进度条阶段走（2026-11-06 同小程序）：「图片上传中」→「上传中」、「图片处理中」→「处理中」，不再统一叫「投屏中」。
  String _itemStageText(AppL10n l10n, String stage) => stage == 'PROCESSING' ? l10n.wifiCastItemProcessing : l10n.wifiCastItemUploading;

  /// 列表滚到第 [index] 张（贴顶，下面露排队的）。
  void _scrollListTo(int index) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_disposed || !_listScroll.hasClients) {
        return;
      }
      final target = (index * _rowHeight).clamp(0.0, _listScroll.position.maxScrollExtent);
      _listScroll.animateTo(target, duration: const Duration(milliseconds: 260), curve: Curves.easeOut);
    });
  }

  /// 写老服务相册记录（img + imgBle）。失败只记日志、返回 false，不影响投屏结果。
  /// [filePath] 传原图（2026-11-06，见类注释），不传投屏图（已按设备旋转角转过）；imgBle 仍是这次投屏的 binUrl。
  Future<bool> _saveAlbumRecord(String filePath, String binUrl) async {
    final userProductId = widget.device.id;
    if (binUrl.isEmpty || userProductId.isEmpty) {
      _appendLog(
        '相册记录：跳过（${binUrl.isEmpty ? '接口没返回 binUrl' : ''}${userProductId.isEmpty ? ' 设备没有 userProductId' : ''}）',
      );
      return false;
    }
    _appendLog('接口【写相册记录】setFileUpload + addUserProductImgRecord 参数 {userProductId: $userProductId, imgBle: $binUrl}');
    _appendLog('相册记录用图：$filePath');
    try {
      final img = await BoltFoxApi.addWifiAlbumRecord(userProductId: userProductId, filePath: filePath, imgBle: binUrl);
      _appendLog('返回 img=$img');
      return true;
    } catch (error) {
      _appendLog('失败 $error');
      return false;
    }
  }

  /// 按顺序投 [indexes] 里的这些张：本轮最后一张刷屏，前面的只上传。
  Future<void> _run(List<int> indexes) async {
    final l10n = AppL10n.of(context);
    setState(() {
      _running = true;
      _carouselTip = '';
      _step = 0;
      _stepState = 'running';
    });
    if (_typeValue == null) {
      final screenType = await widget.state?.resolveScreenType(widget.device) ?? '';
      _typeValue = screenType.isNotEmpty ? screenType : widget.type;
      _appendLog('type=$_typeValue（${screenType.isNotEmpty ? '产品屏幕方向 screenType' : '产品未配置 screenType，按分辨率回退'}）');
    }
    if (_renderMode == null) {
      _renderMode = await widget.state?.resolveRenderMode(widget.device) ?? '';
      _appendLog('渲染模式 renderMode=${_renderMode!.isNotEmpty ? _renderMode : '（产品未配置，不传）'}');
    }
    if (_disposed) return;
    final type = _typeValue!;
    final renderMode = _renderMode!;
    for (var n = 0; n < indexes.length; n++) {
      if (_disposed) return;
      final index = indexes[n];
      final refresh = n == indexes.length - 1;
      setState(() {
        _current = index;
        _progress = 0;
        _stageText = l10n.wifiCastStage('UPLOADING');
        _step = _stepUploading;
        _stepState = 'running';
        _items[index]
          ..status = 'running'
          ..text = _itemStageText(l10n, 'UPLOADING');
      });
      _scrollListTo(index);
      final path = _items[index].path;
      if (_verbose) {
        var size = '?KB';
        try {
          size = '${(File(path).lengthSync() / 1024).round()}KB';
        } catch (_) {
          // 取不到大小只影响日志
        }
        _appendLog('—— 第 ${index + 1} / ${_items.length} 张${refresh ? '（本轮最后一张，刷屏）' : '（只上传，不刷屏）'} —— 图片：$path，$size');
      }
      // 同一张图、同样的刷屏方式复用原键；本轮刷屏方式变了（原只上传、重试成最后一张）换新键
      final idempotencyKey = _playKeys.putIfAbsent('$index:$refresh', WifiProjection.newPlayKey);
      final result = await WifiProjection.projectOne(
        l10n: l10n,
        deviceNo: widget.device.serialNumber,
        filePath: path,
        type: type,
        renderMode: renderMode,
        idempotencyKey: idempotencyKey,
        refresh: refresh,
        addToCarousel: widget.addToCarousel,
        isCancelled: () => _disposed,
        onStage: (stage, progress) {
          if (!_disposed) {
            setState(() {
              _stageText = l10n.wifiCastStage(stage);
              _progress = progress;
              // 上传中 / 处理中推进步骤；成功 / 失败等接口返回后再定（见下方）
              if (stage == 'UPLOADING' || stage == 'PROCESSING') {
                _step = stage == 'PROCESSING' ? _stepProcessing : _stepUploading;
                _stepState = 'running';
              }
              // 这一张还在进行中时，列表文案跟着阶段变（上传中 / 处理中）
              if (_items[index].status == 'running' && (stage == 'UPLOADING' || stage == 'PROCESSING')) {
                _items[index].text = _itemStageText(l10n, stage);
              }
            });
          }
        },
      );
      if (_disposed || result.status == 'CANCELLED') return;
      // 步骤：发出去了第 4 步打勾（写相册记录不另占一步）；失败在当时那一步打叉，记下来供结束时用
      final failStep = result.sent ? -1 : (_step > _stepUploading ? _step : _stepUploading);
      setState(() {
        _step = result.sent ? _stepSent : failStep;
        _stepState = result.sent ? 'done' : 'fail';
      });
      var text = result.message.isNotEmpty ? result.message : l10n.wifiCastStage(result.status);
      // 写相册记录时不改阶段文案：100% 只显示「已发送，屏幕即将刷新」（2026-10-29 同小程序），过程只进日志
      if (result.sent) {
        final saved = await _saveAlbumRecord(_items[index].original, result.binUrl);
        if (_disposed) return;
        if (!saved) {
          text = l10n.wifiCastAlbumNotSaved(text);
        }
      }
      setState(() {
        _items[index]
          ..status = result.status
          ..text = text
          ..failStep = failStep
          ..carouselFailed = result.sent && result.carouselUpdated == false;
        _stageText = text;
      });
    }
    final success = _successCount;
    final total = _items.length;
    final failed = _items.where((item) => !item.sent).toList();
    final lastFailed = failed.isEmpty ? null : failed.last;
    setState(() {
      _running = false;
      // 全部成功四步全勾；有失败按最后一张失败的那一步打叉
      if (lastFailed == null) {
        _step = _stepSent;
        _stepState = 'done';
      } else {
        _step = lastFailed.failStep > _stepUploading ? lastFailed.failStep : _stepUploading;
        _stepState = 'fail';
      }
      if (success == total) {
        _stageText = total > 1 ? l10n.wifiCastAllSent(total) : l10n.wifiCastStage('SENT');
      } else if (success > 0) {
        _stageText = l10n.wifiCastPartial(success, total - success);
      }
      _carouselTip = widget.addToCarousel && _items.any((item) => item.sent && item.carouselFailed)
          ? l10n.wifiCarouselAddFailed
          : '';
    });
  }

  /// 重试未成功的（接口失败）：同样按「本轮最后一张刷屏」。
  void _retryFailed() {
    if (_running) return;
    final indexes = [
      for (var i = 0; i < _items.length; i++)
        if (!_items[i].sent) i,
    ];
    if (indexes.isNotEmpty) {
      _appendLog('重试未成功的：第 ${indexes.map((i) => i + 1).join('、')} 张');
      _run(indexes);
    }
  }

  void _backHome() {
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  /// 「继续投屏」：不跳首页，在本页弹「拍照 / 相册」二选一（与蓝牙版结果页同一做法）；选图后用本次投屏的同一台设备
  /// 进预览页构图，预览页认出 WiFi 版、导出后再回到本页。结果页是流程终点，用 pushReplacement。用户取消选择不报错。
  Future<void> _continueProjection() async {
    if (_running || _picking) {
      return;
    }
    _picking = true;
    try {
      final source = await CastPhotoPicker.chooseSource(context);
      if (source == null || !mounted) {
        return;
      }
      List<String> paths;
      try {
        paths = source == ImageSourceType.camera ? await CastPhotoPicker.takePhoto() : await CastPhotoPicker.pickFromAlbum();
      } catch (_) {
        if (mounted) {
          AppToast.show(context, AppL10n.of(context).castCannotReadPhoto);
        }
        return;
      }
      if (paths.isEmpty || !mounted) {
        return;
      }
      await Navigator.of(context).pushReplacement(
        AppPageRoute<void>(
          builder: (_) => CastPreviewPage(state: widget.state, device: widget.device, imagePaths: paths),
        ),
      );
    } finally {
      _picking = false;
    }
  }

  /// 投屏步骤卡（同配网状态页 .provision-steps：每行 48 高，行间细分隔线）。
  Widget _buildSteps(AppL10n l10n) {
    final texts = [
      l10n.wifiCastPrepare,
      l10n.wifiCastStage('UPLOADING'),
      l10n.wifiCastStage('PROCESSING'),
      l10n.wifiCastStage('SENT'),
    ];
    return FigmaGlassCard(
      borderRadius: 16,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
      child: Column(
        children: [
          for (var i = 0; i < texts.length; i++)
            Container(
              height: 48,
              decoration: i == 0
                  ? null
                  : const BoxDecoration(
                      border: Border(top: BorderSide(color: Color(0x0F2A2B2B), width: 0.5)),
                    ),
              child: Row(
                children: [
                  WifiStepIcon(index: i, status: _stepStatus(i)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      texts[i],
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: switch (_stepStatus(i)) {
                          'fail' => const Color(0xFFE5533D),
                          'pending' => const Color(0xFF8B9098),
                          _ => const Color(0xFF2A2D32),
                        },
                        fontSize: 14,
                        fontWeight: _stepStatus(i) == 'loading' ? FontWeight.w700 : FontWeight.w400,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final total = _items.length;
    final done = !_running;
    final allSuccess = done && total > 0 && _successCount == total;
    final retryable = done && total > 0 && !allSuccess;
    return FigmaScreen(
      title: l10n.wifiCastTitle,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 16),
          FigmaGlassCard(
            borderRadius: 16,
            padding: const EdgeInsets.all(18),
            child: Column(
              children: [
                // 2026-10-29（同小程序）：中间不再放投屏图片，改为状态图标（与蓝牙版投屏页同一组：进行中 / 成功 / 失败）
                Image.asset(
                  !done
                      ? 'assets/images/upload-icon01.png'
                      : allSuccess
                      ? 'assets/images/upload-icon03.png'
                      : 'assets/images/upload-icon02.png',
                  width: 130,
                  height: 110,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) => const SizedBox(height: 110),
                ),
                const SizedBox(height: 12),
                Text(
                  total > 1
                      ? '${widget.device.name}　${l10n.wifiCastPageIndex(_current + 1, total)}'
                      : widget.device.name,
                  style: const TextStyle(color: Color(0xFF2A2D32), fontSize: 15, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Text(
                  _stageText.isNotEmpty ? _stageText : l10n.wifiCastPrepare,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: allSuccess
                        ? kWifiGreen
                        : retryable
                        ? const Color(0xFFE5533D)
                        : const Color(0xFF5E6470),
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (done && _carouselTip.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    _carouselTip,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Color(0xFFE5533D), fontSize: 13, height: 1.5),
                  ),
                ],
                if (_running) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(999),
                          child: LinearProgressIndicator(
                            value: _progress / 100,
                            minHeight: 6,
                            backgroundColor: const Color(0xFFEDEFF2),
                            valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFFF6A24)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text('$_progress%', style: const TextStyle(color: Color(0xFF8B9098), fontSize: 12)),
                    ],
                  ),
                ],
                const SizedBox(height: 10),
                Text(
                  l10n.wifiCastNote,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Color(0xFF8B9098), fontSize: 12, height: 1.4),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _buildSteps(l10n),
          if (total > 1) ...[
            const SizedBox(height: 14),
            FigmaGlassCard(
              borderRadius: 16,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              // 逐张列表最多露 4 行，多出的上下滑动查看（2026-11-06 同小程序）；不足 4 张按实际高度
              child: SizedBox(
                height: _rowHeight * (total < _visibleRows ? total : _visibleRows),
                child: ListView.builder(
                  controller: _listScroll,
                  padding: EdgeInsets.zero,
                  itemExtent: _rowHeight,
                  itemCount: total,
                  itemBuilder: (context, i) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            // 缩略图用原图（2026-11-06 同小程序），与「我的相册」记录图同方位
                            child: Image.file(
                              File(_items[i].original),
                              width: 40,
                              height: 40,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) => const SizedBox(width: 40, height: 40),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(l10n.wifiCastItemNo(i + 1), style: const TextStyle(color: Color(0xFF2A2D32), fontSize: 14)),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _items[i].text.isNotEmpty ? _items[i].text : l10n.wifiCastWaiting,
                              textAlign: TextAlign.right,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: _items[i].sent
                                    ? kWifiGreen
                                    : _items[i].status == 'FAILED'
                                    ? const Color(0xFFE5533D)
                                    : const Color(0xFF8B9098),
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 24),
        ],
      ),
      // 两个按钮，与蓝牙版结果页一致：成功「继续投屏」/ 有失败「重试未成功的」+「返回首页」
      bottom: done
          ? Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (retryable)
                  FigmaHomePrimaryButton(
                    label: l10n.wifiCastRetryFailed,
                    fontWeight: FontWeight.w700,
                    onPressed: _retryFailed,
                  )
                else if (total > 0)
                  FigmaHomePrimaryButton(
                    label: l10n.castContinue,
                    fontWeight: FontWeight.w700,
                    onPressed: _continueProjection,
                  ),
                const SizedBox(height: 12),
                FigmaSecondaryButton(label: l10n.castBackHome, onPressed: _backHome),
              ],
            )
          : null,
    );
  }
}
