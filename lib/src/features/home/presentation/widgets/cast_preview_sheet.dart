import 'package:flutter/material.dart';

import '../../../../shared/shared.dart';
import '../../../../state.dart';

class CastPreviewSheet extends StatefulWidget {
  const CastPreviewSheet({super.key, required this.state, required this.draft});

  final PhotoFrameState state;
  final DraftPhoto draft;

  @override
  State<CastPreviewSheet> createState() => _CastPreviewSheetState();
}

class _CastPreviewSheetState extends State<CastPreviewSheet> {
  late String _deviceId;

  @override
  void initState() {
    super.initState();
    _deviceId = widget.state.selectedDevice.id;
  }

  @override
  Widget build(BuildContext context) {
    final device = widget.state.deviceById(_deviceId);
    final usage = widget.state.deviceUsage(device.id);

    return BottomSheetFrame(
      title: widget.state.tr(
        zh: '预览图确认',
        en: 'Preview Before Cast',
        ja: '投映前プレビュー',
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: PhotoArtwork(
              color: widget.draft.color,
              source: widget.draft.source,
              width: 190,
              height: 230,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            widget.draft.title,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 6),
          Text(
            widget.state.tr(
              zh: '预处理尺寸：${widget.draft.width.toInt()} × ${widget.draft.height.toInt()}',
              en: 'Processed size: ${widget.draft.width.toInt()} × ${widget.draft.height.toInt()}',
              ja: '処理後サイズ: ${widget.draft.width.toInt()} × ${widget.draft.height.toInt()}',
            ),
          ),
          const SizedBox(height: 6),
          Text(widget.draft.note),
          const SizedBox(height: 18),
          Text(
            widget.state.tr(zh: '目标设备', en: 'Target Device', ja: '投映先端末'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: widget.state.devices.map((deviceItem) {
              final selected = _deviceId == deviceItem.id;
              return ChoiceChip(
                selected: selected,
                label: Text(deviceItem.name),
                onSelected: (_) {
                  setState(() {
                    _deviceId = deviceItem.id;
                  });
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 18),
          Text(
            '${device.name} · $usage/${device.capacity}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: usage / device.capacity,
            minHeight: 10,
            borderRadius: BorderRadius.circular(999),
            backgroundColor: Colors.black.withValues(alpha: 0.06),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(_deviceId),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
            ),
            child: Text(
              widget.state.tr(zh: '确认投屏', en: 'Confirm Cast', ja: '投映を確定'),
            ),
          ),
        ],
      ),
    );
  }
}
