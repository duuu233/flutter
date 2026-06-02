import 'package:flutter/material.dart';

import 'package:BoltStar/src/shared/widgets/figma_common.dart';

/// 绑定邮箱页（已填写完成）：可提交绑定的状态，对应 UI 稿「绑定邮箱-已完成」。
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
          const Padding(
            padding: EdgeInsets.only(top: 14),
            child: FigmaInfoTip(text: '绑定邮箱可以用于app登录'),
          ),
        ],
      ),
      bottom: FigmaPrimaryButton(label: '确认绑定', onPressed: widget.onConfirm),
    );
  }
}
