import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../native_device_api.dart';
import '../../../shared/l10n/app_l10n.dart';
import '../../../shared/widgets/figma_common.dart';
import '../../../shared/widgets/home_figma_common.dart';
import '../../../state.dart';
import '../wifi_l10n.dart';
import '../wifi_provision.dart';
import 'wifi_glyphs.dart';

/// WiFi 版设备配网状态页，同步小程序 `subpackages/device/wifi-provision`（流程本体见 [WifiProvision]）。
///
/// 四个状态依次执行：执行中的状态圈转圈，通过打勾；全部通过标题改「设备入网成功」并出「立即体验」
/// （选中该设备回首页）；任一步失败打叉、标题改成具体错误，出「重新配网」（整行主按钮）与「取消」（橙色文字）。
/// 重新配网从第 1 步整套重来（已绑定过的设备第 3 步会复用原绑定记录，不会重复绑定）。离开页面即取消，蓝牙随之释放。
class WifiProvisionPage extends StatefulWidget {
  const WifiProvisionPage({super.key, required this.state});

  final PhotoFrameState state;

  @override
  State<WifiProvisionPage> createState() => _WifiProvisionPageState();
}

enum _Phase { running, success, failed }

class _WifiProvisionPageState extends State<WifiProvisionPage> {
  final List<String> _steps = List<String>.filled(4, 'pending');
  _Phase _phase = _Phase.running;
  String _failTitle = '';
  String _deviceId = '';
  int _runId = 0;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    // 本页没有输入框，进来时把可能残留的键盘收掉（11-11 用户反馈：上一页密码框的键盘留在本页底部关不掉，
    // 挡住按钮，后续页面也一直在）。上一页离开前已先解除焦点，这里再兜底：焦点已不在任何输入框时，
    // 点空白的全局收键盘也收不回它，只能直接让系统收起。
    FocusManager.instance.primaryFocus?.unfocus();
    unawaited(SystemChannels.textInput.invokeMethod<void>('TextInput.hide'));
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(NativeDeviceApi.setKeepScreenOn(false));
    super.dispose();
  }

  Future<void> _start() async {
    if (!mounted) {
      return;
    }
    final l10n = AppL10n.of(context);
    final runId = ++_runId;
    setState(() {
      _phase = _Phase.running;
      _failTitle = '';
      _steps.fillRange(0, 4, 'pending');
    });
    if (!WifiProvision.hasJob) {
      // 交接信息丢了（如进程被回收后重进本页）：没有 WiFi 密码与设备句柄，只能回去重填
      setState(() {
        _steps[0] = 'fail';
        _phase = _Phase.failed;
        _failTitle = l10n.wifiJobExpired;
      });
      return;
    }
    // 配网全程约 1 分钟，期间息屏会让蓝牙被挂起（同小程序 setKeepScreenOn，跑完或离开页面恢复）
    unawaited(NativeDeviceApi.setKeepScreenOn(true));
    bool stale() => _disposed || runId != _runId;
    try {
      await _run(l10n, stale);
    } finally {
      // 跑完（成功或失败）就恢复息屏，不等离开页面（同小程序 start() 的 finally）；被新一轮取代时由新一轮接管
      if (!stale()) {
        unawaited(NativeDeviceApi.setKeepScreenOn(false));
      }
    }
  }

  Future<void> _run(AppL10n l10n, bool Function() stale) async {
    try {
      final deviceId = await WifiProvision.run(
        widget.state,
        l10n,
        onStep: (index, status) {
          if (!stale()) {
            setState(() => _steps[index] = status);
          }
        },
        isCancelled: stale,
      );
      if (stale()) {
        return;
      }
      setState(() {
        _deviceId = deviceId;
        _phase = _Phase.success;
      });
    } on WifiProvisionError catch (error) {
      if (stale()) {
        return;
      }
      setState(() {
        _steps[error.step] = 'fail';
        _phase = _Phase.failed;
        _failTitle = error.message;
      });
    } catch (error) {
      if (stale()) {
        return;
      }
      setState(() {
        final running = _steps.indexOf('loading');
        _steps[running < 0 ? 0 : running] = 'fail';
        _phase = _Phase.failed;
        _failTitle = l10n.wifiErrProvisionFailed;
      });
    }
  }

  /// 立即体验：选中刚配好的设备，回到首页（首页即该设备的主页）。
  void _goExperience() {
    if (_deviceId.isNotEmpty) {
      widget.state.selectDevice(_deviceId);
    }
    WifiProvision.clear();
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final title = switch (_phase) {
      _Phase.running => l10n.wifiProvisionRunning,
      _Phase.success => l10n.wifiProvisionSuccess,
      _Phase.failed => _failTitle,
    };
    final titleColor = switch (_phase) {
      _Phase.running => const Color(0xFF2A2D32),
      _Phase.success => const Color(0xFFFF5A1E),
      _Phase.failed => const Color(0xFFE5533D),
    };
    final texts = l10n.wifiProvisionSteps;
    return FigmaScreen(
      title: l10n.wifiProvisionTitle,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 20),
          // 头图与 WiFi 配网页同一张（同小程序 wifi-provision-art.svg）
          const WifiProvisionArt(),
          const SizedBox(height: 18),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: titleColor,
              fontSize: _phase == _Phase.failed ? 16 : 19,
              fontWeight: FontWeight.w700,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.wifiProvisionHint,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFF8B9098), fontSize: 12),
          ),
          const SizedBox(height: 24),
          // 四个状态（同小程序 .provision-steps）：每行 48 高，行间细分隔线
          FigmaGlassCard(
            borderRadius: 16,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
            child: Column(
              children: [
                for (var i = 0; i < 4; i++)
                  Container(
                    height: 48,
                    decoration: i == 0
                        ? null
                        : const BoxDecoration(
                            border: Border(top: BorderSide(color: Color(0x0F2A2B2B), width: 0.5)),
                          ),
                    child: Row(
                      children: [
                        WifiStepIcon(index: i, status: _steps[i]),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            texts[i],
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: switch (_steps[i]) {
                                'fail' => const Color(0xFFE5533D),
                                'pending' => const Color(0xFF8B9098),
                                _ => const Color(0xFF2A2D32),
                              },
                              fontSize: 14,
                              fontWeight: _steps[i] == 'loading' ? FontWeight.w700 : FontWeight.w400,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
      bottom: switch (_phase) {
        _Phase.running => null,
        _Phase.success => FigmaHomePrimaryButton(
          label: l10n.wifiTryNow,
          fontWeight: FontWeight.w700,
          onPressed: _goExperience,
        ),
        // 失败：上下排，「重新配网」主按钮占满整行在上，「取消」在下只是橙色文字
        _Phase.failed => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FigmaHomePrimaryButton(
              label: l10n.wifiRetryProvision,
              fontWeight: FontWeight.w700,
              onPressed: _start,
            ),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(context).maybePop(),
              child: SizedBox(
                height: 44,
                child: Center(
                  child: Text(
                    l10n.wifiCancel,
                    style: const TextStyle(color: Color(0xFFFF621F), fontSize: 16),
                  ),
                ),
              ),
            ),
          ],
        ),
      },
    );
  }
}

