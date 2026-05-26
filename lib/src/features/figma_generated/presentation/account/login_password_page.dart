import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../widgets/figma_common.dart';

class LoginPasswordPage extends StatefulWidget {
  const LoginPasswordPage({
    super.key,
    this.initialShowErrors = false,
    this.onLogin,
    this.onForgotPassword,
    this.onRegister,
  });

  final bool initialShowErrors;
  final VoidCallback? onLogin;
  final VoidCallback? onForgotPassword;
  final VoidCallback? onRegister;

  @override
  State<LoginPasswordPage> createState() => _LoginPasswordPageState();
}

class _LoginPasswordPageState extends State<LoginPasswordPage> {
  static const double _designWidth = 375;
  static const double _designHeight = 812;

  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  late bool _showErrors;
  bool _passwordVisible = false;
  bool _agreed = false;

  @override
  void initState() {
    super.initState();
    _showErrors = widget.initialShowErrors;
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
                      child: _LoginPasswordCanvas(
                        emailController: _emailController,
                        passwordController: _passwordController,
                        showErrors: _showErrors,
                        passwordVisible: _passwordVisible,
                        agreed: _agreed,
                        onPasswordVisibilityChanged: () {
                          setState(() {
                            _passwordVisible = !_passwordVisible;
                          });
                        },
                        onForgotPassword: widget.onForgotPassword,
                        onRegister: widget.onRegister,
                        onAgreementChanged: () {
                          setState(() {
                            _agreed = !_agreed;
                          });
                        },
                        onLogin: _handleLogin,
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

  void _handleLogin() {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final emailValid = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email);

    if (!emailValid || password.isEmpty) {
      setState(() {
        _showErrors = true;
      });
      return;
    }

    widget.onLogin?.call();
  }
}

class _LoginPasswordCanvas extends StatelessWidget {
  const _LoginPasswordCanvas({
    required this.emailController,
    required this.passwordController,
    required this.showErrors,
    required this.passwordVisible,
    required this.agreed,
    required this.onPasswordVisibilityChanged,
    required this.onAgreementChanged,
    required this.onLogin,
    this.onForgotPassword,
    this.onRegister,
  });

  final TextEditingController emailController;
  final TextEditingController passwordController;
  final bool showErrors;
  final bool passwordVisible;
  final bool agreed;
  final VoidCallback onPasswordVisibilityChanged;
  final VoidCallback onAgreementChanged;
  final VoidCallback onLogin;
  final VoidCallback? onForgotPassword;
  final VoidCallback? onRegister;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const Positioned.fill(child: _LoginPasswordBackground()),
        const Positioned(left: 0, top: 0, width: 375, child: FigmaStatusBar()),
        const Positioned(left: 28, top: 223, child: _LoginPasswordTitle()),
        Positioned(
          left: 26,
          top: 325,
          width: 323,
          height: 64,
          child: _LoginInputField(
            controller: emailController,
            hintText: '请输入邮箱',
            icon: Icons.mail_outline_rounded,
            keyboardType: TextInputType.emailAddress,
            showError: showErrors,
          ),
        ),
        if (showErrors)
          const Positioned(
            left: 49,
            top: 391,
            child: _LoginErrorText(text: '请输入正确的邮箱地址'),
          ),
        Positioned(
          left: 26,
          top: 419,
          width: 323,
          height: 64,
          child: _LoginInputField(
            controller: passwordController,
            hintText: '请输入密码',
            icon: Icons.verified_user_outlined,
            obscureText: !passwordVisible,
            keyboardType: TextInputType.visiblePassword,
            showError: showErrors,
            trailing: IconButton(
              onPressed: onPasswordVisibilityChanged,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 36, height: 36),
              icon: Icon(
                passwordVisible
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                color: const Color(0xFF8C9092),
                size: 22,
              ),
            ),
          ),
        ),
        if (showErrors)
          const Positioned(
            left: 49,
            top: 485,
            child: _LoginErrorText(text: '密码不能为空'),
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
              child: Text('忘记密码?', style: _LoginPasswordStyles.linkMuted),
            ),
          ),
        ),
        Positioned(
          left: 26,
          top: 543,
          width: 323,
          height: 64,
          child: _LoginPrimaryButton(onPressed: onLogin),
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
          child: _AgreementText(agreed: agreed, onChanged: onAgreementChanged),
        ),
        const FigmaBottomHomeIndicator(),
      ],
    );
  }
}

class _LoginPasswordBackground extends StatelessWidget {
  const _LoginPasswordBackground();

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
          child: _FigmaImageAsset(
            assetPath: 'assets/images/login_bg_image_5130.png',
            fallback: _LoginBackgroundFallback(),
          ),
        ),
      ],
    );
  }
}

