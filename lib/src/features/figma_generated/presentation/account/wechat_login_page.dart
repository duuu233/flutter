import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../widgets/figma_common.dart';

/// 微信登录页，对应 UI 稿「微信登录页」。
///
/// 仅做前端壳：点击微信登录前要求勾选协议；微信图标使用占位资源，后续替换 `login-wx-icon.png`。
class WechatLoginPage extends StatefulWidget {
  const WechatLoginPage({super.key, this.onLogin, this.onBack});

  final VoidCallback? onLogin;
  final VoidCallback? onBack;

  @override
  State<WechatLoginPage> createState() => _WechatLoginPageState();
}

class _WechatLoginPageState extends State<WechatLoginPage> {
  static const double _designWidth = 375;
  static const double _designHeight = 812;

  bool _agreed = false;

  void _login() {
    if (!_agreed) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('请先阅读并同意用户协议和隐私政策')));
      return;
    }
    widget.onLogin?.call();
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
                      child: _buildCanvas(context),
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

  Widget _buildCanvas(BuildContext context) {
    return Stack(
      children: [
        const Positioned.fill(child: _WechatBackground()),
        const Positioned(left: 0, top: 0, width: 375, child: FigmaStatusBar()),
        Positioned(
          left: 22,
          top: 46,
          width: 34,
          height: 34,
          child: FigmaRoundIconButton(
            icon: Icons.chevron_left_rounded,
            onTap: widget.onBack ?? () => Navigator.maybePop(context),
          ),
        ),
        const Positioned(
          left: 0,
          top: 250,
          width: 375,
          child: Center(child: _BoltStarWordmark()),
        ),
        Positioned(
          left: 26,
          top: 452,
          width: 323,
          height: 56,
          child: _WechatLoginButton(onPressed: _login),
        ),
        Positioned(
          left: 0,
          top: 536,
          width: 375,
          child: Center(
            child: _AgreementRow(
              agreed: _agreed,
              onChanged: () => setState(() => _agreed = !_agreed),
            ),
          ),
        ),
        const FigmaBottomHomeIndicator(),
      ],
    );
  }
}

class _WechatBackground extends StatelessWidget {
  const _WechatBackground();

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/images/login_bg_image_5130.png',
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) =>
          const FigmaSoftLoginBackground(),
    );
  }
}

class FigmaSoftLoginBackground extends StatelessWidget {
  const FigmaSoftLoginBackground({super.key});

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFEAF4FF), Color(0xFFF9FBFF), Color(0xFFFFF7F1)],
          stops: [0, 0.56, 1],
        ),
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
      width: 180,
      height: 45,
      fit: BoxFit.contain,
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
          child: const Text(
            'BoltStar',
            style: TextStyle(
              fontSize: 40,
              fontStyle: FontStyle.italic,
              fontWeight: FontWeight.w800,
              height: 1,
            ),
          ),
        );
      },
    );
  }
}

class _WechatLoginButton extends StatelessWidget {
  const _WechatLoginButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFF7D36), Color(0xFFFF621F)],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFEB5F1B).withValues(alpha: 0.31),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(28),
        child: InkWell(
          borderRadius: BorderRadius.circular(28),
          onTap: onPressed,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const _WechatIcon(),
              const SizedBox(width: 10),
              const Text(
                '微信登录',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                  height: 1.2,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WechatIcon extends StatelessWidget {
  const _WechatIcon();

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/images/login-wx-icon.png',
      width: 24,
      height: 24,
      fit: BoxFit.contain,
      errorBuilder: (context, error, stackTrace) =>
          const Icon(Icons.chat_rounded, color: Colors.white, size: 24),
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
            style: const TextStyle(
              color: Color(0x992A2B2B),
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
