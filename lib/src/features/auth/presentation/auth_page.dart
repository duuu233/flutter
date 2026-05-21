import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../state.dart';

/// 邮箱验证码登录/注册页。
///
/// 这个页面按 Figma 的 375x812 设计稿做高保真还原，视觉层尽量集中在
/// `_AuthCanvas` 及其子组件里；业务层只保留验证码发送、登录和协议勾选校验。
class AuthPage extends StatefulWidget {
  const AuthPage({super.key, required this.state});

  final PhotoFrameState state;

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  // Figma 原稿尺寸。页面外层根据实际屏幕做等比 cover 缩放，内部坐标保持设计稿单位。
  static const double _designWidth = 375;
  static const double _designHeight = 812;

  late final TextEditingController _emailController;
  final TextEditingController _codeController = TextEditingController();
  bool _agreed = false;

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
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: const Color(0xFFEAF3FF),
      ),
      child: Scaffold(
        backgroundColor: Colors.white,
        resizeToAvoidBottomInset: false,
        body: LayoutBuilder(
          builder: (context, constraints) {
            // 使用 cover 缩放保证 375x812 的 Figma 画布铺满屏幕；
            // 各组件仍以设计稿坐标定位，避免在多个地方换算尺寸。
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
                        codeController: _codeController,
                        agreed: _agreed,
                        onSendCode: _sendCode,
                        onLoginOrRegister: _loginOrRegister,
                        onAgreementChanged: () {
                          setState(() {
                            _agreed = !_agreed;
                          });
                        },
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

  /// 当前演示项目只需要本地格式校验；真实接口接入时可替换为后端返回规则。
  bool _isValidEmail(String value) {
    return RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value.trim());
  }

  /// 发送验证码前先做前端轻校验，避免无效输入进入全局状态。
  void _sendCode() {
    final email = _emailController.text.trim();
    if (!_isValidEmail(email)) {
      _showFeedback('请输入有效的邮箱地址');
      return;
    }

    widget.state.sendEmailCode(email);
    _showFeedback('验证码已发送，演示验证码为 246810');
  }

  /// 登录按钮的业务入口：输入校验、协议校验和状态层登录调用都从这里发起。
  void _loginOrRegister() {
    final email = _emailController.text.trim();
    final code = _codeController.text.trim();
    if (!_isValidEmail(email)) {
      _showFeedback('请输入有效的邮箱地址');
      return;
    }
    if (code.isEmpty) {
      _showFeedback('请输入验证码');
      return;
    }
    if (!_agreed) {
      _showFeedback('请先阅读并同意用户协议和隐私政策');
      return;
    }

    final feedback = widget.state.loginWithEmail(email, code);
    _showFeedback(feedback.success ? '登录成功' : '验证码错误，请先获取验证码');
  }

  void _showFeedback(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

/// 登录页的视觉画布。
///
/// 子节点顺序对应 Figma 的层叠关系：背景图、波纹覆盖层、状态栏、标题、表单和协议。
/// 需要调整高保真位置时优先改这里的 `Positioned` 坐标，组件内部只处理自身布局。
class _AuthCanvas extends StatelessWidget {
  const _AuthCanvas({
    required this.emailController,
    required this.codeController,
    required this.agreed,
    required this.onSendCode,
    required this.onLoginOrRegister,
    required this.onAgreementChanged,
  });

  final TextEditingController emailController;
  final TextEditingController codeController;
  final bool agreed;
  final VoidCallback onSendCode;
  final VoidCallback onLoginOrRegister;
  final VoidCallback onAgreementChanged;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const Positioned.fill(child: ColoredBox(color: Colors.white)),
        const Positioned(
          left: 0,
          top: 0,
          width: 376,
          height: 812,
          child: _AuthHeroAsset(),
        ),
        const Positioned(
          left: 0,
          top: 0,
          width: 375,
          height: 812,
          child: _AuthWaveAsset(),
        ),
        const Positioned(left: 0, top: 0, width: 375, child: _StatusBar()),
        const Positioned(left: 28, top: 349, child: _TitleGroup()),
        Positioned(
          left: 26,
          top: 442,
          width: 323,
          height: 56,
          child: _PillTextField(
            controller: emailController,
            hintText: '请输入邮箱',
            icon: Icons.mail_outline_rounded,
            keyboardType: TextInputType.emailAddress,
          ),
        ),
        Positioned(
          left: 26,
          top: 518,
          width: 323,
          height: 56,
          child: _CodeTextField(
            controller: codeController,
            onSendCode: onSendCode,
          ),
        ),
        Positioned(
          left: 26,
          top: 610,
          width: 323,
          height: 56,
          child: _PrimaryAuthButton(onPressed: onLoginOrRegister),
        ),
        Positioned(
          left: 56,
          top: 702,
          child: _AgreementRow(agreed: agreed, onChanged: onAgreementChanged),
        ),
      ],
    );
  }
}

