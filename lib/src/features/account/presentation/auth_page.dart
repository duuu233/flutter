import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../routes/app_routes.dart';
import '../../../state.dart';

/// 邮箱密码登录页（应用唯一登录页，路由 `/auth`）。
///
/// 退出登录 / 用户注销后进入；按 375x812 设计稿还原，背景图全屏铺满、表单等比适配。
/// 登录逻辑只保留邮箱密码校验；忘记密码 / 去注册 / 用户协议 / 隐私政策均跳转对应页面。
class AuthPage extends StatefulWidget {
  const AuthPage({super.key, required this.state});

  final PhotoFrameState state;

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  late final TextEditingController _emailController;
  final TextEditingController _passwordController = TextEditingController();

  bool _passwordVisible = false;
  bool _agreed = false;
  bool _showErrors = false;

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
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.white,
      ),
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        backgroundColor: const Color(0xFFF7FAFF),
        body: Stack(
          fit: StackFit.expand,
          children: [
            const _LoginBackground(),
            SafeArea(
              child: _AuthCanvas(
                emailController: _emailController,
                passwordController: _passwordController,
                passwordVisible: _passwordVisible,
                agreed: _agreed,
                showErrors: _showErrors,
                onPasswordVisibilityChanged: () {
                  setState(() {
                    _passwordVisible = !_passwordVisible;
                  });
                },
                onAgreementChanged: () {
                  setState(() {
                    _agreed = !_agreed;
                  });
                },
                onForgotPassword: _forgotPassword,
                onRegister: _register,
                onUserAgreement: _openUserAgreement,
                onPrivacyPolicy: _openPrivacyPolicy,
                onLogin: _login,
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _submitting = false;

  Future<void> _login() async {
    if (_submitting) {
      return;
    }
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final emailValid = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email);

    if (!emailValid || password.trim().isEmpty) {
      setState(() {
        _showErrors = true;
      });
      return;
    }
    if (!_agreed) {
      _showFeedback('请先阅读并同意用户协议和隐私政策');
      return;
    }

    setState(() => _submitting = true);
    final feedback = await widget.state.loginWithPassword(email, password);
    if (!mounted) {
      return;
    }
    setState(() => _submitting = false);
    _showFeedback(feedback.message);
    // 登录页通常以 pushNamedAndRemoveUntil 进入，成功后若可返回则回到主壳层。
    if (feedback.success && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  void _forgotPassword() {
    Navigator.of(context).pushNamed<void>(AppRoutes.figmaForgotPassword);
  }

  void _register() {
    Navigator.of(context).pushNamed<void>(AppRoutes.figmaRegister);
  }

  void _openUserAgreement() {
    Navigator.of(context).pushNamed<void>(AppRoutes.figmaUserAgreement);
  }

  void _openPrivacyPolicy() {
    Navigator.of(context).pushNamed<void>(AppRoutes.figmaPrivacyPolicy);
  }

  void _showFeedback(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

class _AuthCanvas extends StatelessWidget {
  const _AuthCanvas({
    required this.emailController,
    required this.passwordController,
    required this.passwordVisible,
    required this.agreed,
    required this.showErrors,
    required this.onPasswordVisibilityChanged,
    required this.onAgreementChanged,
    required this.onForgotPassword,
    required this.onRegister,
    required this.onUserAgreement,
    required this.onPrivacyPolicy,
    required this.onLogin,
  });

  final TextEditingController emailController;
  final TextEditingController passwordController;
  final bool passwordVisible;
  final bool agreed;
  final bool showErrors;
  final VoidCallback onPasswordVisibilityChanged;
  final VoidCallback onAgreementChanged;
  final VoidCallback onForgotPassword;
  final VoidCallback onRegister;
  final VoidCallback onUserAgreement;
  final VoidCallback onPrivacyPolicy;
  final VoidCallback onLogin;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Spacer(flex: 3),
          const _TitleGroup(),
          const SizedBox(height: 36),
          SizedBox(
            height: 56,
            child: _PillTextField(
              controller: emailController,
              hintText: '请输入邮箱',
              iconAsset: 'assets/images/email-icon.svg',
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              showError: showErrors,
            ),
          ),
          if (showErrors)
            const Padding(
              padding: EdgeInsets.only(top: 8, left: 23),
              child: _ErrorText(text: '请输入正确的邮箱地址'),
            ),
          const SizedBox(height: 16),
          SizedBox(
            height: 56,
            child: _PillTextField(
              controller: passwordController,
              hintText: '请输入密码',
              iconAsset: 'assets/images/password-icon.svg',
              keyboardType: TextInputType.visiblePassword,
              textInputAction: TextInputAction.done,
              obscureText: !passwordVisible,
              showError: showErrors,
              onSubmitted: (_) => onLogin(),
              trailing: IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(
                  width: 36,
                  height: 36,
                ),
                onPressed: onPasswordVisibilityChanged,
                icon: Icon(
                  passwordVisible
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  color: const Color(0xFF8C9092),
                  size: 20,
                ),
              ),
            ),
          ),
          if (showErrors)
            const Padding(
              padding: EdgeInsets.only(top: 8, left: 23),
              child: _ErrorText(text: '密码不能为空'),
            ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onForgotPassword,
              child: const Text('忘记密码?', style: _AuthTextStyles.linkMuted),
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(height: 56, child: _PrimaryButton(onPressed: onLogin)),
          const SizedBox(height: 24),
          _RegisterPrompt(onRegister: onRegister),
          const Spacer(flex: 4),
          Center(
            child: _AgreementRow(
              agreed: agreed,
              onChanged: onAgreementChanged,
              onUserAgreement: onUserAgreement,
              onPrivacyPolicy: onPrivacyPolicy,
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _LoginBackground extends StatelessWidget {
  const _LoginBackground();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: Color(0xFFF7FAFF),
      child: _AssetImageWithFallback(
        assetPath: 'assets/images/bg01.png',
        fallback: _LoginBackgroundFallback(),
      ),
    );
  }
}

class _AssetImageWithFallback extends StatelessWidget {
  const _AssetImageWithFallback({
    required this.assetPath,
    required this.fallback,
  });

  final String assetPath;
  final Widget fallback;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      assetPath,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) => fallback,
    );
  }
}

class _LoginBackgroundFallback extends StatelessWidget {
  const _LoginBackgroundFallback();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _LoginBackgroundPainter());
  }
}

class _LoginBackgroundPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFEAF4FF), Color(0xFFF9FBFF), Color(0xFFFFF7F1)],
          stops: [0, 0.56, 1],
        ).createShader(rect),
    );

    final haze = Paint()
      ..color = Colors.white.withValues(alpha: 0.42)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18);
    canvas.drawCircle(const Offset(120, 20), 118, haze);
    canvas.drawCircle(const Offset(55, 270), 170, haze);

    canvas.drawCircle(
      const Offset(372, 180),
      125,
      Paint()
        ..shader =
            RadialGradient(
              colors: [
                const Color(0xFFFFC9A7).withValues(alpha: 0.68),
                const Color(0x00FFC9A7),
              ],
            ).createShader(
              Rect.fromCircle(center: const Offset(372, 180), radius: 125),
            ),
    );

    final curvePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.62)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    canvas.drawArc(
      const Rect.fromLTWH(-82, -205, 335, 335),
      0.08,
      2.12,
      false,
      curvePaint,
    );
    canvas.drawArc(
      const Rect.fromLTWH(-130, 112, 418, 220),
      3.66,
      1.72,
      false,
      curvePaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _TitleGroup extends StatelessWidget {
  const _TitleGroup();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: const [
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text('欢迎使用', style: _AuthTextStyles.title),
            SizedBox(width: 6),
            _PositionedBoltStarWordmark(),
          ],
        ),
        SizedBox(height: 12),
        Text('使用邮箱密码登录或注册', style: _AuthTextStyles.subtitle),
      ],
    );
  }
}

