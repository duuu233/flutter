import 'package:flutter/material.dart';

import '../../../shared/shared.dart';
import '../../../state.dart';

class AuthPage extends StatefulWidget {
  const AuthPage({super.key, required this.state});

  final PhotoFrameState state;

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  late final TextEditingController _emailController;
  final TextEditingController _codeController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _emailController = TextEditingController(
      text: widget.state.currentUser.email,
    );
  }

  @override
  void dispose() {
    _emailController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    return SubPageScaffold(
      title: state.tr(zh: '登录注册', en: 'Email Login', ja: 'メールログイン'),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          AppPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  state.tr(
                    zh: 'APP 端邮箱验证码登录',
                    en: 'App Email Verification Login',
                    ja: 'アプリのメール認証ログイン',
                  ),
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  state.tr(
                    zh: '用于替代表格中的小程序授权登录流程，适配 iOS / Android / 鸿蒙 app。',
                    en: 'Replaces mini-program auth with email code login for iOS / Android / HarmonyOS apps.',
                    ja: 'ミニプログラム認証の代わりに、iOS / Android / HarmonyOS 向けのメール認証を提供します。',
                  ),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    labelText: state.tr(zh: '邮箱', en: 'Email', ja: 'メール'),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _codeController,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: state.tr(
                            zh: '验证码',
                            en: 'Code',
                            ja: '認証コード',
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    FilledButton.tonal(
                      onPressed: () {
                        final feedback = state.sendEmailCode(
                          _emailController.text,
                        );
                        _showFeedback(context, feedback.message);
                      },
                      child: Text(
                        state.tr(zh: '发送验证码', en: 'Send Code', ja: '送信'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: () {
                    final feedback = state.loginWithEmail(
                      _emailController.text,
                      _codeController.text,
                    );
                    _showFeedback(context, feedback.message);
                  },
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                  ),
                  child: Text(
                    state.tr(
                      zh: '注册 / 登录',
                      en: 'Register / Login',
                      ja: '登録 / ログイン',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showFeedback(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}
