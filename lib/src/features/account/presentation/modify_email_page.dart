import 'dart:async';

import 'package:flutter/material.dart';

import 'package:BoltStar/src/shared/widgets/figma_common.dart';
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
    return FigmaScreen(
      title: '修改邮箱',
      // 全ページ共通背景 bg01（小程序は全画面 mock-bg = 単一背景）。
      background: const FigmaScreenBackground(),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 12),
          FigmaAccountFormCard(
            children: [
              FigmaAccountField(
                label: '当前邮箱',
                controller: _currentEmailController,
                hintText: '',
                readOnly: true,
              ),
              const FigmaFormDivider(),
              FigmaAccountField(
                label: '新邮箱',
                controller: _newEmailController,
                hintText: '请输入新的邮箱地址',
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
                label: '密码',
                controller: _passwordController,
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
      bottom: FigmaPrimaryButton(label: '确认修改', onPressed: _confirm),
    );
  }

  Future<void> _getCode() async {
    if (_countdown > 0) {
      return;
    }
    // 验证码发送到新邮箱，sendType:3；统一走 sendEmail。
    final feedback = await widget.state.sendEmailCode(
      email: _newEmailController.text,
      sendType: 3,
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
    final password = _passwordController.text;
    final confirmPassword = _confirmPasswordController.text;
    // 密码与确认密码一致性校验（对齐小程序 change-email 提交前校验）。
    if (password != confirmPassword) {
      _showSnack('两次输入的密码不一致，请重新输入。');
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
