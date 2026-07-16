import 'dart:async';

import 'package:flutter/material.dart';

import 'package:BoltStar/src/shared/widgets/app_widgets.dart';
import 'package:BoltStar/src/shared/widgets/figma_common.dart';
import '../../../shared/l10n/app_l10n.dart';
import '../../../state.dart';

/// 绑定邮箱页：为未绑定邮箱的账号设置「邮箱 + 登录密码」，对照小程序
/// `subpackages/settings/bind-email`（邮箱/验证码/密码/确认密码 四行 + 提示）。
///
/// 邮箱验证码 sendType:3（统一走 sendEmail）；提交走 `changeUserEmail`
/// （携带 md5 密码，见 [PhotoFrameState.changeBoundEmail]）。密码两次一致才可提交。
class BindEmailIncompletePage extends StatefulWidget {
  const BindEmailIncompletePage({super.key, required this.state, this.onBound});

  final PhotoFrameState state;
  final VoidCallback? onBound;

  @override
  State<BindEmailIncompletePage> createState() =>
      _BindEmailIncompletePageState();
}

class _BindEmailIncompletePageState extends State<BindEmailIncompletePage> {
  final TextEditingController _emailController = TextEditingController();
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
      title: l10n.accBindEmailTitle,
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
          Padding(
            padding: const EdgeInsets.only(top: 14),
            child: FigmaInfoTip(text: l10n.accBindEmailTip),
          ),
        ],
      ),
      bottom: FigmaPrimaryButton(
        label: l10n.accConfirmBind,
        onPressed: _submitting ? null : _confirm,
      ),
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
    // 验证码发送到待绑定邮箱，sendType:3；统一走 sendEmail。
    final feedback = await widget.state.sendEmailCode(
      email: _emailController.text,
      sendType: 3,
      loggedIn: true,
    );
    _sendingCode = false;
    if (mounted) {
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
    final password = _passwordController.text;
    if (password.isEmpty) {
      _showSnack(AppL10n.of(context).accSetLoginPassword);
      return;
    }
    if (password != _confirmPasswordController.text) {
      _showSnack(AppL10n.of(context).accPasswordMismatchRetry);
      return;
    }
    setState(() => _submitting = true);
    final feedback = await widget.state.changeBoundEmail(
      email: _emailController.text,
      emailCode: _codeController.text,
      password: password,
    );
    if (!mounted) {
      return;
    }
    setState(() => _submitting = false);
    _showSnack(feedback.message);
    if (feedback.success) {
      widget.onBound?.call();
      Navigator.maybePop(context);
    }
  }

  void _showSnack(String message) {
    AppToast.show(context, message);
  }
}
