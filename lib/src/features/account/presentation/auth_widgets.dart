import 'package:flutter/material.dart';

/// 登录 / 注册共用的视觉组件（从登录页抽出）。
///
/// 注册页按产品要求与登录页共享同一套风格：同一张全屏背景、同一款胶囊输入框、
/// 同一款渐变主按钮与协议确认行。**改这里 = 登录注册一起变**，两页不再各自手搓。
/// 修改密码 / 忘记密码等二级页仍走 `figma_common.dart` 的表单卡风格，与此无关。

/// 登录/注册页全屏背景：`bg02.jpg` 铺满，加载失败回退到手绘渐变。
class AuthBackground extends StatelessWidget {
  const AuthBackground({super.key});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFFF7FAFF),
      child: Image.asset(
        'assets/images/bg02.jpg',
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) =>
            const _AuthBackgroundFallback(),
      ),
    );
  }
}

class _AuthBackgroundFallback extends StatelessWidget {
  const _AuthBackgroundFallback();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _AuthBackgroundPainter());
  }
}

class _AuthBackgroundPainter extends CustomPainter {
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

/// BoltStar 文字商标图（logo.png），加载失败回退到渐变斜体文字。
class BoltStarWordmark extends StatelessWidget {
  const BoltStarWordmark({super.key});

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
            child: const Text('BoltStar', style: AuthTextStyles.brandFallback),
          );
        },
      ),
    );
  }
}

/// 胶囊输入框（56 高 / 71 圆角 / 半透明白底），左图标 + 输入 + 可选尾部控件。
class AuthPillTextField extends StatelessWidget {
  const AuthPillTextField({
    super.key,
    required this.controller,
    required this.hintText,
    required this.icon,
    required this.keyboardType,
    required this.textInputAction,
    required this.showError,
    this.obscureText = false,
    this.trailing,
    this.onSubmitted,
    this.autofillHints,
    this.iconGap = 14,
  });

  final TextEditingController controller;
  final String hintText;

  /// 左侧图标：登录/注册常规行传 `Image.asset(..., width: 24, height: 24)`；
  /// 没有切图资源的行（如验证码）可传同色系 [Icon]。
  final Widget icon;
  final TextInputType keyboardType;
  final TextInputAction textInputAction;
  final bool showError;
  final bool obscureText;
  final Widget? trailing;
  final ValueChanged<String>? onSubmitted;

  /// 密码管理器自动填充提示（AutofillHints.email / .password）。
  final List<String>? autofillHints;

  /// 左图标与输入文字之间的间距。登录页保持设计稿的 14；注册页单独取值
  /// （见 [AuthPillTextField.registerIconGap]），所以做成参数而不是直接改死。
  final double iconGap;

  /// 注册页专用的图标—文字间距。
  /// 2026-07-31 曾按需求收窄到 8；2026-08-01 产品复看后要求「每个输入框项的图标和
  /// label 文案的间距放大一点」，调到 16（比登录页的 14 再宽一档，四行统一）。
  static const double registerIconGap = 16;

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
            icon,
            SizedBox(width: iconGap),
            Expanded(
              child: TextField(
                controller: controller,
                keyboardType: keyboardType,
                textInputAction: textInputAction,
                obscureText: obscureText,
                onSubmitted: onSubmitted,
                autofillHints: autofillHints,
                cursorColor: const Color(0xFFEB5F1B),
                style: AuthTextStyles.input,
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
                      hintStyle: AuthTextStyles.inputHint,
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

/// 密码可见性切换的眼睛按钮（登录/注册密码行共用尾部控件）。
class AuthEyeButton extends StatelessWidget {
  const AuthEyeButton({
    super.key,
    required this.visible,
    required this.onPressed,
    required this.showTooltip,
    required this.hideTooltip,
  });

  final bool visible;
  final VoidCallback onPressed;
  final String showTooltip;
  final String hideTooltip;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 36, height: 36),
      onPressed: onPressed,
      tooltip: visible ? hideTooltip : showTooltip,
      icon: Icon(
        visible ? Icons.visibility_outlined : Icons.visibility_off_outlined,
        color: const Color(0xFF8C9092),
        size: 20,
      ),
    );
  }
}

