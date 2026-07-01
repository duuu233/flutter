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
  });

  final double progress;
  final String progressLabel;

  /// 后端设备 id（写投屏记录用）。为空则为纯展示模式。
  final Object? userProductId;

  /// 待投屏原图的本地文件路径。非空则进入真实投屏链路。
  final List<String> imagePaths;

  bool get _live => imagePaths.isNotEmpty && userProductId != null;

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
      _label = '0/${widget.imagePaths.length}';
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
    final result = await ServerImageProjectionService().castImages(
      userProductId: widget.userProductId!,
      filePaths: widget.imagePaths,
      shouldAbort: () => _aborted,
      onProgress: (p) {
        if (!mounted) return;
        setState(() {
          _percent = p.percent;
          _label = '${p.current}/${p.total}';
          _desc = p.message;
        });
      },
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
