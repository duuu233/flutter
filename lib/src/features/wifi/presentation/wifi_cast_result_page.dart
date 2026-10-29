import 'dart:io';

import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../network/boltfox_api.dart';
import '../../../network/iot/iot_client.dart';
import '../../../shared/l10n/app_l10n.dart';
import '../../../shared/widgets/app_toast.dart';
import '../../../shared/widgets/figma_common.dart';
import '../../../shared/widgets/home_figma_common.dart';
import '../../../state.dart';
import '../wifi_l10n.dart';
import '../wifi_projection.dart';
import '../wifi_widgets.dart';

/// WiFi 版投屏结果页，同步小程序 `subpackages/projection/wifi-result`：预览页构图导出后 pushReplacement 到这里
/// （蓝牙版去 [CastingProgressPage]）。
///
/// 逐张调 [WifiProjection.projectOne]：上传进度条 0~100（上传进度）→ 图片处理中 → 接口返回即结束。
/// V1.4 起不再等设备 ack：返回 SENT 就提示「已发送，屏幕即将刷新」，设备真正的成功 / 失败由服务端写消息通知。
/// 多张按顺序一张一张传：本轮最后一张 refresh=true（刷屏），前面的 refresh=false（只上传、返回 UPLOADED、不刷屏），
/// 整批只刷一次屏（更新说明 2.4）。重试时同样按「本轮最后一张刷屏」。
/// 每张拿到 binUrl 后写老服务相册记录（[BoltFoxApi.addWifiAlbumRecord]，img + imgBle），「我的相册」、轮播选图、
/// 删除都靠它；写记录失败不算投屏失败，只在这一张的文案后注明「未存入我的上传」并记日志。
/// 同时加入轮播（实现报告反馈追加内容第二节）：预览页打开了「同时加入轮播」时 [addToCarousel]=true，每张（含只上传的）
/// 都带 addToCarousel=true；有任何一张成功投出但 carouselUpdated=false，结束后在结果下方追加
/// 「未成功加入轮播，请前往轮播设置添加」；true / null 不额外提示。
/// 结束后：全部成功只给「完成」；有失败给「重试未成功的」+「完成」。
/// 投屏日志（同小程序）：非正式包在页面下方显示、可一键复制；正式包不显示，只打控制台 [WiFi投屏]。重试不清空。
class WifiCastResultPage extends StatefulWidget {
  const WifiCastResultPage({
    super.key,
    required this.device,
    required this.imagePaths,
    required this.type,
    this.addToCarousel = false,
  });

  final DeviceItem device;

  /// 预览页导出的本地图（设备物理分辨率）。
  final List<String> imagePaths;

  /// 与蓝牙版抖动出帧同口径：480×720 传 '1'，其余 '0'（评审回复 8.1）。
  final String type;

  /// 预览页「同时加入轮播」：只有设备正在轮播且用户打开了开关才为 true。
  final bool addToCarousel;

  @override
  State<WifiCastResultPage> createState() => _WifiCastResultPageState();
}

class _Item {
  _Item(this.path);

  final String path;

  /// pending / running / SENT / UPLOADED / FAILED
  String status = 'pending';
  String text = '';

  /// 这张投出去了但没加进轮播（只认 carouselUpdated=false）。
  bool carouselFailed = false;

  bool get sent => status == 'SENT' || status == 'UPLOADED';
}

class _WifiCastResultPageState extends State<WifiCastResultPage> {
  static const int _logLimit = 500;

