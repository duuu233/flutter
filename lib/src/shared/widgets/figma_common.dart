import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 响应式页面脚手架（全屏背景 + 安全区 + 顶部导航 + 内容 +（可选）底部固定区）。
///
/// 结构：全屏背景 + [SafeArea] + 顶部导航 + 可滚动内容 +（可选）底部固定区，
/// 适配任意屏幕尺寸、刘海与系统字号。
class FigmaScreen extends StatelessWidget {
  const FigmaScreen({
    super.key,
    this.title,
    this.showBack = true,
    this.onBack,
    this.trailing,
    required this.body,
    this.bottom,
    this.scrollable = true,
    this.bodyPadding = const EdgeInsets.symmetric(horizontal: 24),
    this.background,
    this.resizeToAvoidBottomInset = true,
  });

  final String? title;
  final bool showBack;
  final VoidCallback? onBack;
  final Widget? trailing;
  final Widget body;
  final Widget? bottom;
  final bool scrollable;
  final EdgeInsets bodyPadding;
  final Widget? background;
  final bool resizeToAvoidBottomInset;

  @override
  Widget build(BuildContext context) {
    final Widget content = scrollable
        ? SingleChildScrollView(padding: bodyPadding, child: body)
        : Padding(padding: bodyPadding, child: body);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.white,
      ),
      child: Scaffold(
        resizeToAvoidBottomInset: resizeToAvoidBottomInset,
        backgroundColor: const Color(0xFFF2F5FC),
        body: Stack(
          fit: StackFit.expand,
          children: [
            background ?? const FigmaScreenBackground(),
            SafeArea(
              child: Column(
                children: [
                  if (title != null)
                    FigmaTopBar(
                      title: title!,
                      showBack: showBack,
                      onBack: onBack,
                      trailing: trailing,
                    ),
                  Expanded(child: content),
                  if (bottom != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
                      child: bottom,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 默认页面背景：`bg01.png` 铺满（对应小程序全屏 `.mock-bg__image`，全部页面统一用同一张背景）。
/// 加载失败回退到顶部浅蓝渐变过渡到底部白。
class FigmaScreenBackground extends StatelessWidget {
  const FigmaScreenBackground({super.key, this.asset = 'assets/images/bg01.png'});

  final String asset;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      asset,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) {
        return const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0xFFEAF1FB),
                Color(0xFFF4F7FC),
                Color(0xFFF2F5FC),
              ],
              stops: [0, 0.4, 1],
            ),
          ),
        );
      },
    );
  }
}

/// 响应式顶部导航条：全宽、标题居中（左右各留等宽槽位保证真正居中）。
class FigmaTopBar extends StatelessWidget {
  const FigmaTopBar({
    super.key,
    required this.title,
    this.showBack = true,
    this.onBack,
    this.trailing,
  });

  final String title;
  final bool showBack;
  final VoidCallback? onBack;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: Stack(
        children: [
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 56),
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: FigmaTextStyles.navigationTitle,
              ),
            ),
          ),
          if (showBack)
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(left: 16),
                child: FigmaBackButton(
                  onTap: onBack ?? () => Navigator.maybePop(context),
                ),
              ),
            ),
          if (trailing != null)
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(right: 16),
                child: trailing,
              ),
            ),
        ],
      ),
    );
  }
}

/// 顶部返回按钮：圆形底图 `return-round-icon.png` + 箭头 `return-arrow-icon.png`
/// 叠加居中（对应小程序 `page-nav` 的 `.nav-back`：56rpx 圆底 + 24rpx 箭头）。
class FigmaBackButton extends StatelessWidget {
  const FigmaBackButton({super.key, this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        width: 30,
        height: 30,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Image.asset(
              'assets/images/return-round-icon.png',
              width: 30,
              height: 30,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) => DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.78),
                  shape: BoxShape.circle,
                ),
              ),
            ),
            Image.asset(
              'assets/images/return-arrow-icon.png',
              width: 13,
              height: 13,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) => const Icon(
                Icons.chevron_left_rounded,
                color: Color(0xFF565D67),
                size: 20,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class FigmaRoundIconButton extends StatelessWidget {
  const FigmaRoundIconButton({super.key, required this.icon, this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.78),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Icon(icon, color: const Color(0xFF2A2B2B), size: 22),
      ),
    );
  }
}

