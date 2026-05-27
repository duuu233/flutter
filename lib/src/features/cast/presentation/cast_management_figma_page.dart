import 'package:flutter/material.dart';

import '../../../state.dart';
import 'package:BoltStar/src/shared/widgets/figma_common.dart';

/// 投屏管理（图库样式版），对应 UI 稿「投屏管理-投屏成功 / 投屏失败」。
///
/// 顶部用成功 / 失败两个分段切换，列表数据来自 [PhotoFrameState.castRecords]。
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

  List<CastRecord> get _records => state.castRecords
      .where((record) => record.status == _tab)
      .toList();

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

    return FigmaScreen(
      title: '投屏管理',
      scrollable: false,
      bodyPadding: const EdgeInsets.symmetric(horizontal: 16),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          _SegmentedTabs(
            current: _tab,
            onChanged: (value) => setState(() => _tab = value),
          ),
          const SizedBox(height: 14),
          Text(
            '共 ${records.length} 条记录',
            style: FigmaTextStyles.bodySmall.copyWith(fontSize: 13),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: records.isEmpty
                ? const _EmptyRecords()
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

class _SegmentedTabs extends StatelessWidget {
  const _SegmentedTabs({required this.current, required this.onChanged});

  final CastStatus current;
  final ValueChanged<CastStatus> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _TabPill(
          label: '投屏成功',
          active: current == CastStatus.success,
          onTap: () => onChanged(CastStatus.success),
        ),
        const SizedBox(width: 12),
        _TabPill(
          label: '投屏失败',
          active: current == CastStatus.failed,
          onTap: () => onChanged(CastStatus.failed),
        ),
      ],
    );
  }
}

class _TabPill extends StatelessWidget {
  const _TabPill({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? const Color(0xFFFF6A24) : Colors.white,
          borderRadius: BorderRadius.circular(17),
          border: Border.all(
            color: active
                ? const Color(0xFFFF6A24)
                : const Color(0x1A2A2B2B),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? Colors.white : const Color(0x992A2B2B),
            fontSize: 14,
            fontWeight: FontWeight.w500,
            height: 1.2,
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
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: 64,
              height: 64,
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
                size: 22,
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
                          color: Color(0xFF2A2B2B),
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          height: 1.2,
                        ),
                      ),
                    ),
                    _StatusBadge(success: success),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  dateText,
                  style: const TextStyle(
                    color: Color(0x992A2B2B),
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                    height: 1.2,
                  ),
                ),
                if (!success) ...[
                  const SizedBox(height: 6),
                  Text(
                    record.message,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFFEB5F1B),
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                      height: 1.3,
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                Row(
                  children: [
                    const Spacer(),
                    _LinkAction(
                      label: success ? '再次投屏' : '重新投屏',
                      color: const Color(0xFFFF6A24),
                      onTap: onRecast,
                    ),
                    const SizedBox(width: 18),
                    _LinkAction(
                      label: '删除',
                      color: const Color(0x992A2B2B),
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

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.success});

  final bool success;

  @override
  Widget build(BuildContext context) {
    final color = success ? const Color(0xFF1AC27F) : const Color(0xFFEB5F1B);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        success ? '投屏成功' : '投屏失败',
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w500,
          height: 1.2,
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
          fontSize: 13,
          fontWeight: FontWeight.w500,
          height: 1.2,
        ),
      ),
    );
  }
}

class _EmptyRecords extends StatelessWidget {
  const _EmptyRecords();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(
            Icons.inbox_outlined,
            color: Color(0x4D2A2B2B),
            size: 56,
          ),
          SizedBox(height: 12),
          Text(
            '暂无记录',
            style: TextStyle(
              color: Color(0x992A2B2B),
              fontSize: 14,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }
}
