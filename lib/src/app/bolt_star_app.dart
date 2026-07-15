import 'package:flutter/material.dart';

import '../device/ble_controller.dart';
import '../features/account/presentation/auth_page.dart';
import '../features/shell/presentation/shell_page.dart';
import '../routes/app_routes.dart';
import '../shared/l10n/app_l10n.dart';
import '../state.dart';
import 'app_theme.dart';

/// 应用根组件。
///
/// 这里集中创建全局业务状态、挂载主题、配置首页壳层和命名路由。
/// 具体页面不要再各自创建 `PhotoFrameState`，统一从这里向下传递。
class BoltStarApp extends StatefulWidget {
  const BoltStarApp({super.key});

  @override
  State<BoltStarApp> createState() => _BoltStarAppState();
}

class _BoltStarAppState extends State<BoltStarApp> with WidgetsBindingObserver {
  final PhotoFrameState _state = PhotoFrameState.seeded();
  int _currentIndex = 0;

  /// 全局 Navigator：登录态失效时需要在没有 BuildContext 的情况下把栈弹回根路由。
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

  /// 上一帧的登录态，用来识别「已登录 → 未登录」这一跳变。
  late bool _wasLoggedIn = _state.isLoggedIn;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _state.addListener(_handleAuthChanged);
    // 恢复上次选择的语言（持久化在本地）。异步读取，读到后 switchLanguage 会 notify 触发整树重译。
    LanguagePreference.load().then((language) {
      if (language != null && mounted) {
        _state.switchLanguage(language);
      }
    });
  }

  @override
  void dispose() {
    _state.removeListener(_handleAuthChanged);
    WidgetsBinding.instance.removeObserver(this);
    _state.dispose();
    super.dispose();
  }

  /// 掉登录态时把导航栈弹回根路由，让强制登录门控真正生效。
  ///
  /// 只换根路由是不够的：业务页大多是 push 在根路由**之上**的（设置、图库、设备详情、投屏…）。
  /// 接口返回 401/406 时（见 `PhotoFrameState._handleSessionExpired`）如果用户正停在这些页面上，
  /// 根路由虽然已经变成登录页，但它被压在栈底看不见——用户会卡在一个登录态已被清空的业务页上，
  /// 之后每个接口都报错。这里统一 popUntil 回根，显式登出与会话失效两条路径就都收敛了。
  void _handleAuthChanged() {
    final loggedIn = _state.isLoggedIn;
    if (_wasLoggedIn && !loggedIn) {
      _currentIndex = 0; // 复位 Tab，下次登录从首页进
      // 不在监听回调里同步操作 Navigator（此刻可能正在 build/notify 中），推迟到帧末。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _navigatorKey.currentState?.popUntil((route) => route.isFirst);
      });
    }
    _wasLoggedIn = loggedIn;
  }

  // 回前台做一次「连接体检」（对齐小程序 app.onShow → deviceBle.reconcileConnections）：
  // 系统在后台挂起蓝牙可能已断开却没补发断开回调，内存会话会假报「已连接」。
  // 这里对账真实连接、清掉死会话，再把各设备的「已连接」显示刷新如实。
  // 不主动重连——连接保持「按需手动」（用户点「连接」按钮时才连）。冷启动/无连接时零开销。
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      return;
    }
    BleController.instance
        .reconcileConnections()
        .then((_) => _state.reconcileConnectionFlags())
        .catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _state,
      builder: (context, _) {
        return MaterialApp(
          navigatorKey: _navigatorKey,
          debugShowCheckedModeBanner: false,
          title: 'BoltStar',
          theme: buildAppTheme(),
          // 强制登录：未登录时根页面就是登录页，登录成功前进不到任何业务页面。
          // 这是 App 与小程序的**有意差异**——小程序有游客模式（未登录也能逛首页），
          // App 不做游客态。登录态变化会经由外层 AnimatedBuilder 重建，自动在
          // 登录页 / 主壳层之间切换，所以登录成功、退出登录都**不需要**手动导航。
          //
          // 注意：登出/注销时只能 `popUntil(isFirst)` 回到根，不要用
          // `pushNamedAndRemoveUntil(auth, (route) => false)` —— 那会把根路由一起清掉，
          // 栈里只剩一个 /auth，登录成功后根节点即便换成主壳层也已不在栈中，用户会卡在登录页。
          home: _state.isLoggedIn
              ? AppShell(
                  state: _state,
                  currentIndex: _currentIndex,
                  onIndexChanged: (index) {
                    setState(() {
                      _currentIndex = index;
                    });
                  },
                )
              : AuthPage(state: _state),
          // 全局路由观察者：让图库/投屏记录等页在被覆盖页 pop 回来时重入刷新。
          navigatorObservers: [appRouteObserver],
          // 命名路由仍复用同一个 `_state`，避免页面之间出现两份业务数据。
          onGenerateRoute: (settings) =>
              AppRoutes.onGenerateRoute(settings: settings, state: _state),
          // 语言作用域置于 Navigator 之上：切换语言时所有路由（含 push 出来的业务页）随之重译。
          builder: (context, child) => AppLocalizationsScope(
            language: _state.language,
            child: child ?? const SizedBox.shrink(),
          ),
        );
      },
    );
  }
}