class FigmaPrimaryButton extends StatelessWidget {
  const FigmaPrimaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.height = 56,
  });

  final String label;
  final VoidCallback? onPressed;
  final double height;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    // .settings-primary：胶囊（圆角全圆）+ 渐变 #ff8b3d→#ff641f + 柔和投影。
    final radius = BorderRadius.circular(height / 2);
    return SizedBox(
      height: height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: enabled ? null : const Color(0xFFE2E2E2),
          borderRadius: radius,
          gradient: enabled
              ? const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFFFF8B3D), Color(0xFFFF641F)],
                )
              : null,
          boxShadow: enabled
              ? [
                  BoxShadow(
                    color: const Color(0xFFFF621F).withValues(alpha: 0.2),
                    blurRadius: 18,
                    offset: const Offset(0, 9),
                  ),
                ]
              : null,
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: radius,
          child: InkWell(
            borderRadius: radius,
            onTap: onPressed,
            child: Center(
              child: Text(
                label,
                style: FigmaTextStyles.primaryButton.copyWith(
                  color: enabled ? Colors.white : const Color(0x992A2B2B),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class FigmaSecondaryButton extends StatelessWidget {
  const FigmaSecondaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.height = 56,
  });

  final String label;
  final VoidCallback? onPressed;
  final double height;

  @override
  Widget build(BuildContext context) {
    // .result-secondary：白 0.86 胶囊 + 白描边。
    final radius = BorderRadius.circular(height / 2);
    return SizedBox(
      height: height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.86),
          borderRadius: radius,
          border: Border.all(color: Colors.white.withValues(alpha: 0.9)),
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: radius,
          child: InkWell(
            borderRadius: radius,
            onTap: onPressed,
            child: Center(
              child: Text(label, style: FigmaTextStyles.secondaryButton),
            ),
          ),
        ),
      ),
    );
  }
}

/// 玻璃面板（小程序 `.glass-panel`）：半透明白 + 2rpx 白描边 + 28rpx(=14) 圆角 + 柔和投影。
class FigmaGlassCard extends StatelessWidget {
  const FigmaGlassCard({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
    this.borderRadius = 14,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: Colors.white.withValues(alpha: 0.86)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF7991B2).withValues(alpha: 0.13),
            blurRadius: 27,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: child,
    );
  }
}

class FigmaAccountFormCard extends StatelessWidget {
  const FigmaAccountFormCard({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return FigmaGlassCard(child: Column(children: children));
  }
}

class FigmaAccountField extends StatelessWidget {
  const FigmaAccountField({
    super.key,
    required this.label,
    required this.controller,
    required this.hintText,
    this.keyboardType,
    this.obscureText = false,
    this.readOnly = false,
    this.errorText,
    this.trailing,
  });

  final String label;
  final TextEditingController controller;
  final String hintText;
  final TextInputType? keyboardType;
  final bool obscureText;
  final bool readOnly;
  final String? errorText;

