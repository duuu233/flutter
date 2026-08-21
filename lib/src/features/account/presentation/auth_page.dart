import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../routes/app_routes.dart';
import '../../../shared/l10n/app_l10n.dart';
import '../../../shared/widgets/app_toast.dart';
import '../../../state.dart';
import '../data/email_history.dart';
import '../data/wechat_authorization_client.dart';
import 'auth_widgets.dart';

/// 邮箱密码 / 微信授权登录页（应用唯一登录页，路由 `/auth`）。
///
/// 退出登录 / 用户注销后进入；按 375x812 设计稿还原，背景图全屏铺满、表单等比适配。
/// 微信入口走微信开放平台「移动应用微信登录」取得 code，再由业务后端换取 userToken。
/// 背景 / 胶囊输入框 / 主按钮 / 协议行等视觉组件抽在 `auth_widgets.dart`，与注册页共用。
class AuthPage extends StatefulWidget {
  const AuthPage({
    super.key,
    required this.state,
    this.weChatAuthorizationClient,
  });

  final PhotoFrameState state;

  /// 便于替换 SDK 和在 widget 测试中注入 fake。
  final WeChatAuthorizationClient? weChatAuthorizationClient;

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage>
    with SingleTickerProviderStateMixin {
  /// 入场动效：表单整体上浮 16px 落位。
  ///
  /// 根节点（闪屏 ↔ 登录页 ↔ 主壳层）是 fade-through 切换，而闪屏和本页共用同一张
  /// 背景图 bg01，真正在换的只有前景内容——不给前景加位移的话观感就是「没有动效」。
  /// 这里给表单补一个上浮：位移是 Transform，不参与布局，不影响键盘弹起时的滚动。
  /// 本页只在「登出后」和「冷启动未登录」时挂载一次，动画不会反复播放。
  late final AnimationController _entryController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  )..forward();

  /// 前 35%（约 525ms）按兵不动：根节点 fade-through 里本页要到 ~385ms 才开始
  /// 显形（kRootTransitionDuration 的后 65% 才是进场段）。动画若从挂载即起跑，
  /// easeOutCubic 的大半位移会消耗在不可见期，等看得见时只剩尾巴两三像素——
  /// 上一版 900ms 就是这么被吃掉的。Interval 顺延到显形后起步，且比淡入晚
  /// ~140ms，形成「页面现身 → 表单落位」的小节奏。
  late final Animation<Offset> _entryOffset =
      Tween<Offset>(begin: const Offset(0, 0.02), end: Offset.zero).animate(
        CurvedAnimation(
          parent: _entryController,
          curve: const Interval(0.35, 1, curve: Curves.easeOutCubic),
        ),
      );

  late final TextEditingController _emailController;
  late final WeChatAuthorizationClient _weChatAuthorizationClient;
  final TextEditingController _passwordController = TextEditingController();

  bool _passwordVisible = false;
  bool _agreed = false;
  // 校验错误只用来把对应输入框标红（文案走吐司，见 _alert）：逐项判断，
  // 同一时刻最多标红一个；输入一变就清除。
  bool _emailError = false;
  bool _passwordError = false;
  bool _weChatSubmitting = false;

  @override
  void initState() {
    super.initState();
    _emailController = TextEditingController(
      text: widget.state.currentUser.email,
    );
    // 输入即清除对应字段的错误提示。
    _emailController.addListener(() {
      if (_emailError && mounted) {
        setState(() => _emailError = false);
      }
    });
    _passwordController.addListener(() {
      if (_passwordError && mounted) {
        setState(() => _passwordError = false);
      }
    });
    _weChatAuthorizationClient =
        widget.weChatAuthorizationClient ?? defaultWeChatAuthorizationClient;
    // 未登录邮箱时，自动填充上次输入过的邮箱（本地缓存），回访用户免于重复输入。
    if (_emailController.text.trim().isEmpty) {
      EmailHistory.latest().then((email) {
        if (mounted &&
            email.isNotEmpty &&
            _emailController.text.trim().isEmpty) {
          _emailController.text = email;
        }
      });
    }
  }

