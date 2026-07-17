import 'dart:async';

import 'package:flutter/material.dart';

import 'package:BoltStar/src/shared/widgets/app_widgets.dart';
import 'package:BoltStar/src/shared/widgets/figma_common.dart';
import '../../../shared/l10n/app_l10n.dart';
import '../../../state.dart';

/// 忘记密码 / 重置密码页，对应 UI 稿「忘记密码」。
class ForgotPassword extends StatefulWidget {
  const ForgotPassword({super.key, required this.state, this.onConfirmed});

  final PhotoFrameState state;
  final VoidCallback? onConfirmed;

  @override
  State<ForgotPassword> createState() => _ForgotPasswordState();
}

class _ForgotPasswordState extends State<ForgotPassword> {
  late final TextEditingController _emailController;
  final TextEditingController _codeController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();

  int _countdown = 0;
  bool _submitting = false;
  // 验证码请求在途标记：服务器响应前连点会发多封验证码邮件。
  bool _sendingCode = false;
  // 两次密码不一致：就地在确认密码行下方提示（原来只弹 2 秒 toast），输入即清除。
  bool _showMismatch = false;
  // 新密码不符合规则（6-12 位且同时含数字与英文字母），就地在密码行下方提示。
  bool _showRuleError = false;
  Timer? _timer;

  static final _emailPattern = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
  // 密码规则：6-12 位，必须同时包含数字和英文字母，且只允许数字/字母。
  static final _passwordPattern = RegExp(
    r'^(?=.*[A-Za-z])(?=.*[0-9])[A-Za-z0-9]{6,12}$',
  );

  @override
  void initState() {
    super.initState();
    _emailController = TextEditingController();
    _passwordController.addListener(_clearMismatch);
    _confirmPasswordController.addListener(_clearMismatch);
  }

  void _clearMismatch() {
    if ((_showMismatch || _showRuleError) && mounted) {
      setState(() {
        _showMismatch = false;
        _showRuleError = false;
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _emailController.dispose();
    _codeController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    return FigmaScreen(
      title: l10n.accForgotPasswordTitle,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 12),
          FigmaAccountFormCard(
            children: [
              FigmaAccountField(
                label: l10n.accEmail,
                controller: _emailController,
                hintText: l10n.accEmailHint,
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
                // 密码行错误优先级：规则不符 > 两次不一致。
                errorText: _showRuleError
                    ? l10n.accPasswordRuleError
                    : (_showMismatch ? l10n.accPasswordMismatch : null),
                autofillHints: const [AutofillHints.newPassword],
              ),
              const FigmaFormDivider(),
              FigmaAccountField(
                label: l10n.accConfirmPassword,
                controller: _confirmPasswordController,
                hintText: l10n.accConfirmPasswordHint,
                obscureText: true,
                errorText:
                    _showMismatch ? l10n.accPasswordMismatchReconfirm : null,
              ),
            ],
          ),
        ],
      ),
      bottom: FigmaPrimaryButton(
        label: l10n.accConfirmButton,
        onPressed: _submitting ? null : _confirm,
        loading: _submitting,
      ),
    );
  }

  Future<void> _getCode() async {
    if (_countdown > 0 || _sendingCode) {
      return;
    }
    // 本地先校验邮箱格式，空/格式错不发请求。
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
      // 忘记密码（未登录）走 sendType:2。
      feedback = await widget.state.sendEmailCode(
        email: _emailController.text,
        sendType: 2,
      );
    } finally {
      // 任何异常都必须收掉 loading，否则遮罩卡死整个页面。
      _sendingCode = false;
      AppLoadingDialog.hide(context);
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

  Future<void> _confirm() async {
    if (_submitting) {
      return;
    }
    if (!_passwordPattern.hasMatch(_passwordController.text)) {
      setState(() => _showRuleError = true);
      return;
    }
    if (_passwordController.text != _confirmPasswordController.text) {
      setState(() => _showMismatch = true);
      return;
    }
    setState(() => _submitting = true);
    final feedback = await widget.state.resetPasswordByEmail(
      email: _emailController.text,
      password: _passwordController.text,
      emailCode: _codeController.text,
    );
    if (!mounted) {
      return;
    }
    setState(() => _submitting = false);
    _showSnack(feedback.message);
    if (feedback.success) {
      widget.onConfirmed?.call();
      Navigator.maybePop(context);
    }
  }

  void _showSnack(String message) {
    AppToast.show(context, message);
  }
}