  /// 输入框右侧附加控件（如昵称行的编辑图标）。
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: errorText == null ? 61 : 78,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 18, 0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              children: [
                Text(label, style: FigmaTextStyles.formLabel),
                const SizedBox(width: 16),
                Expanded(
                  child: TextField(
                    controller: controller,
                    textAlign: TextAlign.right,
                    readOnly: readOnly,
                    keyboardType: keyboardType,
                    obscureText: obscureText,
                    cursorColor: const Color(0xFFEB5F1B),
                    // 只读值（如当前邮箱）用小程序的灰色 #777e88，可编辑值用深色。
                    style: readOnly
                        ? FigmaTextStyles.formValue.copyWith(
                            color: const Color(0xFF777E88),
                          )
                        : FigmaTextStyles.formValue,
                    decoration: const InputDecoration(
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
                      hintStyle: FigmaTextStyles.formHint,
                    ),
                  ),
                ),
                if (trailing != null) ...[
                  const SizedBox(width: 9),
                  trailing!,
                ],
              ],
            ),
            if (errorText != null) ...[
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  const Icon(
                    Icons.error_outline_rounded,
                    size: 14,
                    color: Color(0xFFFF5C35),
                  ),
                  const SizedBox(width: 5),
                  Text(errorText!, style: FigmaTextStyles.formError),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class FigmaVerificationField extends StatelessWidget {
  const FigmaVerificationField({
    super.key,
    required this.controller,
    required this.onGetCode,
    this.countdownLabel,
  });

  final TextEditingController controller;
  final VoidCallback? onGetCode;
  final String? countdownLabel;

  @override
  Widget build(BuildContext context) {
    final label = countdownLabel ?? '获取验证码';
    final disabled = countdownLabel != null;

    return SizedBox(
      height: 61,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 18, 0),
        child: Row(
          children: [
            Text('验证码', style: FigmaTextStyles.formLabel),
            const SizedBox(width: 16),
            Expanded(
              child: TextField(
                controller: controller,
                textAlign: TextAlign.right,
                keyboardType: TextInputType.number,
                cursorColor: const Color(0xFFEB5F1B),
                style: FigmaTextStyles.formValue,
                decoration: const InputDecoration(
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
                  hintText: '请输入验证码',
                  hintStyle: TextStyle(
                    color: Color(0xFF8B9098),
                    fontSize: 14,
                    height: 1.2,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: disabled ? null : onGetCode,
              // 验证码按钮（小程序 `.code-btn`）：橙描边圆角矩形；倒计时态灰底无描边。
              child: Container(
                height: 29,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: disabled
                      ? const Color(0xFFF2F2F2)
                      : Colors.white.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(8),
                  border: disabled
                      ? null
                      : Border.all(color: const Color(0xFFFF5F1F)),
                ),
                child: Text(
                  label,
                  style: FigmaTextStyles.codeButton.copyWith(
                    color: disabled
                        ? const Color(0xFFFF7654)
                        : const Color(0xFFFF5F1F),
                    fontWeight: FontWeight.w500,
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

/// 表单行分隔线（小程序 `.form-row + .form-row::before` / `.thin-divider`）：
/// 左右内缩 18、1px、rgba(207,214,224,0.72)。
class FigmaFormDivider extends StatelessWidget {
  const FigmaFormDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 18),
      child: Divider(height: 1, thickness: 1, color: Color(0xB8CFD6E0)),
    );
  }
}

/// 居中提示行（小程序 `.email-tip`）：圆圈「i」徽标 + 说明文字（如「绑定邮箱可以用于app登录」）。
class FigmaInfoTip extends StatelessWidget {
  const FigmaInfoTip({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 13,
          height: 13,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFF8A929D)),
          ),
          child: const Text(
            'i',
            style: TextStyle(
              color: Color(0xFF8A929D),
              fontSize: 9,
              fontWeight: FontWeight.w700,
              height: 1,
            ),
          ),
        ),
        const SizedBox(width: 5),
        Text(
          text,
          style: const TextStyle(
            color: Color(0xFF888F99),
            fontSize: 12,
            fontWeight: FontWeight.w400,
            height: 1.2,
          ),
        ),
      ],
    );
  }
}

class FigmaInfoRow extends StatelessWidget {
  const FigmaInfoRow({
    super.key,
    required this.label,
    required this.value,
    this.icon,
    this.onTap,
    this.danger = false,
  });

  final String label;
  final String value;
  final IconData? icon;
  final VoidCallback? onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        height: 60,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              if (icon != null) ...[
                Icon(
                  icon,
                  size: 20,
                  color: danger
                      ? const Color(0xFFEB5F1B)
                      : const Color(0x992A2B2B),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Text(
                  label,
                  // 信息行标题保持 w600（小程序设备详情 `.info-label`），不随表单标签加粗到 w700。
                  style: FigmaTextStyles.formLabel.copyWith(
                    fontWeight: FontWeight.w600,
                    color: danger
                        ? const Color(0xFFEB5F1B)
                        : const Color(0xFF2A2B2B),
                  ),
                ),
              ),
              Flexible(
                child: Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: FigmaTextStyles.formHint.copyWith(
                    color: danger
                        ? const Color(0xFFEB5F1B)
                        : const Color(0x992A2B2B),
                  ),
                ),
              ),
              if (onTap != null) ...[
                const SizedBox(width: 6),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: Color(0x992A2B2B),
                  size: 18,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

enum FigmaRadarState { searching, found, notFound }

class FigmaDeviceRadar extends StatefulWidget {
  const FigmaDeviceRadar({
    super.key,
    this.state = FigmaRadarState.searching,
    this.animate = false,
  });

  final FigmaRadarState state;
  final bool animate;

  @override
  State<FigmaDeviceRadar> createState() => _FigmaDeviceRadarState();
}

class _FigmaDeviceRadarState extends State<FigmaDeviceRadar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
    if (widget.animate) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant FigmaDeviceRadar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animate && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.animate && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return CustomPaint(
          painter: _FigmaDeviceRadarPainter(
            state: widget.state,
            progress: widget.animate ? _controller.value : 0,
          ),
          child: Center(
            child: Container(
              width: 62,
              height: 62,
              decoration: const BoxDecoration(
                color: Color(0xFFFFF4EC),
                shape: BoxShape.circle,
              ),
              child: Icon(
                widget.state == FigmaRadarState.found
                    ? Icons.check_rounded
                    : widget.state == FigmaRadarState.notFound
                    ? Icons.close_rounded
                    : Icons.bluetooth_searching_rounded,
                color: const Color(0xFFFF6A24),
                size: 30,
              ),
            ),
          ),
        );
      },
    );
  }
}

class FigmaDeviceListCard extends StatelessWidget {
  const FigmaDeviceListCard({
    super.key,
    required this.name,
    this.selected = false,
    this.onTap,
  });

  final String name;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: 327,
        height: 64,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected
                ? const Color(0xFFFF6A24)
                : Colors.white.withValues(alpha: 0.76),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: const Color(0xFFFFF4EC),
                borderRadius: BorderRadius.circular(13),
              ),
              child: const Icon(
                Icons.photo_library_outlined,
                color: Color(0xFFFF6A24),
                size: 26,
              ),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: FigmaTextStyles.deviceName,
              ),
            ),
            Icon(
              selected
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_unchecked_rounded,
              color: selected
                  ? const Color(0xFFFF6A24)
                  : const Color(0x332A2B2B),
              size: 26,
            ),
          ],
        ),
      ),
    );
  }
}

