import 'package:flutter/material.dart';

/// 背景图解码完成前的兜底底色：取自 `assets/images/bg02.jpg` 本身
/// （顶部 8px 均值 → 底部 120px 均值）。
///
/// ⚠️ 不要改回 `#F7EDE2 → #E9D9C4`：那是 bg01 时代的暖米色，图 2026-08-27 已删。
/// 留着暖色的后果不是「配色不统一」这么轻——冷启动时它就夹在原生启动图和 bg02
/// 中间，实测就是一帧米黄闪光。同一套取色也落在原生侧（`values/colors.xml`、
/// `LaunchScreen.storyboard`），三处要一起改。
const Color _kSplashTintTop = Color(0xFFDEE6F4);
const Color _kSplashTintBottom = Color(0xFFECF0F3);

/// LOGO 宽度，**必须与原生启动图逐点对齐**。
///
/// Android 侧是 `drawable/splash_logo.png`（210×44，与本页用的 `logo.png` 同一份
/// 文件、sha256 相同）。它放在无密度限定符的 `drawable/` 里 ⇒ 按 mdpi 基线解释
/// ⇒ 上屏就是 210dp。Flutter 的逻辑像素在 Android 上等于 dp，所以这里写 210。
/// 原来写的 200 差着 5%：原生启动图交接给 Flutter 首帧时 LOGO 会缩一下。
const double _kSplashLogoWidth = 210;

/// APP 启动页（冷启动闪屏）。
///
/// 按需求「暂时使用 LOGO + 背景图」实现：全屏铺 `bg02.jpg`，居中显示品牌
/// `logo.png`（横版字标，约 4:1）。由根组件 [BoltStarApp] 在冷启动时先展示本页
/// 一小段时间，再切到登录页/主壳层（切换动效见 `bolt_star_app.dart`）。
///
/// ## 冷启动这条链上有三屏，本页是第二屏
///
///     原生启动图（Android launch_background / iOS LaunchScreen.storyboard）
///       → 本页（Flutter 首帧）
///         → 登录页 / 主壳层
///
/// 前两屏之间**没有任何过渡动画**，是引擎画出首帧的那一刻硬切的。所以「丝滑」
/// 与否完全取决于两屏的首帧长不长得一样。本页首帧被刻意做成与原生启动图重合：
/// 同一张背景、同一份 LOGO、同样 210dp、同样落在屏幕正中（LOGO **不淡入**，
/// 首帧就是全不透明）。真正的动效从这个重合点之后才开始——slogan 撑开高度、
/// 把 LOGO 顶上去一点点，见 [_slogan]。
///
/// 曾经的三处「闪一下」，成因都在首帧不重合，改动时注意别改回去：
///   1. LOGO 从 opacity 0 淡入 —— 原生那屏已经有 LOGO 了，交接时先消失再淡回来；
///   2. Scaffold 底色是主题的 `#F6EFE5`（暖米），背景图解码完成前先闪一屏米黄；
///   3. 原生侧的背景还是老图 bg01（暖白纸纹），Flutter 侧早已是 bg02（冷蓝白）。
class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1000),
  )..forward();

  /// slogan 的进场：前 25% 留白（让首帧与原生启动图静静重合一小会儿，
  /// 交接完成前不动任何东西），之后 easeOutCubic 撑开。
  ///
  /// 同一个量既驱动淡入也驱动 [SizeTransition] 的高度：高度从 0 长到
  /// 「16 间距 + 一行文字」，而 LOGO+slogan 这一列是整体居中的，于是 LOGO 会
  /// 被匀速顶上去约 17dp。这就是本页全部的动效——它天然从「LOGO 正中」这个
  /// 与原生完全一致的位姿出发，所以看不到接缝。
  late final Animation<double> _slogan = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0.25, 1, curve: Curves.easeOutCubic),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // 不用主题的 scaffoldBackgroundColor（`#F6EFE5` 暖米，见类文档第 2 条）。
      backgroundColor: _kSplashTintTop,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 兜底底色层：背景图解码完成前（以及万一加载失败时）由它顶着，
          // 取色即 bg02 本身，所以即便真的露出来也看不出与背景图的分界。
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [_kSplashTintTop, _kSplashTintBottom],
              ),
            ),
          ),
          // 全屏背景 bg02.jpg（与原生启动图、登录/首页等页面统一的**唯一**背景）。
          Image.asset(
            'assets/images/bg02.jpg',
            fit: BoxFit.cover,
            // 解码没能赶上首帧时（低端机冷启动）不要硬切上屏，180ms 淡入接到
            // 底色层上；同步解码到位就直接返回，不平白加一次动画。
            frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
              if (wasSynchronouslyLoaded) return child;
              return AnimatedOpacity(
                opacity: frame == null ? 0 : 1,
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                child: child,
              );
            },
            // 失败时透出下面的底色层即可，别再画一层自己的渐变。
            errorBuilder: (context, error, stackTrace) =>
                const SizedBox.expand(),
          ),
          // 居中品牌 LOGO（英文字标，与原生启动图 splash_logo 同一份文件）+ slogan。
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset(
                  'assets/images/logo.png',
                  width: _kSplashLogoWidth,
                  fit: BoxFit.contain,
                ),
                // axisAlignment: -1 ⇒ 贴着顶边往下长，配合外层 Center
                // 得到「LOGO 徐徐上浮、slogan 在下方显影」的观感。
                SizeTransition(
                  sizeFactor: _slogan,
                  axisAlignment: -1,
                  child: FadeTransition(
                    opacity: _slogan,
                    child: const Padding(
                      padding: EdgeInsets.only(top: 16),
                      child: Text(
                        '把美好，留在一张纸上',
                        style: TextStyle(
                          color: Color(0xFF808690),
                          fontSize: 15,
                          fontWeight: FontWeight.w400,
                          letterSpacing: 1,
                          height: 1.2,
                          decoration: TextDecoration.none,
                        ),
                      ),
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
}