class _AuthHeroAsset extends StatelessWidget {
  const _AuthHeroAsset();

  @override
  Widget build(BuildContext context) {
    // TODO: Export Figma node "ChatGPT Image 2026年5月16日 16_08_37 1"
    // as assets/images/auth_hero_background.png and replace this placeholder.
    return Image.asset(
      'images/1.png',
      width: 376,
      height: 812,
      fit: BoxFit.cover,
    );
  }
}

class _AuthWaveAsset extends StatelessWidget {
  const _AuthWaveAsset();

  @override
  Widget build(BuildContext context) {
    // TODO: Export Figma node "组 1 1" as assets/images/auth_wave_overlay.png
    // and replace this placeholder.
    return Image.asset(
      'images/1.png',
      width: 375,
      height: 812,
      fit: BoxFit.cover,
    );
  }
}

class _HeroFallback extends StatelessWidget {
  const _HeroFallback();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _HeroFallbackPainter(),
      child: const SizedBox.expand(),
    );
  }
}

class _WaveFallback extends StatelessWidget {
  const _WaveFallback();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _WaveFallbackPainter(),
      child: const SizedBox.expand(),
    );
  }
}

/// Figma 中的 iPhone 状态栏，仅用于视觉还原，不读取真实系统状态。
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
            child: Center(
              child: Text(
                '9:41',
                style: TextStyle(
                  color: Colors.black,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  height: 1.0,
                ),
              ),
            ),
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