  @override
  void dispose() {
    _entryController.dispose();
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
        // 键盘弹起时压缩视口并允许滚动（配合 _AuthCanvas 的 SingleChildScrollView），
        // 否则小屏上登录按钮被键盘盖住，用户必须先收起键盘。
        resizeToAvoidBottomInset: true,
        backgroundColor: const Color(0xFFF7FAFF),
        body: Stack(
          fit: StackFit.expand,
          children: [
            const AuthBackground(),
            SafeArea(
              child: SlideTransition(
                position: _entryOffset,
                child: _AuthCanvas(
                  emailController: _emailController,
                  passwordController: _passwordController,
                  passwordVisible: _passwordVisible,
                  agreed: _agreed,
                  emailError: _emailError,
                  passwordError: _passwordError,
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
                  onWeChatLogin: _loginWithWeChat,
                  submitting: _submitting,
                  weChatSubmitting: _weChatSubmitting,
                ),
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
    // 点击登录先收起键盘：未勾选协议弹提示时键盘若还开着，
    // 用户看不全提示、还可能通过键盘继续操作。
    FocusManager.instance.primaryFocus?.unfocus();
    final l10n = AppL10n.of(context);
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    // 逐项校验：命中第一条就弹提示并返回，不再一次性把所有错误全部铺出来。
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
      _markError(email: true);
      _alert(l10n.accEmailInvalid);
      return;
    }
    if (password.trim().isEmpty) {
      _markError(password: true);
      _alert(l10n.accPasswordEmpty);
      return;
    }
    if (!_agreed) {
      _alert(l10n.accAgreementRequired);
      return;
    }
    _markError();

    setState(() {
      _submitting = true;
      // 邮箱密码登录：走主按钮 loading（primary loading = submitting && !weChatSubmitting）。
      _weChatSubmitting = false;
    });
    final feedback = await widget.state.loginWithPassword(email, password);
    if (!mounted) {
      return;
    }
    setState(() => _submitting = false);
    if (feedback.success) {
      await EmailHistory.add(email); // 记住成功登录过的邮箱，下次自动填充
    } else {
      // 只在失败时提示。登录成功不弹「登录成功，已同步个人资料」——
      // 根节点随即切到主壳层，界面变化本身就是反馈（用户要求去掉）。
      _showFeedback(feedback.message);
    }
    // 登录成功后**不需要**在这里导航：本页是强制登录门控下的根页面（见 bolt_star_app.dart），
    // `loginWithPassword` 置好登录态并 notifyListeners 后，根节点会自动把自己换成主壳层。
  }

  Future<void> _loginWithWeChat() async {
    if (_submitting) {
      return;
    }
    // 同 _login：先收起键盘再弹提示/拉起微信。
    FocusManager.instance.primaryFocus?.unfocus();
    if (!_agreed) {
      _alert(AppL10n.of(context).accAgreementRequired);
      return;
    }

    setState(() {
      _submitting = true;
      _weChatSubmitting = true;
    });
    try {
      final code = await _weChatAuthorizationClient.authorize();
      final feedback = await widget.state.loginWithWeChatCode(code);
      if (!mounted) {
        return;
      }
      if (feedback.success) {
        // 2026-08-19：微信登录**成功也提示**（Android/iOS 一致）。这与邮箱登录的
        // 「成功不弹提示」是有意的差别——微信登录中途切到微信客户端再跳回 App，
        // 回来时用户需要一句确认这趟授权走通了，光靠界面切到主壳层不够明确。
        //
        // 时序：这句只在**换到 userToken 之后**才弹，所以「授权成功但后端拒登」
        // 不会先弹一句成功再被错误顶掉。toast 走根 Overlay（AppToast rootOverlay），
        // 紧接着根节点把登录页换成主壳层也不会把它带走。
        _showFeedback(AppL10n.of(context).accWechatLoginSuccess);
      } else {
        // 同邮箱登录：失败才提示（成功侧见上面的微信特例）。
        // 调试期补一条「微信侧已拿到 code」的事实：微信授权成功、后端换 token 失败时，
        // 只看 toast 文案分不清是哪一段挂了（详见 _withDiagnostics）。
        // 其后跟着状态层给的请求现场（[ActionFeedback.diagnostics]，当前是被 406 拒掉
        // 的那次调用的方法/URL/公共参数/body），后端据此复现。
        final diagnostics = feedback.diagnostics;
        final copyable = kWeChatLoginDiagnostics && diagnostics != null;
        final detail = <String>[
          '微信 code 已取得(${code.length} 位)',
          if (diagnostics != null) diagnostics,
          // toast 最长只停 6 秒（[AppToast] 的硬上限），一屏请求现场根本抄不完，
          // 所以同一份内容再落一次剪贴板——但得让人知道可以直接粘给后端。
          if (copyable) '（以上内容已复制到剪贴板）',
        ].join('\n');
        _showFeedback(_withDiagnostics(feedback.message, detail));
        if (copyable) {
          debugPrint('[WeChatLogin] rejected\n$diagnostics');
          unawaited(
            Clipboard.setData(
              ClipboardData(text: '${feedback.message}\n$detail'),
            ),
          );
        }
      }
    } on WeChatAuthorizationException catch (error) {
      if (mounted) {
        // 按错误类别取当前语言文案；exception.message 是中文详情，调试期一并进 toast。
        debugPrint('[WeChatAuth] ${error.code}: ${error.message}');
        final l10n = AppL10n.of(context);
        final message = switch (error.code) {
          WeChatAuthErrorCode.notInstalled => l10n.accWechatNotInstalled,
          WeChatAuthErrorCode.canceled => l10n.accWechatCanceled,
          WeChatAuthErrorCode.denied => l10n.accWechatDenied,
          WeChatAuthErrorCode.versionUnsupported =>
            l10n.accWechatVersionUnsupported,
          WeChatAuthErrorCode.timeout => l10n.accWechatTimeout,
          WeChatAuthErrorCode.config ||
          WeChatAuthErrorCode.generic => l10n.accWechatAuthFailed,
        };
        _showFeedback(
          _withDiagnostics(message, '${error.code.name}: ${error.message}'),
        );
      }
    } catch (error, stack) {
      // 预期外异常（插件 MissingPluginException、类型错误等）：原来整条被吞成
      // 「微信授权失败，请稍后重试」，真机上无从判断挂在哪。日志留全量，toast 留摘要。
      debugPrint('[WeChatAuth] unexpected: $error\n$stack');
      if (mounted) {
        _showFeedback(
          _withDiagnostics(AppL10n.of(context).accWechatAuthFailed, '$error'),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
          _weChatSubmitting = false;
        });
      }
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
    AppToast.show(context, message);
  }

  /// 微信登录失败时把原始错误细节拼在提示文案后面（[kWeChatLoginDiagnostics] 为 true 时）。
  ///
  /// 排查期必须能在**真机屏幕上**看到细节：微信按开放平台登记的签名校验，
  /// 授权只有用 release 包才能走通，而 release 包 `kDebugMode` 恒 false、
  /// 也没有 `adb logcat` 之外的出口，`debugPrint` 等于没有。上线前用
  /// `--dart-define=WECHAT_LOGIN_DIAGNOSTICS=false` 关掉即可恢复纯净文案。
  String _withDiagnostics(String message, String detail) {
    final trimmed = detail.trim();
    if (!kWeChatLoginDiagnostics || trimmed.isEmpty) {
      return message;
    }
    return '$message\n[$trimmed]';
  }

  /// 校验失败的统一提示。
  ///
  /// 2026-07-19：由「标题 + 知道了 按钮」的模态确认框改为居中黑色吐司
  /// （[AppToast]，对齐小程序 toast 组件：黑色半透明底 + 白字，2~3 秒自动消失）。
  /// 表单校验失败是**瞬时反馈**，不该要求用户先点一次「知道了」才能改输入；
  /// 且同一页里成功/失败的接口反馈本来就走吐司，两套提示混用观感割裂。
  void _alert(String message) {
    AppToast.warn(context, message);
  }

  /// 只把**当前这一条**校验失败的输入框标红，其余复位。
  void _markError({bool email = false, bool password = false}) {
    if (_emailError == email && _passwordError == password) {
      return;
    }
    setState(() {
      _emailError = email;
      _passwordError = password;
    });
  }
}

class _AuthCanvas extends StatelessWidget {
  const _AuthCanvas({
    required this.emailController,
    required this.passwordController,
    required this.passwordVisible,
    required this.agreed,
    required this.emailError,
    required this.passwordError,
    required this.onPasswordVisibilityChanged,
    required this.onAgreementChanged,
    required this.onForgotPassword,
    required this.onRegister,
    required this.onUserAgreement,
    required this.onPrivacyPolicy,
    required this.onLogin,
    required this.onWeChatLogin,
    required this.submitting,
    required this.weChatSubmitting,
  });

  final TextEditingController emailController;
  final TextEditingController passwordController;
  final bool passwordVisible;
  final bool agreed;
  final bool emailError;
  final bool passwordError;
  final VoidCallback onPasswordVisibilityChanged;
  final VoidCallback onAgreementChanged;
  final VoidCallback onForgotPassword;
  final VoidCallback onRegister;
  final VoidCallback onUserAgreement;
  final VoidCallback onPrivacyPolicy;
  final VoidCallback onLogin;
  final VoidCallback onWeChatLogin;
  final bool submitting;
  final bool weChatSubmitting;

  @override
  Widget build(BuildContext context) {
    // 键盘弹起（resizeToAvoidBottomInset: true 压缩视口）时可滚动；
    // 键盘收起时 ConstrainedBox(minHeight) + IntrinsicHeight 让 Spacer 布局与原来一致。
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 26),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: IntrinsicHeight(child: _buildColumn(context)),
        ),
      ),
    );
  }

  Widget _buildColumn(BuildContext context) {
    // AutofillGroup：让系统密码管理器识别「邮箱+密码」组合并支持自动填充。
    return AutofillGroup(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Spacer(flex: 3),
          const _TitleGroup(),
          const SizedBox(height: 36),
          SizedBox(
            height: 56,
            child: AuthPillTextField(
              controller: emailController,
              hintText: AppL10n.of(context).accEmailHint,
              icon: Image.asset(
                'assets/images/email_icon.png',
                width: 24,
                height: 24,
              ),
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              showError: emailError,
              autofillHints: const [AutofillHints.email],
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 56,
            child: AuthPillTextField(
              controller: passwordController,
              hintText: AppL10n.of(context).accPasswordHint,
              icon: Image.asset(
                'assets/images/password_icon.png',
                width: 24,
                height: 24,
              ),
              keyboardType: TextInputType.visiblePassword,
              textInputAction: TextInputAction.done,
              obscureText: !passwordVisible,
              showError: passwordError,
              autofillHints: const [AutofillHints.password],
              // 不绑定 onSubmitted 触发登录：键盘「完成」只收起键盘，
              // 否则未勾选协议时按「完成」会再次弹出协议提示。
              trailing: AuthEyeButton(
                visible: passwordVisible,
                onPressed: onPasswordVisibilityChanged,
                showTooltip: AppL10n.of(context).accShowPassword,
                hideTooltip: AppL10n.of(context).accHidePassword,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onForgotPassword,
              child: Text(
                AppL10n.of(context).accForgotPasswordLink,
                style: AuthTextStyles.linkMuted,
              ),
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 56,
            child: AuthPrimaryButton(
              label: AppL10n.of(context).accLoginButton,
              onPressed: submitting ? null : onLogin,
              loading: submitting && !weChatSubmitting,
            ),
          ),
          const SizedBox(height: 24),
          _RegisterPrompt(onRegister: onRegister),
          const Spacer(flex: 4),
          Center(
            child: _WeChatLoginButton(
              onPressed: submitting ? null : onWeChatLogin,
              loading: weChatSubmitting,
            ),
          ),
          const SizedBox(height: 20),
          Center(
            child: AuthAgreementRow(
              agreed: agreed,
              onChanged: onAgreementChanged,
              onUserAgreement: onUserAgreement,
              onPrivacyPolicy: onPrivacyPolicy,
              prefixText: AppL10n.of(context).accAgreementPrefix,
              userAgreementText: AppL10n.of(context).accUserAgreementLink,
              andText: AppL10n.of(context).accAnd,
              privacyPolicyText: AppL10n.of(context).accPrivacyPolicyLink,
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _TitleGroup extends StatelessWidget {
  const _TitleGroup();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(AppL10n.of(context).accWelcome, style: AuthTextStyles.title),
            const SizedBox(width: 6),
            // 相对基线微调 4，让 logo 与「欢迎使用」文字垂直对齐。
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: BoltStarWordmark(),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          AppL10n.of(context).accLoginSubtitle,
          style: AuthTextStyles.subtitle,
        ),
      ],
    );
  }
}

/// 微信授权登录圆形入口：作为次要入口置于页面底部。
class _WeChatLoginButton extends StatelessWidget {
  const _WeChatLoginButton({required this.onPressed, required this.loading});

  final VoidCallback? onPressed;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: onPressed != null,
      label: AppL10n.of(context).accWechatLogin,
      child: SizedBox.square(
        dimension: 48,
        child: Material(
          color: onPressed == null
              ? const Color(0xFF07C160).withValues(alpha: 0.55)
              : const Color(0xFF07C160),
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed,
            customBorder: const CircleBorder(),
            child: Center(
              child: loading
                  ? const SizedBox.square(
                      dimension: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Image.asset(
                      'assets/images/login-wx-icon.png',
                      width: 30,
                      height: 30,
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) => const Icon(
                        Icons.wechat,
                        size: 30,
                        color: Colors.white,
                      ),
                    ),
            ),
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
          TextSpan(
            children: [
              TextSpan(text: AppL10n.of(context).accNoAccount),
              TextSpan(
                text: AppL10n.of(context).accGoRegister,
                style: const TextStyle(color: Color(0xFFFF5B1F)),
              ),
            ],
          ),
          style: AuthTextStyles.register,
        ),
      ),
    );
  }
}
