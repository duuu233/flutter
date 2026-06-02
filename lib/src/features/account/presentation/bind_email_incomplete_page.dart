import 'package:flutter/material.dart';

import 'package:BoltStar/src/shared/widgets/figma_common.dart';

/// 绑定邮箱页（未填写完整）：对照小程序 `subpackages/settings/bind-email` 的 `!canSubmit` 状态——
/// 完整展示「邮箱 / 验证码 / 密码 / 确认密码」四行 + 提示，仅「确认绑定」主按钮置灰不可点。
class BindEmailIncompletePage extends StatefulWidget {
  const BindEmailIncompletePage({super.key, this.onGetCode});

  final VoidCallback? onGetCode;

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
          const Padding(
            padding: EdgeInsets.only(top: 14),
            child: FigmaInfoTip(text: '绑定邮箱可以用于app登录'),
          ),
        ],
      ),
      // 未填写完整：主按钮置灰不可点（onPressed 为 null）。
      bottom: const FigmaPrimaryButton(label: '确认绑定'),
    );
  }
}
