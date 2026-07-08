import 'package:flutter/material.dart';

import 'package:BoltStar/src/shared/widgets/figma_common.dart';
import '../projection_service.dart';
import 'cast_result_common.dart';

/// 投屏进行中页：展示投屏传输进度，对应 UI 稿「投屏中」。
///
/// 两种用法：
/// - 纯展示（默认 / 路由 mock）：给定 [progress] / [progressLabel] 静态展示。
/// - 真实投屏：给定 [userProductId] + [imagePaths]（原图本地路径），进入即走
///   「后端转换 + BLE 图传」链路（见 [ServerImageProjectionService]，移植自小程序 result.js），
///   进度与结果为真实结果，传完在本页切到成功/失败态。
class CastingProgressPage extends StatefulWidget {
  const CastingProgressPage({
    super.key,
    this.progress = 10 / 12,
    this.progressLabel = '10/12',
    this.userProductId,
    this.imagePaths = const [],
    this.compressImage = true,
    this.recastImgBle,
    this.recastUpirId,
    this.recastImgUrl,
  });

  final double progress;
  final String progressLabel;

  /// 后端设备 id（写投屏记录用）。为空则为纯展示模式。
  final Object? userProductId;

  /// 待投屏原图的本地文件路径。非空则进入真实投屏链路。
  final List<String> imagePaths;

  /// 是否压缩图片后再传后端转码（预览页「压缩开关」值，默认压缩）。
  final bool compressImage;

  /// 再次/重新投屏：投屏记录里后端转换好的设备帧地址(imgBle)。非空则走「imgBle 直传」链路
  /// （直接下载 .bin 图传，不走后端转码），见 [ServerImageProjectionService.recastRecord]。
  final String? recastImgBle;

  /// 再次投屏记账用的原记录 id（upirId）。
  final Object? recastUpirId;

  /// 再次投屏记账用的原图地址（img）。
  final String? recastImgUrl;

  bool get _isRecast =>
      recastImgBle != null && recastImgBle!.isNotEmpty && userProductId != null;

  bool get _live =>
      userProductId != null && (imagePaths.isNotEmpty || _isRecast);

  @override
  State<CastingProgressPage> createState() => _CastingProgressPageState();
}

enum _CastStatus { progress, success, fail }

class _CastingProgressPageState extends State<CastingProgressPage> {
  _CastStatus _status = _CastStatus.progress;
  double _percent = 0;
  String _label = '';
  String _title = '投屏中';
  String _desc = '投屏过程中请不要关闭手机';
  bool _aborted = false;

  @override
  void initState() {
    super.initState();
    if (widget._live) {
      _percent = 0;
      // 再次投屏为单张（imgBle 直传），其余按待投原图张数。
      _label = widget._isRecast ? '0/1' : '0/${widget.imagePaths.length}';
      WidgetsBinding.instance.addPostFrameCallback((_) => _runProjection());
    } else {
      _percent = widget.progress;
      _label = widget.progressLabel;
    }
  }

  @override
  void dispose() {
    _aborted = true; // 离开页面：中止投屏（切后台/离开会挂起蓝牙）。
    super.dispose();
  }

  Future<void> _runProjection() async {
    final service = ServerImageProjectionService();
    void handleProgress(CastProgress p) {
      if (!mounted) return;
      setState(() {
        _percent = p.percent;
        _label = '${p.current}/${p.total}';
        _desc = p.message;
      });
    }

    // 再次/重新投屏（记录页带入 imgBle）：走 imgBle 直传链路；否则走「后端转换 + 图传」链路。
    final result = widget._isRecast
        ? await service.recastRecord(
            userProductId: widget.userProductId!,
            imgBleUrl: widget.recastImgBle!,
            upirId: widget.recastUpirId,
            imgUrl: widget.recastImgUrl,
            shouldAbort: () => _aborted,
            onProgress: handleProgress,
          )
        : await service.castImages(
            userProductId: widget.userProductId!,
            filePaths: widget.imagePaths,
            compressImage: widget.compressImage,
            shouldAbort: () => _aborted,
            onProgress: handleProgress,
          );
    if (!mounted) return;
    setState(() {
      if (result.success) {
        _status = _CastStatus.success;
        _title = '投屏成功';
        _desc = '照片已成功投屏到设备，可前往相册查看';
        _percent = 1;
      } else {
        _status = _CastStatus.fail;
        _title = '投屏失败';
        _desc = result.message;
      }
      _label = '${result.uploaded}/${result.total}';
    });
  }

  String get _art {
    switch (_status) {
      case _CastStatus.success:
        return 'assets/images/upload-icon03.png';
      case _CastStatus.fail:
        return 'assets/images/upload-icon02.png';
      case _CastStatus.progress:
        return 'assets/images/upload-icon01.png';
    }
  }

  @override
  Widget build(BuildContext context) {
    return FigmaScreen(
      title: _status == _CastStatus.progress ? '投屏中' : _title,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 20),
          Center(
            child: ProjectionResultArt(
              asset: _art,
              fallbackIcon: _status == _CastStatus.fail
                  ? Icons.error_outline
                  : (_status == _CastStatus.success
                      ? Icons.check_circle_outline
                      : Icons.cloud_upload_outlined),
            ),
          ),
          const SizedBox(height: 24),
          Text(_title, textAlign: TextAlign.center, style: projectionResultTitleStyle),
          const SizedBox(height: 11),
          Text(_desc, textAlign: TextAlign.center, style: projectionResultDescStyle),
          const SizedBox(height: 32),
          if (_status == _CastStatus.progress)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 19),
              child: ProjectionProgress(percent: _percent, label: _label),
            ),
        ],
      ),
    );
  }
}
