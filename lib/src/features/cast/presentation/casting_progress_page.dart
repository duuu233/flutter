import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

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

  // 投屏明细（真实投屏结束后填充，对齐小程序 result.js applyStatus 的 成功/失败/总数）。
  int _successCount = 0;
  int _failCount = 0;
  int _selectedTotal = 0;

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
      _successCount = result.uploaded;
      _selectedTotal = result.total;
      _failCount = (result.total - result.uploaded).clamp(0, result.total);
      if (result.success) {
        _status = _CastStatus.success;
        _title = '投屏成功';
        _desc = '照片已成功投屏到设备，可前往相册查看';
        _percent = 1;
      } else {
        _status = _CastStatus.fail;
        _title = '投屏失败';
        _desc = _friendlyFailure(result.message);
      }
      _label = '${result.uploaded}/${result.total}';
    });
  }

  /// 失败原因归类为友好话术（对齐小程序 result.js:46-64 classifyFailureMessage）：
  /// 设备忙(0x0B) / 内存满 / 断连 / 超时 / 取消 分别给可操作的提示，其余原样透出。
  String _friendlyFailure(String raw) {
    final lower = raw.toLowerCase();
    if (raw.contains('繁忙') || raw.contains('忙') || lower.contains('busy') || lower.contains('0x0b')) {
      return '设备正忙，请稍后重试';
    }
    if (raw.contains('空间') || raw.contains('已满') || raw.contains('内存') || lower.contains('storage') || lower.contains('full')) {
      return '设备存储已满，请先在图库删除部分照片后重试';
    }
    if (raw.contains('断') || lower.contains('disconnect')) {
      return '与设备的连接已断开，请确认设备在附近并保持开机后重试';
    }
    if (raw.contains('超时') || lower.contains('timeout')) {
      return '传输超时，请将手机靠近设备后重试';
    }
    if (raw.contains('中止') || raw.contains('取消') || lower.contains('abort')) {
      return '投屏已取消';
    }
    return raw.isEmpty ? '投屏失败，请重试' : raw;
  }

  /// 继续投屏：复用当前设备，弹「拍照 / 相册」再选图，替换本页进入新一轮投屏
  /// （对齐小程序 result.js:887-964 continueProjection）。
  Future<void> _continueProjection() async {
    final picker = ImagePicker();
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('拍照'),
              onTap: () => Navigator.of(sheetContext).pop('camera'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('从相册选择'),
              onTap: () => Navigator.of(sheetContext).pop('album'),
            ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) {
      return;
    }
    List<String> paths;
    try {
      if (choice == 'camera') {
        final file = await picker.pickImage(source: ImageSource.camera);
        paths = file == null ? const [] : [file.path];
      } else {
        final files = await picker.pickMultiImage();
        paths = files.map((file) => file.path).toList();
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(content: Text('无法读取照片，请检查相机/相册权限后重试。')));
      }
      return;
    }
    if (paths.isEmpty || !mounted) {
      return;
    }
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => CastingProgressPage(
          userProductId: widget.userProductId,
          imagePaths: paths,
          compressImage: widget.compressImage,
        ),
      ),
    );
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
          // 投屏明细（成功/失败/总数），仅真实投屏结束后展示。
          if (_status != _CastStatus.progress && widget._live)
            Text(
              '本次投屏：成功 $_successCount 张 · 失败 $_failCount 张 · 共 $_selectedTotal 张',
              textAlign: TextAlign.center,
              style: projectionResultDescStyle,
            ),
          // 失败排查提示（对齐小程序失败页固定引导）。
          if (_status == _CastStatus.fail) ...[
            const SizedBox(height: 20),
            const _TroubleshootTips(),
          ],
          // 结果态操作：继续投屏（复用设备）/ 返回首页。
          if (_status != _CastStatus.progress) ...[
            const SizedBox(height: 36),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 19),
              child: FigmaPrimaryButton(
                label: '继续投屏',
                onPressed:
                    widget.userProductId == null ? null : _continueProjection,
              ),
            ),
            const SizedBox(height: 14),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () =>
                  Navigator.of(context).popUntil((route) => route.isFirst),
              child: const Text(
                '返回首页',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF777E88),
                  fontSize: 15,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 投屏失败排查提示（固定 4 条，对齐小程序绑定/投屏的「扫描不到怎么办」风格）。
class _TroubleshootTips extends StatelessWidget {
  const _TroubleshootTips();

  @override
  Widget build(BuildContext context) {
    const tips = [
      '1. 设备是否在手机附近、保持开机',
      '2. 手机蓝牙是否已打开',
      '3. 设备是否有电、存储是否已满',
      '4. 投屏过程中请勿锁屏或切到后台',
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '请检查：',
            style: TextStyle(
              color: Color(0xFF2A2B2B),
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          for (final tip in tips)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                tip,
                style: const TextStyle(
                  color: Color(0xFF777E88),
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
