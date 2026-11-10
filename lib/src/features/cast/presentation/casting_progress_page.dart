import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:BoltStar/src/shared/widgets/app_dialog.dart';
import 'package:BoltStar/src/shared/widgets/figma_common.dart';
import '../../../device/ble/device_ble.dart' show FrameBleErrorKind;
import '../../../device/frame_device_protocol.dart';
import '../../../routes/app_routes.dart';
import '../../../shared/l10n/app_l10n.dart';
import '../../../shared/tap_guard.dart';
import '../../../shared/widgets/low_battery_tip.dart';
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
    this.originalPaths = const [],
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

  /// 待投屏图片的本地文件路径（预览页处理后的设备分辨率图）。非空则进入真实投屏链路。
  final List<String> imagePaths;

  /// 与 [imagePaths] 逐张对应的**原图**路径（进预览页前未操作过的图，小程序 _origSrc 语义）：
  /// 投屏记录/后端存图用它，设备帧用处理后的图。为空则记录也用处理后的图。
  /// （2026-07-23：再次/重新投屏已并入正常链路，旧 recastImgBle 直传参数随 .bin 链路删除。）
  final List<String> originalPaths;

  bool get _live => userProductId != null && imagePaths.isNotEmpty;

  @override
  State<CastingProgressPage> createState() => _CastingProgressPageState();
}

enum _CastStatus { progress, success, fail }

/// 批量投屏逐张状态（2026-11-06 同小程序 result.js BATCH_TEXT / BATCH_RANK）：
/// 等待投屏 → 处理中 → 已发送 → 传输中 → 投屏完成；失败那张「投屏失败」/ 中断「已中断」，之后没投的「未投屏」。
/// 状态只往前走（[rank]），迟到的预取回调不会把「传输中」拉回「已发送」。
enum _BatchStatus {
  pending(0),
  processing(1),
  sent(2),
  transferring(3),
  done(4),
  failed(4),
  aborted(4),
  skipped(4);

  const _BatchStatus(this.rank);

  final int rank;
}

class _BatchItem {
  _BatchItem(this.thumb);