class _FigmaImageAsset extends StatelessWidget {
  const _FigmaImageAsset({required this.assetPath, required this.fallback});

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
    final paint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFEAF4FF), Color(0xFFF9FBFF), Color(0xFFFFF7F1)],
        stops: [0, 0.56, 1],
      ).createShader(rect);
    canvas.drawRect(rect, paint);

    final bluePaint = Paint()
      ..color = const Color(0xFFFFFFFF).withValues(alpha: 0.42)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18);
    canvas.drawCircle(const Offset(120, 20), 118, bluePaint);
    canvas.drawCircle(const Offset(55, 270), 170, bluePaint);

    final warmPaint = Paint()
      ..shader =
          RadialGradient(
            colors: [
              const Color(0xFFFFC9A7).withValues(alpha: 0.68),
              const Color(0x00FFC9A7),
            ],
          ).createShader(
            Rect.fromCircle(center: const Offset(372, 180), radius: 125),
          );
    canvas.drawCircle(const Offset(372, 180), 125, warmPaint);

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

class _LoginPasswordTitle extends StatelessWidget {
  const _LoginPasswordTitle();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 320,
      height: 72,
      child: Stack(
        children: [
          const Positioned(
            left: 0,
            top: 0,
            child: Text('欢迎使用', style: _LoginPasswordStyles.title),
          ),
          const Positioned(left: 137, top: 3, child: _BoltStarWordmark()),
          Positioned(
            left: 0,
            top: 50,
            child: Text('使用邮箱密码登录或注册', style: _LoginPasswordStyles.subtitle),
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
        return Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: const [
            _GradientText('B', style: _LoginPasswordStyles.brand),
            Padding(
              padding: EdgeInsets.only(left: 1, right: 1, top: 2),
              child: _BoltOIcon(),
            ),
            _GradientText('ltStar', style: _LoginPasswordStyles.brand),
          ],
        );
      },
    );
  }
}

class _GradientText extends StatelessWidget {
  const _GradientText(this.text, {required this.style});

  final String text;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (bounds) {
        return const LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [Color(0xFFFEA24C), Color(0xFFFF5B1F)],
        ).createShader(bounds);
      },
      child: Text(text, style: style),
    );
  }
}

class _BoltOIcon extends StatelessWidget {
  const _BoltOIcon();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(size: const Size(21, 21), painter: _BoltOIconPainter());
  }
}

class _BoltOIconPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final circlePaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFFFA24A), Color(0xFFFF5B1F)],
      ).createShader(rect);
    canvas.drawOval(rect, circlePaint);

    final boltPath = Path()
      ..moveTo(size.width * 0.56, size.height * 0.14)
      ..lineTo(size.width * 0.28, size.height * 0.56)
      ..lineTo(size.width * 0.48, size.height * 0.56)
      ..lineTo(size.width * 0.39, size.height * 0.88)
      ..lineTo(size.width * 0.74, size.height * 0.42)
      ..lineTo(size.width * 0.53, size.height * 0.42)
      ..close();
    canvas.drawPath(boltPath, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _LoginInputField extends StatelessWidget {
  const _LoginInputField({
    required this.controller,
    required this.hintText,
    required this.icon,
    required this.keyboardType,
    required this.showError,
    this.obscureText = false,
    this.trailing,
  });

  final TextEditingController controller;
  final String hintText;
  final IconData icon;
  final TextInputType keyboardType;
  final bool showError;
  final bool obscureText;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xCCFEFEFE),
        borderRadius: BorderRadius.circular(71),
        border: Border.all(
          color: showError ? const Color(0xFFFF3B3B) : Colors.transparent,
          width: 1,
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
                obscureText: obscureText,
                cursorColor: const Color(0xFFEB5F1B),
                style: _LoginPasswordStyles.input,
                decoration: InputDecoration(
                  isCollapsed: true,
                  border: InputBorder.none,
                  hintText: hintText,
                  hintStyle: _LoginPasswordStyles.inputHint,
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

class _LoginErrorText extends StatelessWidget {
  const _LoginErrorText({required this.text});

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
        Text(text, style: _LoginPasswordStyles.error),
      ],
    );
  }
}

class _LoginPrimaryButton extends StatelessWidget {
  const _LoginPrimaryButton({required this.onPressed});

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
            child: Text('登 录', style: _LoginPasswordStyles.button),
          ),
        ),
      ),
    );
  }
}

class _RegisterPrompt extends StatelessWidget {
  const _RegisterPrompt({this.onRegister});

  final VoidCallback? onRegister;

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
          style: _LoginPasswordStyles.register,
        ),
      ),
    );
  }
}

class _AgreementText extends StatelessWidget {
  const _AgreementText({required this.agreed, required this.onChanged});

  final bool agreed;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onChanged,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 16,
            height: 16,
            margin: const EdgeInsets.only(top: 1),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: agreed ? const Color(0xFFEB5F1B) : Colors.transparent,
              border: Border.all(
                color: agreed
                    ? const Color(0xFFEB5F1B)
                    : const Color(0xFF8C9092),
                width: 1,
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
            style: _LoginPasswordStyles.agreement,
          ),
        ],
      ),
    );
  }
}

class _LoginPasswordStyles {
  const _LoginPasswordStyles._();

  static const title = TextStyle(
    color: Color(0xFF2A2B2B),
    fontSize: 30,
    fontWeight: FontWeight.w500,
    height: 1.18,
  );

  static const brand = TextStyle(
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
    fontSize: 15,
    fontWeight: FontWeight.w400,
    height: 1.2,
  );

  static const input = TextStyle(
    color: Color(0xFF2A2B2B),
    fontSize: 15,
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
