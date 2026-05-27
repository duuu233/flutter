import 'package:flutter/material.dart';

import '../../../../shared/shared.dart';
import '../../../../state.dart';

/// 草稿选择底部弹层（非独立页面）：从首页选择待投屏的照片草稿。
class DraftPickerSheet extends StatelessWidget {
  const DraftPickerSheet({super.key, required this.state});

  final PhotoFrameState state;

  @override
  Widget build(BuildContext context) {
    return BottomSheetFrame(
      title: state.tr(
        zh: '选择相册图片',
        en: 'Choose an Album Photo',
        ja: 'アルバム画像を選択',
      ),
      child: Column(
        children: state.draftLibrary.map((draft) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: InkWell(
              onTap: () => Navigator.of(context).pop(draft),
              borderRadius: BorderRadius.circular(24),
              child: Ink(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  color: Colors.white.withValues(alpha: 0.78),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    PhotoArtwork(
                      color: draft.color,
                      source: draft.source,
                      width: 82,
                      height: 100,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            draft.title,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '${draft.width.toInt()} × ${draft.height.toInt()}',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          const SizedBox(height: 6),
                          Text(draft.note),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
