import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'package:BoltStar/src/shared/widgets/figma_common.dart';
import '../../../routes/app_routes.dart';
import '../projection_service.dart';
import 'cast_result_common.dart';

/// 投屏页（进行中 / 成功 / 失败三态同页），1:1 复刻小程序
/// `photo-album/subpackages/projection/result`（result.js + result.wxml + result.wxss）。
///
/// 进行中：插画 + 阶段标题（图片转码中 → 图片处理中 → 图片传输中）+ 阶段描述
///        + 大号百分比 + 进度条 + 张数 + 4 条注意事项。
///        百分比是**当前这一张**的传输进度（同小程序 progressPercent），整单进度看「第 n/总数 张」。
/// 结束后：插画 + 结果标题 + 描述 + 信息卡（投屏设备 / 投屏明细）+（失败时）4 条排查提示
///        + 底部操作（继续投屏 / 重新投屏，返回首页）。
///
/// 两种用法：
/// - 纯展示（路由 mock）：不传 [userProductId]，只按 [progress] / [progressLabel] 静态展示。
/// - 真实投屏：给定 [userProductId] + [imagePaths]（原图本地路径），进入即走
///   「后端转换 + BLE 图传」链路（见 [ServerImageProjectionService]）。
class CastingProgressPage extends StatefulWidget {
  const CastingProgressPage({
    super.key,
    this.progress = 10 / 12,
    this.progressLabel = '10/12',
    this.userProductId,
    this.deviceName = '相框',
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

  /// 投屏目标设备名，结果页信息卡「投屏设备」一行展示。
  final String deviceName;

  /// 待投屏原图的本地文件路径。非空则进入真实投屏链路。
  final List<String> imagePaths;

  /// 是否压缩图片后再传后端转码（默认压缩）。
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

/// 进行中的 4 条注意事项（原文照搬小程序 result.wxml `.progress-tips`）。
const _progressTips = <String>[
  '投屏过程请保持手机亮屏，不要远离设备',
  '批量投屏如果意外中断，请前往图库主动刷新屏幕',
  '图片在投屏记录中可继续操作',
  '投屏完成后设备会自动刷新，刷新期间设备繁忙无法投屏，请等待刷新结束',
];

/// 失败页的 4 条排查提示（原文照搬小程序 result.wxml `.fail-tips`）。
const _failTips = <String>[
  '请确认设备蓝牙正常连接中，手机蓝牙正常使用',
  '如屏幕正在刷新中，请稍后再试',
  '如遇系统网络故障，请稍后再试',
  '投屏失败的图片可以前往投屏记录重新上传',
];

class _CastingProgressPageState extends State<CastingProgressPage> {
  _CastStatus _status = _CastStatus.progress;

  // 进行中态（对齐小程序 data：title / desc / progressPercent / progressCurrent / progressTotal）。
  String _stageTitle = CastStage.transcoding;
  String _desc = '投屏过程中请不要关闭手机';
  double _percent = 0;
  int _current = 0;
  int _total = 0;

  // 结果态。
  String _resultTitle = '';
  bool _aborted = false;

  // 投屏明细：成功 / 失败 / 本次所选总数。
  int _successCount = 0;
  int _failCount = 0;
  int _selectedTotal = 0;

  @override
  void initState() {
    super.initState();
    if (widget._live) {
      // 再次投屏为单张（imgBle 直传），其余按待投原图张数。
      _total = widget._isRecast ? 1 : widget.imagePaths.length;
      WidgetsBinding.instance.addPostFrameCallback((_) => _runProjection());
    } else {
      // 纯展示：把外部给的整单进度当作进度条数值。
      _percent = widget.progress;
      final parts = widget.progressLabel.split('/');
      _current = int.tryParse(parts.first) ?? 0;
      _total = parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;
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
        _current = p.current;
        _total = p.total;
        _stageTitle = p.title;
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
      _current = result.uploaded;
      if (result.success) {
        // 文案原文对齐小程序 STATUS_TEXT.success。
        _status = _CastStatus.success;
        _resultTitle = '投屏完成';
        _desc = '照片已成功投屏到设备，可前往相册查看';
        _percent = 1;
      } else {
        _status = _CastStatus.fail;
        _resultTitle = '投屏失败';
        // 有具体原因就用具体原因，否则用小程序 STATUS_TEXT.fail 的默认文案。
        final reason = _friendlyFailure(result.message);
        _desc = reason.isEmpty ? '设备连接中断，请检查设备状态后重试' : reason;
      }
    });
  }

  /// 失败原因归类为友好话术（对齐小程序 result.js classifyFailureMessage）：
  /// 设备忙(0x0B) / 内存满 / 断连 / 超时 / 取消 分别给可操作的提示，其余原样透出。
  String _friendlyFailure(String raw) {
    final lower = raw.toLowerCase();
    if (raw.contains('繁忙') ||
        raw.contains('忙') ||
        lower.contains('busy') ||
        lower.contains('0x0b')) {
      return '当前设备繁忙，请稍后重试';
    }
    if (raw.contains('空间') ||
        raw.contains('已满') ||
        raw.contains('内存') ||
        lower.contains('storage') ||
        lower.contains('full')) {
      return '设备内存已满，请清理后继续。';
    }
    if (raw.contains('断') ||
        raw.contains('未连接') ||
        raw.contains('该型号暂不支持图传') ||
        lower.contains('disconnect')) {
      return '设备未连接，请检查手机或设备连接后继续';
    }
    if (raw.contains('超时') || lower.contains('timeout')) {
      return '传输超时，请将手机靠近设备后重试';
    }
    if (raw.contains('中止') || raw.contains('取消') || lower.contains('abort')) {
      return '投屏已取消';
    }
    return raw;
  }

  /// 「继续投屏」：不跳首页，在本页弹「拍照 / 相册」二选一，选完图替换本页进入新一轮投屏
  /// （对齐小程序 result.js continueProjection）。
  Future<void> _continueProjection() async {
    final picker = ImagePicker();
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: Text(
                '选择投屏方式',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF2A2D32),
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('拍照'),
              subtitle: const Text('调用手机相机拍照'),
              onTap: () => Navigator.of(sheetContext).pop('camera'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('相册'),
              subtitle: const Text('从手机相册选择照片'),
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
        // 单批投屏上限 5 张，对齐小程序 media.chooseFromAlbum(count:5)。
        final files = await picker.pickMultiImage(limit: 5);
        paths = files.map((file) => file.path).toList();
      }
    } catch (_) {
      if (mounted) {
        AppToast.show(context, '无法读取照片，请检查相机/相册权限后重试。');
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
          deviceName: widget.deviceName,
          imagePaths: paths,
          compressImage: widget.compressImage,
        ),
      ),
    );
  }