/// 欢迎标题区，包含普通标题、品牌渐变字和副标题。
class _TitleGroup extends StatelessWidget {
  const _TitleGroup();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 280,
      height: 68,
      child: Stack(
        children: const [
          Positioned(
            left: 0,
            top: 0,
            child: Text(
              '欢迎使用',
              style: TextStyle(
                color: Color(0xFF2A2B2B),
                fontFamily: 'Source Han Sans CN VF',
                fontSize: 28,
                fontWeight: FontWeight.w500,
                height: 1.2,
              ),
            ),
          ),
          Positioned(left: 115, top: 6, child: _GradientBrandText()),
          Positioned(
            left: 0,
            top: 47,
            child: Text(
              '使用邮箱验证码登录或注册',
              style: TextStyle(
                color: Color(0x992A2B2B),
                fontFamily: 'Source Han Sans CN VF',
                fontSize: 14,
                fontWeight: FontWeight.w400,
                height: 1.2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GradientBrandText extends StatelessWidget {
  const _GradientBrandText();

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (bounds) {
        return const LinearGradient(
          colors: [Color(0xFFFD6320), Color(0xFFFEA74F)],
        ).createShader(bounds);
      },
      child: const Text(
        'BoltStar',
        style: TextStyle(
          fontFamily: 'Roboto',
          fontSize: 30,
          fontWeight: FontWeight.w600,
          height: 1.0,
          letterSpacing: 1,
        ),
      ),
    );
  }
}

/// 复用的圆角输入框；邮箱和后续同规格输入可共用这套间距和字体。
class _PillTextField extends StatelessWidget {
  const _PillTextField({
    required this.controller,
    required this.hintText,
    required this.icon,
    required this.keyboardType,
  });

  final TextEditingController controller;
  final String hintText;
  final IconData icon;
  final TextInputType keyboardType;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0x80FEFEFE),
        borderRadius: BorderRadius.circular(71),
      ),
      child: Padding(
        padding: const EdgeInsets.only(left: 22, right: 22),
        child: Row(
          children: [
            Icon(icon, color: const Color(0xFF8C9092), size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: controller,
                keyboardType: keyboardType,
                cursorColor: const Color(0xFFEB5F1B),
                style: _AuthTextStyles.inputText,
                decoration: InputDecoration(
                  isCollapsed: true,
                  border: InputBorder.none,
                  hintText: hintText,
                  hintStyle: _AuthTextStyles.inputHint,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 验证码输入框比普通输入框多了分割线和发送入口，所以单独拆出组件。
class _CodeTextField extends StatelessWidget {
  const _CodeTextField({required this.controller, required this.onSendCode});

  final TextEditingController controller;
  final VoidCallback onSendCode;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0x80FEFEFE),
        borderRadius: BorderRadius.circular(71),
      ),
      child: Padding(
        padding: const EdgeInsets.only(left: 22, right: 22),
        child: Row(
          children: [
            const Icon(
              Icons.verified_user_outlined,
              color: Color(0xFF8C9092),
              size: 24,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: controller,
                keyboardType: TextInputType.number,
                cursorColor: const Color(0xFFEB5F1B),
                style: _AuthTextStyles.inputText,
                decoration: InputDecoration(
                  isCollapsed: true,
                  border: InputBorder.none,
                  hintText: '请输入验证码',
                  hintStyle: _AuthTextStyles.inputHint,
                ),
              ),
            ),
            const SizedBox(width: 20),
            Container(width: 1, height: 30, color: const Color(0x1A2A2B2B)),
            const SizedBox(width: 20),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onSendCode,
              child: const SizedBox(
                width: 70,
                child: Text(
                  '获取验证码',
                  textAlign: TextAlign.right,
                  maxLines: 1,
                  style: TextStyle(
                    color: Color(0xFFEB5F1B),
                    fontFamily: 'Source Han Sans CN VF',
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                    height: 1.2,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 主操作按钮，保留 Figma 的渐变、圆角和投影参数。
class _PrimaryAuthButton extends StatelessWidget {
  const _PrimaryAuthButton({required this.onPressed});

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
        boxShadow: const [
          BoxShadow(
            color: Color(0x4FEB5F1B),
            blurRadius: 7.3,
            offset: Offset(0, 3),
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
            child: Text(
              '登录/注册',
              style: TextStyle(
                color: Colors.white,
                fontFamily: 'Source Han Sans CN VF',
                fontSize: 18,
                fontWeight: FontWeight.w400,
                height: 1.2,
                letterSpacing: 2,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 协议勾选行。整行都可点击，扩大触控面积，降低移动端误触成本。
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Container(
              width: 15,
              height: 15,
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
                  ? const Icon(
                      Icons.check_rounded,
                      size: 12,
                      color: Colors.white,
                    )
                  : null,
            ),
          ),
          const SizedBox(width: 7),
          Text.rich(
            TextSpan(
              children: const [
                TextSpan(text: '我已阅读并同意'),
                TextSpan(
                  text: '《用户协议》',
                  style: TextStyle(color: Color(0xFFEB5F1B)),
                ),
                TextSpan(text: '和'),
                TextSpan(
                  text: '《隐私政策》',
                  style: TextStyle(color: Color(0xFFEB5F1B)),
                ),
              ],
            ),
            textAlign: TextAlign.left,
            maxLines: 1,
            style: const TextStyle(
              color: Color(0x992A2B2B),
              fontFamily: 'Source Han Sans CN VF',
              fontSize: 12,
              fontWeight: FontWeight.w400,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}

/// 页面内固定文本样式集中管理，避免输入框和占位文案出现细微不一致。
class _AuthTextStyles {
  const _AuthTextStyles._();

  static const inputHint = TextStyle(
    color: Color(0x992A2B2B),
    fontFamily: 'Source Han Sans CN VF',
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 1.2,
  );

  static const inputText = TextStyle(
    color: Color(0xFF2A2B2B),
    fontFamily: 'Source Han Sans CN VF',
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 1.2,
  );
}

/// 切图资源缺失时的本地兜底绘制，保证开发环境不会出现空白首屏。
class _HeroFallbackPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final backgroundPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFFE9F5FF), Color(0xFFF9FBFF), Color(0xFFEAF3FF)],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, backgroundPaint);

    final glowPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          Colors.white.withValues(alpha: 0.94),
          Colors.white.withValues(alpha: 0),
        ],
      ).createShader(const Rect.fromLTWH(90, 16, 190, 170));
    canvas.drawOval(const Rect.fromLTWH(90, 16, 190, 170), glowPaint);

    final tablePaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFFFFFFFF), Color(0xFFF2F7FF)],
      ).createShader(const Rect.fromLTWH(0, 276, 375, 98));
    canvas.drawOval(const Rect.fromLTWH(-22, 266, 420, 128), tablePaint);

    canvas.save();
    canvas.translate(77, 121);
    canvas.rotate(-0.075);
    final shadowPaint = Paint()
      ..color = const Color(0x22000000)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14);
    final frameRect = RRect.fromRectAndRadius(
      const Rect.fromLTWH(0, 0, 214, 164),
      const Radius.circular(15),
    );
    canvas.drawRRect(frameRect.shift(const Offset(4, 8)), shadowPaint);
    canvas.drawRRect(frameRect, Paint()..color = const Color(0xFFFDFDFB));
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(5, 5, 204, 154),
        const Radius.circular(11),
      ),
      Paint()..color = const Color(0xFFE7E2D8),
    );
    canvas.drawRect(
      const Rect.fromLTWH(27, 28, 160, 101),
      Paint()..color = const Color(0xFFD6B594),
    );
    canvas.drawOval(
      const Rect.fromLTWH(86, 62, 54, 38),
      Paint()..color = const Color(0xFFC98E4A),
    );
    canvas.drawCircle(
      const Offset(113, 60),
      20,
      Paint()..color = const Color(0xFFD9A15C),
    );
    canvas.drawCircle(
      const Offset(142, 88),
      19,
      Paint()..color = const Color(0xFF7A6C63),
    );
    canvas.drawCircle(
      const Offset(111, 15),
      3,
      Paint()..color = const Color(0xFFC6C2BB),
    );
    canvas.restore();

    final vasePaint = Paint()..color = const Color(0xFFF8F4EC);
    canvas.drawOval(const Rect.fromLTWH(308, 208, 29, 54), vasePaint);
    canvas.drawRect(const Rect.fromLTWH(316, 190, 10, 46), vasePaint);
    final leafPaint = Paint()
      ..color = const Color(0xFFB9BD84)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    canvas.drawLine(const Offset(321, 198), const Offset(341, 171), leafPaint);
    canvas.drawLine(const Offset(321, 202), const Offset(305, 182), leafPaint);
    canvas.drawOval(
      const Rect.fromLTWH(338, 164, 10, 18),
      leafPaint..style = PaintingStyle.fill,
    );
    canvas.drawOval(const Rect.fromLTWH(299, 176, 11, 18), leafPaint);

    final sparklePaint = Paint()..color = Colors.white.withValues(alpha: 0.9);
    for (final point in const [
      Offset(40, 108),
      Offset(271, 83),
      Offset(67, 73),
      Offset(292, 326),
    ]) {
      canvas.drawCircle(point, 1.6, sparklePaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// 底部波纹覆盖层的兜底绘制，与主背景分开便于后续替换真实切图。
class _WaveFallbackPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final lowerPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0x00FFFFFF), Color(0x99EAF3FF), Color(0xFFEAF3FF)],
        stops: [0.0, 0.58, 1.0],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, lowerPaint);

    final wavePath = Path()
      ..moveTo(0, 753)
      ..cubicTo(72, 793, 129, 786, 191, 767)
      ..cubicTo(263, 745, 319, 744, 375, 755)
      ..lineTo(375, 812)
      ..lineTo(0, 812)
      ..close();
    canvas.drawPath(wavePath, Paint()..color = const Color(0xCCE5F0FF));

    final highlightPath = Path()
      ..moveTo(0, 760)
      ..cubicTo(77, 796, 131, 793, 193, 773)
      ..cubicTo(263, 751, 319, 750, 375, 761);
    canvas.drawPath(
      highlightPath,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..shader = const LinearGradient(
          colors: [Color(0xFFFFFFFF), Color(0xFFFFD7CF), Color(0x00FFFFFF)],
        ).createShader(const Rect.fromLTWH(0, 744, 375, 56)),
    );

    final dotPaint = Paint()..color = Colors.white.withValues(alpha: 0.92);
    canvas.drawCircle(const Offset(293, 792), 2.8, dotPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