class FigmaProgressBar extends StatelessWidget {
  const FigmaProgressBar({
    super.key,
    required this.progress,
    required this.label,
  });

  final double progress;
  final String label;

  @override
  Widget build(BuildContext context) {
    final value = progress.clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            height: 8,
            child: Stack(
              children: [
                const Positioned.fill(
                  child: ColoredBox(color: Color(0xFFE8E8E8)),
                ),
                FractionallySizedBox(
                  widthFactor: value,
                  child: const ColoredBox(color: Color(0xFFEB5F1B)),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(label, style: FigmaTextStyles.bodySmall),
      ],
    );
  }
}

class FigmaCastResultIcon extends StatelessWidget {
  const FigmaCastResultIcon({super.key, required this.success});

  final bool success;

  @override
  Widget build(BuildContext context) {
    final color = success ? const Color(0xFF1AC27F) : const Color(0xFFFF6A24);
    return Container(
      width: 116,
      height: 116,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: 0.13),
      ),
      child: Center(
        child: Container(
          width: 76,
          height: 76,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withValues(alpha: 0.18),
          ),
          child: Icon(
            success ? Icons.check_rounded : Icons.close_rounded,
            color: color,
            size: 38,
          ),
        ),
      ),
    );
  }
}

class FigmaTextStyles {
  const FigmaTextStyles._();

