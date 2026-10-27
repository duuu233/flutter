import 'dart:io';

import 'package:flutter/material.dart';

import '../../../shared/l10n/app_l10n.dart';
import '../../../shared/widgets/figma_common.dart';
import '../../../shared/widgets/home_figma_common.dart';
import '../../../state.dart';
import '../wifi_l10n.dart';
import '../wifi_projection.dart';
import '../wifi_widgets.dart';

/// WiFi 版投屏结果页，同步小程序 `subpackages/projection/wifi-result`：预览页构图导出后 pushReplacement 到这里
/// （蓝牙版去 [CastingProgressPage]）。
///
/// 逐张调 [WifiProjection.projectOne]：上传进度条 0~100（上传进度），之后按阶段文案推进
/// （图片处理中 → 指令已下发 → 屏幕即将刷新 → 设备刷屏中 → 终态）。多张按顺序一张一张投。
/// 结束后：全部成功只给「完成」；有失败 / 超时 / 结果未知给「重试未成功的」+「完成」。
/// 投屏记录（setUserProductUpload / 相册归属）WiFi 版尚未确定口径（需产品 / 老服务确认），本页不写记录。
class WifiCastResultPage extends StatefulWidget {
  const WifiCastResultPage({
    super.key,
    required this.device,
    required this.imagePaths,
    required this.type,
  });

  final DeviceItem device;

  /// 预览页导出的本地图（设备物理分辨率）。
  final List<String> imagePaths;

  /// 与蓝牙版抖动出帧同口径：480×720 传 '1'，其余 '0'（评审回复 8.1）。
  final String type;

  @override
  State<WifiCastResultPage> createState() => _WifiCastResultPageState();
}

class _Item {
  _Item(this.path);

  final String path;

  /// pending / running / SUCCESS / FAILED / TIMEOUT / UNKNOWN / EXPIRED
  String status = 'pending';
  String text = '';
}

class _WifiCastResultPageState extends State<WifiCastResultPage> {
  late final List<_Item> _items = [for (final path in widget.imagePaths) _Item(path)];
  bool _running = true;
  bool _disposed = false;
  int _current = 0;
  int _progress = 0;
  String _stageText = '';

  int get _successCount => _items.where((item) => item.status == 'SUCCESS').length;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final l10n = AppL10n.of(context);
      if (_items.isEmpty) {
        setState(() {
          _running = false;
          _stageText = l10n.wifiCastInfoExpired;
        });
        return;
      }
      _run([for (var i = 0; i < _items.length; i++) i]);
    });
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  String _resultText(AppL10n l10n, WifiCastResult result) {
    if (result.status == 'FAILED') {
      final reason = l10n.wifiCastReason(result.reason);
      if (reason.isNotEmpty) return reason;
      if (result.message.isNotEmpty) return result.message;
    }
    return l10n.wifiCastStage(result.status);
  }

  /// 按顺序投 [indexes] 里的这些张。
  Future<void> _run(List<int> indexes) async {
    final l10n = AppL10n.of(context);
    setState(() => _running = true);
    for (final index in indexes) {
      if (_disposed) return;
      setState(() {
        _current = index;
        _progress = 0;
        _stageText = l10n.wifiCastStage('UPLOADING');
        _items[index]
          ..status = 'running'
          ..text = l10n.wifiCastInProgress;
      });
      final result = await WifiProjection.projectOne(
        deviceNo: widget.device.serialNumber,
        filePath: _items[index].path,
        type: widget.type,
        isCancelled: () => _disposed,
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
      final text = _resultText(l10n, result);
      setState(() {
        _items[index]
          ..status = result.status
          ..text = text;
        _stageText = text;
      });
    }
    final success = _successCount;
    final total = _items.length;
    setState(() {
      _running = false;
      if (success == total) {
        _stageText = l10n.wifiCastStage('SUCCESS');
      } else if (success > 0) {
        _stageText = l10n.wifiCastPartial(success, total - success);
      }
    });
  }

  /// 重试未成功的（失败 / 超时 / 结果未知）。超时已在 projectOne 里等过 3 秒并查过一次最终状态，这里可直接重投。
  void _retryFailed() {
    if (_running) return;
    final indexes = [
      for (var i = 0; i < _items.length; i++)
        if (_items[i].status != 'SUCCESS') i,
    ];
    if (indexes.isNotEmpty) {
      _run(indexes);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final total = _items.length;
    final done = !_running;
    final allSuccess = done && total > 0 && _successCount == total;
    final retryable = done && total > 0 && !allSuccess;
    final current = total > 0 ? _items[_current < total ? _current : total - 1] : null;
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
                if (current != null)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.file(
                      File(current.path),
                      height: 220,
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) => const SizedBox(height: 220),
                    ),
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
                              errorBuilder: (context, error, stackTrace) =>
                                  const SizedBox(width: 40, height: 40),
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
                                color: _items[i].status == 'SUCCESS'
                                    ? kWifiGreen
                                    : const ['FAILED', 'TIMEOUT', 'UNKNOWN', 'EXPIRED'].contains(_items[i].status)
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
                        child: Text(
                          l10n.wifiCastDone,
                          style: const TextStyle(color: Color(0xFFFF621F), fontSize: 16),
                        ),
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