  /// 列表缩略图：原图（与「我的相册」记录图同方位；投屏用图已按设备旋转角转过）。
  final String thumb;
  _BatchStatus status = _BatchStatus.pending;
}

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

  /// 批量逐张状态（只在多张时显示，单张界面不变）；最多露 4 行，传到第几张就滚到那一行。
  late final List<_BatchItem> _batch = [
    for (var i = 0; i < widget.imagePaths.length; i++)
      if (widget.imagePaths[i].isNotEmpty)
        _BatchItem(
          i < widget.originalPaths.length && widget.originalPaths[i].isNotEmpty
              ? widget.originalPaths[i]
              : widget.imagePaths[i],
        ),
  ];
  final ScrollController _batchScroll = ScrollController();
  static const double _batchRowHeight = 48;
  static const int _batchVisibleRows = 4;

  /// 逐张状态只往前推进；单张 / 越界不处理。
  void _setBatch(int index, _BatchStatus status) {
    if (_batch.length < 2 || index < 0 || index >= _batch.length) {
      return;
    }
    final item = _batch[index];
    if (status.rank <= item.status.rank) {
      return;
    }
    if (mounted) {
      setState(() => item.status = status);
    } else {
      item.status = status;
    }
    if (status == _BatchStatus.transferring) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_batchScroll.hasClients) {
          return;
        }
        final target = (index * _batchRowHeight).clamp(0.0, _batchScroll.position.maxScrollExtent);
        _batchScroll.animateTo(target, duration: const Duration(milliseconds: 260), curve: Curves.easeOut);
      });
    }
  }

  /// 批量收尾：出错那张（[failedIndex]，-1 = 还没进逐张）标失败 / 中断，后面没投的标「未投屏」，已完成的不动。
  void _closeBatch(int failedIndex, bool aborted) {
    if (failedIndex >= 0) {
      _setBatch(failedIndex, aborted ? _BatchStatus.aborted : _BatchStatus.failed);
    }
    for (var j = failedIndex + 1 < 0 ? 0 : failedIndex + 1; j < _batch.length; j++) {
      _setBatch(j, _BatchStatus.skipped);
    }
  }

  @override
  void initState() {
    super.initState();
    if (widget._live) {
      _total = widget.imagePaths.length;
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
    _batchScroll.dispose();
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

    DeviceItem? target = widget.device;
    if (target == null &&
        widget.state != null &&
        widget.userProductId != null) {
      final candidate = widget.state!.deviceById(
        widget.userProductId.toString(),
      );
      if (!candidate.isPlaceholder) {
        target = candidate;
      }
    }
    final targetSerial = target?.serialNumber ?? '';
    final targetScreenCode = target?.screenCode ?? 0;
    String? connectError;
    if (target == null || targetSerial.trim().isEmpty) {
      connectError = AppL10n.of(context).castFailureDisconnected;
    } else if (widget.state != null &&
        !widget.state!.isDeviceActuallyConnected(target.id)) {
      handleProgress(
        CastProgress(
          percent: 0,
          current: 0,
          total: widget.imagePaths.length,
          title: AppL10n.of(context).castStageTranscoding,
          message: AppL10n.of(context).castConnectingDevice,
        ),
      );
      final feedback = await widget.state!.connectDevice(target.id);
      if (!feedback.success) {
        connectError = feedback.message;
      }
    }

    // 跳转后再次按目标设备 ID 确认会话：预览期间即使其它页面切换了连接，
    // 这里也只会重连并投到原目标，不会复用同尺寸设备的旧句柄。
    final result = connectError != null
        ? ProjectionResult(
            success: false,
            uploaded: 0,
            total: widget.imagePaths.length,
            message: connectError,
            failureKind: FrameBleErrorKind.connectFailed,
          )
        : await service.castImages(
            userProductId: widget.userProductId!,
            expectedSerial: targetSerial,
            expectedScreenCode: targetScreenCode,
            // 出帧尺寸取设备列表记录（新机型如 EB-169 400×400 只能从这里来）。
            deviceWidth: target?.screenWidth ?? 0,
            deviceHeight: target?.screenHeight ?? 0,
            deviceShapeType: target?.shapeType,
            deviceBroadcastId: target?.broadcastId ?? '',
            // 出帧 type 取产品屏幕方向 screenType（2026-10-28 同小程序），与第一张出帧并行查，没配才按分辨率回退
            screenType: widget.state != null && target != null
                ? widget.state!.resolveScreenType(target)
                : null,
            filePaths: widget.imagePaths,
            recordFilePaths: widget.originalPaths.isEmpty
                ? null
                : widget.originalPaths,
            shouldAbort: () => _aborted,
            onProgress: handleProgress,
            onItemStage: (index, stage) => _setBatch(index, switch (stage) {
              CastItemStage.processing => _BatchStatus.processing,
              CastItemStage.sent => _BatchStatus.sent,
              CastItemStage.transferring => _BatchStatus.transferring,
              CastItemStage.done => _BatchStatus.done,
            }),
          );
    // 批量列表收尾：逐张是顺序投的，第一张没完成的（= 已成功张数）就是出错 / 中断的那张；没进逐张（连接失败）全部「未投屏」
    if (result.uploaded < _batch.length) {
      _closeBatch(
        connectError != null ? -1 : result.uploaded,
        result.failureKind == FrameBleErrorKind.aborted,
      );
    }
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

    // 设备忙：除了失败页的说明文字，再弹一次系统提示框（用户要求）。
    // 投屏服务已经会等刷屏结束再继续（见 _readTransferInfoAwaitingIdle），
    // 能走到这里说明等满超时设备仍然忙——这时候用户确实需要一个明确的
    // 「等一会儿再来」，而不是只在失败页上留一行小字。
    if (!result.success &&
        (result.failureKind == FrameBleErrorKind.busy ||
            result.failureKind == FrameBleErrorKind.commandPending)) {
      await showAppNoticeDialog(
        context,
        title: l10n.castDeviceBusyTitle,
        message: l10n.castDeviceBusyMessage,
      );
    }
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
      case FrameBleErrorKind.connectFailed: // GATT 连接失败，同断连话术桶（靠近设备重试）
        return l10n.castFailureDisconnected;
      // 型号、尺寸、身份不一致等不是断连：保留具体原因，不再落进「未连接」话术桶
      // （2026-10-22 同步小程序 10-19；新机型 EB-169 原来就是在这里被说成未连接）。
      case FrameBleErrorKind.unsupported:
        return l10n.castFailureDeviceConfig(raw);
      case FrameBleErrorKind.timeout:
        return l10n.castFailureTimeout;
      case FrameBleErrorKind.aborted:
        return l10n.castFailureCanceled;
      case FrameBleErrorKind.unknown:
      case null:
        break; // 落回子串匹配
    }
    final lower = raw.toLowerCase();
    // 图传卡住（2026-11-06 同小程序）：device_ble 抛「图传中断：设备停在已接收第 N 包不再前进（窗口 / 间隔）… MTU、每包字节」，
    // 包号、窗口、MTU 只对排查有用，用户看不懂；改成一句能照做的话。原文仍在服务层日志里。必须在「忙」之前判（原文含「设备忙」）。
    if (raw.contains('图传中断') || raw.contains('不再前进') || raw.contains('处理不过来')) {
      return l10n.castFailureStall;
    }
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
    // 「继续投屏」是主动操作，按小程序 result.js `pickAndContinue` 的口径要提醒一次电量
    // （2026-08-27 补齐 08-21 遗留入口）。⚠️ 这一支**自己不建连接**——连接发生在下一页
    // （预览页预热 / 投屏页续连），那属于自动连接、按口径不弹；所以只有「此刻已连着这台」
    // 时才读得到电量、才会弹。
    final tipDevice = widget.device;
    final tipState = widget.state;
    if (tipDevice != null && tipState != null) {
      await showLowBatteryTipIfNeeded(context, tipState, tipDevice.id);
      if (!mounted) {
        return;
      }
    }
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
          : await CastPhotoPicker.pickFromAlbum();
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
      AppPageRoute<void>(
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

  /// 「重新投屏」：重新进入预览/编辑流程（对齐小程序记录页与结果页）。
  /// 回预览页优先带**原图**（originalPaths）：处理后的图只含取景框内内容，
  /// 用它重编辑就再也拖不出上次裁掉的部分了。
  void _retry() {
    final previewPaths = widget.originalPaths.isNotEmpty
        ? widget.originalPaths
        : widget.imagePaths;
    Navigator.of(context).pushReplacement(
      AppPageRoute<void>(
        builder: (_) => widget.device != null && previewPaths.isNotEmpty
            ? CastPreviewPage(
                state: widget.state,
                device: widget.device!,
                imagePaths: previewPaths,
              )
            : CastingProgressPage(
                state: widget.state,
                userProductId: widget.userProductId,
                device: widget.device,
                deviceName: widget.deviceName,
                imagePaths: widget.imagePaths,
                originalPaths: widget.originalPaths,
              ),
      ),
    );
  }

  /// 「投屏明细」整行可点。2026-08-12 产品改口径（同步小程序）：由**投屏管理（投屏记录）**
  /// 改成**我的相册** —— 刚投完屏的人想看的是「刚才那几张现在长什么样」，
  /// 我的相册渲染的正是投屏成功的记录。行文案与右侧 n/n 计数没动。
  ///
  /// 仍用 pushReplacement（与改动前一致，小程序那边是 redirectTo）：结果页是流程终点，
  /// 不该留在返回栈里让人退回来，目标页上面也不该压着一个已结束的投屏页。
  ///
  /// ⚠️ 副作用与小程序一致：投屏管理页（含失败记录 + 重新投屏）**自此没有入口**了
  ///（2026-08-04 两端把「我的」里的入口去掉后，唯一入口就是这一行）。
  /// 页面本身没下线，产品定了挂哪儿再把入口加回来。
  void _goRecords() {
    Navigator.of(context).pushReplacementNamed(AppRoutes.figmaGallery);
  }

  String _batchText(AppL10n l10n, _BatchStatus status) => switch (status) {
    _BatchStatus.pending => l10n.castBatchPending,
    _BatchStatus.processing => l10n.castBatchProcessing,
    _BatchStatus.sent => l10n.castBatchSent,
    _BatchStatus.transferring => l10n.castBatchTransferring,
    _BatchStatus.done => l10n.castBatchDone,
    _BatchStatus.failed => l10n.castBatchFailed,
    _BatchStatus.aborted => l10n.castBatchAborted,
    _BatchStatus.skipped => l10n.castBatchSkipped,
  };

  /// 批量逐张列表（仿 WiFi 版结果页；多张才显示）：缩略图（原图）+ 第 N 张 + 状态，最多露 4 行、可上下滑。
  /// 进行中橙色（处理中 / 已发送 / 传输中），完成绿色，失败 / 中断红色，等待 / 未投屏灰色。
  Widget _buildBatchList(AppL10n l10n) {
    final rows = _batch.length < _batchVisibleRows ? _batch.length : _batchVisibleRows;
    return FigmaGlassCard(
      borderRadius: 16,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: SizedBox(
        height: _batchRowHeight * rows,
        child: ListView.separated(
          controller: _batchScroll,
          padding: EdgeInsets.zero,
          itemCount: _batch.length,
          separatorBuilder: (context, index) => Container(height: 0.5, color: const Color(0x0F2A2B2B)),
          itemBuilder: (context, i) {
            final item = _batch[i];
            final color = switch (item.status) {
              _BatchStatus.processing || _BatchStatus.sent || _BatchStatus.transferring => const Color(0xFFFF621F),
              _BatchStatus.done => const Color(0xFF0E9F87),
              _BatchStatus.failed || _BatchStatus.aborted => const Color(0xFFE5533D),
              _ => const Color(0xFF8B9098),
            };
            return SizedBox(
              height: _batchRowHeight - 0.5,
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: Image.file(
                      File(item.thumb),
                      width: 32,
                      height: 32,
                      fit: BoxFit.cover,
                      cacheWidth: 96,
                      errorBuilder: (context, error, stackTrace) => const SizedBox(width: 32, height: 32),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(l10n.castBatchItemNo(i + 1), style: const TextStyle(color: Color(0xFF4A5059), fontSize: 13)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _batchText(l10n, item.status),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: color, fontSize: 13),
                    ),
                  ),
                ],
              ),
            );
          },
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
            // 批量逐张状态在进度条下方、注意事项之前（2026-11-06 同小程序）
            if (_batch.length > 1) ...[
              const SizedBox(height: 18),
              _buildBatchList(l10n),
            ],
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
            // 批量逐张状态：结束后留在结果卡片下方
            if (_batch.length > 1) ...[
              const SizedBox(height: 14),
              _buildBatchList(l10n),
            ],
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
              // 防重复点击（2026-11-04 同小程序 tapGuard，key projection）：选图 / 跳转期间再点忽略
              onPressed: widget.userProductId == null
                  ? null
                  : () => TapGuard.run(
                      this,
                      'projection',
                      _status == _CastStatus.success ? _continueProjection : () async => _retry(),
                    ),
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
