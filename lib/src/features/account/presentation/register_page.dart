import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:BoltStar/src/shared/widgets/app_widgets.dart';
import 'package:BoltStar/src/shared/widgets/figma_common.dart';
import '../../../routes/app_routes.dart';
import '../../../shared/l10n/app_l10n.dart';
import '../../../state.dart';
import '../data/email_history.dart';
import 'auth_widgets.dart';

/// 创建账户 / 注册页（一级业务界面）。
///
/// 与登录页共用同一套视觉（`auth_widgets.dart`）：同一张全屏背景、LOGO、
/// 胶囊输入框、渐变主按钮与协议确认行；**不**再与修改/忘记密码页共用表单卡样式。
///
/// 校验时机与登录页一致：点「注册」时统一判断并在对应输入框下方就地提示，
/// 重新输入即清除提示；键盘「完成」只收起键盘，不触发校验。
/// 注册同样要求勾选协议（对齐登录页的协议确认）。
class RegisterPage extends StatefulWidget {
  const RegisterPage({
    super.key,
    required this.state,
    this.onRegistered,
    this.onBackToLogin,
  });

  final PhotoFrameState state;
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

  bool _passwordVisible = false;
  bool _confirmVisible = false;
  bool _agreed = false;

  // 各字段独立的校验错误：点「注册」时统一判定，重新输入即清除对应项。
  bool _emailError = false;
  bool _codeError = false;
  // 密码不符合规则（6-12 位且同时含数字与英文字母），就地在密码行下方提示。
  bool _ruleError = false;
  bool _mismatchError = false;

  bool _submitting = false;
  // 验证码请求在途标记：服务器响应前连点会发多封验证码邮件。
  bool _sendingCode = false;
  int _countdown = 0;
  Timer? _timer;

  static final _emailPattern = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
  // 密码规则：6-12 位，必须同时包含数字和英文字母，且只允许数字/字母。
  static final _passwordPattern = RegExp(
    r'^(?=.*[A-Za-z])(?=.*[0-9])[A-Za-z0-9]{6,12}$',
  );

