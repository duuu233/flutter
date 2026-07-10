import 'dart:async';

import 'package:flutter/material.dart';

import 'package:BoltStar/src/shared/widgets/figma_common.dart';
import '../../../state.dart';

/// 绑定邮箱页：为未绑定邮箱的账号设置「邮箱 + 登录密码」，对照小程序
/// `subpackages/settings/bind-email`（邮箱/验证码/密码/确认密码 四行 + 提示）。
///
/// 邮箱验证码 sendType:3（已登录走 sendEmailToken）；提交走 `changeUserEmail`
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
    return FigmaScreen(
      title: '绑定邮箱',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 12),
          FigmaAccountFormCard(
            children: [
              FigmaAccountField(
                label: '邮箱',
                controller: _emailController,
                hintText: '请输入邮箱地址',
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
          const Padding(
            padding: EdgeInsets.only(top: 14),
            child: FigmaInfoTip(text: '绑定邮箱可以用于app登录'),
          ),
        ],
      ),
      bottom: FigmaPrimaryButton(
        label: '确认绑定',
        onPressed: _submitting ? null : _confirm,
      ),
    );
  }

  Future<void> _getCode() async {
    if (_countdown > 0) {
      return;
    }
    // 验证码发送到待绑定邮箱，sendType:3；已登录走 sendEmailToken。
    final feedback = await widget.state.sendEmailCode(
      email: _emailController.text,
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
    final password = _passwordController.text;
    if (password.isEmpty) {
      _showSnack('请设置用于 app 登录的密码。');
      return;
    }
    if (password != _confirmPasswordController.text) {
      _showSnack('两次输入的密码不一致，请重新输入。');
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
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}