class _PositionedBoltStarWordmark extends StatelessWidget {
  const _PositionedBoltStarWordmark();

  // 相对基线的微调偏移，让 logo 与「欢迎使用」文字垂直对齐。
  static const double _logoTop = 4;

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(top: _logoTop),
      child: _BoltStarWordmark(),
    );
  }
}

class _BoltStarWordmark extends StatelessWidget {
  const _BoltStarWordmark();

  static const double logoWidth = 130;
  static const double logoHeight = 32;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: logoWidth,
      height: logoHeight,
      child: Image.asset(
        'assets/images/logo.png',
        width: logoWidth,
        height: logoHeight,
        fit: BoxFit.contain,
        alignment: Alignment.centerLeft,
        errorBuilder: (context, error, stackTrace) {
          return ShaderMask(
            blendMode: BlendMode.srcIn,
            shaderCallback: (bounds) {
              return const LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [Color(0xFFFEA24C), Color(0xFFFF5B1F)],
              ).createShader(bounds);
            },
            child: const Text('BoltStar', style: _AuthTextStyles.brandFallback),
          );
        },
      ),
    );
  }
}

class _PillTextField extends StatelessWidget {
  const _PillTextField({
    required this.controller,
    required this.hintText,
    required this.iconAsset,
    required this.keyboardType,
    required this.textInputAction,
    required this.showError,

    this.obscureText = false,
    this.trailing,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String hintText;
  final String iconAsset;
  final TextInputType keyboardType;
  final TextInputAction textInputAction;
  final bool showError;
  final bool obscureText;
  final Widget? trailing;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xCCFEFEFE),
        borderRadius: BorderRadius.circular(71),
        border: Border.all(
          color: showError ? const Color(0xFFFF3B3B) : Colors.transparent,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.only(left: 24, right: 25),
        child: Row(
          children: [
            SvgPicture.asset(iconAsset, width: 24, height: 24),
            const SizedBox(width: 14),
            Expanded(
              child: TextField(
                controller: controller,
                keyboardType: keyboardType,
                textInputAction: textInputAction,
                obscureText: obscureText,
                onSubmitted: onSubmitted,
                cursorColor: const Color(0xFFEB5F1B),
                style: _AuthTextStyles.input,
                decoration:
                    const InputDecoration(
                      isCollapsed: true,
                      filled: false,
                      fillColor: Colors.transparent,
                      hoverColor: Colors.transparent,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      disabledBorder: InputBorder.none,
                      errorBorder: InputBorder.none,
                      focusedErrorBorder: InputBorder.none,
                    ).copyWith(
                      hintText: hintText,
                      hintStyle: _AuthTextStyles.inputHint,
                    ),
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 8), trailing!],
          ],
        ),
      ),
    );
  }
}

