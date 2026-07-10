import 'package:flutter/material.dart';

import 'package:BoltStar/src/shared/widgets/figma_common.dart';

/// 照片预览-裁剪调整页：投屏前调整照片显示区域，对应 UI 稿「照片预览-调整」。
class PhotoPreviewAdjustImagePage extends StatelessWidget {
  const PhotoPreviewAdjustImagePage({
    super.key,
    this.onSave,
    this.onStartCasting,
    this.onCrop,
    this.onRotate,
    this.onOriginal,
    this.compressImage = true,
    this.onCompressChanged,
  });

  final VoidCallback? onSave;
  final VoidCallback? onStartCasting;
  final VoidCallback? onCrop;
  final VoidCallback? onRotate;
  final VoidCallback? onOriginal;

  /// 「压缩图片」开关初始值（对齐小程序预览页 switch，默认开启=后端压到约300-400KB）。
  final bool compressImage;

  /// 开关变化回调（接 PhotoFrameState.setProjectionCompress，投屏链路据此传 isCompress）。
  final ValueChanged<bool>? onCompressChanged;

  @override
  Widget build(BuildContext context) {
    return FigmaScreen(
      title: '照片预览',
      scrollable: false,
      trailing: TextButton(
        onPressed: onSave,
        child: const Text(
          '保存',
          style: TextStyle(color: Color(0xFF2A2B2B), fontSize: 14),
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          Expanded(
            child: Stack(
              children: const [
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Color(0xFFD9D9D9),
                      borderRadius: BorderRadius.all(Radius.circular(16)),
                    ),
                    child: Center(
                      child: Text(
                        'Image Placeholder',
                        style: TextStyle(
                          color: Color(0xFF737373),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.topCenter,
                  child: Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: SizedBox(
                      width: 71,
                      height: 30,
                      child: _PreviewCounter(label: '2/10'),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 74,
            child: _PhotoToolBar(
              onCrop: onCrop,
              onRotate: onRotate,
              onOriginal: onOriginal,
            ),
          ),
          const SizedBox(height: 12),
          _CompressSwitchRow(
            value: compressImage,
            onChanged: onCompressChanged,
          ),
        ],
      ),
      bottom: FigmaPrimaryButton(label: '开始投屏', onPressed: onStartCasting),
    );
  }
}

/// 「压缩图片」开关行（对齐小程序预览页）：开=后端压缩到约300-400KB，关=传原图。
/// 页面本身是 Stateless，这里内聚一个局部 State 让开关即时响应，再经 [onChanged] 上报持久层。
class _CompressSwitchRow extends StatefulWidget {
  const _CompressSwitchRow({required this.value, this.onChanged});

  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  State<_CompressSwitchRow> createState() => _CompressSwitchRowState();
}

class _CompressSwitchRowState extends State<_CompressSwitchRow> {
  late bool _value = widget.value;

  @override
  Widget build(BuildContext context) {
    return FigmaGlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      child: Row(
        children: [
          const Expanded(
            child: Text('压缩图片（关闭后传原图，耗时更久）', style: FigmaTextStyles.bodySmall),
          ),
          Switch(
            value: _value,
            activeThumbColor: const Color(0xFFEB5F1B),
            onChanged: (value) {
              setState(() => _value = value);
              widget.onChanged?.call(value);
            },
          ),
        ],
      ),
    );
  }
}

class _PreviewCounter extends StatelessWidget {
  const _PreviewCounter({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Center(
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class _PhotoToolBar extends StatelessWidget {
  const _PhotoToolBar({this.onCrop, this.onRotate, this.onOriginal});

  final VoidCallback? onCrop;
  final VoidCallback? onRotate;
  final VoidCallback? onOriginal;

  @override
  Widget build(BuildContext context) {
    return FigmaGlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _PhotoToolButton(
            icon: Icons.crop_rounded,
            label: '裁剪',
            onTap: onCrop,
          ),
          _PhotoToolButton(
            icon: Icons.rotate_right_rounded,
            label: '旋转',
            onTap: onRotate,
          ),
          _PhotoToolButton(
            icon: Icons.image_outlined,
            label: '原图',
            onTap: onOriginal,
          ),
        ],
      ),
    );
  }
}

class _PhotoToolButton extends StatelessWidget {
  const _PhotoToolButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: SizedBox(
        width: 72,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: const Color(0xFF2A2B2B), size: 22),
            const SizedBox(height: 7),
            Text(label, style: FigmaTextStyles.bodySmall),
          ],
        ),
      ),
    );
  }
}
