import 'package:flutter/material.dart';

import '../../../routes/app_routes.dart';
import '../../../shared/l10n/app_l10n.dart';
import '../../../shared/widgets/app_toast.dart';
import '../../../shared/widgets/figma_common.dart';
import '../../../shared/widgets/home_figma_common.dart';
import '../../../state.dart';
import '../wifi_l10n.dart';
import '../wifi_provision.dart';
import '../wifi_widgets.dart';
import 'wifi_list_page.dart';
import 'wifi_provision_page.dart';

/// WiFi 版设备配网第二步：WiFi 账号密码，同步小程序 `subpackages/device/wifi-config`。
///   · 名称由列表页带过来（选「手动输入」时为空，用户自己填）；名称后的切换图标回到 WiFi 列表重选；
///   · 密码默认加密显示，右侧小眼睛切换明文 / 密文；「下一步」把名称 / 密码交给配网流程
///     （内存交接，**密码不进路由**），进配网状态页。
class WifiConfigPage extends StatefulWidget {
  const WifiConfigPage({super.key, required this.state, this.initialSsid = ''});

  final PhotoFrameState state;
  final String initialSsid;

  @override
  State<WifiConfigPage> createState() => _WifiConfigPageState();
}

class _WifiConfigPageState extends State<WifiConfigPage> {
  late final TextEditingController _ssid = TextEditingController(text: widget.initialSsid);
  final TextEditingController _password = TextEditingController();
  bool _showPassword = false;

  @override
  void dispose() {
    _ssid.dispose();
    _password.dispose();
    super.dispose();
  }

  /// 切换图标：回到 WiFi 列表重选（正常从列表页进来，返回上一页即可）。
  void _openWifiList() {
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
      return;
    }
    navigator.pushReplacement(
      AppPageRoute<void>(builder: (_) => WifiListPage(state: widget.state)),
    );
  }

  void _goNext() {
    final l10n = AppL10n.of(context);
    final ssid = _ssid.text.trim();
    if (ssid.isEmpty) {
      AppToast.warn(context, l10n.wifiSsidHint);
      return;
    }
    if (WifiProvision.target == null) {
      AppToast.warn(context, l10n.wifiConfigTargetExpired);
      return;
    }
    WifiProvision.setCredentials(ssid, _password.text);
    Navigator.of(context).push<void>(
      AppPageRoute(builder: (_) => WifiProvisionPage(state: widget.state)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final target = WifiProvision.target;
    return FigmaScreen(
      title: l10n.wifiConfigTitle,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 20),
          const WifiProvisionArt(),
          const SizedBox(height: 16),
          if (target != null)
            Column(
              children: [
                Text(
                  target.name.isNotEmpty ? target.name : target.deviceNo,
                  style: const TextStyle(color: Color(0xFF2A2D32), fontSize: 17, fontWeight: FontWeight.w700),
                ),
                if (target.spec.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(target.spec, style: const TextStyle(color: Color(0xFF8B9098), fontSize: 13)),
                ],
                const SizedBox(height: 12),
              ],
            ),
          WifiTipRow(text: l10n.wifiOnly24G),
          const SizedBox(height: 16),
          FigmaGlassCard(
            borderRadius: 16,
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Field(
                  label: l10n.wifiSsidLabel,
                  controller: _ssid,
                  hint: l10n.wifiSsidHint,
                  trailing: IconButton(
                    tooltip: l10n.wifiListTitle,
                    onPressed: _openWifiList,
                    icon: const Icon(Icons.swap_horiz_rounded, color: Color(0xFFFF6A24), size: 22),
                  ),
                ),
                const SizedBox(height: 14),
                _Field(
                  label: l10n.wifiPasswordLabel,
                  controller: _password,
                  hint: l10n.wifiPasswordHint,
                  obscure: !_showPassword,
                  trailing: IconButton(
                    onPressed: () => setState(() => _showPassword = !_showPassword),
                    icon: Icon(
                      _showPassword ? Icons.visibility_rounded : Icons.visibility_off_rounded,
                      color: const Color(0xFF8B9098),
                      size: 20,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
      bottom: FigmaHomePrimaryButton(
        label: l10n.wifiNext,
        fontWeight: FontWeight.w700,
        onPressed: _goNext,
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.controller,
    required this.hint,
    required this.trailing,
    this.obscure = false,
  });

  final String label;
  final TextEditingController controller;
  final String hint;
  final Widget trailing;
  final bool obscure;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Color(0xFF2A2D32), fontSize: 14, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Container(
          height: 48,
          padding: const EdgeInsets.only(left: 14),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.8),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE6E8EC)),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  obscureText: obscure,
                  autocorrect: false,
                  enableSuggestions: !obscure,
                  style: const TextStyle(color: Color(0xFF2A2D32), fontSize: 15),
                  decoration: InputDecoration(
                    isCollapsed: true,
                    border: InputBorder.none,
                    hintText: hint,
                    hintStyle: const TextStyle(color: Color(0xFFB7BBC0), fontSize: 15),
                  ),
                ),
              ),
              trailing,
            ],
          ),
        ),
      ],
    );
  }
}

/// 配网头图：手机 → 设备 → 云（小程序用 svg 头图，这里用图标拼，不新增图片资源）。
class WifiProvisionArt extends StatelessWidget {
  const WifiProvisionArt({super.key});

  @override
  Widget build(BuildContext context) {
    Widget node(IconData icon, Color color) => Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: color, size: 28),
    );
    const dots = Padding(
      padding: EdgeInsets.symmetric(horizontal: 8),
      child: Icon(Icons.more_horiz_rounded, color: Color(0xFFB7BBC0)),
    );
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        node(Icons.smartphone_rounded, const Color(0xFFFF6A24)),
        dots,
        node(Icons.photo_outlined, kWifiGreen),
        dots,
        node(Icons.cloud_outlined, const Color(0xFF2F6FEB)),
      ],
    );
  }
}
