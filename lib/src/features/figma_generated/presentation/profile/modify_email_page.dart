import 'package:flutter/material.dart';

import '../widgets/figma_common.dart';

class ModifyEmailPage extends StatefulWidget {
  const ModifyEmailPage({super.key, this.onGetCode, this.onConfirm});

  final VoidCallback? onGetCode;
  final VoidCallback? onConfirm;

  @override
  State<ModifyEmailPage> createState() => _ModifyEmailPageState();
}

class _ModifyEmailPageState extends State<ModifyEmailPage> {
  final TextEditingController _currentEmailController = TextEditingController(
    text: '123456789@qq.com',
  );
  final TextEditingController _newEmailController = TextEditingController();
  final TextEditingController _codeController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();

  @override
  void dispose() {
    _currentEmailController.dispose();
    _newEmailController.dispose();
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
            child: FigmaTopNavigation(title: '修改邮箱'),
          ),
          Positioned(
            left: 24,
            top: 109,
            width: 327,
            height: 305,
            child: FigmaAccountFormCard(
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
                  onGetCode: widget.onGetCode,
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
              label: '确认修改',
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