/// 状态圈（同小程序 .step-icon，20 见方）：未开始白底灰边、圈里是序号；执行中橙色转圈；
/// 通过橙色渐变实心打勾；失败红色实心打叉。配网状态页与固件升级页共用（小程序两页也是同一套 .step-icon）。
class WifiStepIcon extends StatelessWidget {
  const WifiStepIcon({super.key, required this.index, required this.status});

  final int index;
  final String status;

  static const double _size = 20;

  @override
  Widget build(BuildContext context) {
    if (status == 'loading') {
      return const SizedBox(
        width: _size,
        height: _size,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFF621F)),
          backgroundColor: Color(0x2EFF621F),
        ),
      );
    }
    final BoxDecoration decoration = switch (status) {
      'done' => const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFF8338), Color(0xFFFF621F)],
        ),
      ),
      'fail' => const BoxDecoration(shape: BoxShape.circle, color: Color(0xFFE5533D)),
      _ => BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white,
        border: Border.all(color: const Color(0xFFC8CDD5), width: 1.5),
      ),
    };
    return Container(
      width: _size,
      height: _size,
      alignment: Alignment.center,
      decoration: decoration,
      child: switch (status) {
        'done' => const Icon(Icons.check_rounded, size: 14, color: Colors.white),
        'fail' => const Icon(Icons.close_rounded, size: 14, color: Colors.white),
        _ => Text(
          '${index + 1}',
          style: const TextStyle(color: Color(0xFF8B9098), fontSize: 12, fontWeight: FontWeight.w700, height: 1),
        ),
      },
    );
  }
}
