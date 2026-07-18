import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:BoltStar/src/shared/widgets/app_dialog.dart';
import 'package:BoltStar/src/shared/widgets/figma_common.dart';
import '../../../device/ble/device_ble.dart' show FrameBleErrorKind;
import '../../../routes/app_routes.dart';
import '../../../shared/l10n/app_l10n.dart';
import '../../../state.dart';
import '../cast_photo_picker.dart';
import '../projection_service.dart';
import 'cast_preview_page.dart';
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
    this.state,
    this.progress = 10 / 12,
    this.progressLabel = '10/12',
    this.userProductId,
    this.device,
    // 空串占位：展示时在 build 里按当前语言兜底成「相框」（此处无 context 不能本地化）。
    this.deviceName = '',
    this.imagePaths = const [],
    this.recastImgBle,
    this.recastUpirId,
    this.recastImgUrl,
  });

  final double progress;
  final String progressLabel;
  final PhotoFrameState? state;

  /// 后端设备 id（写投屏记录用）。为空则为纯展示模式。
  final Object? userProductId;

  /// 投屏目标设备。仅「继续投屏」需要——它要跳回投屏预览页，而预览页的裁剪比例取自设备屏幕分辨率。
  /// 从投屏记录页「再次投屏」进来时没有设备对象（那条链路直传 imgBle、不重新选图），此时为 null，
  /// 「继续投屏」退化为不经预览页直接投。
  final DeviceItem? device;

  /// 投屏目标设备名，结果页信息卡「投屏设备」一行展示。
  final String deviceName;

  /// 待投屏原图的本地文件路径。非空则进入真实投屏链路。
  final List<String> imagePaths;

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

  // 进行中态（对齐小程序 data：title / desc / progressPercent / progressCurrent / progressTotal）。
  String _stageTitle = CastStage.transcoding;
  // 空串占位；进行中默认描述在 build 里按语言取（无 context 的字段初始化处无法本地化）。
  String _desc = '';
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
    final service = ServerImageProjectionService(l10n: AppL10n.of(context));
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
            shouldAbort: () => _aborted,
            onProgress: handleProgress,
          );
    if (!mounted) return;
    if (widget.state != null && widget.userProductId != null) {
      await widget.state!.refreshConnectedDeviceInfo(
        widget.userProductId.toString(),
      );
      if (!mounted) return;
      // 投屏成功即上传了新照片：顺手刷新账号级计数（getUserInfo 的 imgCount），
      // 否则「我的」页的图库数字会一直停在投屏前的旧值（它不看本地相册列表）。
      if (result.success) {
        unawaited(widget.state!.refreshCurrentUser());
      }
    }
    final l10n = AppL10n.of(context);
    // 关键节点触觉反馈（iOS 惯例）：投屏结束时轻震一下，用户不用盯着屏幕等。
    HapticFeedback.mediumImpact();
    setState(() {
      _successCount = result.uploaded;
      _selectedTotal = result.total;
      _failCount = (result.total - result.uploaded).clamp(0, result.total);
      _current = result.uploaded;
      if (result.success) {
        // 文案原文对齐小程序 STATUS_TEXT.success。
        _status = _CastStatus.success;
        _resultTitle = l10n.castResultSuccessTitle;
        _desc = l10n.castResultSuccessDesc;
        _percent = 1;
      } else {
        _status = _CastStatus.fail;
        _resultTitle = l10n.castFailed;
        // 有具体原因就用具体原因，否则用小程序 STATUS_TEXT.fail 的默认文案。
        final reason = _friendlyFailure(result.message, result.failureKind);
        _desc = reason.isEmpty ? l10n.castResultFailDefaultDesc : reason;
      }
    });
  }

  /// 失败原因归类为友好话术（对齐小程序 result.js classifyFailureMessage）：
  /// 设备忙(0x0B) / 内存满 / 断连 / 超时 / 取消 分别给可操作的提示，其余原样透出。
  ///
  /// 优先按 [kind]（FrameBleException 的机器可读分类）归类——错误语义不再依赖
  /// 消息文案，服务层文案翻译后归类依然正确；[kind] 缺失（老抛出点/非 BLE 错误）
  /// 才落回下方的子串匹配兜底。
  String _friendlyFailure(String raw, FrameBleErrorKind? kind) {
    final l10n = AppL10n.of(context);
    switch (kind) {
      case FrameBleErrorKind.busy:
      case FrameBleErrorKind.commandPending:
        return l10n.castFailureBusy;
      case FrameBleErrorKind.storageFull:
        return l10n.castFailureStorageFull;
      case FrameBleErrorKind.disconnected:
      case FrameBleErrorKind.unsupported: // 沿用原逻辑：不支持机型与断连同一话术桶
      case FrameBleErrorKind.connectFailed: // GATT 连接失败，同断连话术桶（靠近设备重试）
        return l10n.castFailureDisconnected;
      case FrameBleErrorKind.connectFailed:
        return l10n.bleConnectFailed;
      case FrameBleErrorKind.timeout:
        return l10n.castFailureTimeout;
      case FrameBleErrorKind.aborted:
        return l10n.castFailureCanceled;
      case FrameBleErrorKind.unknown:
      case null:
        break; // 落回子串匹配
    }
    final lower = raw.toLowerCase();
    if (raw.contains('繁忙') ||
        raw.contains('忙') ||
        lower.contains('busy') ||
        lower.contains('0x0b')) {
      return l10n.castFailureBusy;
    }
    if (raw.contains('空间') ||
        raw.contains('已满') ||
        raw.contains('内存') ||
        lower.contains('storage') ||
        lower.contains('full')) {
      return l10n.castFailureStorageFull;
    }
    if (raw.contains('断') ||
        raw.contains('未连接') ||
        raw.contains('该型号暂不支持图传') ||
        lower.contains('disconnect')) {
      return l10n.castFailureDisconnected;
    }
    if (raw.contains('超时') || lower.contains('timeout')) {
      return l10n.castFailureTimeout;
    }
    if (raw.contains('中止') || raw.contains('取消') || lower.contains('abort')) {
      return l10n.castFailureCanceled;
    }
    return raw;
  }

  /// 「继续投屏」：不跳首页，在本页弹「拍照 / 相册」二选一，选完图替换本页进入新一轮投屏
  /// （对齐小程序 result.js continueProjection）。
  Future<void> _continueProjection() async {
    // 走共用卡片式弹层（对齐小程序 `.media-sheet` / 首页同款），取代原手搓 ListTile 版。
    final source = await CastPhotoPicker.chooseSource(context);
    if (source == null || !mounted) {
      return;
    }
    List<String> paths;
    try {
      // 统一走 CastPhotoPicker：选图时就用平台原生解码器把长边降到 1920，
      // 避免把 4~12MB 的相机原图整个传给后端（投屏耗时大头在上传，不在 BLE）。
      paths = (source == ImageSourceType.camera)
          ? await CastPhotoPicker.takePhoto()
          : await CastPhotoPicker.pickFromAlbum(context);
    } catch (_) {
      if (mounted) {
        AppToast.show(context, AppL10n.of(context).castCannotReadPhoto);
      }
      return;
    }
    if (paths.isEmpty || !mounted) {
      return;
    }
    final device = widget.device;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        // 选完图先进预览页（对齐小程序 result.js chooseCamera/chooseAlbum → 跳 preview）。
        // 没有设备对象（从投屏记录「再次投屏」进来的）时退化为直接投。
        builder: (_) => device != null
            ? CastPreviewPage(
                state: widget.state,
                device: device,
                imagePaths: paths,
              )
            : CastingProgressPage(
                state: widget.state,
                userProductId: widget.userProductId,
                deviceName: widget.deviceName,
                imagePaths: paths,
              ),
      ),
    );
  }

  /// 「重新投屏」：重新进入预览/裁剪流程（对齐小程序记录页与结果页）。
  void _retry() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => widget.device != null && widget.imagePaths.isNotEmpty
            ? CastPreviewPage(
                state: widget.state,
                device: widget.device!,
                imagePaths: widget.imagePaths,
                recastImgBle: widget.recastImgBle,
                recastUpirId: widget.recastUpirId,
                recastImgUrl: widget.recastImgUrl,
              )
            : CastingProgressPage(
                state: widget.state,
                userProductId: widget.userProductId,
                device: widget.device,
                deviceName: widget.deviceName,
                imagePaths: widget.imagePaths,
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
    Navigator.of(context).pushReplacementNamed(AppRoutes.figmaCastManagement);
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

  /// 传输中确认退出：返回 true 表示用户坚持退出（将中断本次投屏）。
  Future<bool> _confirmExitWhileCasting() async {
    final l10n = AppL10n.of(context);
    final leave = await showAppConfirmDialog(
      context,
      title: l10n.castExitConfirmTitle,
      message: l10n.castExitConfirmContent,
      icon: Icons.exit_to_app_rounded,
      tone: AppDialogTone.danger,
      cancelLabel: l10n.castExitConfirmStay,
      confirmLabel: l10n.castExitConfirmLeave,
    );
    return leave ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final inProgress = _status == _CastStatus.progress;
    // 真实投屏传输中拦截返回（顶栏返回键走 maybePop、系统返回/侧滑同样经过 PopScope）：
    // 之前无任何拦截，误触返回会静默掐断 BLE 图传（dispose 里 _aborted=true），整单投屏作废。
    return PopScope(
      canPop: !(inProgress && widget._live),
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final leave = await _confirmExitWhileCasting();
        if (leave && mounted) {
          Navigator.of(context).pop();
        }
      },
      child: _buildScreen(context, l10n, inProgress),
    );
  }

  Widget _buildScreen(BuildContext context, AppL10n l10n, bool inProgress) {
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
            _desc.isEmpty ? l10n.castProgressDefaultDesc : _desc,
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
            ProjectionTips(
              tips: [
                l10n.castProgressTip1,
                l10n.castProgressTip2,
                l10n.castProgressTip3,
                l10n.castProgressTip4,
              ],
            ),
          ],

          // ── 结束：信息卡（投屏设备 / 投屏明细）──────────────────────────
          if (!inProgress && widget._live) ...[
            const SizedBox(height: 30), // .info-card margin-top 60rpx
            ProjectionResultInfoCard(
              deviceName: widget.deviceName.isEmpty
                  ? l10n.castDefaultDeviceName
                  : widget.deviceName,
              successCount: _successCount,
              failCount: _failCount,
              total: _selectedTotal,
              onTapRecords: _goRecords,
            ),
          ],

          // ── 失败：固定排查提示 ────────────────────────────────────────
          if (_status == _CastStatus.fail) ...[
            const SizedBox(height: 16), // .fail-tips margin-top 32rpx
            ProjectionTips(
              tips: [
                l10n.castFailTip1,
                l10n.castFailTip2,
                l10n.castFailTip3,
                l10n.castFailTip4,
              ],
            ),
          ],

          // ── 结束：底部操作 ───────────────────────────────────────────
          if (!inProgress) ...[
            const SizedBox(height: 30),
            FigmaPrimaryButton(
              // 成功 → 继续投屏（再选图）；失败 → 重新投屏（同一批图重跑）。
              label: _status == _CastStatus.success
                  ? l10n.castContinue
                  : l10n.castRecast,
              onPressed: widget.userProductId == null
                  ? null
                  : (_status == _CastStatus.success
                        ? _continueProjection
                        : _retry),
            ),
            const SizedBox(height: 12), // .result-actions gap 24rpx
            // 返回首页：白 0.86 药丸按钮（对齐小程序 .result-secondary），不是灰色文字链接。
            FigmaSecondaryButton(
              label: l10n.castBackHome,
              onPressed: () =>
                  Navigator.of(context).popUntil((route) => route.isFirst),
            ),
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
