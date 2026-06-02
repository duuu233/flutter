import 'package:flutter/material.dart';

import '../../../state.dart';
import 'package:BoltStar/src/shared/widgets/figma_common.dart';

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

class _CastManagementFigmaPageState extends State<CastManagementFigmaPage> {
  CastStatus _tab = CastStatus.success;

  PhotoFrameState get state => widget.state;

  List<CastRecord> get _records =>
      state.castRecords.where((record) => record.status == _tab).toList();

  void _recast(CastRecord record) {
    final result = state.recastRecord(record.id, record.deviceId);
    setState(() {});
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(result.message)));
  }

  void _delete(CastRecord record) {
    state.deleteCastRecord(record.id);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final records = _records;
    final success = _tab == CastStatus.success;

    return FigmaScreen(
      title: '投屏管理',
      scrollable: false,
      bodyPadding: const EdgeInsets.symmetric(horizontal: 24),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          _SegmentedTabs(
            current: _tab,
            onChanged: (value) => setState(() => _tab = value),
          ),
          const SizedBox(height: 18),
          Text(
            '共 ${records.length} 条记录',
            style: const TextStyle(
              color: Color(0xFF777E88),
              fontSize: 12,
              height: 1,
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: records.isEmpty
                ? _EmptyRecords(success: success)
                : ListView.separated(
                    padding: const EdgeInsets.only(bottom: 12),
                    physics: const BouncingScrollPhysics(),
                    itemCount: records.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final record = records[index];
                      return _RecordCard(
                        deviceName: state.deviceName(record.deviceId),
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
                label: '投屏成功',
                active: success,
                onTap: () => onChanged(CastStatus.success),
              ),
              _Tab(
                label: '投屏失败',
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
              child: Icon(
                record.source == ImageSourceType.camera
                    ? Icons.photo_camera_outlined
                    : Icons.collections_outlined,
                color: Colors.white.withValues(alpha: 0.9),
                size: 24,
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
                      label: success ? '再次投屏' : '重新投屏',
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
                      label: '删除',
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
        success ? '投屏成功' : '投屏失败',
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
    return FigmaGlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 39),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            success ? '暂无成功记录' : '暂无失败记录',
            style: const TextStyle(
              color: Color(0xFF2A2D32),
              fontSize: 16,
              fontWeight: FontWeight.w500,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            success ? '完成一次照片投屏后会显示在这里。' : '投屏失败时会保留原因，方便排查。',
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
