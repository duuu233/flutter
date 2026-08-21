import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/app_l10n.dart';

// 居中吐司：从这里 re-export，凡 import 本文件的页面可直接用 AppToast，无需再单独 import。
export 'app_toast.dart';

/// 响应式页面脚手架（全屏背景 + 安全区 + 顶部导航 + 内容 +（可选）底部固定区）。
///
/// 结构：全屏背景 + [SafeArea] + 顶部导航 + 可滚动内容 +（可选）底部固定区，
/// 适配任意屏幕尺寸、刘海与系统字号。
class FigmaScreen extends StatelessWidget {
  const FigmaScreen({
    super.key,
    this.title,
    this.centerContent,
    this.showBack = true,
    this.onBack,
    this.trailing,
    required this.body,
    this.bottom,
    this.scrollable = true,
    this.fillViewport = false,
    this.bodyPadding = const EdgeInsets.symmetric(horizontal: 24),
    this.background,
    this.resizeToAvoidBottomInset = true,
  });

  final String? title;

  /// 顶栏**标题位**的自定义内容；给了它就顶掉标题文字（[title] 仍需非 null，
  /// 否则整条顶栏连返回键一起不渲染）。
  ///
  /// 「设备照片 / 投屏管理」两页用它把设备下拉放进标题位：产品要求去掉页面标题、
  /// 由下拉承担标题作用，那它就该站在标题该在的位置——屏幕水平居中。
  /// 放 [trailing] 会靠右贴边（小程序那边正是因此压上了微信胶囊）。
  final Widget? centerContent;

  final bool showBack;
  final VoidCallback? onBack;
  final Widget? trailing;
  final Widget body;
  final Widget? bottom;
  final bool scrollable;

  /// 折叠屏/分屏/横屏适配（2026-08-05）：内容**不够高时撑满视口、够高时可滚动**。
  ///
  /// 给的是那些「靠 [Spacer]/[Expanded] 把内容顶开、按一屏排版」的页面用的
  /// （绑定设备的搜索中 / 未发现设备等）。它们原本传 `scrollable: false`：一屏装得下时
  /// 排版正确，装不下（折叠屏展开、横屏、分屏、系统大字号）就直接 RenderFlex overflow 被裁掉，
  /// 且没有任何办法滚到下面。
  ///
  /// 打开后：`minHeight = 视口高`，内容不够高时 [Spacer] 照旧按比例分配剩余空间，
  /// **观感与改动前逐像素一致**；内容超过视口时按内容高度排并允许滚动。
  ///
  /// ⚠️ body 里已经有 `Expanded(child: ListView/SingleChildScrollView…)` 的页面**不要**打开：
  /// [IntrinsicHeight] 量不出无界滚动子树的固有高度。那类页面本来就有自己的滚动区，
  /// 继续用 `scrollable: false` 即可。
  ///
  /// 对齐小程序 `styles/fold-adapt.wxss` 的 `.fold-scroll` + `.fold-scroll-body`。
  final bool fillViewport;
  final EdgeInsets bodyPadding;
  final Widget? background;
  final bool resizeToAvoidBottomInset;

  @override
  Widget build(BuildContext context) {
    final Widget content = scrollable
        ? (fillViewport
              ? LayoutBuilder(
                  builder: (context, constraints) {
                    // 减掉 padding：ConstrainedBox 在 padding 之内，直接用 maxHeight
                    // 会把内容撑高一个 padding，短窗口下反而多出一截空滚动。
                    final double available =
                        constraints.maxHeight - bodyPadding.vertical;
                    return SingleChildScrollView(
                      padding: bodyPadding,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: available > 0 ? available : 0.0,
                        ),
                        child: IntrinsicHeight(child: body),
                      ),
                    );
                  },
                )
              : SingleChildScrollView(padding: bodyPadding, child: body))
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
                      centerContent: centerContent,
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