  // .mock-nav__title / page-nav title → 34rpx(=17) / weight 700 / #111111
  static const navigationTitle = TextStyle(
    color: Color(0xFF111111),
    fontSize: 17,
    fontWeight: FontWeight.w700,
    height: 1.25,
  );

  static const pageHeading = TextStyle(
    color: Color(0xFF2A2B2B),
    fontSize: 20,
    fontWeight: FontWeight.w500,
    height: 1.45,
  );

  static const bodySmall = TextStyle(
    color: Color(0x992A2B2B),
    fontSize: 12,
    fontWeight: FontWeight.w400,
    height: 1.45,
  );

  // .form-label / .email-label / .profile-label → 28rpx(=14) / weight 700 / #2a2d32
  static const formLabel = TextStyle(
    color: Color(0xFF2A2D32),
    fontSize: 14,
    fontWeight: FontWeight.w700,
    height: 1.4,
  );

  static const formValue = TextStyle(
    color: Color(0xFF2A2B2B),
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 1.4,
  );

  // .form-placeholder / .email-placeholder → #8b9098
  static const formHint = TextStyle(
    color: Color(0xFF8B9098),
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 1.4,
  );

  static const formError = TextStyle(
    color: Color(0xFFFF5C35),
    fontSize: 12,
    fontWeight: FontWeight.w400,
    height: 1.4,
  );

  static const codeButton = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w400,
    height: 1.2,
  );

  // .settings-primary → 34rpx(=17) / weight 700
  static const primaryButton = TextStyle(
    color: Colors.white,
    fontSize: 17,
    fontWeight: FontWeight.w700,
    height: 1.2,
    letterSpacing: 1,
  );

  // .result-secondary → 34rpx(=17) / weight 700 / #2a2d32
  static const secondaryButton = TextStyle(
    color: Color(0xFF2A2D32),
    fontSize: 17,
    fontWeight: FontWeight.w700,
    height: 1.2,
    letterSpacing: 1,
  );

  static const deviceName = TextStyle(
    color: Color(0xFF2A2B2B),
    fontSize: 14,
    fontWeight: FontWeight.w500,
    height: 1.4,
  );
}

class _FigmaDeviceRadarPainter extends CustomPainter {
  const _FigmaDeviceRadarPainter({required this.state, required this.progress});

  final FigmaRadarState state;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final pulse = progress * 28;
    final color = state == FigmaRadarState.notFound
        ? const Color(0xFFFF8868)
        : const Color(0xFFFFA063);

    for (final radius in <double>[38, 64, 86]) {
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = color.withValues(alpha: 0.22),
      );
    }

    if (progress > 0) {
      canvas.drawCircle(
        center,
        92 + pulse,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = color.withValues(alpha: 0.22 * (1 - progress)),
      );
    }

    canvas.drawCircle(
      center,
      61,
      Paint()..color = const Color(0xFFFFEAD9).withValues(alpha: 0.82),
    );
    canvas.drawCircle(
      center,
      39,
      Paint()..color = Colors.white.withValues(alpha: 0.96),
    );

    if (state == FigmaRadarState.found) {
      canvas.drawCircle(
        center + const Offset(45, 43),
        10,
        Paint()..color = const Color(0xFFFF6A24),
      );
    } else if (state == FigmaRadarState.notFound) {
      canvas.drawCircle(
        center + const Offset(45, 43),
        10,
        Paint()..color = const Color(0xFFFF6A24),
      );
      final crossPaint = Paint()
        ..color = Colors.white
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(
        center + const Offset(41, 39),
        center + const Offset(49, 47),
        crossPaint,
      );
      canvas.drawLine(
        center + const Offset(49, 39),
        center + const Offset(41, 47),
        crossPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _FigmaDeviceRadarPainter oldDelegate) {
    return oldDelegate.state != state || oldDelegate.progress != progress;
  }
}