  late final List<_Item> _items = [for (final path in widget.imagePaths) _Item(path)];
  final ScrollController _logScroll = ScrollController();
  final List<String> _logs = <String>[];
  final bool _showLog = !kReleaseMode;
  bool _running = true;
  bool _disposed = false;
  int _current = 0;
  int _progress = 0;
  String _stageText = '';
  String _carouselTip = '';

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
    _logScroll.dispose();
    super.dispose();
  }

  /// 追加一行投屏日志（带时分秒毫秒）；只在显示日志面板时写页面数据。
  void _appendLog(String text) {
    if (_disposed || !_showLog) {
      return;
    }
    final now = DateTime.now();
    String pad(int n, [int len = 2]) => '$n'.padLeft(len, '0');
    final line = '${pad(now.hour)}:${pad(now.minute)}:${pad(now.second)}.${pad(now.millisecond, 3)} $text';
    setState(() {
      _logs.add(line);
      if (_logs.length > _logLimit) {
        _logs.removeRange(0, _logs.length - _logLimit);
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_logScroll.hasClients) {
        _logScroll.jumpTo(_logScroll.position.maxScrollExtent);
      }
    });
  }

  /// 复制全部日志，方便发给开发对照。
  Future<void> _copyLogs() async {
    if (_logs.isEmpty) {
      return;
    }
    await Clipboard.setData(ClipboardData(text: _logs.join('\n')));
    if (mounted) {
      AppToast.show(context, AppL10n.of(context).wifiLogCopied);
    }
  }

  /// 写老服务相册记录（img + imgBle）。失败只记日志、返回 false，不影响投屏结果。
  Future<bool> _saveAlbumRecord(String filePath, String binUrl) async {
    final userProductId = widget.device.id;
    if (binUrl.isEmpty || userProductId.isEmpty) {
      _appendLog(
        '相册记录：跳过（${binUrl.isEmpty ? '接口没返回 binUrl' : ''}${userProductId.isEmpty ? ' 设备没有 userProductId' : ''}）',
      );
      return false;
    }
    _appendLog('接口【写相册记录】setFileUpload + addUserProductImgRecord 参数 {userProductId: $userProductId, imgBle: $binUrl}');
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
    });
    for (var n = 0; n < indexes.length; n++) {
      if (_disposed) return;
      final index = indexes[n];
      final refresh = n == indexes.length - 1;
      setState(() {
        _current = index;
        _progress = 0;
        _stageText = l10n.wifiCastStage('UPLOADING');
        _items[index]
          ..status = 'running'
          ..text = l10n.wifiCastInProgress;
      });
      final path = _items[index].path;
      if (_showLog) {
        var size = '?KB';
        try {
          size = '${(File(path).lengthSync() / 1024).round()}KB';
        } catch (_) {
          // 取不到大小只影响日志
        }
        _appendLog('—— 第 ${index + 1} / ${_items.length} 张${refresh ? '（本轮最后一张，刷屏）' : '（只上传，不刷屏）'} —— 图片：$path，$size');
      }
      final result = await WifiProjection.projectOne(
        l10n: l10n,
        deviceNo: widget.device.serialNumber,
        filePath: path,
        type: widget.type,
        refresh: refresh,
        addToCarousel: widget.addToCarousel,
        isCancelled: () => _disposed,
        onLog: _appendLog,
        onStage: (stage, progress) {
          if (!_disposed) {
            setState(() {
              _stageText = l10n.wifiCastStage(stage);
              _progress = progress;
            });
          }
        },
      );
      if (_disposed || result.status == 'CANCELLED') return;
      var text = result.message.isNotEmpty ? result.message : l10n.wifiCastStage(result.status);
      if (result.sent) {
        setState(() => _stageText = l10n.wifiCastSavingAlbum);
        final saved = await _saveAlbumRecord(path, result.binUrl);
        if (_disposed) return;
        if (!saved) {
          text = l10n.wifiCastAlbumNotSaved(text);
        }
      }
      setState(() {
        _items[index]
          ..status = result.status
          ..text = text
          ..carouselFailed = result.sent && result.carouselUpdated == false;
        _stageText = text;
      });
    }
    final success = _successCount;
    final total = _items.length;
    setState(() {
      _running = false;
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

  Widget _buildLogPanel(AppL10n l10n) {
    return Container(
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: const Color(0xCC1F2329), borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.wifiCastLogTitle,
                  style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _copyLogs,
                child: Text(l10n.wifiCopyLog, style: const TextStyle(color: Color(0xFFFF8A4C), fontSize: 13)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 220,
            child: _logs.isEmpty
                ? Text(l10n.wifiLogEmpty, style: const TextStyle(color: Color(0xFFB8BDC6), fontSize: 11))
                : ListView.builder(
                    controller: _logScroll,
                    itemCount: _logs.length,
                    itemBuilder: (context, index) => SelectableText(
                      _logs[index],
                      style: const TextStyle(color: Color(0xFFE6E8EB), fontSize: 11, height: 1.4),
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
          if (total > 1) ...[
            const SizedBox(height: 14),
            FigmaGlassCard(
              borderRadius: 16,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              child: Column(
                children: [
                  for (var i = 0; i < total; i++)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: Image.file(
                              File(_items[i].path),
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
                ],
              ),
            ),
          ],
          if (_showLog) _buildLogPanel(l10n),
          const SizedBox(height: 24),
        ],
      ),
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
                  ),
                if (retryable)
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => Navigator.of(context).maybePop(),
                    child: SizedBox(
                      height: 44,
                      child: Center(
                        child: Text(l10n.wifiCastDone, style: const TextStyle(color: Color(0xFFFF621F), fontSize: 16)),
                      ),
                    ),
                  )
                else
                  FigmaHomePrimaryButton(
                    label: l10n.wifiCastDone,
                    fontWeight: FontWeight.w700,
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
              ],
            )
          : null,
    );
  }
}
