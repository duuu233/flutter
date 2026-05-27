import 'package:flutter/material.dart';

import 'package:BoltStar/src/shared/widgets/figma_common.dart';

/// 修改密码页，对应 UI 稿「修改密码」。
class ModifyPassword extends StatefulWidget {
  const ModifyPassword({super.key, this.onConfirmed});

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

  @override
  void initState() {
    super.initState();
    _emailController = TextEditingController(text: '123456789@qq.com');
  }

  @override
  void dispose() {
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
                onGetCode: _showCodeMessage,
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

  void _showCodeMessage() {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('验证码已发送')));
  }

  void _confirm() {
    widget.onConfirmed?.call();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('密码已修改')));
  }
}
