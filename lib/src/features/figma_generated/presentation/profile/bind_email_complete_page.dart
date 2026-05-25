import 'package:flutter/material.dart';

import '../widgets/figma_common.dart';

class BindEmailCompletePage extends StatefulWidget {
  const BindEmailCompletePage({super.key, this.onConfirm});

  final VoidCallback? onConfirm;

  @override
  State<BindEmailCompletePage> createState() => _BindEmailCompletePageState();
}

class _BindEmailCompletePageState extends State<BindEmailCompletePage> {
  final TextEditingController _emailController = TextEditingController(
    text: '123456789@qq.com',
  );
  final TextEditingController _codeController = TextEditingController(
    text: '123456',
  );
  final TextEditingController _passwordController = TextEditingController(
    text: '123456',
  );
  final TextEditingController _confirmPasswordController =
      TextEditingController(text: '123456');

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
            child: FigmaTopNavigation(title: '绑定邮箱'),
          ),
          Positioned(
            left: 24,
            top: 109,
            width: 327,
            height: 244,
            child: FigmaAccountFormCard(
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
                  countdownLabel: '30秒后重新获取',
                  onGetCode: null,
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
          const Positioned(
            left: 44,
            top: 369,
            width: 287,
            child: Text('绑定邮箱可以用于app登录', style: FigmaTextStyles.bodySmall),
          ),
          Positioned(
            left: 26,
            top: 543,
            width: 323,
            height: 64,
            child: FigmaPrimaryButton(
              label: '确认绑定',
              height: 64,
              onPressed: widget.onConfirm,
            ),
          ),
          const FigmaBottomHomeIndicator(),
        ],
      ),
    );
  }
}
