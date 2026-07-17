import 'dart:async';

import 'package:flutter/material.dart';

import 'package:BoltStar/src/shared/widgets/app_widgets.dart';
import 'package:BoltStar/src/shared/widgets/figma_common.dart';
import '../../../shared/l10n/app_l10n.dart';
import '../../../state.dart';

/// 修改密码页，对应 UI 稿「修改密码」。
///
/// 已登录用户改密：验证码走 `sendEmail(sendType:2)` 发到**账号绑定邮箱**，
/// 提交走 `/Client/User/changePassword`（后端按 userToken 定位账号，body 无邮箱字段）。
/// 邮箱行只读展示绑定邮箱，不可改——填别的邮箱收到的码对不上账号。
/// 未登录的忘记密码流程才走 `resetPassword`（见 forgot_password.dart）。
class ModifyPassword extends StatefulWidget {
  const ModifyPassword({super.key, required this.state, this.onConfirmed});

  final PhotoFrameState state;
  final VoidCallback? onConfirmed;

  @override
  State<ModifyPassword> createState() => _ModifyPasswordState();
}

class _ModifyPasswordState extends State<ModifyPassword> {
  late final TextEditingController _emailController;
  final TextEditingController _codeController = TextEditingController();
  final TextEditingController _newPasswordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();

  int _countdown = 0;
  bool _submitting = false;
  // 验证码请求在途标记：服务器响应前连点会发多封验证码邮件。
  bool _sendingCode = false;
  Timer? _timer;

  // 密码规则：6-12 位，必须同时包含数字和英文字母，且只允许数字/字母。
  static final _passwordPattern = RegExp(
    r'^(?=.*[A-Za-z])(?=.*[0-9])[A-Za-z0-9]{6,12}$',
  );

  @override
  void initState() {
    super.initState();
    final email = widget.state.currentUser.email;
    _emailController = TextEditingController(
      text: email.isEmpty ? '' : email,
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _emailController.dispose();
    _codeController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    return FigmaScreen(
      title: l10n.accModifyPasswordTitle,
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
                readOnly: true,
              ),
              const FigmaFormDivider(),
              FigmaVerificationField(
                controller: _codeController,
                onGetCode: _getCode,
                countdownLabel: _countdown > 0 ? l10n.accResendIn(_countdown) : null,
              ),
              const FigmaFormDivider(),
              FigmaAccountField(
                label: l10n.accNewPassword,
                controller: _newPasswordController,
                // 密码规则占位提示（6-12位数字+英文），登录页不展示。
                hintText: l10n.accPasswordRuleHint,
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
      bottom: FigmaPrimaryButton(label: l10n.accConfirmButton, onPressed: _confirm),
    );
  }

  Future<void> _getCode() async {
    if (_countdown > 0 || _sendingCode) {
      return;
    }
    // changePassword 按 userToken 定位账号，验证码只能发到绑定邮箱；未绑定先去绑定。
    if (_emailController.text.trim().isEmpty) {
      _showSnack(AppL10n.of(context).accModifyPasswordNeedEmail);
      return;
    }
    _sendingCode = true;
    // 点击立刻弹蒙层 loading：后端同步发信可能数秒才响应，期间阻断重复点击
    //（否则连点会发多封验证码邮件），也让用户立刻感知「已在发送」。
    AppLoadingDialog.show(context, AppL10n.of(context).accSendingCode);
    final ActionFeedback feedback;
    try {
      // 已登录用户改密，验证码统一走 sendEmail，sendType:2。
      feedback = await widget.state.sendEmailCode(
        email: _emailController.text,
        sendType: 2,
        loggedIn: true,
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
    if (!_passwordPattern.hasMatch(_newPasswordController.text)) {
      _showSnack(AppL10n.of(context).accPasswordRuleError);
      return;
    }
    if (_newPasswordController.text != _confirmPasswordController.text) {
      _showSnack(AppL10n.of(context).accPasswordMismatchTwice);
      return;
    }
    setState(() => _submitting = true);
    // 已登录改密走 changePassword（userToken 定位账号，无邮箱字段）。
    final feedback = await widget.state.changePasswordLoggedIn(
      password: _newPasswordController.text,
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
