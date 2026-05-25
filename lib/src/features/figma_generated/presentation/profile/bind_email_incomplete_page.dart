import 'package:flutter/material.dart';

import '../widgets/figma_common.dart';

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
            height: 122,
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
                  onGetCode: widget.onGetCode,
                ),
              ],
            ),
          ),
          Positioned(
            left: 26,
            top: 543,
            width: 323,
            height: 64,
            child: const FigmaPrimaryButton(label: '确认绑定', height: 64),
          ),
          const FigmaBottomHomeIndicator(),
        ],
      ),
    );
  }
}