  /// 「重新投屏」：用同一批图（或同一条记录的设备帧）原样再跑一次。
  ///
  /// 小程序这里是 `redirectTo` 回投屏预览页重选；App 没有预览页（既定方针：选图即投），
  /// 故直接以相同入参替换本页重跑，语义等价「再来一次」。
  void _retry() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => CastingProgressPage(
          userProductId: widget.userProductId,
          deviceName: widget.deviceName,
          imagePaths: widget.imagePaths,
          compressImage: widget.compressImage,
          recastImgBle: widget.recastImgBle,
          recastUpirId: widget.recastUpirId,
          recastImgUrl: widget.recastImgUrl,
        ),
      ),
    );
  }

  /// 「投屏明细」整行可点：进投屏记录（小程序 goRecords 是 redirectTo，这里同样替换本页，
  /// 避免记录页上面还压着一个已结束的投屏页）。
  void _goRecords() {
    Navigator.of(
      context,
    ).pushReplacementNamed(AppRoutes.figmaCastManagement);
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

  /// 页面标题 = 进行中显示阶段标题，结束后显示结果标题（小程序 page-nav 绑的就是同一个 title）。
  String get _title =>
      _status == _CastStatus.progress ? _stageTitle : _resultTitle;

  @override
  Widget build(BuildContext context) {
    final inProgress = _status == _CastStatus.progress;
    return FigmaScreen(
      title: _title,
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
          Text(
            _title,
            textAlign: TextAlign.center,
            style: projectionResultTitleStyle,
          ),
          const SizedBox(height: 11),
          Text(
            _desc,
            textAlign: TextAlign.center,
            style: projectionResultDescStyle,
          ),

          // ── 进行中：大号百分比 + 进度条 + 张数 + 注意事项 ──────────────────
          if (inProgress) ...[
            const SizedBox(height: 28), // .progress-percent margin-top 56rpx
            ProjectionPercent(percent: _percent),
            const SizedBox(height: 14), // .progress-wrap margin-top 28rpx
            ProjectionProgress(percent: _percent, label: '$_current/$_total'),
            const SizedBox(height: 22), // .progress-tips margin-top 44rpx
            const ProjectionTips(tips: _progressTips),
          ],

          // ── 结束：信息卡（投屏设备 / 投屏明细）──────────────────────────
          if (!inProgress && widget._live) ...[
            const SizedBox(height: 30), // .info-card margin-top 60rpx
            ProjectionResultInfoCard(
              deviceName: widget.deviceName,
              successCount: _successCount,
              failCount: _failCount,
              total: _selectedTotal,
              onTapRecords: _goRecords,
            ),
          ],

          // ── 失败：固定排查提示 ────────────────────────────────────────
          if (_status == _CastStatus.fail) ...[
            const SizedBox(height: 16), // .fail-tips margin-top 32rpx
            const ProjectionTips(tips: _failTips),
          ],

          // ── 结束：底部操作 ───────────────────────────────────────────
          if (!inProgress) ...[
            const SizedBox(height: 30),
            FigmaPrimaryButton(
              // 成功 → 继续投屏（再选图）；失败 → 重新投屏（同一批图重跑）。
              label: _status == _CastStatus.success ? '继续投屏' : '重新投屏',
              onPressed: widget.userProductId == null
                  ? null
                  : (_status == _CastStatus.success
                        ? _continueProjection
                        : _retry),
            ),
            const SizedBox(height: 12),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () =>
                  Navigator.of(context).popUntil((route) => route.isFirst),
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  '返回首页',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFF777E88),
                    fontSize: 15,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
