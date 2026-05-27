import 'dart:async';

import 'package:flutter/material.dart';

import 'package:BoltStar/src/shared/widgets/figma_common.dart';

/// 创建账户 / 注册页，对应 UI 稿「创建账户-未输入 / 已输入可注册 / 密码不一致」。
///
/// 三种状态由用户输入自然驱动：未填写时主按钮置灰，填写后变为可点击，
/// 点击时若两次密码不一致则在密码、确认密码下方提示。
class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key, this.onRegistered, this.onBackToLogin});

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
  int _countdown = 0;
  Timer? _timer;

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
    if (_showMismatch) {
      setState(() => _showMismatch = false);
    } else {
      setState(() {});
    }
  }

  bool get _canSubmit =>
      _emailController.text.trim().isNotEmpty &&
      _codeController.text.trim().isNotEmpty &&
      _passwordController.text.isNotEmpty &&
      _confirmController.text.isNotEmpty;

  void _getCode() {
    if (_countdown > 0) {
      return;
    }
    setState(() => _countdown = 30);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_countdown <= 1) {
        timer.cancel();
        setState(() => _countdown = 0);
      } else {
        setState(() => _countdown -= 1);
      }
    });
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('验证码已发送')));
  }

  void _register() {
    if (_passwordController.text != _confirmController.text) {
      setState(() => _showMismatch = true);
      return;
    }
    widget.onRegistered?.call();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('注册成功')));
  }

  @override
  Widget build(BuildContext context) {
    final mismatchText = _showMismatch ? '密码不一致' : null;

    return FigmaScreen(
      title: '创建账户',
      onBack: widget.onBackToLogin,
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
                errorText: mismatchText,
              ),
              const FigmaFormDivider(),
              FigmaAccountField(
                label: '确认密码',
                controller: _confirmController,
                hintText: '请确认密码',
                obscureText: true,
                errorText: _showMismatch ? '密码不一致，请重新确认密码' : null,
              ),
            ],
          ),
        ],
      ),
      bottom: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FigmaPrimaryButton(
            label: '注 册',
            onPressed: _canSubmit ? _register : null,
          ),
          const SizedBox(height: 16),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onBackToLogin ?? () => Navigator.maybePop(context),
            child: Text.rich(
              const TextSpan(
                children: [
                  TextSpan(text: '已有账户？'),
                  TextSpan(
                    text: ' 去登录',
                    style: TextStyle(color: Color(0xFFFF5B1F)),
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
