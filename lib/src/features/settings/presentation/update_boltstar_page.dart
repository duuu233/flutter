import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:BoltStar/src/shared/widgets/figma_common.dart';
import '../../../shared/l10n/app_l10n.dart';
import '../../../shared/widgets/app_toast.dart';
import '../../../state.dart';

/// 更新 BoltStar 页面的展示态，对应 UI 稿：
/// - [checking]：进入页面正在请求版本检查（logo + 「检查更新中…」）。
/// - [upToDate]：已是最新（logo + 「版本 x.x.x」+ 应用简介，无按钮）。
/// - [updateAvailable]：有新版本（logo + 「当前版本 x · 最新版本 y」+ 简介 + 「立即更新」）。
/// - [downloading]：点「立即更新」后（logo + 「正在更新…」+ 进度环）。
enum BoltStarUpdateStage { checking, upToDate, updateAvailable, downloading }

/// 更新 BoltStar 页面（设置页「检测更新」入口跳转到此）。
///
/// 进入即调用 [PhotoFrameState.checkAppVersion] 真实检查版本：
/// 当前版本来自 `package_info`，最新版本 / 下载地址来自后端 `getLastVersion`。
/// 「立即更新」用系统浏览器 / 应用商店打开下载地址（对齐项目既定设计，见 pubspec
/// 中 url_launcher 的说明）；打开下载地址的同时切到「正在更新」进度环作为视觉反馈。
/// 页面背景走 [FigmaScreen] 默认的 `bg01.png`（与其它页面统一，非 UI 稿里的过时浅蓝渐变）。
///
/// [previewStage] 仅供未接入导航的演示路由（`figmaUpdateBoltStar*`）强制展示某一态，
/// 此时用占位版本号、不发起真实请求；正常入口只传 [state]。
class UpdateBoltStarPage extends StatefulWidget {
  const UpdateBoltStarPage({super.key, this.state, this.previewStage});

  final PhotoFrameState? state;
  final BoltStarUpdateStage? previewStage;

  @override
  State<UpdateBoltStarPage> createState() => _UpdateBoltStarPageState();
}

class _UpdateBoltStarPageState extends State<UpdateBoltStarPage>
    with SingleTickerProviderStateMixin {
  late BoltStarUpdateStage _stage;
  late final AnimationController _downloadController;

  String _currentVersion = '';
  String _latestVersion = '';
  String _downloadUrl = '';

  @override
  void initState() {
    super.initState();
    _downloadController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    );

    final preview = widget.previewStage;
    if (preview != null) {
      // 演示路由：占位版本号 + 指定态，不发真实请求。
      _stage = preview;
      _currentVersion = '1.0.0';
      _latestVersion = '1.2.0';
      if (preview == BoltStarUpdateStage.downloading) {
        _downloadController.forward();
      }
      return;
    }

    // 正常入口：进入即真实检查版本。
    _stage = BoltStarUpdateStage.checking;
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  @override
  void dispose() {
    _downloadController.dispose();
    super.dispose();
  }

  Future<void> _check() async {
    final state = widget.state;
    if (state == null) {
      return;
    }
    final info = await state.checkAppVersion();
    if (!mounted) {
      return;
    }
    if (info == null) {
      // 检查失败（网络异常等）：提示后返回，不停在空白页。
      AppToast.warn(context, AppL10n.of(context).setCheckUpdateFailed);
      Navigator.of(context).maybePop();
      return;
    }
    setState(() {
      _currentVersion = info.currentVersion;
      _latestVersion = info.latestVersion;
      _downloadUrl = info.downloadUrl;
      _stage = info.hasUpdate
          ? BoltStarUpdateStage.updateAvailable
          : BoltStarUpdateStage.upToDate;
    });
  }

  Future<void> _startUpdate() async {
    // 切到「正在更新」进度环作为视觉反馈，同时用系统浏览器/商店打开下载地址
    //（真实下载/安装交给系统，对齐项目既定设计）。
    setState(() => _stage = BoltStarUpdateStage.downloading);
    _downloadController.forward(from: 0);

    final url = _downloadUrl.trim();
    final uri = url.isEmpty ? null : Uri.tryParse(url);
    if (uri == null) {
      if (mounted) {
        AppToast.warn(context, AppL10n.of(context).setCheckUpdateFailed);
      }
      return;
    }
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (mounted) {
        AppToast.warn(context, AppL10n.of(context).setDownloadOpenFailed);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return FigmaScreen(
      title: AppL10n.of(context).setUpdateBoltStar,
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
                builder: (context, _) =>
                    _DownloadProgressRing(progress: _downloadController.value),
              ),
            )
          else if (_stage != BoltStarUpdateStage.checking)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Text(
                AppL10n.of(context).setAppIntro,
                textAlign: TextAlign.center,
                style: const TextStyle(
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
          ? FigmaPrimaryButton(
              label: AppL10n.of(context).setUpdateNow,
              onPressed: _startUpdate,
            )
          : null,
    );
  }

  Widget _versionLabel() {
    final l10n = AppL10n.of(context);
    switch (_stage) {
      case BoltStarUpdateStage.checking:
        return Text(l10n.setCheckingUpdate, style: _versionStyle);
      case BoltStarUpdateStage.upToDate:
        return Text(l10n.setVersionLabel(_currentVersion), style: _versionStyle);
      case BoltStarUpdateStage.updateAvailable:
        return Text(
          l10n.setVersionCompare(_currentVersion, _latestVersion),
          style: _versionStyle,
        );
      case BoltStarUpdateStage.downloading:
        return Text(l10n.setUpdating, style: _versionStyle);
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
              Text(
                AppL10n.of(context).setDownloading,
                style: const TextStyle(
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

/// 进度环（小程序 `.progress-ring`）：外圈饼图（橙 #ff762f 进度 + 灰 #dfe5ee 余量），
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

    canvas.drawCircle(
      center,
      innerRadius,
      Paint()..color = const Color(0xFFEDF6FF),
    );
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
