import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:BoltStar/src/shared/widgets/figma_common.dart';

/// 更新 BoltStar 页面的三种状态，分别对应 UI 稿
/// 「更新BoltStar」(已是最新)、「立即更新」(有新版本)、「正在更新」(下载中)。
enum BoltStarUpdateStage { upToDate, updateAvailable, downloading }

const String _currentVersion = '1.0.0';
const String _latestVersion = '1.2.0';
const String _appIntro = 'BoltStar是一款帮助你轻松管理和分享照片的应用，连接设备，珍藏生活每一刻。';

/// 更新 BoltStar 页面。
///
/// 真实环境下应在进入页面时请求版本检查接口，根据返回结果决定初始 [stage]。
/// 这里用 [stage] 入参模拟三种状态，并用本地动画模拟下载进度（伪逻辑）。
class UpdateBoltStarPage extends StatefulWidget {
  const UpdateBoltStarPage({
    super.key,
    this.stage = BoltStarUpdateStage.upToDate,
  });

  final BoltStarUpdateStage stage;

  @override
  State<UpdateBoltStarPage> createState() => _UpdateBoltStarPageState();
}

class _UpdateBoltStarPageState extends State<UpdateBoltStarPage>
    with SingleTickerProviderStateMixin {
  late BoltStarUpdateStage _stage = widget.stage;
  late final AnimationController _downloadController;

  @override
  void initState() {
    super.initState();
    _downloadController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..addStatusListener(_onDownloadStatus);
    if (_stage == BoltStarUpdateStage.downloading) {
      _downloadController.forward();
    }
  }

  @override
  void dispose() {
    _downloadController.dispose();
    super.dispose();
  }

  void _onDownloadStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed && mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('已更新到最新版本')));
      Navigator.maybePop(context);
    }
  }

  void _startDownload() {
    setState(() => _stage = BoltStarUpdateStage.downloading);
    _downloadController.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    return FigmaScreen(
      title: '更新BoltStar',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 88),
          const Center(child: _BoltStarWordmark()),
          const SizedBox(height: 21),
          Center(child: _versionLabel()),
          const SizedBox(height: 64),
          if (_stage == BoltStarUpdateStage.downloading)
            Center(
              child: AnimatedBuilder(
                animation: _downloadController,
                builder: (context, _) {
                  return _DownloadProgressRing(
                    progress: _downloadController.value,
                  );
                },
              ),
            )
          else
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 28),
              child: Text(
                _appIntro,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF2A2D32),
                  fontSize: 15,
                  fontWeight: FontWeight.w400,
                  height: 1.58,
                ),
              ),
            ),
        ],
      ),
      bottom: _stage == BoltStarUpdateStage.updateAvailable
          ? FigmaPrimaryButton(label: '立即更新', onPressed: _startDownload)
          : null,
    );
  }

  Widget _versionLabel() {
    switch (_stage) {
      case BoltStarUpdateStage.upToDate:
        return const Text('版本$_currentVersion', style: _versionStyle);
      case BoltStarUpdateStage.updateAvailable:
        return const Text(
          '当前版本$_currentVersion · 最新版本$_latestVersion',
          style: _versionStyle,
        );
      case BoltStarUpdateStage.downloading:
        return const Text('正在更新...', style: _versionStyle);
    }
  }
}

const TextStyle _versionStyle = TextStyle(
  color: Color(0xFF808690),
  fontSize: 13,
  fontWeight: FontWeight.w400,
  height: 1,
);

class _BoltStarWordmark extends StatelessWidget {
  const _BoltStarWordmark();

  @override
  Widget build(BuildContext context) {
    // 小程序 logo.png（246×62rpx ≈ 123×31）。
    return Image.asset(
      'assets/images/logo.png',
      height: 31,
      fit: BoxFit.contain,
      errorBuilder: (context, error, stackTrace) {
        return const Text(
          'BoltStar',
          style: TextStyle(
            color: Color(0xFFFF6A24),
            fontSize: 28,
            fontWeight: FontWeight.w700,
            fontStyle: FontStyle.italic,
            letterSpacing: 0.5,
          ),
        );
      },
    );
  }
}

class _DownloadProgressRing extends StatelessWidget {
  const _DownloadProgressRing({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    final percent = (progress * 100).round();
    return SizedBox(
      width: 180,
      height: 180,
      child: CustomPaint(
        painter: _RingPainter(progress: progress),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text.rich(
                TextSpan(
                  text: '$percent',
                  style: const TextStyle(
                    color: Color(0xFFFF6421),
                    fontSize: 37,
                    fontWeight: FontWeight.w400,
                    height: 1,
                  ),
                  children: const [
                    TextSpan(text: '%', style: TextStyle(fontSize: 14)),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                '正在下载更新中',
                style: TextStyle(
                  color: Color(0xFF808690),
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                  height: 1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 进度环（小程序 `.progress-ring`）：外圈 conic 饼图（橙 #ff762f 进度 + 灰 #dfe5ee 余量），
/// 内圈 #edf6ff 实心盖住中心 → 呈现一圈约 8px 的进度带。
class _RingPainter extends CustomPainter {
  const _RingPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    const ringWidth = 8.0;
    final outerRadius = size.width / 2;
    final ringRadius = outerRadius - ringWidth / 2;
    final innerRadius = outerRadius - ringWidth;

    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = ringWidth
      ..color = const Color(0xFFDFE5EE);
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = ringWidth
      ..color = const Color(0xFFFF762F);

    // 内圈浅蓝实心盘。
    canvas.drawCircle(
      center,
      innerRadius,
      Paint()..color = const Color(0xFFEDF6FF),
    );
    // 进度带：灰底 + 橙色弧（butt 端，呈饼图的锐利切边）。
    canvas.drawCircle(center, ringRadius, track);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: ringRadius),
      -math.pi / 2,
      2 * math.pi * progress.clamp(0.0, 1.0),
      false,
      arc,
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
