import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../routes/app_routes.dart';
import '../../../state.dart';

/// 邮箱密码登录页。
///
/// 页面按 375x812 设计稿坐标还原；登录逻辑只保留邮箱密码校验，不再展示验证码登录入口。
class AuthPage extends StatefulWidget {
  const AuthPage({super.key, required this.state});

  final PhotoFrameState state;

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  static const double _designWidth = 375;
  static const double _designHeight = 812;

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
        backgroundColor: Colors.white,
        body: LayoutBuilder(
          builder: (context, constraints) {
            final scale = math.max(
              constraints.maxWidth / _designWidth,
              constraints.maxHeight / _designHeight,
            );

            return ClipRect(
              child: SizedBox.expand(
                child: OverflowBox(
                  maxWidth: _designWidth * scale,
                  maxHeight: _designHeight * scale,
                  child: Transform.scale(
                    scale: scale,
                    child: SizedBox(
                      width: _designWidth,
                      height: _designHeight,
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
                        onLogin: _login,
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  void _login() {
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

    final feedback = widget.state.loginWithPassword(email, password);
    _showFeedback(feedback.message);
  }

  void _forgotPassword() {
    _showFeedback('请前往忘记密码流程重置密码');
  }

  void _register() {
    Navigator.of(context).pushNamed<void>(AppRoutes.figmaRegister);
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
  final VoidCallback onLogin;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const Positioned.fill(child: _LoginBackground()),
        const Positioned(left: 0, top: 0, width: 375, child: _StatusBar()),
        const Positioned(left: 28, top: 223, child: _TitleGroup()),
        Positioned(
          left: 26,
          top: 325,
          width: 323,
          height: 64,
          child: _PillTextField(
            controller: emailController,
            hintText: '请输入邮箱',
            icon: Icons.mail_outline_rounded,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            showError: showErrors,
          ),
        ),
        if (showErrors)
          const Positioned(
            left: 49,
            top: 391,
            child: _ErrorText(text: '请输入正确的邮箱地址'),
          ),
        Positioned(
          left: 26,
          top: 419,
          width: 323,
          height: 64,
          child: _PillTextField(
            controller: passwordController,
            hintText: '请输入密码',
            icon: Icons.verified_user_outlined,
            keyboardType: TextInputType.visiblePassword,
            textInputAction: TextInputAction.done,
            obscureText: !passwordVisible,
            showError: showErrors,
            onSubmitted: (_) => onLogin(),
            trailing: IconButton(
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 36, height: 36),
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
          const Positioned(
            left: 49,
            top: 485,
            child: _ErrorText(text: '密码不能为空'),
          ),
        Positioned(
          left: 258,
          top: 498,
          width: 70,
          height: 22,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onForgotPassword,
            child: const Align(
              alignment: Alignment.centerLeft,
              child: Text('忘记密码?', style: _AuthTextStyles.linkMuted),
            ),
          ),
        ),
        Positioned(
          left: 26,
          top: 543,
          width: 323,
          height: 64,
          child: _PrimaryButton(onPressed: onLogin),
        ),
        Positioned(
          left: 0,
          top: 633,
          width: 375,
          child: _RegisterPrompt(onRegister: onRegister),
        ),
        Positioned(
          left: 57,
          top: 744,
          child: _AgreementRow(agreed: agreed, onChanged: onAgreementChanged),
        ),
        const _HomeIndicator(),
      ],
    );
  }
}

class _LoginBackground extends StatelessWidget {
  const _LoginBackground();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: const [
        Positioned.fill(child: ColoredBox(color: Color(0xFFF7FAFF))),
        Positioned(
          left: 0,
          top: 0,
          width: 376,
          height: 812,
          child: _AssetImageWithFallback(
            assetPath: 'assets/images/login_bg_image_5130.png',
            fallback: _LoginBackgroundFallback(),
          ),
        ),
      ],
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

class _StatusBar extends StatelessWidget {
  const _StatusBar();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: Stack(
        children: [
          const Positioned(
            left: 21,
            top: 12,
            width: 54,
            height: 21,
            child: Center(child: Text('9:41', style: _AuthTextStyles.status)),
          ),
          Positioned(
            right: 14,
            top: 16,
            child: Row(
              children: const [
                Icon(Icons.signal_cellular_alt_rounded, size: 16),
                SizedBox(width: 4),
                Icon(Icons.wifi_rounded, size: 16),
                SizedBox(width: 4),
                Icon(Icons.battery_full_rounded, size: 21),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TitleGroup extends StatelessWidget {
  const _TitleGroup();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 320,
      height: 72,
      child: Stack(
        children: const [
          Positioned(
            left: 0,
            top: 0,
            child: Text('欢迎使用', style: _AuthTextStyles.title),
          ),
          Positioned(left: 137, top: 3, child: _BoltStarWordmark()),
          Positioned(
            left: 0,
            top: 50,
            child: Text('使用邮箱密码登录或注册', style: _AuthTextStyles.subtitle),
          ),
        ],
      ),
    );
  }
}

class _BoltStarWordmark extends StatelessWidget {
  const _BoltStarWordmark();

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/images/login_boltstar_logo.png',
      width: 129,
      height: 32,
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
    );
  }
}

class _PillTextField extends StatelessWidget {
  const _PillTextField({
    required this.controller,
    required this.hintText,
    required this.icon,
    required this.keyboardType,
    required this.textInputAction,
    required this.showError,
    this.obscureText = false,
    this.trailing,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String hintText;
  final IconData icon;
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
            Icon(icon, color: const Color(0xFFFF5B1F), size: 21),
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
                      border: InputBorder.none,
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
  const _AgreementRow({required this.agreed, required this.onChanged});

  final bool agreed;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onChanged,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
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
          const SizedBox(width: 7),
          Text.rich(
            const TextSpan(
              children: [
                TextSpan(text: '我已阅读并同意'),
                TextSpan(
                  text: '《用户协议》',
                  style: TextStyle(color: Color(0xFFFF5B1F)),
                ),
                TextSpan(text: '和'),
                TextSpan(
                  text: '《隐私政策》',
                  style: TextStyle(color: Color(0xFFFF5B1F)),
                ),
              ],
            ),
            maxLines: 1,
            style: _AuthTextStyles.agreement,
          ),
        ],
      ),
    );
  }
}

class _HomeIndicator extends StatelessWidget {
  const _HomeIndicator();

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 120,
      bottom: 8,
      width: 135,
      height: 5,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(100),
        ),
      ),
    );
  }
}

class _AuthTextStyles {
  const _AuthTextStyles._();

  static const status = TextStyle(
    color: Colors.black,
    fontSize: 14,
    fontWeight: FontWeight.w600,
    height: 1,
  );

  static const title = TextStyle(
    color: Color(0xFF2A2B2B),
    fontSize: 30,
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
}
