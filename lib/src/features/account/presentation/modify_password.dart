import 'dart:async';

import 'package:flutter/material.dart';

import 'package:BoltStar/src/shared/widgets/figma_common.dart';
import '../../../state.dart';

/// 修改密码页，对应 UI 稿「修改密码」。
///
/// 已登录用户通过邮箱验证码重置密码：验证码走已登录通道 `sendEmailToken`，
/// 提交走 `resetPassword`（email/password/emailCode）。
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
  Timer? _timer;

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
    return FigmaScreen(
      title: '修改密码',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 12),
          FigmaAccountFormCard(
            children: [
              FigmaAccountField(
                label: '邮箱',
                controller: _emailController,
                hintText: '请输入邮箱',
                keyboardType: TextInputType.emailAddress,
              ),
              const FigmaFormDivider(),
              FigmaVerificationField(
                controller: _codeController,
                onGetCode: _getCode,
                countdownLabel: _countdown > 0 ? '$_countdown秒后重新获取' : null,
              ),
              const FigmaFormDivider(),
              FigmaAccountField(
                label: '新密码',
                controller: _newPasswordController,
                hintText: '请输入密码',
                obscureText: true,
              ),
              const FigmaFormDivider(),
              FigmaAccountField(
                label: '确认密码',
                controller: _confirmPasswordController,
                hintText: '请确认密码',
                obscureText: true,
              ),
            ],
          ),
        ],
      ),
      bottom: FigmaPrimaryButton(label: '确认', onPressed: _confirm),
    );
  }

  Future<void> _getCode() async {
    if (_countdown > 0) {
      return;
    }
    // 已登录用户改密走 sendEmailToken，sendType:2。
    final feedback = await widget.state.sendEmailCode(
      email: _emailController.text,
      sendType: 2,
      loggedIn: true,
    );
    if (!mounted) {
      return;
    }
    _showSnack(feedback.message);
    if (feedback.success) {
      _startCountdown();
    }
  }

  void _startCountdown() {
    setState(() => _countdown = 30);
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
    if (_newPasswordController.text != _confirmPasswordController.text) {
      _showSnack('两次输入的密码不一致');
      return;
    }
    setState(() => _submitting = true);
    final feedback = await widget.state.resetPasswordByEmail(
      email: _emailController.text,
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
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}
