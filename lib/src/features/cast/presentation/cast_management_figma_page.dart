import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../../routes/app_routes.dart';
import '../../../shared/l10n/app_l10n.dart';
import '../../../state.dart';
import 'package:BoltStar/src/shared/widgets/app_widgets.dart';
import 'package:BoltStar/src/shared/widgets/figma_common.dart';
import 'cast_preview_page.dart';
import 'casting_progress_page.dart';

/// 投屏管理（投屏记录），对照微信小程序 `photo-album/subpackages/projection/records`。
///
/// 顶部「投屏成功 / 投屏失败」分段切换（滑动指示器，成功橙、失败红），
/// 列表数据来自 [PhotoFrameState.castRecords]。
class CastManagementFigmaPage extends StatefulWidget {
  const CastManagementFigmaPage({super.key, required this.state});

  final PhotoFrameState state;

  @override
  State<CastManagementFigmaPage> createState() =>
      _CastManagementFigmaPageState();
}

class _CastManagementFigmaPageState extends State<CastManagementFigmaPage>
    with RouteAware {
  CastStatus _tab = CastStatus.success;

  /// 每次拉取的本地 loading（区别于 state.castRecordsLoaded 这个「一旦成功就常驻 true」的
  /// stale-while-revalidate 标记）。切 tab / 重入 / 首屏拉取期间都显示列表区 loading，
  /// 避免数据回来前先闪「暂无记录」空态。
  bool _loading = true;

  PhotoFrameState get state => widget.state;

  @override
  void initState() {
    super.initState();
    // 打开时刷新设备 + 当前 tab 的投屏记录，两者并发（原来串行 await，
    // 记录页的 loading 要白等一个跟记录无关的设备接口往返）。
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final devices = state.refreshDevices();
      final records = _loadTab();
      await devices;
      await records;
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute) {
      appRouteObserver.subscribe(this, route);
    }
  }

  @override
  void dispose() {
    appRouteObserver.unsubscribe(this);
    super.dispose();
  }

  /// 被覆盖的页 pop 回来（重入）：刷新设备 + 当前 tab 记录（对齐小程序 onShow loadRecords）。
  @override
  void didPopNext() {
    state.refreshDevices();
    _loadTab();
  }

  /// 成功 tab→deviceUploadState:1 / 失败 tab→0（对齐小程序 records.js filterToUploadState）。
  int _uploadStateOf(CastStatus tab) => tab == CastStatus.success ? 1 : 0;

  /// 按当前 tab 状态回后端拉取记录（分状态拉取，避免 >100 条时本地切片丢行）。
  Future<void> _loadTab() async {
    if (mounted) {
      setState(() => _loading = true);
    }
    await state.refreshCastRecords(deviceUploadState: _uploadStateOf(_tab));
    if (mounted) {
      setState(() => _loading = false);
    }
  }

  // 后端已按状态过滤；仍按 tab 再筛一层作兜底（后端忽略过滤参数时也不串档）。
  List<CastRecord> get _records =>
      state.castRecords.where((record) => record.status == _tab).toList();

  // 再次/重新投屏：对齐小程序 records.js retryProjection —— 重新进入「裁剪/预览」流程（用记录原图），
  // 让用户可再裁剪/旋转/还原后再投，而不是直接 imgBle 直传。
  // 先连设备；连上后把记录原图下载到本地进投屏预览页（裁剪流程）；拿不到原图才回退 imgBle 直传，保证仍能再投。
  Future<void> _recast(CastRecord record) async {
    final l10n = AppL10n.of(context);
    final imgBle = record.imgBle;
    if (imgBle == null || imgBle.isEmpty) {
      _showSnack(l10n.castRecordMissingFrame);
      return;
    }
    _showSnack(l10n.castConnectingDevice);
    final feedback = await state.connectDevice(record.deviceId);
    if (!mounted) {
      return;
    }
    if (!feedback.success) {
      _showSnack(feedback.message);
      return;
    }
    final device = state.deviceById(record.deviceId);
    final imageUrl = record.imageUrl;
    final localPath = (imageUrl != null && imageUrl.isNotEmpty)
        ? await _downloadToTemp(imageUrl)
        : null;
    if (!mounted) {
      return;
    }
    if (localPath != null) {
      // 原图可用：进入裁剪/预览流程（与小程序一致），确认后由预览页走投屏。
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) =>
              CastPreviewPage(device: device, imagePaths: [localPath]),
        ),
      );
    } else {
      // 原图不可用（无 URL 或下载失败）：回退到 imgBle 直传，避免完全无法再投。
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => CastingProgressPage(
            userProductId: record.deviceId,
            deviceName: record.deviceName.isNotEmpty
                ? record.deviceName
                : state.deviceName(record.deviceId),
            recastImgBle: imgBle,
            recastUpirId: record.id,
            recastImgUrl: record.imageUrl,
          ),
        ),
      );
    }
    if (!mounted) {
      return;
    }
    // 再次投屏会新增一条投屏记录：返回后按当前 tab 刷新列表。
    await _loadTab();
  }

  /// 把记录原图下载到本地临时文件，供投屏预览页（裁剪流程）使用；失败返回 null。
  Future<String?> _downloadToTemp(String url) async {
    try {
      final resp = await http.get(Uri.parse(url));
      if (resp.statusCode != 200) {
        return null;
      }
      final file = File(
        '${Directory.systemTemp.path}/recast_${DateTime.now().microsecondsSinceEpoch}.jpg',
      );
      await file.writeAsBytes(resp.bodyBytes, flush: true);
      return file.path;
    } catch (_) {
      return null;
    }
  }

  void _showSnack(String message) {
    AppToast.show(context, message);
  }

  Future<void> _delete(CastRecord record) async {
    final l10n = AppL10n.of(context);
    // 二次确认（对齐小程序 records.js:215-232 的 wx.showModal），避免误删不可恢复的记录。
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.castDeleteRecordTitle),
        content: Text(l10n.castDeleteRecordConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.castDelete),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    final feedback = await state.deleteCastRecord(record.id);
    if (!mounted) {
      return;
    }
    setState(() {});
    AppToast.show(context, feedback.message);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final records = _records;
    final success = _tab == CastStatus.success;

    return FigmaScreen(
      title: l10n.castManagementTitle,
      scrollable: false,
      bodyPadding: const EdgeInsets.symmetric(horizontal: 24),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          _SegmentedTabs(
            current: _tab,
            onChanged: (value) {
              if (value == _tab) {
                return;
              }
              setState(() => _tab = value);
              _loadTab(); // 切 tab 时按状态回后端重新拉取（对齐小程序 switchFilter）
            },
          ),
          const SizedBox(height: 18),
          // 「共 N 条记录」也要等接口回来再显示，否则首帧会先闪一行「共 0 条记录」
          // （小程序把它一并包在 loading 的 else 分支里，同理）。
          if (!_loading)
            Text(
              l10n.castTotalRecords(records.length),
              style: const TextStyle(
                color: Color(0xFF777E88),
                fontSize: 12,
                height: 1,
              ),
            ),
          const SizedBox(height: 12),
          Expanded(
            // 三分支互斥链（loading 优先）：接口没回来之前不渲染「暂无记录」空态。
            child: _loading
                ? const PageLoading()
                : records.isEmpty
                ? _EmptyRecords(success: success)
                : ListView.separated(
                    padding: const EdgeInsets.only(bottom: 12),
                    physics: const BouncingScrollPhysics(),
                    itemCount: records.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final record = records[index];
                      return _RecordCard(
                        // 设备名直接用记录自带的 productName（后端逐行下发）。
                        // 原来按 deviceId 反查设备列表，设备列表没加载好就会显示成原始数字 id。
                        deviceName: record.deviceName.isNotEmpty
                            ? record.deviceName
                            : state.deviceName(record.deviceId),
                        dateText: state.formatDateTime(record.createdAt),
                        record: record,
                        onRecast: () => _recast(record),
                        onDelete: () => _delete(record),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

/// 分段切换：单个胶囊容器 + 滑动指示器（成功橙 #ff6a20 / 失败红 #ff4350）。
class _SegmentedTabs extends StatelessWidget {
  const _SegmentedTabs({required this.current, required this.onChanged});

  final CastStatus current;
  final ValueChanged<CastStatus> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final success = current == CastStatus.success;
    return Container(
      height: 41,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.84),
        borderRadius: BorderRadius.circular(999),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF7E96B8).withValues(alpha: 0.08),
            blurRadius: 19,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Stack(
        children: [
          AnimatedAlign(
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeOut,
            alignment: success ? Alignment.centerLeft : Alignment.centerRight,
            child: FractionallySizedBox(
              widthFactor: 0.5,
              heightFactor: 1,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: success
                      ? const Color(0xFFFF6A20)
                      : const Color(0xFFFF4350),
                  borderRadius: BorderRadius.circular(999),
                  boxShadow: [
                    BoxShadow(
                      color:
                          (success
                                  ? const Color(0xFFFF6A20)
                                  : const Color(0xFFFF4350))
                              .withValues(alpha: 0.32),
                      blurRadius: 12,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Row(
            children: [
              _Tab(
                label: l10n.castSucceeded,
                active: success,
                onTap: () => onChanged(CastStatus.success),
              ),
              _Tab(
                label: l10n.castFailed,
                active: !success,
                onTap: () => onChanged(CastStatus.failed),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({required this.label, required this.active, required this.onTap});

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: active ? Colors.white : const Color(0xFF858B94),
              fontSize: 14,
              fontWeight: FontWeight.w500,
              height: 1.2,
            ),
          ),
        ),
      ),
    );
  }
}

class _RecordCard extends StatelessWidget {
  const _RecordCard({
    required this.deviceName,
    required this.dateText,
    required this.record,
    required this.onRecast,
    required this.onDelete,
  });

  final String deviceName;
  final String dateText;
  final CastRecord record;
  final VoidCallback onRecast;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final success = record.status == CastStatus.success;
    return FigmaGlassCard(
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 缩略图（小程序 .thumb：144rpx≈72，圆角 14rpx≈7）。
          ClipRRect(
            borderRadius: BorderRadius.circular(7),
            child: Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    record.color.withValues(alpha: 0.92),
                    record.color.withValues(alpha: 0.5),
                  ],
                ),
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (record.imageUrl != null)
                    Image.network(
                      record.imageUrl!,
                      // aspectFit：与我的图库一致，保持比例不裁切不拉伸，按后端记录 img 原样展示
                      // （对齐小程序 records.wxml mode=aspectFit）；留白落在下方色块渐变上。
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) =>
                          const SizedBox.shrink(),
                    ),
                  Center(
                    child: Icon(
                      record.source == ImageSourceType.camera
                          ? Icons.photo_camera_outlined
                          : Icons.collections_outlined,
                      color: Colors.white.withValues(alpha: 0.9),
                      size: 24,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        deviceName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF2A2D32),
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          height: 1.2,
                        ),
                      ),
                    ),
                    const SizedBox(width: 9),
                    _StatusBadge(success: success),
                  ],
                ),
                const SizedBox(height: 12),
                // 时间行：日期图标 + 时间。
                _MetaLine(
                  iconAsset: 'assets/images/date-icon01.png',
                  fallbackIcon: Icons.schedule_rounded,
                  text: dateText,
                  color: const Color(0xFF8B9098),
                ),
                if (!success) ...[
                  const SizedBox(height: 10),
                  _MetaLine(
                    iconAsset: 'assets/images/warning-icon01.png',
                    fallbackIcon: Icons.error_outline_rounded,
                    text: record.message,
                    color: const Color(0xFFEF5B50),
                  ),
                ],
                const SizedBox(height: 16),
                Container(
                  height: 1,
                  color: const Color(0xFF2A2B2B).withValues(alpha: 0.08),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    const Spacer(),
                    _LinkAction(
                      label: success ? l10n.castCastAgain : l10n.castRecast,
                      color: const Color(0xFFFF6A20),
                      onTap: onRecast,
                    ),
                    Container(
                      width: 1,
                      height: 15,
                      margin: const EdgeInsets.symmetric(horizontal: 18),
                      color: const Color(0xFF2A2B2B).withValues(alpha: 0.1),
                    ),
                    _LinkAction(
                      label: l10n.castDelete,
                      color: const Color(0xFF8B9098),
                      onTap: onDelete,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 时间 / 失败原因行：小图标 + 文案。
class _MetaLine extends StatelessWidget {
  const _MetaLine({
    required this.iconAsset,
    required this.fallbackIcon,
    required this.text,
    required this.color,
  });

  final String iconAsset;
  final IconData fallbackIcon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Image.asset(
            iconAsset,
            width: 12,
            height: 12,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) =>
                Icon(fallbackIcon, size: 12, color: color),
          ),
        ),
        const SizedBox(width: 5),
        Expanded(
          child: Text(
            text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: color, fontSize: 12, height: 1.2),
          ),
        ),
      ],
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.success});

  final bool success;

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final color = success ? const Color(0xFF35B856) : const Color(0xFFFF3045);
    final bg = success ? const Color(0xFFE9F8EF) : const Color(0xFFFFF0F1);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7),
      height: 18,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        success ? l10n.castSucceeded : l10n.castFailed,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w500,
          height: 1,
        ),
      ),
    );
  }
}

class _LinkAction extends StatelessWidget {
  const _LinkAction({
    required this.label,
    required this.color,
    required this.onTap,
  });

  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w400,
          height: 1,
        ),
      ),
    );
  }
}

/// 空态（小程序 `.empty-record`）：玻璃卡 + 标题 + 说明（文案随 tab 变化）。
class _EmptyRecords extends StatelessWidget {
  const _EmptyRecords({required this.success});

  final bool success;

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    return FigmaGlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 39),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            success ? l10n.castEmptySuccessTitle : l10n.castEmptyFailedTitle,
            style: const TextStyle(
              color: Color(0xFF2A2D32),
              fontSize: 16,
              fontWeight: FontWeight.w500,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            success ? l10n.castEmptySuccessDesc : l10n.castEmptyFailedDesc,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF777E88),
              fontSize: 13,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}
