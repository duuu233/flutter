import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:BoltStar/src/shared/widgets/figma_common.dart';
import '../../../routes/app_routes.dart';
import '../../../shared/l10n/app_l10n.dart';
import '../../../shared/widgets/app_toast.dart';
import '../../../state.dart';

/// 更新 BoltStar 页面的展示态，对应 UI 稿：
/// - [checking]：进入页面正在请求版本检查（logo + 「检查更新中…」）。
/// - [upToDate]：已是最新（logo + 「版本 x.x.x」+ 应用简介，无按钮）。
/// - [updateAvailable]：有新版本（logo + 「当前版本 x · 最新版本 y」+ 简介 + 「立即更新」）。
///
/// 没有「下载中」态：下载与安装完全由应用商店 / 浏览器接管，App 侧拿不到真实进度，
/// 原来的进度环是一个 6 秒假动画，会让用户以为 App 在自己下载（已移除）。
enum BoltStarUpdateStage { checking, upToDate, updateAvailable }

/// 更新 BoltStar 页面（设置页「检测更新」入口跳转到此）。
///
/// 进入即调用 [PhotoFrameState.checkAppVersion] 真实检查版本：
/// 当前版本来自 `package_info`，最新版本 / 下载地址来自后端 `getLastVersion`。
/// 「立即更新」用应用商店 / 系统浏览器打开下载地址后即停留在本页，
/// 后续下载安装交给系统（对齐项目既定设计，见 pubspec 中 url_launcher 的说明）。
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

class _UpdateBoltStarPageState extends State<UpdateBoltStarPage> {
  late BoltStarUpdateStage _stage;

  String _currentVersion = '';
  String _latestVersion = '';
  String _downloadUrl = '';

  @override
  void initState() {
    super.initState();

    final preview = widget.previewStage;
    if (preview != null) {
      // 演示路由：占位版本号 + 指定态，不发真实请求。
      _stage = preview;
      _currentVersion = '1.0.0';
      _latestVersion = '1.2.0';
      return;
    }

    // 正常入口：进入即真实检查版本。
    _stage = BoltStarUpdateStage.checking;
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  Future<void> _check() async {
    final state = widget.state;
    if (state == null) {
      return;
    }
    // checkAppVersion 失败时**抛异常**（返回非空 AppVersionInfo，不返回 null），
    // 必须 try/catch：否则网络异常会成为未捕获异步错误，页面永远停在「检查更新中…」
    // 并污染崩溃日志。
    final AppVersionInfo info;
    try {
      info = await state.checkAppVersion();
    } catch (error) {
      if (!mounted) {
        return;
      }
      AppToast.warn(context, AppL10n.of(context).setCheckUpdateFailed);
      Navigator.of(context).maybePop();
      return;
    }
    if (!mounted) {
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
    // 用应用商店 / 系统浏览器打开下载地址，下载与安装全部交给系统；
    // 页面停留在「有新版本」态，不再切假进度环。
    final url = _downloadUrl.trim();
    final uri = url.isEmpty ? null : Uri.tryParse(url);
    // scheme 白名单：downloadUrl 来自后端接口，若后端被篡改返回 intent://、tel://
    // 等任意 scheme，externalApplication 会直接拉起任意外部应用。只放行
    // https 与两端应用商店 scheme，其余静默拒绝并提示失败。
    const allowedSchemes = {'https', 'market', 'itms-apps'};
    if (uri == null || !allowedSchemes.contains(uri.scheme)) {
      debugPrint('[UpdateBoltStar] 拒绝非白名单下载地址: $url');
      if (mounted) {
        AppToast.warn(context, AppL10n.of(context).setCheckUpdateFailed);
      }
      return;
    }
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (error) {
      // market:// 在没有应用商店的 ROM 上无处理者会抛 PlatformException
      //（ActivityNotFoundException），不能让它冒泡崩掉 App。
      debugPrint('[UpdateBoltStar] 打开下载地址失败: $error');
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
          // 版本号连点 7 次 → 「投屏性能自检」页（隐藏诊断入口，见 AppRoutes.blePerf）。
          // 正式包里也可达：iOS 没有任何应用内日志、没有 Mac 拿不到 Xcode 输出，
          // 「15ms 连接间隔生没生效」只能靠那一页在机内自证。放在这里是因为版本号是
          // 全 App 唯一一个「点它本来没有任何反应」的控件，绝不会被用户误触。
          Center(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _onVersionTapped,
              child: _versionLabel(),
            ),
          ),
          const SizedBox(height: 64),
          if (_stage != BoltStarUpdateStage.checking)
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

  // ── 隐藏诊断入口：版本号连点 7 次 ────────────────────────
  int _versionTaps = 0;
  DateTime? _firstTapAt;

  void _onVersionTapped() {
    final now = DateTime.now();
    // 3 秒内连点才算数：隔了很久的零散点击不该累积成一次「秘密手势」。
    if (_firstTapAt == null || now.difference(_firstTapAt!) > const Duration(seconds: 3)) {
      _firstTapAt = now;
      _versionTaps = 0;
    }
    _versionTaps++;
    if (_versionTaps < 7) return;
    _versionTaps = 0;
    _firstTapAt = null;
    Navigator.of(context).pushNamed(AppRoutes.blePerf);
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
