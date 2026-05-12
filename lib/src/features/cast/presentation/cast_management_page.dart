import 'package:flutter/material.dart';

import '../../../shared/shared.dart';
import '../../../state.dart';

class CastManagementPage extends StatelessWidget {
  const CastManagementPage({super.key, required this.state});

  final PhotoFrameState state;

  @override
  Widget build(BuildContext context) {
    return SubPageScaffold(
      title: state.tr(zh: '投屏管理', en: 'Cast Management', ja: '投映管理'),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: state.castRecords.map((record) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: RecordCard(
              state: state,
              record: record,
              onRecast: () async {
                final deviceId = await _pickDevice(context, state);
                if (!context.mounted || deviceId == null) {
                  return;
                }
                final result = state.recastRecord(record.id, deviceId);
                _showFeedback(context, result.message);
              },
              onDelete: () => state.deleteCastRecord(record.id),
            ),
          );
        }).toList(),
      ),
    );
  }

  Future<String?> _pickDevice(BuildContext context, PhotoFrameState state) {
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(state.tr(zh: '选择设备', en: 'Choose Device', ja: '端末選択')),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: state.devices.map((device) {
              return ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(device.name),
                subtitle: Text(device.kind),
                onTap: () => Navigator.of(context).pop(device.id),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  void _showFeedback(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}
