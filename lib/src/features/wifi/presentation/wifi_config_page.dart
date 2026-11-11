import 'package:flutter/material.dart';

import '../../../routes/app_routes.dart';
import '../../../shared/l10n/app_l10n.dart';
import '../../../shared/widgets/app_toast.dart';
import '../../../shared/widgets/figma_common.dart';
import '../../../shared/widgets/home_figma_common.dart';
import '../../../state.dart';
import '../wifi_l10n.dart';
import '../wifi_provision.dart';
import 'wifi_glyphs.dart';
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

  /// 离开本页前先收起键盘。只靠路由切换移走焦点不可靠：11-11 用户反馈在密码框打开键盘后点「下一步」，
  /// 键盘留在配网状态页上关不掉（该页没有输入框，点空白也收不回），连后续页面也一直挡着底部按钮。
  /// 先在本页解除焦点，让输入连接在仍挂着时正常关闭并收起键盘（同登录页提交前的做法）。
  void _dismissKeyboard() {
    FocusManager.instance.primaryFocus?.unfocus();
  }

  /// 切换图标：回到 WiFi 列表重选（正常从列表页进来，返回上一页即可）。
  void _openWifiList() {
    _dismissKeyboard();
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
    _dismissKeyboard();
    Navigator.of(context).push<void>(
      AppPageRoute(builder: (_) => WifiProvisionPage(state: widget.state)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final target = WifiProvision.target;
    final deviceName = target == null ? '' : (target.name.isNotEmpty ? target.name : target.deviceNo);
    return FigmaScreen(
      title: l10n.wifiConfigTitle,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 20),
          // 头图：手机 → 设备 → 云（与小程序同一张图，见 wifi_glyphs.dart）
          const WifiProvisionArt(),
          // 设备名与尺寸同一行（同小程序 .wifi-device）
          if (deviceName.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Flexible(
                    child: Text(
                      deviceName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Color(0xFF2A2D32), fontSize: 15, fontWeight: FontWeight.w700),
                    ),
                  ),
                  if (target!.spec.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Text(target.spec, style: const TextStyle(color: Color(0xFF8B9098), fontSize: 12)),
                  ],
                ],
              ),
            ),
          // 「设备仅支持 2.4G WiFi 配网」提示条 2026-11-05 去掉（同小程序）
          const SizedBox(height: 18),
          FigmaGlassCard(
            borderRadius: 16,
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Field(
                  label: l10n.wifiSsidLabel,
                  controller: _ssid,
                  hint: l10n.wifiSsidHint,
                  trailing: _FieldAction(
                    tooltip: l10n.wifiListTitle,
                    onTap: _openWifiList,
                    child: const WifiSwitchGlyph(size: 22),
                  ),
                ),
                _Field(
                  label: l10n.wifiPasswordLabel,
                  controller: _password,
                  hint: l10n.wifiPasswordHint,
                  obscure: !_showPassword,
                  trailing: _FieldAction(
                    onTap: () => setState(() => _showPassword = !_showPassword),
                    child: WifiEyeGlyph(open: _showPassword, size: 20),
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

/// 输入框右侧的图标点击区（同小程序 .wifi-field__switch：80rpx 见方 = 40）。
class _FieldAction extends StatelessWidget {
  const _FieldAction({required this.onTap, required this.child, this.tooltip});

  final VoidCallback onTap;
  final Widget child;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final button = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(width: 40, height: 40, child: Center(child: child)),
    );
    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}

/// 一行输入：标题 + 输入框（同小程序 .wifi-field / .wifi-field__box）。
///
/// 聚焦时整个输入框描橙色边。⚠️ 内层 TextField 必须把 `enabledBorder` / `focusedBorder` 也写成 none、
/// 并关掉 `filled`：全局 `AppTheme.inputDecorationTheme` 给了 `filled` 白底和带橙色描边的 `focusedBorder`，
/// 只写 `border: none` 盖不住，聚焦时会在内层紧贴文字画出一圈被裁掉的橙框（11-11 用户反馈的「橙色边框不正常」）。
class _Field extends StatefulWidget {
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
  State<_Field> createState() => _FieldState();
}

class _FieldState extends State<_Field> {
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocusChanged);
  }

  void _onFocusChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocusChanged);
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final focused = _focus.hasFocus;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.label,
            style: const TextStyle(color: Color(0xFF2A2D32), fontSize: 14, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 7),
          AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            height: 48,
            padding: const EdgeInsets.only(left: 14, right: 4),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.86),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: focused ? const Color(0xFFFF6A24) : const Color(0x0F2A2B2B),
                width: focused ? 1.2 : 1,
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: widget.controller,
                    focusNode: _focus,
                    obscureText: widget.obscure,
                    autocorrect: false,
                    enableSuggestions: !widget.obscure,
                    cursorColor: const Color(0xFFFF6A24),
                    style: const TextStyle(color: Color(0xFF2A2D32), fontSize: 15),
                    decoration: InputDecoration(
                      isCollapsed: true,
                      filled: false,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      disabledBorder: InputBorder.none,
                      errorBorder: InputBorder.none,
                      focusedErrorBorder: InputBorder.none,
                      hintText: widget.hint,
                      hintStyle: const TextStyle(color: Color(0xFFB3B8C0), fontSize: 15),
                    ),
                  ),
                ),
                widget.trailing,
              ],
            ),
          ),
        ],
      ),
    );
  }
}