  @override
  void initState() {
    super.initState();
    // 输入即清除对应字段的错误提示（与登录页一致；仅在有提示挂着时才重建）。
    _emailController.addListener(() {
      if (_emailError && mounted) {
        setState(() => _emailError = false);
      }
    });
    _codeController.addListener(() {
      if (_codeError && mounted) {
        setState(() => _codeError = false);
      }
    });
    _passwordController.addListener(() {
      if ((_ruleError || _mismatchError) && mounted) {
        setState(() {
          _ruleError = false;
          _mismatchError = false;
        });
      }
    });
    _confirmController.addListener(() {
      if (_mismatchError && mounted) {
        setState(() => _mismatchError = false);
      }
    });
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

  Future<void> _getCode() async {
    if (_countdown > 0 || _sendingCode) {
      return;
    }
    // 本地先校验邮箱格式，空/格式错不发请求（原来空邮箱也会打接口）。
    if (!_emailPattern.hasMatch(_emailController.text.trim())) {
      setState(() => _emailError = true);
      return;
    }
    _sendingCode = true;
    // 点击立刻弹蒙层 loading：后端同步发信可能数秒才响应，期间阻断重复点击
    //（否则连点会发多封验证码邮件），也让用户立刻感知「已在发送」。
    AppLoadingDialog.show(context, AppL10n.of(context).accSendingCode);
    final ActionFeedback feedback;
    try {
      // sendType:1 = 注册验证码。
      feedback = await widget.state.sendEmailCode(
        email: _emailController.text,
        sendType: 1,
      );
    } finally {
      // 任何异常都必须收掉 loading，否则遮罩卡死整个页面。
      _sendingCode = false;
      if (mounted) {
        AppLoadingDialog.hide(context);
      }
    }
    if (!mounted) {
      return;
    }
    _showSnack(feedback.message);
    if (feedback.success) {
      _startCountdown();
    }
  }

  void _startCountdown() {
    setState(() => _countdown = 60);
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_countdown <= 1) {
        timer.cancel();
        setState(() => _countdown = 0);
      } else {
        setState(() => _countdown -= 1);
      }
    });
  }

  Future<void> _register() async {
    if (_submitting) {
      return;
    }
    // 同登录页：点注册先收起键盘，再校验/弹提示。
    FocusManager.instance.primaryFocus?.unfocus();
    final emailValid = _emailPattern.hasMatch(_emailController.text.trim());
    final codeFilled = _codeController.text.trim().isNotEmpty;
    final ruleOk = _passwordPattern.hasMatch(_passwordController.text);
    final confirmOk = _passwordController.text == _confirmController.text;
    if (!emailValid || !codeFilled || !ruleOk || !confirmOk) {
      setState(() {
        _emailError = !emailValid;
        _codeError = !codeFilled;
        _ruleError = !ruleOk;
        // 密码本身不合规时先只提示规则错误，规则过了再比对两次一致性。
        _mismatchError = ruleOk && !confirmOk;
      });
      return;
    }
    if (!_agreed) {
      _showSnack(AppL10n.of(context).accAgreementRequired);
      return;
    }
    setState(() => _submitting = true);
    final feedback = await widget.state.registerWithEmail(
      email: _emailController.text,
      password: _passwordController.text,
      emailCode: _codeController.text,
    );
    if (!mounted) {
      return;
    }
    setState(() => _submitting = false);
    if (feedback.success) {
      await EmailHistory.add(_emailController.text); // 记住注册邮箱，登录页自动填充
    }
    _showSnack(feedback.message);
    if (feedback.success) {
      widget.onRegistered?.call();
    }
  }

  void _showSnack(String message) {
    AppToast.show(context, message);
  }

  void _openUserAgreement() {
    Navigator.of(context).pushNamed<void>(AppRoutes.figmaUserAgreement);
  }

  void _openPrivacyPolicy() {
    Navigator.of(context).pushNamed<void>(AppRoutes.figmaPrivacyPolicy);
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.white,
      ),
      child: Scaffold(
        // 同登录页：键盘弹起时压缩视口并允许滚动，小屏上注册按钮不被键盘盖住。
        resizeToAvoidBottomInset: true,
        backgroundColor: const Color(0xFFF7FAFF),
        body: Stack(
          fit: StackFit.expand,
          children: [
            const AuthBackground(),
            SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) => SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 26),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight,
                    ),
                    child: IntrinsicHeight(child: _buildColumn(context)),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildColumn(BuildContext context) {
    final l10n = AppL10n.of(context);
    return AutofillGroup(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: FigmaBackButton(
              onTap:
                  widget.onBackToLogin ?? () => Navigator.maybePop(context),
            ),
          ),
          const Spacer(flex: 2),
          // LOGO + 标题（同登录页的标题组风格）。
          const BoltStarWordmark(),
          const SizedBox(height: 14),
          Text(l10n.accCreateAccount, style: AuthTextStyles.title),
          const SizedBox(height: 12),
          Text(l10n.accRegisterSubtitle, style: AuthTextStyles.subtitle),
          const SizedBox(height: 30),
          // 邮箱。
          SizedBox(
            height: 56,
            child: AuthPillTextField(
              controller: _emailController,
              hintText: l10n.accEmailAddressHint,
              icon: Image.asset(
                'assets/images/email_icon.png',
                width: 24,
                height: 24,
              ),
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              showError: _emailError,
              autofillHints: const [AutofillHints.email],
            ),
          ),
          if (_emailError)
            Padding(
              padding: const EdgeInsets.only(top: 8, left: 23),
              child: AuthErrorText(text: l10n.accEmailInvalid),
            ),
          const SizedBox(height: 16),
          // 验证码 + 获取验证码。
          SizedBox(
            height: 56,
            child: AuthPillTextField(
              controller: _codeController,
              hintText: l10n.accVerifyCodeHint,
              // 无验证码切图资源，用同色系图标保持与左侧图标一致的视觉份量。
              icon: const Icon(
                Icons.verified_user_outlined,
                size: 24,
                color: Color(0xFF8C9092),
              ),
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.next,
              showError: _codeError,
              trailing: _CodeButton(
                label: _countdown > 0
                    ? l10n.accResendIn(_countdown)
                    : l10n.accGetVerifyCode,
                enabled: _countdown <= 0 && !_sendingCode,
                onTap: _getCode,
              ),
            ),
          ),
          if (_codeError)
            Padding(
              padding: const EdgeInsets.only(top: 8, left: 23),
              child: AuthErrorText(text: l10n.accVerifyCodeHint),
            ),
          const SizedBox(height: 16),
          // 密码（占位提示密码规则：6-12位数字+英文）。
          SizedBox(
            height: 56,
            child: AuthPillTextField(
              controller: _passwordController,
              hintText: l10n.accPasswordRuleHint,
              icon: Image.asset(
                'assets/images/password_icon.png',
                width: 24,
                height: 24,
              ),
              keyboardType: TextInputType.visiblePassword,
              textInputAction: TextInputAction.next,
              obscureText: !_passwordVisible,
              showError: _ruleError,
              autofillHints: const [AutofillHints.newPassword],
              trailing: AuthEyeButton(
                visible: _passwordVisible,
                onPressed: () =>
                    setState(() => _passwordVisible = !_passwordVisible),
                showTooltip: l10n.accShowPassword,
                hideTooltip: l10n.accHidePassword,
              ),
            ),
          ),
          if (_ruleError)
            Padding(
              padding: const EdgeInsets.only(top: 8, left: 23),
              child: AuthErrorText(text: l10n.accPasswordRuleError),
            ),
          const SizedBox(height: 16),
          // 确认密码。
          SizedBox(
            height: 56,
            child: AuthPillTextField(
              controller: _confirmController,
              hintText: l10n.accConfirmPasswordHint,
              icon: Image.asset(
                'assets/images/password_icon.png',
                width: 24,
                height: 24,
              ),
              keyboardType: TextInputType.visiblePassword,
              // 键盘「完成」只收起键盘，不触发校验（同登录页）。
              textInputAction: TextInputAction.done,
              obscureText: !_confirmVisible,
              showError: _mismatchError,
              trailing: AuthEyeButton(
                visible: _confirmVisible,
                onPressed: () =>
                    setState(() => _confirmVisible = !_confirmVisible),
                showTooltip: l10n.accShowPassword,
                hideTooltip: l10n.accHidePassword,
              ),
            ),
          ),
          if (_mismatchError)
            Padding(
              padding: const EdgeInsets.only(top: 8, left: 23),
              child: AuthErrorText(text: l10n.accPasswordMismatchReconfirm),
            ),
          const SizedBox(height: 28),
          SizedBox(
            height: 56,
            child: AuthPrimaryButton(
              label: l10n.accRegisterButton,
              onPressed: _submitting ? null : _register,
              loading: _submitting,
            ),
          ),
          const SizedBox(height: 24),
          Center(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.onBackToLogin ?? () => Navigator.maybePop(context),
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: l10n.accHaveAccount),
                    TextSpan(
                      text: l10n.accGoLogin,
                      style: const TextStyle(color: Color(0xFFFF5B1F)),
                    ),
                  ],
                ),
                style: AuthTextStyles.register,
              ),
            ),
          ),
          const Spacer(flex: 3),
          Center(
            child: AuthAgreementRow(
              agreed: _agreed,
              onChanged: () => setState(() => _agreed = !_agreed),
              onUserAgreement: _openUserAgreement,
              onPrivacyPolicy: _openPrivacyPolicy,
              prefixText: l10n.accAgreementPrefix,
              userAgreementText: l10n.accUserAgreementLink,
              andText: l10n.accAnd,
              privacyPolicyText: l10n.accPrivacyPolicyLink,
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

/// 验证码行尾部的「获取验证码 / 60s后重发」文字按钮：橙字可点，倒计时置灰。
class _CodeButton extends StatelessWidget {
  const _CodeButton({
    required this.label,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: enabled ? onTap : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Text(
          label,
          style: TextStyle(
            color: enabled ? const Color(0xFFFF5F1F) : const Color(0x992A2B2B),
            fontSize: 14,
            fontWeight: FontWeight.w500,
            height: 1.2,
          ),
        ),
      ),
    );
  }
}
