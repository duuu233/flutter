import 'package:flutter/material.dart';

/// APP 启动页（冷启动闪屏）。
///
/// 目前按需求「暂时使用 LOGO + 背景图」实现：全屏铺 `bg01.png`，
/// 居中显示品牌 `logo.png`（logo 为横版字标，约 4:1）。由根组件
/// [BoltStarApp] 在冷启动时先展示本页一小段时间，再切到登录页/主壳层。
class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  )..forward();

  late final Animation<double> _fade = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOut,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 全屏背景 bg01.png（与登录/首页等页面统一）。加载失败回退到品牌渐变。
          Image.asset(
            'assets/images/bg01.png',
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) => const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFFF7EDE2), Color(0xFFE9D9C4)],
                ),
              ),
            ),
          ),
          // 居中品牌 LOGO，淡入。
          Center(
            child: FadeTransition(
              opacity: _fade,
              child: Image.asset(
                'assets/images/logo.png',
                width: 200,
                fit: BoxFit.contain,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
