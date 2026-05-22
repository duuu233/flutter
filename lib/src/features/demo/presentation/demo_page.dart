import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../shared/shared.dart';
import '../../../state.dart';

class DemoPage extends StatefulWidget {
  const DemoPage({super.key, required this.state});

  final PhotoFrameState state;

  @override
  State<DemoPage> createState() => _DemoPageState();
}

class _DemoPageState extends State<DemoPage> {
  static const _imageAsset = 'assets/images/1.png';

  Rect _crop = const Rect.fromLTWH(0.14, 0.14, 0.72, 0.62);
  double _angle = 0;

  double get _degrees => _angle * 180 / math.pi;

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final theme = Theme.of(context);

    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 120),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      color: theme.colorScheme.primary.withValues(alpha: 0.12),
                    ),
                    child: Icon(
                      Icons.crop_rotate_rounded,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          state.tr(
                            zh: '图片裁剪旋转',
                            en: 'Crop & Rotate',
                            ja: 'クロップと回転',
                          ),
                          style: theme.textTheme.headlineSmall,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          state.tr(
                            zh: '拖动裁剪框，拖拽四角调整范围。',
                            en: 'Drag the crop box or resize from corners.',
                            ja: '枠をドラッグし、四隅で範囲を調整します。',
                          ),
                          style: theme.textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              AppPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _PanelTitle(
                      icon: Icons.tune_rounded,
                      title: state.tr(zh: '编辑区', en: 'Editor', ja: '編集'),
                      trailing:
                          '${_degrees.round()}deg · ${(_crop.width * 100).round()}% x ${(_crop.height * 100).round()}%',
                    ),
                    const SizedBox(height: 14),
                    _CropEditor(
                      imageAsset: _imageAsset,
                      crop: _crop,
                      angle: _angle,
                      onCropChanged: (crop) => setState(() => _crop = crop),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              AppPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _PanelTitle(
                      icon: Icons.rotate_90_degrees_ccw_rounded,
                      title: state.tr(zh: '旋转', en: 'Rotate', ja: '回転'),
                      trailing: '${_degrees.round()}deg',
                    ),
                    Slider(
                      value: _degrees,
                      min: -180,
                      max: 180,
                      divisions: 72,
                      label: '${_degrees.round()}deg',
                      onChanged: _setDegrees,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        _ActionChipButton(
                          icon: Icons.rotate_left_rounded,
                          label: '-90deg',
                          onPressed: () => _rotateBy(-90),
                        ),
                        _ActionChipButton(
                          icon: Icons.rotate_right_rounded,
                          label: '+90deg',
                          onPressed: () => _rotateBy(90),
                        ),
                        _ActionChipButton(
                          icon: Icons.refresh_rounded,
                          label: state.tr(zh: '重置', en: 'Reset', ja: 'リセット'),
                          onPressed: _resetEditor,
                        ),
                      ],
                    ),
                    const Divider(height: 28),
                    _PanelTitle(
                      icon: Icons.aspect_ratio_rounded,
                      title: state.tr(zh: '裁剪比例', en: 'Crop Ratio', ja: '比率'),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        _ActionChipButton(
                          label: '1:1',
                          onPressed: () => _applyRatio(1),
                        ),
                        _ActionChipButton(
                          label: '4:3',
                          onPressed: () => _applyRatio(4 / 3),
                        ),
                        _ActionChipButton(
                          label: '16:9',
                          onPressed: () => _applyRatio(16 / 9),
                        ),
                        _ActionChipButton(
                          label: '3:4',
                          onPressed: () => _applyRatio(3 / 4),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              AppPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _PanelTitle(
                      icon: Icons.image_search_rounded,
                      title: state.tr(zh: '实时预览', en: 'Preview', ja: 'プレビュー'),
                      trailing:
                          '${(_crop.left * 100).round()},${(_crop.top * 100).round()}',
                    ),
                    const SizedBox(height: 14),
                    _CropPreview(
                      imageAsset: _imageAsset,
                      crop: _crop,
                      angle: _angle,
                    ),
                  ],
                ),
              ),
            ]),
          ),
        ),
      ],
    );
  }

  void _setDegrees(double value) {
    setState(() {
      _angle = value * math.pi / 180;
    });
  }

  void _rotateBy(double degrees) {
    setState(() {
      final next = _normalizeDegrees(_degrees + degrees);
      _angle = next * math.pi / 180;
    });
  }

  void _applyRatio(double aspectRatio) {
    setState(() {
      final center = _crop.center;
      const maxWidth = 0.76;
      const maxHeight = 0.68;

      var width = maxWidth;
      var height = width / aspectRatio;
      if (height > maxHeight) {
        height = maxHeight;
        width = height * aspectRatio;
      }

      _crop = _rectFromCenter(center, width, height);
    });
  }

  void _resetEditor() {
    setState(() {
      _crop = const Rect.fromLTWH(0.14, 0.14, 0.72, 0.62);
      _angle = 0;
    });
  }
}

