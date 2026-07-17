import 'dart:async';

import 'package:flutter/material.dart';

import 'package:BoltStar/src/shared/widgets/app_widgets.dart';
import 'package:BoltStar/src/shared/widgets/figma_common.dart';
import '../../../shared/l10n/app_l10n.dart';
import '../../../state.dart';

/// 修改邮箱页：更换已绑定的邮箱地址，对应 UI 稿「修改邮箱」。
///
/// 验证码发送到「新邮箱」（sendType:3，统一走 sendEmail），
/// 提交走 `changeUserEmail`（email/emailCode）。
class ModifyEmailPage extends StatefulWidget {
  const ModifyEmailPage({super.key, required this.state, this.onConfirmed});

  final PhotoFrameState state;
  final VoidCallback? onConfirmed;

  @override
  State<ModifyEmailPage> createState() => _ModifyEmailPageState();
}

class _ModifyEmailPageState extends State<ModifyEmailPage> {
  late final TextEditingController _currentEmailController;
  final TextEditingController _newEmailController = TextEditingController();
  final TextEditingController _codeController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();

  int _countdown = 0;
  bool _submitting = false;
  // 验证码请求在途标记：服务器响应前连点会发多封验证码邮件。
  bool _sendingCode = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    final email = widget.state.currentUser.email;
    _currentEmailController = TextEditingController(text: email);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _currentEmailController.dispose();
    _newEmailController.dispose();
    _codeController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    return FigmaScreen(
      title: l10n.accModifyEmailTitle,
      // 全ページ共通背景 bg01（小程序は全画面 mock-bg = 単一背景）。
      background: const FigmaScreenBackground(),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 12),
          FigmaAccountFormCard(
            children: [
              FigmaAccountField(
                label: l10n.accCurrentEmail,
                controller: _currentEmailController,
                hintText: '',
                readOnly: true,
              ),
              const FigmaFormDivider(),
              FigmaAccountField(
                label: l10n.accNewEmail,
                controller: _newEmailController,
                hintText: l10n.accNewEmailHint,
                keyboardType: TextInputType.emailAddress,
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
                hintText: l10n.accPasswordHint,
                obscureText: true,
              ),
              const FigmaFormDivider(),
              FigmaAccountField(
                label: l10n.accConfirmPassword,
                controller: _confirmPasswordController,
                hintText: l10n.accConfirmPasswordHint,
                obscureText: true,
              ),
            ],
          ),
        ],
      ),
      bottom: FigmaPrimaryButton(label: l10n.accConfirmModify, onPressed: _confirm),
    );
  }

  Future<void> _getCode() async {
    if (_countdown > 0 || _sendingCode) {
      return;
    }
    _sendingCode = true;
    // 点击立刻弹蒙层 loading：后端同步发信可能数秒才响应，期间阻断重复点击
    //（否则连点会发多封验证码邮件），也让用户立刻感知「已在发送」。
    AppLoadingDialog.show(context, AppL10n.of(context).accSendingCode);
    // 验证码发送到新邮箱，sendType:3；统一走 sendEmail。
    final feedback = await widget.state.sendEmailCode(
      email: _newEmailController.text,
      sendType: 3,
      loggedIn: true,
    );
    _sendingCode = false;
    AppLoadingDialog.hide(context);
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
    final password = _passwordController.text;
    final confirmPassword = _confirmPasswordController.text;
    // 密码与确认密码一致性校验（对齐小程序 change-email 提交前校验）。
    if (password != confirmPassword) {
      _showSnack(AppL10n.of(context).accPasswordMismatchRetry);
      return;
    }
    setState(() => _submitting = true);
    final feedback = await widget.state.changeBoundEmail(
      email: _newEmailController.text,
      emailCode: _codeController.text,
      password: password,
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
