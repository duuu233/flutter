import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../widgets/figma_common.dart';

/// 更新 BoltStar 页面的三种状态，分别对应 UI 稿
/// 「更新BoltStar」(已是最新)、「立即更新」(有新版本)、「正在更新」(下载中)。
enum BoltStarUpdateStage { upToDate, updateAvailable, downloading }

const String _currentVersion = '1.0.0';
const String _latestVersion = '1.2.0';
const String _appIntro = 'BoltStar是一款帮助您轻松管理和分享照片的应用，\n连接设备，珍藏生活每一刻。';

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
    return FigmaPhoneFrame(
      child: Stack(
        children: [
          const FigmaPageBackground(),
          const Positioned(
            left: 0,
            top: 0,
            width: 375,
            height: 90,
            child: FigmaTopNavigation(title: '更新BoltStar'),
          ),
          const Positioned(
            left: 0,
            top: 168,
            width: 375,
            child: Center(child: _BoltStarWordmark()),
          ),
          Positioned(
            left: 24,
            top: 224,
            width: 327,
            child: Center(child: _versionLabel()),
          ),
          if (_stage == BoltStarUpdateStage.downloading)
            Positioned(
              left: 0,
              top: 300,
              width: 375,
              child: Center(
                child: AnimatedBuilder(
                  animation: _downloadController,
                  builder: (context, _) {
                    return _DownloadProgressRing(
                      progress: _downloadController.value,
                    );
                  },
                ),
              ),
            )
          else
            const Positioned(
              left: 40,
              top: 296,
              width: 295,
              child: Text(
                _appIntro,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xCC2A2B2B),
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                  height: 1.7,
                ),
              ),
            ),
          if (_stage == BoltStarUpdateStage.updateAvailable)
            Positioned(
              left: 26,
              top: 543,
              width: 323,
              height: 64,
              child: FigmaPrimaryButton(
                label: '立即更新',
                height: 64,
                onPressed: _startDownload,
              ),
            ),
          const FigmaBottomHomeIndicator(),
        ],
      ),
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
  color: Color(0x992A2B2B),
  fontSize: 13,
  fontWeight: FontWeight.w400,
  height: 1.4,
);

class _BoltStarWordmark extends StatelessWidget {
  const _BoltStarWordmark();

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/images/login_boltstar_logo.png',
      height: 40,
      fit: BoxFit.contain,
      errorBuilder: (context, error, stackTrace) {
        return const Text(
          'BoltStar',
          style: TextStyle(
            color: Color(0xFFFF6A24),
            fontSize: 34,
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
      width: 168,
      height: 168,
      child: CustomPaint(
        painter: _RingPainter(progress: progress),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '$percent%',
                style: const TextStyle(
                  color: Color(0xFFFF6A24),
                  fontSize: 34,
                  fontWeight: FontWeight.w600,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                '正在下载更新中',
                style: TextStyle(
                  color: Color(0x992A2B2B),
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - 12) / 2;
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFFEDEDED);
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFFFF6A24);

    canvas.drawCircle(center, radius, track);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
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