class _CropEditor extends StatelessWidget {
  const _CropEditor({
    required this.imageAsset,
    required this.crop,
    required this.angle,
    required this.onCropChanged,
  });

  final String imageAsset;
  final Rect crop;
  final double angle;
  final ValueChanged<Rect> onCropChanged;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 4 / 3,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = Size(constraints.maxWidth, constraints.maxHeight);
          final cropRect = Rect.fromLTRB(
            crop.left * size.width,
            crop.top * size.height,
            crop.right * size.width,
            crop.bottom * size.height,
          );

          return ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: Stack(
              fit: StackFit.expand,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: const Color(0xFF1F2933),
                    borderRadius: BorderRadius.circular(22),
                  ),
                ),
                Transform.rotate(
                  angle: angle,
                  child: Image.asset(imageAsset, fit: BoxFit.cover),
                ),
                IgnorePointer(
                  child: CustomPaint(painter: _CropShadePainter(cropRect)),
                ),
                Positioned.fromRect(
                  rect: cropRect,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.move,
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onPanUpdate: (details) {
                        final delta = Offset(
                          details.delta.dx / size.width,
                          details.delta.dy / size.height,
                        );
                        onCropChanged(_moveCrop(crop, delta));
                      },
                    ),
                  ),
                ),
                for (final handle in _CropHandle.values)
                  _CropHandleGrip(
                    handle: handle,
                    cropRect: cropRect,
                    editorSize: size,
                    onPanUpdate: (delta) {
                      onCropChanged(_resizeCrop(crop, handle, delta));
                    },
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _CropPreview extends StatelessWidget {
  const _CropPreview({
    required this.imageAsset,
    required this.crop,
    required this.angle,
  });

  final String imageAsset;
  final Rect crop;
  final double angle;

  @override
  Widget build(BuildContext context) {
    final aspectRatio = crop.width / crop.height;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = _clampDouble(width / aspectRatio, 180, 320);

        return SizedBox(
          width: width,
          height: height,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: DecoratedBox(
              decoration: const BoxDecoration(color: Color(0xFF111827)),
              child: LayoutBuilder(
                builder: (context, previewConstraints) {
                  final previewWidth = previewConstraints.maxWidth;
                  final previewHeight = previewConstraints.maxHeight;
                  final sourceWidth = previewWidth / crop.width;
                  final sourceHeight = previewHeight / crop.height;

                  return ClipRect(
                    child: Transform.rotate(
                      angle: angle,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Positioned(
                            left: -sourceWidth * crop.left,
                            top: -sourceHeight * crop.top,
                            width: sourceWidth,
                            height: sourceHeight,
                            child: Image.asset(imageAsset, fit: BoxFit.cover),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CropHandleGrip extends StatelessWidget {
  const _CropHandleGrip({
    required this.handle,
    required this.cropRect,
    required this.editorSize,
    required this.onPanUpdate,
  });

  final _CropHandle handle;
  final Rect cropRect;
  final Size editorSize;
  final ValueChanged<Offset> onPanUpdate;

  @override
  Widget build(BuildContext context) {
    const hitSize = 40.0;
    const gripSize = 14.0;
    final center = _handleCenter(cropRect, handle);

    return Positioned(
      left: center.dx - hitSize / 2,
      top: center.dy - hitSize / 2,
      width: hitSize,
      height: hitSize,
      child: MouseRegion(
        cursor: _cursorForHandle(handle),
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onPanUpdate: (details) {
            onPanUpdate(
              Offset(
                details.delta.dx / editorSize.width,
                details.delta.dy / editorSize.height,
              ),
            );
          },
          child: Center(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: Theme.of(context).colorScheme.secondary,
                  width: 2,
                ),
                boxShadow: [
                  BoxShadow(
                    blurRadius: 8,
                    color: Colors.black.withValues(alpha: 0.24),
                  ),
                ],
              ),
              child: const SizedBox(width: gripSize, height: gripSize),
            ),
          ),
        ),
      ),
    );
  }
}

class _CropShadePainter extends CustomPainter {
  const _CropShadePainter(this.cropRect);

  final Rect cropRect;

  @override
  void paint(Canvas canvas, Size size) {
    final cropRRect = RRect.fromRectAndRadius(
      cropRect,
      const Radius.circular(16),
    );
    final shadePath = Path()
      ..addRect(Offset.zero & size)
      ..addRRect(cropRRect)
      ..fillType = PathFillType.evenOdd;

    canvas.drawPath(
      shadePath,
      Paint()..color = Colors.black.withValues(alpha: 0.46),
    );

    final borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2;
    canvas.drawRRect(cropRRect, borderPaint);

    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.68)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    for (var index = 1; index < 3; index++) {
      final dx = cropRect.left + cropRect.width * index / 3;
      canvas.drawLine(
        Offset(dx, cropRect.top),
        Offset(dx, cropRect.bottom),
        gridPaint,
      );

      final dy = cropRect.top + cropRect.height * index / 3;
      canvas.drawLine(
        Offset(cropRect.left, dy),
        Offset(cropRect.right, dy),
        gridPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CropShadePainter oldDelegate) {
    return oldDelegate.cropRect != cropRect;
  }
}

class _PanelTitle extends StatelessWidget {
  const _PanelTitle({required this.icon, required this.title, this.trailing});

  final IconData icon;
  final String title;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        Icon(icon, size: 20, color: theme.colorScheme.primary),
        const SizedBox(width: 8),
        Expanded(child: Text(title, style: theme.textTheme.titleMedium)),
        if (trailing != null)
          Text(
            trailing!,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
      ],
    );
  }
}

class _ActionChipButton extends StatelessWidget {
  const _ActionChipButton({
    required this.label,
    required this.onPressed,
    this.icon,
  });

  final String label;
  final IconData? icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton.tonal(
      onPressed: onPressed,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 18),
            const SizedBox(width: 6),
          ],
          Text(label),
        ],
      ),
    );
  }
}

