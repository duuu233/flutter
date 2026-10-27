import 'package:flutter/material.dart';

import '../../../shared/l10n/app_l10n.dart';
import '../../../shared/widgets/figma_common.dart';
import '../../../shared/widgets/home_figma_common.dart';
import '../../../state.dart';
import '../wifi_l10n.dart';
import '../wifi_provision.dart';
import '../wifi_widgets.dart';
import 'wifi_config_page.dart';

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
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  @override
  void dispose() {
    _disposed = true;
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
    bool stale() => _disposed || runId != _runId;
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
          const SizedBox(height: 24),
          const WifiProvisionArt(),
          const SizedBox(height: 20),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: titleColor,
              fontSize: _phase == _Phase.failed ? 16 : 19,
              fontWeight: FontWeight.w700,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            l10n.wifiProvisionHint,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFF8B9098), fontSize: 12),
          ),
          const SizedBox(height: 20),
          FigmaGlassCard(
            borderRadius: 16,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            child: Column(
              children: [
                for (var i = 0; i < 4; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Row(
                      children: [
                        _StepIcon(index: i, status: _steps[i]),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            texts[i],
                            style: TextStyle(
                              color: _steps[i] == 'fail'
                                  ? const Color(0xFFE5533D)
                                  : _steps[i] == 'pending'
                                  ? const Color(0xFF8B9098)
                                  : const Color(0xFF2A2D32),
                              fontSize: 15,
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

/// 状态圈：未开始显示序号；执行中转圈，通过打勾，失败打叉。
class _StepIcon extends StatelessWidget {
  const _StepIcon({required this.index, required this.status});

  final int index;
  final String status;

  @override
  Widget build(BuildContext context) {
    final Color background = switch (status) {
      'done' => const Color(0xFFFF6A24),
      'fail' => const Color(0xFFE5533D),
      _ => Colors.white,
    };
    return Container(
      width: 26,
      height: 26,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: background,
        shape: BoxShape.circle,
        border: status == 'pending' || status == 'loading'
            ? Border.all(color: const Color(0xFFE6E8EC))
            : null,
      ),
      child: switch (status) {
        'loading' => const WifiMiniSpinner(size: 14),
        'done' => const Icon(Icons.check_rounded, size: 16, color: Colors.white),
        'fail' => const Icon(Icons.close_rounded, size: 16, color: Colors.white),
        _ => Text('${index + 1}', style: const TextStyle(color: Color(0xFF8B9098), fontSize: 12)),
      },
    );
  }
}
