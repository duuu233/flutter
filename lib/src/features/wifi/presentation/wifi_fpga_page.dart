import 'package:flutter/material.dart';

import '../../../routes/app_routes.dart';
import '../../../shared/l10n/app_l10n.dart';
import '../../../shared/widgets/app_toast.dart';
import '../../../shared/widgets/app_widgets.dart';
import '../../../shared/widgets/figma_common.dart';
import '../../../state.dart';
import '../wifi_fpga.dart';
import '../wifi_l10n.dart';
import 'wifi_ota_page.dart';

/// WiFi 版「优雅刷新升级」（2026-11-13，原名渲染固件管理；同小程序 `subpackages/device/wifi-fpga`；逻辑说明见 [wifi_fpga.dart]）：
/// 设备信息页进来（只有渲染模式 = fpga16 的设备才有入口）；列出后台启用的版本：版本号、简介、安装。
/// 设备不上报 FPGA 版本（ota/status 的 baseVersion 为 null），不显示设备当前版本。
/// 点「安装」→ [WifiOtaPage] 的安装模式（`fpgaTarget`）。列表接口后端还没提供时显示「版本列表暂未开放」。
class WifiFpgaPage extends StatefulWidget {
  const WifiFpgaPage({super.key, required this.state, required this.deviceId});

  final PhotoFrameState state;
  final String deviceId;

  @override
  State<WifiFpgaPage> createState() => _WifiFpgaPageState();
}

enum _View { loading, error, notFpga, pending, ready }

class _WifiFpgaPageState extends State<WifiFpgaPage> {
  _View _view = _View.loading;
  List<WifiFpgaVersion> _versions = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _load();
      }
    });
  }

  DeviceItem get _device => widget.state.deviceById(widget.deviceId);

  Future<void> _load() async {
    setState(() => _view = _View.loading);
    final device = _device;
    String renderMode;
    try {
      renderMode = await widget.state.resolveRenderMode(device);
    } catch (_) {
      renderMode = '';
    }
    if (!mounted) {
      return;
    }
    if (!isFpgaRenderMode(renderMode)) {
      setState(() => _view = _View.notFpga);
      return;
    }
    ({bool pending, List<WifiFpgaVersion> list}) result;
    try {
      result = await fetchWifiFpgaVersions(device.productId);
    } catch (error) {
      debugPrint('[优雅刷新] 版本列表查询失败 $error');
      if (mounted) {
        setState(() => _view = _View.error);
      }
      return;
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _versions = result.list;
      _view = result.pending ? _View.pending : _View.ready;
    });
  }

  Future<void> _install(WifiFpgaVersion target) async {
    if (!target.hasValidUrl) {
      AppToast.warn(context, AppL10n.of(context).wifiFpgaInvalidUrl);
      return;
    }
    await Navigator.of(context).push<void>(
      AppPageRoute(builder: (_) => WifiOtaPage(state: widget.state, deviceId: widget.deviceId, fpgaTarget: target)),
    );
  }

  Widget _notice(String title, String hint, {VoidCallback? onRetry}) {
    final l10n = AppL10n.of(context);
    return FigmaGlassCard(
      borderRadius: 18,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 32),
      child: Column(
        children: [
          Text(title, textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFF2A2D32), fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(hint, textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFF8B9098), fontSize: 12, height: 1.5)),
          if (onRetry != null) ...[
            const SizedBox(height: 16),
            TextButton(onPressed: onRetry, child: Text(l10n.retry)),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final children = <Widget>[const SizedBox(height: 16)];
    switch (_view) {
      case _View.loading:
        children.add(const Padding(padding: EdgeInsets.only(top: 80), child: PageLoading()));
      case _View.error:
        children.add(_notice(l10n.wifiFpgaLoadFailed, '', onRetry: _load));
      case _View.notFpga:
        children.add(_notice(l10n.wifiFpgaNotSupported, l10n.wifiFpgaNotSupportedHint));
      case _View.pending:
      case _View.ready:
        if (_view == _View.pending) {
          children.add(_notice(l10n.wifiFpgaPendingTitle, l10n.wifiFpgaPendingHint));
        } else if (_versions.isEmpty) {
          children.add(_notice(l10n.wifiFpgaEmptyTitle, l10n.wifiFpgaEmptyHint));
        } else {
          for (final item in _versions) {
            children
              ..add(
                FigmaGlassCard(
                  key: ValueKey('wifi-fpga-${item.id}'),
                  borderRadius: 18,
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    item.version,
                                    style: const TextStyle(color: Color(0xFF2A2D32), fontSize: 15, fontWeight: FontWeight.w700),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              item.intro.isNotEmpty ? item.intro : l10n.wifiFpgaNoIntro,
                              style: const TextStyle(color: Color(0xFF8B9098), fontSize: 12, height: 1.6),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      FilledButton(
                        style: FilledButton.styleFrom(backgroundColor: const Color(0xFFFF6A20), shape: const StadiumBorder()),
                        onPressed: () => _install(item),
                        child: Text(l10n.wifiFpgaInstall),
                      ),
                    ],
                  ),
                ),
              )
              ..add(const SizedBox(height: 10));
          }
        }
    }
    return FigmaScreen(
      title: l10n.wifiFpgaManage,
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [...children, const SizedBox(height: 24)]),
    );
  }
}