enum _CropHandle { topLeft, topRight, bottomLeft, bottomRight }

Rect _moveCrop(Rect crop, Offset delta) {
  final left = _clampDouble(crop.left + delta.dx, 0, 1 - crop.width);
  final top = _clampDouble(crop.top + delta.dy, 0, 1 - crop.height);
  return Rect.fromLTWH(left, top, crop.width, crop.height);
}

Rect _resizeCrop(Rect crop, _CropHandle handle, Offset delta) {
  const minSize = 0.18;
  var left = crop.left;
  var top = crop.top;
  var right = crop.right;
  var bottom = crop.bottom;

  switch (handle) {
    case _CropHandle.topLeft:
      left = _clampDouble(left + delta.dx, 0, right - minSize);
      top = _clampDouble(top + delta.dy, 0, bottom - minSize);
      break;
    case _CropHandle.topRight:
      right = _clampDouble(right + delta.dx, left + minSize, 1);
      top = _clampDouble(top + delta.dy, 0, bottom - minSize);
      break;
    case _CropHandle.bottomLeft:
      left = _clampDouble(left + delta.dx, 0, right - minSize);
      bottom = _clampDouble(bottom + delta.dy, top + minSize, 1);
      break;
    case _CropHandle.bottomRight:
      right = _clampDouble(right + delta.dx, left + minSize, 1);
      bottom = _clampDouble(bottom + delta.dy, top + minSize, 1);
      break;
  }

  return Rect.fromLTRB(left, top, right, bottom);
}

Rect _rectFromCenter(Offset center, double width, double height) {
  final halfWidth = width / 2;
  final halfHeight = height / 2;
  final left = _clampDouble(center.dx - halfWidth, 0, 1 - width);
  final top = _clampDouble(center.dy - halfHeight, 0, 1 - height);

  return Rect.fromLTWH(left, top, width, height);
}

Offset _handleCenter(Rect rect, _CropHandle handle) {
  switch (handle) {
    case _CropHandle.topLeft:
      return rect.topLeft;
    case _CropHandle.topRight:
      return rect.topRight;
    case _CropHandle.bottomLeft:
      return rect.bottomLeft;
    case _CropHandle.bottomRight:
      return rect.bottomRight;
  }
}

MouseCursor _cursorForHandle(_CropHandle handle) {
  switch (handle) {
    case _CropHandle.topLeft:
    case _CropHandle.bottomRight:
      return SystemMouseCursors.resizeUpLeftDownRight;
    case _CropHandle.topRight:
    case _CropHandle.bottomLeft:
      return SystemMouseCursors.resizeUpRightDownLeft;
  }
}

double _normalizeDegrees(double degrees) {
  var normalized = degrees % 360;
  if (normalized > 180) {
    normalized -= 360;
  }
  return normalized;
}

double _clampDouble(double value, double min, double max) {
  return value.clamp(min, max).toDouble();
}