/// 默认页面背景：`bg02.jpg` 铺满（对应小程序全屏 `.mock-bg__image`，全部页面统一用同一张背景）。
/// 加载失败回退到顶部浅蓝渐变过渡到底部白。
///
/// ⚠️ 2026-08-21 换图：小程序把全站背景换成了
/// `https://oss.boltfox.cn/prodFile/202608211340094498724.jpg`（浅蓝墙面 + 窗光），
/// App 侧背景是**打进包里的本地图**，所以把同一张图落成 `assets/images/bg02.jpg`（与线上逐字节相同）。
/// 旧的暖白背景 `assets/images/bg01.png` **保留在仓库里**（产品要求「怕要换回去」），
/// 要整体换回去：把本文件的默认值与各页写死的 `bg02.jpg` 一起改回 `bg01.png` 即可
/// （`grep -rn "assets/images/bg02.jpg" lib` 能列全）。
class FigmaScreenBackground extends StatelessWidget {
  const FigmaScreenBackground({super.key, this.asset = 'assets/images/bg02.jpg'});

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
    this.centerContent,
    this.showBack = true,
    this.onBack,
    this.trailing,
  });

  final String title;

  /// 标题位的自定义内容（见 [FigmaScreen.centerContent]）。非空时替换标题文字，
  /// 位置不变——仍然是屏幕水平居中。
  final Widget? centerContent;

  final bool showBack;
  final VoidCallback? onBack;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: Stack(
        children: [
          // 居中位：自定义内容优先，否则是标题文字。
          // [Center] 只在子组件自身的尺寸内接收点击，外侧仍然让给返回键/trailing。
          Center(
            child:
                centerContent ??
                Padding(
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
                // 9 + (44-30)/2 = 16：命中区扩到 44 后保持圆钮视觉位置不变。
                padding: const EdgeInsets.only(left: 9),
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

/// 顶部返回按钮：整颗按钮就是一张 `ai-back-button.png`
/// （2026-07-31 起两端统一换成这张，对应小程序 `page-nav` 的 `.nav-back-image`；
/// 原来的 `return-round-icon.png` + `return-arrow-icon.png` 两图叠加已废弃）。
class FigmaBackButton extends StatelessWidget {
  const FigmaBackButton({super.key, this.onTap});

  final VoidCallback? onTap;

  /// 图源画布尺寸(136)里「看得见的白色圆角方块」只占 48.5%，四周全是透明投影留白，
  /// 所以要画到 62 白块才是 30 —— 与换图前的圆钮等大、左边缘同样落在 16。
  static const double _artSize = 62;

  /// 投影是往下糊的，白块在画布里偏上 5.15%（画布 136 里偏上 7px）。
  /// 直接居中会看着偏高，整张图要再往下推自身高度的 5.15%，
  /// 居中的才是「白块」而不是「图+投影」。
  static const double _artDownShift = _artSize * 0.0515;

  @override
  Widget build(BuildContext context) {
    // 视觉仍是 30×30 的圆角方块，但命中区扩到 44×44（无障碍最小触达），
    // 并补语义标签让读屏器可识别（此前全 App 顶栏返回键对读屏器不可见）。
    return Semantics(
      button: true,
      label: MaterialLocalizations.of(context).backButtonTooltip,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: 44,
          height: 44,
          // OverflowBox：让 62 的图画得出 44 的命中盒（多出来的只有透明投影），
          // 命中仍按 44 算 —— 对齐小程序给溢出图片加的 pointer-events:none。
          child: OverflowBox(
            maxWidth: _artSize,
            maxHeight: _artSize,
            child: _backButtonArt(),
          ),
        ),
      ),
    );
  }

  Widget _backButtonArt() {
    return Transform.translate(
      offset: const Offset(0, _artDownShift),
      child: Image.asset(
        'assets/images/ai-back-button.png',
        width: _artSize,
        height: _artSize,
        fit: BoxFit.contain,
        // 图丢了也要还原「30 的白色圆角方块 + 箭头」这个视觉，不能掉到 62 的空盒。
        // 兜底图是自己画的、没有投影，所以要把上面为投影补的下移抵消掉。
        errorBuilder: (context, error, stackTrace) => Transform.translate(
          offset: const Offset(0, -_artDownShift),
          child: Center(
            child: Container(
              width: 30,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.78),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.arrow_back_rounded,
                color: Color(0xFF565D67),
                size: 18,
              ),
            ),
          ),
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
    this.loading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final double height;

  /// 提交中：显示白色转圈代替文字（调用方一般同时把 onPressed 置 null 防重复提交）。
  final bool loading;

  @override
  Widget build(BuildContext context) {
    // loading 时保持渐变底色（否则灰底 + 白转圈几乎看不见）。
    final enabled = onPressed != null || loading;
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
              child: loading
                  ? const SizedBox.square(
                      dimension: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(
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

/// 「改名」铅笔图标按钮（设备详情 / 我的设备共用）。
///
/// 图标视觉仍是 18×18，点击区由 padding 撑到 40×40。命中测试**不会越过父级
/// RenderBox 的边界**，所以 `OverflowBox` 这类「不占布局又想扩大点击区」的写法
/// 在这里无效——必须真正占位。撑开后图标四周自带 11px 视觉留白，调用处相邻的
/// 固定间距（原来的 `SizedBox(width: 3)` 等）应一并去掉，整体观感才与之前一致。
class FigmaEditIconButton extends StatelessWidget {
  const FigmaEditIconButton({
    super.key,
    required this.onTap,
    this.iconSize = 18,
    this.hitPadding = 11,
  });

  /// 可空：调用方（如 `DeviceDetailsBody.onEditName`）本来就把「改名」声明成可选回调。
  /// 与被替换掉的裸 `GestureDetector(onTap: ...)` 保持同样的签名，调用处无需改动。
  final VoidCallback? onTap;
  final double iconSize;
  final double hitPadding;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      // 没有回调时不要 opaque：那会让这块 40×40 白白吃掉落在它上面的点击
      // （原来的裸 GestureDetector 就有这个毛病，顺手修掉）。
      behavior: onTap == null
          ? HitTestBehavior.deferToChild
          : HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.all(hitPadding),
        child: Image.asset(
          'assets/images/edit-icon01.png',
          width: iconSize,
          height: iconSize,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) => Icon(
            Icons.edit_outlined,
            size: iconSize - 2,
            color: const Color(0x992A2B2B),
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

class FigmaAccountField extends StatefulWidget {
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
    this.autofillHints,
    this.valueColor,
  });

  final String label;
  final TextEditingController controller;
  final String hintText;
  final TextInputType? keyboardType;
  final bool obscureText;
  final bool readOnly;
  final String? errorText;

  /// 输入值文字颜色覆盖（如个人信息页昵称行按小程序用灰色 #777E88）。
  final Color? valueColor;

  /// 输入框右侧附加控件（如昵称行的编辑图标）。
  final Widget? trailing;

  /// 密码管理器自动填充提示（AutofillHints.email / .newPassword 等）。
  final List<String>? autofillHints;

  @override
  State<FigmaAccountField> createState() => _FigmaAccountFieldState();
}

class _FigmaAccountFieldState extends State<FigmaAccountField> {
  /// 密码字段的当前可见性（obscureText=true 时自动附带眼睛切换，与登录页一致）。
  late bool _obscured = widget.obscureText;

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    // 密码行自动补眼睛按钮（调用方没自定义 trailing 时）。
    final trailing =
        widget.trailing ??
        (widget.obscureText
            ? IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(
                  width: 36,
                  height: 36,
                ),
                onPressed: () => setState(() => _obscured = !_obscured),
                tooltip: _obscured ? l10n.accShowPassword : l10n.accHidePassword,
                icon: Icon(
                  _obscured
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  color: const Color(0xFF8C9092),
                  size: 20,
                ),
              )
            : null);
    // minHeight 而非固定高：系统大字号（1.3x+）时固定 SizedBox 会被内容挤爆。
    return Container(
      constraints: BoxConstraints(
        minHeight: widget.errorText == null ? 61 : 78,
      ),
      alignment: Alignment.center,
      padding: const EdgeInsets.fromLTRB(20, 8, 18, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text(widget.label, style: FigmaTextStyles.formLabel),
              const SizedBox(width: 16),
              Expanded(
                child: TextField(
                  controller: widget.controller,
                  textAlign: TextAlign.right,
                  readOnly: widget.readOnly,
                  keyboardType: widget.keyboardType,
                  obscureText: _obscured,
                  autofillHints: widget.autofillHints,
                  cursorColor: const Color(0xFFEB5F1B),
                  // 只读值（如当前邮箱）用小程序的灰色 #777e88，可编辑值用深色；
                  // valueColor 显式指定时优先。
                  style: widget.valueColor != null
                      ? FigmaTextStyles.formValue.copyWith(
                          color: widget.valueColor,
                        )
                      : widget.readOnly
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
                    hintText: widget.hintText,
                    hintStyle: FigmaTextStyles.formHint,
                  ),
                ),
              ),
              if (trailing != null) ...[const SizedBox(width: 9), trailing],
            ],
          ),
          if (widget.errorText != null) ...[
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
                Text(widget.errorText!, style: FigmaTextStyles.formError),
              ],
            ),
          ],
        ],
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
    final l10n = AppL10n.of(context);
    final label = countdownLabel ?? l10n.accGetVerifyCode;
    final disabled = countdownLabel != null;

    return SizedBox(
      height: 61,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 18, 0),
        child: Row(
          children: [
            Text(l10n.accVerifyCodeLabel, style: FigmaTextStyles.formLabel),
            const SizedBox(width: 16),
            Expanded(
              child: TextField(
                controller: controller,
                textAlign: TextAlign.right,
                keyboardType: TextInputType.number,
                cursorColor: const Color(0xFFEB5F1B),
                style: FigmaTextStyles.formValue,
                decoration: InputDecoration(
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
                  hintText: l10n.accVerifyCodeHint,
                  hintStyle: const TextStyle(
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
              // label 左对齐、按内容宽度（这些标题都是短标签）。**必须用纯 Text**：
              // Expanded 会把 label 强撑占满剩余的一大块、把 value 挤窄到稍长就 `...`；
              // Flexible 又会与 value 的 Expanded 平分空间（label 短时 value 只占一半、
              // 右边留白）。纯 Text 只占内容宽，剩余才全部留给 value。
              Text(
                label,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
                // 信息行标题保持 w600（小程序设备详情 `.info-label`），不随表单标签加粗到 w700。
                style: FigmaTextStyles.formLabel.copyWith(
                  fontWeight: FontWeight.w600,
                  color: danger
                      ? const Color(0xFFEB5F1B)
                      : const Color(0xFF2A2B2B),
                ),
              ),
              const SizedBox(width: 12),
              // value 右对齐、占据 label 之外的**全部**剩余空间：中间空间够大就多显示，
              // 真的超出剩余宽度才 `...`。value 为空（如「修改密码」纯入口行）时是空占位，
              // 把右侧箭头推到最右，与上面各行的箭头对齐。
              Expanded(
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
        // 撑满父容器（页面自带边距）：写死 327 在 ≤320dp 宽屏/分屏会横向溢出。
        width: double.infinity,
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
