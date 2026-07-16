import 'dart:async';

import 'package:flutter/material.dart';

import 'package:BoltStar/src/shared/widgets/app_widgets.dart';
import 'package:BoltStar/src/shared/widgets/figma_common.dart';
import '../../../shared/l10n/app_l10n.dart';
import '../../../state.dart';
import '../data/email_history.dart';

/// 创建账户 / 注册页，对应 UI 稿「创建账户-未输入 / 已输入可注册 / 密码不一致」。
///
/// 三种状态由用户输入自然驱动：未填写时主按钮置灰，填写后变为可点击，
/// 点击时若两次密码不一致则在密码、确认密码下方提示。
class RegisterPage extends StatefulWidget {
  const RegisterPage({
    super.key,
    required this.state,
    this.onRegistered,
    this.onBackToLogin,
  });

  final PhotoFrameState state;
  final VoidCallback? onRegistered;
  final VoidCallback? onBackToLogin;

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _codeController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmController = TextEditingController();

  bool _showMismatch = false;
  // 密码不符合规则（6-12 位且同时含数字与英文字母），就地在密码行下方提示。
  bool _showRuleError = false;
  bool _submitting = false;
  // 验证码请求在途标记：服务器响应前连点会发多封验证码邮件。
  bool _sendingCode = false;
  int _countdown = 0;
  Timer? _timer;

  static final _emailPattern = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
  // 密码规则：6-12 位，必须同时包含数字和英文字母，且只允许数字/字母。
  static final _passwordPattern = RegExp(
    r'^(?=.*[A-Za-z])(?=.*[0-9])[A-Za-z0-9]{6,12}$',
  );

  @override
  void initState() {
    super.initState();
    for (final controller in [
      _emailController,
      _codeController,
      _passwordController,
      _confirmController,
    ]) {
      controller.addListener(_onChanged);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _emailController.dispose();
    _codeController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (_showMismatch || _showRuleError) {
      setState(() {
        _showMismatch = false;
        _showRuleError = false;
      });
    } else {
      setState(() {});
    }
  }

  bool get _canSubmit =>
      _emailController.text.trim().isNotEmpty &&
      _codeController.text.trim().isNotEmpty &&
      _passwordController.text.isNotEmpty &&
      _confirmController.text.isNotEmpty;

  Future<void> _getCode() async {
    if (_countdown > 0 || _sendingCode) {
      return;
    }
    // 本地先校验邮箱格式，空/格式错不发请求（原来空邮箱也会打接口）。
    if (!_emailPattern.hasMatch(_emailController.text.trim())) {
      _showSnack(AppL10n.of(context).accEmailInvalid);
      return;
    }
    _sendingCode = true;
    // 点击立刻弹蒙层 loading：后端同步发信可能数秒才响应，期间阻断重复点击
    //（否则连点会发多封验证码邮件），也让用户立刻感知「已在发送」。
    AppLoadingDialog.show(context, AppL10n.of(context).accSendingCode);
    final ActionFeedback feedback;
    try {
      // sendType:1 = 注册验证码。
      feedback = await widget.state.sendEmailCode(
        email: _emailController.text,
        sendType: 1,
      );
    } finally {
      // 任何异常都必须收掉 loading，否则遮罩卡死整个页面。
      _sendingCode = false;
      if (mounted) {
        AppLoadingDialog.hide(context);
      }
    }
    if (!mounted) {
      return;
    }
    _showSnack(feedback.message);
    if (feedback.success) {
      _startCountdown();
    }
  }

  void _startCountdown() {
    setState(() => _countdown = 60);
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_countdown <= 1) {
        timer.cancel();
        setState(() => _countdown = 0);
      } else {
        setState(() => _countdown -= 1);
      }
    });
  }

  Future<void> _register() async {
    if (_submitting) {
      return;
    }
    if (!_passwordPattern.hasMatch(_passwordController.text)) {
      setState(() => _showRuleError = true);
      return;
    }
    if (_passwordController.text != _confirmController.text) {
      setState(() => _showMismatch = true);
      return;
    }
    setState(() => _submitting = true);
    final feedback = await widget.state.registerWithEmail(
      email: _emailController.text,
      password: _passwordController.text,
      emailCode: _codeController.text,
    );
    if (!mounted) {
      return;
    }
    setState(() => _submitting = false);
    if (feedback.success) {
      await EmailHistory.add(_emailController.text); // 记住注册邮箱，登录页自动填充
    }
    _showSnack(feedback.message);
    if (feedback.success) {
      widget.onRegistered?.call();
    }
  }

  void _showSnack(String message) {
    AppToast.show(context, message);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    // 密码行错误优先级：规则不符 > 两次不一致。
    final passwordErrorText = _showRuleError
        ? l10n.accPasswordRuleError
        : (_showMismatch ? l10n.accPasswordMismatch : null);

    return FigmaScreen(
      title: l10n.accCreateAccount,
      onBack: widget.onBackToLogin,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 12),
          FigmaAccountFormCard(
            children: [
              FigmaAccountField(
                label: l10n.accEmail,
                controller: _emailController,
                hintText: l10n.accEmailAddressHint,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
              ),
              const FigmaFormDivider(),
              FigmaVerificationField(
                controller: _codeController,
                onGetCode: _getCode,
                countdownLabel: _countdown > 0 ? l10n.accResendIn(_countdown) : null,
              ),
              const FigmaFormDivider(),
              FigmaAccountField(
                label: l10n.accPassword,
                controller: _passwordController,
                // 密码规则占位提示（6-12位数字+英文），登录页不展示。
                hintText: l10n.accPasswordRuleHint,
                obscureText: true,
                errorText: passwordErrorText,
                autofillHints: const [AutofillHints.newPassword],
              ),
              const FigmaFormDivider(),
              FigmaAccountField(
                label: l10n.accConfirmPassword,
                controller: _confirmController,
                hintText: l10n.accConfirmPasswordHint,
                obscureText: true,
                errorText: _showMismatch ? l10n.accPasswordMismatchReconfirm : null,
              ),
            ],
          ),
        ],
      ),
      bottom: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FigmaPrimaryButton(
            label: l10n.accRegisterButton,
            // 提交中按钮转圈并不可点，用户能感知「正在提交」（原来只有静默防重入）。
            onPressed: (_canSubmit && !_submitting) ? _register : null,
            loading: _submitting,
          ),
          const SizedBox(height: 16),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onBackToLogin ?? () => Navigator.maybePop(context),
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: l10n.accHaveAccount),
                  TextSpan(
                    text: l10n.accGoLogin,
                    style: const TextStyle(color: Color(0xFFFF5B1F)),
                  ),
                ],
              ),
              style: const TextStyle(
                color: Color(0x992A2B2B),
                fontSize: 14,
                fontWeight: FontWeight.w400,
                height: 1.2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