class _ErrorText extends StatelessWidget {
  const _ErrorText({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(
          Icons.info_outline_rounded,
          color: Color(0xFFFF3B3B),
          size: 16,
        ),
        const SizedBox(width: 6),
        Text(text, style: _AuthTextStyles.error),
      ],
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(71),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFF7D36), Color(0xFFFF621F)],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFEB5F1B).withValues(alpha: 0.31),
            blurRadius: 7.3,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(71),
        child: InkWell(
          borderRadius: BorderRadius.circular(71),
          onTap: onPressed,
          child: const Center(
            child: Text('登 录', style: _AuthTextStyles.button),
          ),
        ),
      ),
    );
  }
}

class _RegisterPrompt extends StatelessWidget {
  const _RegisterPrompt({required this.onRegister});

  final VoidCallback onRegister;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onRegister,
        child: Text.rich(
          const TextSpan(
            children: [
              TextSpan(text: '没有账户？'),
              TextSpan(
                text: ' 去注册',
                style: TextStyle(color: Color(0xFFFF5B1F)),
              ),
            ],
          ),
          style: _AuthTextStyles.register,
        ),
      ),
    );
  }
}

class _AgreementRow extends StatelessWidget {
  const _AgreementRow({
    required this.agreed,
    required this.onChanged,
    required this.onUserAgreement,
    required this.onPrivacyPolicy,
  });

  final bool agreed;
  final VoidCallback onChanged;
  final VoidCallback onUserAgreement;
  final VoidCallback onPrivacyPolicy;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onChanged,
          child: Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: agreed ? const Color(0xFFEB5F1B) : Colors.transparent,
              border: Border.all(
                color: agreed
                    ? const Color(0xFFEB5F1B)
                    : const Color(0xFF8C9092),
              ),
            ),
            child: agreed
                ? const Icon(Icons.check_rounded, size: 12, color: Colors.white)
                : null,
          ),
        ),
        const SizedBox(width: 7),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onChanged,
          child: const Text('我已阅读并同意', style: _AuthTextStyles.agreement),
        ),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onUserAgreement,
          child: const Text('《用户协议》', style: _AuthTextStyles.agreementLink),
        ),
        const Text('和', style: _AuthTextStyles.agreement),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onPrivacyPolicy,
          child: const Text('《隐私政策》', style: _AuthTextStyles.agreementLink),
        ),
      ],
    );
  }
}

class _AuthTextStyles {
  const _AuthTextStyles._();

  static const title = TextStyle(
    color: Color(0xFF2A2B2B),
    fontSize: 33,
    fontWeight: FontWeight.w500,
    height: 1.18,
  );

  static const brandFallback = TextStyle(
    fontSize: 30,
    fontStyle: FontStyle.italic,
    fontWeight: FontWeight.w800,
    height: 1,
  );

  static const subtitle = TextStyle(
    color: Color(0x992A2B2B),
    fontSize: 15,
    fontWeight: FontWeight.w400,
    height: 1.2,
  );

  static const inputHint = TextStyle(
    color: Color(0x992A2B2B),
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 1.2,
  );

  static const input = TextStyle(
    color: Color(0xFF2A2B2B),
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 1.2,
  );

  static const error = TextStyle(
    color: Color(0xFFFF3B3B),
    fontSize: 13,
    fontWeight: FontWeight.w400,
    height: 1.2,
  );

  static const linkMuted = TextStyle(
    color: Color(0x992A2B2B),
    fontSize: 15,
    fontWeight: FontWeight.w400,
    height: 1.2,
  );

  static const button = TextStyle(
    color: Colors.white,
    fontSize: 18,
    fontWeight: FontWeight.w500,
    height: 1.2,
    letterSpacing: 2,
  );

  static const register = TextStyle(
    color: Color(0x992A2B2B),
    fontSize: 16,
    fontWeight: FontWeight.w400,
    height: 1.2,
  );

  static const agreement = TextStyle(
    color: Color(0x992A2B2B),
    fontSize: 12,
    fontWeight: FontWeight.w400,
    height: 1.2,
  );

  static const agreementLink = TextStyle(
    color: Color(0xFFFF5B1F),
    fontSize: 12,
    fontWeight: FontWeight.w400,
    height: 1.2,
  );
}
