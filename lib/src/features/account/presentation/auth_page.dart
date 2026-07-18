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

class _AuthPageState extends State<AuthPage> {
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
      if (!feedback.success) {
        // 同邮箱登录：成功不弹提示，失败才提示。
        _showFeedback(feedback.message);
      }
    } on WeChatAuthorizationException catch (error) {
      if (mounted) {
        // 按错误类别取当前语言文案；exception.message 是中文详情，只进日志。
        debugPrint('[WeChatAuth] ${error.code}: ${error.message}');
        final l10n = AppL10n.of(context);
        _showFeedback(switch (error.code) {
          WeChatAuthErrorCode.notInstalled => l10n.accWechatNotInstalled,
          WeChatAuthErrorCode.canceled => l10n.accWechatCanceled,
          WeChatAuthErrorCode.denied => l10n.accWechatDenied,
          WeChatAuthErrorCode.versionUnsupported =>
            l10n.accWechatVersionUnsupported,
          WeChatAuthErrorCode.timeout => l10n.accWechatTimeout,
          WeChatAuthErrorCode.config ||
          WeChatAuthErrorCode.generic => l10n.accWechatAuthFailed,
        });
      }
    } catch (_) {
      if (mounted) {
        _showFeedback(AppL10n.of(context).accWechatAuthFailed);
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
