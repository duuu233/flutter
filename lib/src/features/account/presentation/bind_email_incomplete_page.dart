import 'package:flutter/material.dart';

import 'package:BoltStar/src/shared/widgets/figma_common.dart';

/// 绑定邮箱页（未填写完整）：输入邮箱与验证码的初始状态，对应 UI 稿「绑定邮箱-未完成」。
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

  @override
  void dispose() {
    _emailController.dispose();
    _codeController.dispose();
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
            ],
          ),
        ],
      ),
      bottom: const FigmaPrimaryButton(label: '确认绑定'),
    );
  }
}
