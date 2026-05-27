import 'package:flutter/material.dart';

import 'package:BoltStar/src/shared/widgets/figma_common.dart';

/// 忘记密码 / 重置密码页，对应 UI 稿「忘记密码」。
class ForgotPassword extends StatefulWidget {
  const ForgotPassword({super.key, this.onConfirmed});

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

  @override
  void initState() {
    super.initState();
    _emailController = TextEditingController(text: '123456789@qq.com');
  }

  @override
  void dispose() {
    _emailController.dispose();
    _codeController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FigmaPhoneFrame(
      child: Stack(
        children: [
          const FigmaPageBackground(),
          const Positioned(
            left: 0,
            top: 0,
            width: 375,
            height: 90,
            child: FigmaTopNavigation(title: '忘记密码'),
          ),
          Positioned(
            left: 24,
            top: 109,
            width: 327,
            height: 249,
            child: FigmaAccountFormCard(
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
                  onGetCode: _showCodeMessage,
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
          ),
          Positioned(
            left: 26,
            top: 543,
            width: 323,
            height: 64,
            child: FigmaPrimaryButton(
              label: '确认',
              height: 64,
              onPressed: _confirm,
            ),
          ),
          const FigmaBottomHomeIndicator(),
        ],
      ),
    );
  }

  void _showCodeMessage() {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('验证码已发送')));
  }

  void _confirm() {
    widget.onConfirmed?.call();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('密码已重置')));
  }
}