/// 橙色渐变胶囊主按钮（登 录 / 注 册），loading 时白色转圈代替文字。
class AuthPrimaryButton extends StatelessWidget {
  const AuthPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    required this.loading,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;

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
          child: Center(
            child: loading
                ? const SizedBox.square(
                    dimension: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Text(label, style: AuthTextStyles.button),
          ),
        ),
      ),
    );
  }
}

/// 协议确认行：圆形勾选 + 「我已阅读并同意《用户协议》和《隐私政策》」。
class AuthAgreementRow extends StatelessWidget {
  const AuthAgreementRow({
    super.key,
    required this.agreed,
    required this.onChanged,
    required this.onUserAgreement,
    required this.onPrivacyPolicy,
    required this.prefixText,
    required this.userAgreementText,
    required this.andText,
    required this.privacyPolicyText,
  });

  /// 各可点元素上下各撑出的**点击热区**（视觉不占位，见 [build] 注释）。
  ///
  /// 调用页要把本行前后的间距**各减去这么多**，行的视觉位置才与加热区之前一致
  /// （登录页/注册页两处都已这么写）。
  static const double hitPadding = 12;

  final bool agreed;
  final VoidCallback onChanged;
  final VoidCallback onUserAgreement;
  final VoidCallback onPrivacyPolicy;
  final String prefixText;
  final String userAgreementText;
  final String andText;
  final String privacyPolicyText;

  /// 上下补热区的可点文字：四段文案的点击高度统一为 `12 + 字高 + 12`。
  Widget _tappable(String text, TextStyle style, VoidCallback onTap) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: hitPadding),
        child: Text(text, style: style),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // ⚠️ 2026-08-31 需求：**协议行一律不换行**。
    // 原来用 Wrap 是为了让 EN 文案 "I have read and agree to User Agreement and
    // Privacy Policy" 在 ≤375dp 窄屏上折行而不横向溢出，但折成两行后这一行会顶到
    // 屏幕最下沿、把按钮区挤上去，观感很差。
    // 改法：Row(mainAxisSize.min) 外面套 [FittedBox]`scaleDown` —— 放得下就**原样不缩**
    // （中/繁/日都放得下，视觉与之前逐像素相同），放不下才整行等比缩到刚好一行。
    // 之所以缩整行而不是只调字号：圆点、间距、四段文字一起缩才不会错位，
    // 而只把 fontSize 写小会连带中文那三种语言一起变小（它们本来就不需要）。
    // ⚠️ FittedBox 会连**点击热区**一起缩（40 高的可点带在 375dp 英文下约剩 34），
    // 仍远大于原来的 16×16，2026-08-28「勾选老点不中」那条修复不受影响。
    //
    // 2026-08-28「勾选老点不中」：视觉是 16 的小圆点，热区却也只有 16×16（约 2.5mm），
    // 而且这一行贴在屏幕最下方、离系统手势区很近，指头稍偏就落空。
    // 对齐小程序 `.login-agreement__check-group` 的 86rpx(=43) 热区做法：**视觉不变、热区放大**——
    // 圆点撑到 32×40，四段文案各自上下补 [hitPadding]，整行连成一条 40 高的可点带。
    // 小程序靠负 margin 抵消热区占位，Flutter 的 Padding 不收负值，这里改为：
    //   ① 圆点右侧的 8 顶掉原来的 7 间距（圆点相对整行只右移约 4，肉眼看不出来）；
    //   ② 纵向多出的 2×12 由调用页把本行前后的间距各减 12 抵消（见 [hitPadding]）。
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.center,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onChanged,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: hitPadding,
              ),
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
                    ? const Icon(
                        Icons.check_rounded,
                        size: 12,
                        color: Colors.white,
                      )
                    : null,
              ),
            ),
          ),
          _tappable(prefixText, AuthTextStyles.agreement, onChanged),
          _tappable(
            userAgreementText,
            AuthTextStyles.agreementLink,
            onUserAgreement,
          ),
          // 「和」不可点：夹在两个链接中间，点它跳哪边都是猜的。热区照补，
          // 否则这一小段会在 40 高的可点带上留一个洞。
          Padding(
            padding: const EdgeInsets.symmetric(vertical: hitPadding),
            child: Text(andText, style: AuthTextStyles.agreement),
          ),
          _tappable(
            privacyPolicyText,
            AuthTextStyles.agreementLink,
            onPrivacyPolicy,
          ),
        ],
      ),
    );
  }
}

class AuthTextStyles {
  const AuthTextStyles._();

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
