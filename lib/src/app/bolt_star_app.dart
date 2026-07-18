import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../device/ble_connection_lease.dart';
import '../device/ble_controller.dart';
import '../features/account/presentation/auth_page.dart';
import '../native_device_api.dart';
import '../features/shell/presentation/shell_page.dart';
import '../features/shell/presentation/splash_page.dart';
import '../routes/app_routes.dart';
import '../shared/l10n/app_l10n.dart';
import '../shared/widgets/app_toast.dart';
import '../shared/widgets/app_widgets.dart' show AppLoadingDialog;
import '../shared/widgets/force_update_dialog.dart';
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
  final BleController _ble = BleController.instance;
  int _currentIndex = 0;

  /// 冷启动闪屏：先展示一小段时间的启动页（LOGO + 背景图），再切到业务首页。
  bool _showSplash = true;
  static const Duration _splashDuration = Duration(milliseconds: 1800);

  /// 全局 Navigator：登录态失效时需要在没有 BuildContext 的情况下把栈弹回根路由。
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

  /// 上一帧的登录态，用来识别「已登录 → 未登录」这一跳变。
  late bool _wasLoggedIn = _state.isLoggedIn;

  /// 本次登录会话是否已做过强制升级检查（登出时复位，下次登录重新查一次）。
  bool _forceUpdateChecked = false;

  /// 上一帧的语言：MaterialApp 本体已收窄为只随 setState 重建（见 build 注释），
  /// 语言变化需要显式 setState 才能更新 MaterialApp.locale（系统组件文案跟随切换）。
  late AppLanguage _lastLanguage = _state.language;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _state.addListener(_handleAuthChanged);
    _ble.addListener(_handleBleStateChanged);
    // 冷启动闪屏：到时且登录态恢复完成后再切走——闪屏期间并行恢复持久化的
    // 登录 token（进程被后台回收后重启的场景），保证闪屏结束那一刻「登录页 or
    // 主壳层」的判定已经尘埃落定，不会先闪一下登录页再跳首页。
    // restoreSession 内部全程吞错（读不到按未登录），不会卡住闪屏。
    Future.wait<void>([
      Future<void>.delayed(_splashDuration),
      _state.restoreSession(),
    ]).whenComplete(() {
      if (mounted) {
        setState(() => _showSplash = false);
        // 闪屏结束后检查上次是否异常退出：有崩溃日志则弹窗展示（可复制），
        // 用于定位「应用因自身原因导致崩溃」这类进程级崩溃（见 CrashLogger）。
        unawaited(_maybeShowCrashReport());
        // 冷启动恢复登录态时，登录跳变发生在闪屏期间（那时不弹窗），到这里补做。
        unawaited(_maybeCheckForceUpdate());
      }
    });
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
    _ble.removeListener(_handleBleStateChanged);
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_ble.disconnect());
    _state.dispose();
    super.dispose();
  }

  void _handleBleStateChanged() {
    _state.reconcileConnectionFlags();
  }

  /// 掉登录态时把导航栈弹回根路由，让强制登录门控真正生效。
  ///
  /// 只换根路由是不够的：业务页大多是 push 在根路由**之上**的（设置、图库、设备详情、投屏…）。
  /// 接口返回 401/406 时（见 `PhotoFrameState._handleSessionExpired`）如果用户正停在这些页面上，
  /// 根路由虽然已经变成登录页，但它被压在栈底看不见——用户会卡在一个登录态已被清空的业务页上，
  /// 之后每个接口都报错。这里统一 popUntil 回根，显式登出与会话失效两条路径就都收敛了。
  void _handleAuthChanged() {
    final loggedIn = _state.isLoggedIn;
    if (!_wasLoggedIn && loggedIn) {
      // 登录成功（邮箱/微信，或冷启动恢复登录态）：查一次强制升级。
      unawaited(_maybeCheckForceUpdate());
    }
    if (_wasLoggedIn && !loggedIn) {
      _forceUpdateChecked = false; // 登出：下次登录重新检查
      _currentIndex = 0; // 复位 Tab，下次登录从首页进
      // 兜底收掉可能在展示的全局 loading：会话过期时若有页面正 show 着蒙层等待
      // 在途请求，popUntil 卸载该页后蒙层会留在 root 栈上（canPop:false，App 假死）。
      // 各调用点的 try/finally 是第一道防线，这里是登出路径的统一兜底（幂等）。
      AppLoadingDialog.hideIfAny();
      // 不在监听回调里同步操作 Navigator（此刻可能正在 build/notify 中），推迟到帧末。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _navigatorKey.currentState?.popUntil((route) => route.isFirst);
      });
    }
    _wasLoggedIn = loggedIn;
    // 语言切换（低频）：重建 MaterialApp 让 locale/系统组件文案跟随。
    if (_lastLanguage != _state.language) {
      _lastLanguage = _state.language;
      if (mounted) {
        setState(() {});
      }
    }
  }

  /// 强制升级门禁：进入已登录状态后查一次 `getLastVersion`，`compulsory=1`
  /// 且确有新版本（`isUpdate=1`）时弹出**关不掉**的升级弹窗。
  ///
  /// 非强制升级（compulsory=2/3/4）这里不打扰用户——按产品要求，由用户自己去
  /// 「设置 → 更新BoltStar」手动点按钮更新。
  ///
  /// 三条「宁可放行也不误挡」的兜底：
  /// - 检查失败（断网/后端异常）静默跳过：网络问题不该把用户锁在门外；
  /// - 下载地址为空时不弹：弹窗关不掉而按钮又打不开商店 = 用户彻底卡死；
  /// - 闪屏期间不弹，等切到主壳层再补做（此时不置 checked 标记，稍后会重来）。
  Future<void> _maybeCheckForceUpdate() async {
    if (_forceUpdateChecked || _showSplash || !_state.isLoggedIn) {
      return;
    }
    _forceUpdateChecked = true; // 置前：避免登录跳变与闪屏结束两条路径并发重复弹
    final AppVersionInfo info;
    try {
      info = await _state.checkAppVersion();
    } catch (error) {
      debugPrint('[ForceUpdate] 版本检查失败，本次放行：$error');
      return;
    }
    if (!mounted || !_state.isLoggedIn || !info.isCompulsory) {
      return;
    }
    if (info.downloadUrl.trim().isEmpty) {
      debugPrint('[ForceUpdate] 强制升级但后端没给下载地址，本次放行');
      return;
    }
    final context = _navigatorKey.currentContext;
    if (context == null) {
      return;
    }
    await ForceUpdateDialog.show(
      context,
      latestVersion: info.latestVersion,
      downloadUrl: info.downloadUrl,
      description: info.description,
    );
  }

  /// AppLanguage → Flutter Locale（Material 内建组件文案的语言）。
  Locale get _locale => switch (_state.language) {
    AppLanguage.zh => const Locale('zh'),
    AppLanguage.zhHant => const Locale.fromSubtags(
      languageCode: 'zh',
      scriptCode: 'Hant',
    ),
    AppLanguage.en => const Locale('en'),
    AppLanguage.ja => const Locale('ja'),
  };

  // 回前台做一次「连接体检」（对齐小程序 app.onShow → deviceBle.reconcileConnections）：
  // 系统在后台挂起蓝牙可能已断开却没补发断开回调，内存会话会假报「已连接」。
  // 这里对账真实连接、清掉死会话，再把各设备的「已连接」显示刷新如实。
  // 不主动重连——连接保持「按需手动」（用户点「连接」按钮时才连）。冷启动/无连接时零开销。
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        unawaited(_resumeBleSession());
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        unawaited(_enterBackgroundLeasePhase());
      case AppLifecycleState.detached:
        unawaited(_ble.disconnect());
      case AppLifecycleState.inactive:
        // Transient interruptions (permission sheets, app switcher, native
        // picker/cropper transitions) must not immediately release BLE.
        break;
    }
  }

  /// paused 分不清「切出 App」和「按电源键息屏（App 仍在栈顶）」，
  /// 由原生查屏幕亮灭判定：亮屏=切出（BLE 宽限 15 分钟）、灭屏=息屏（30 分钟）。
  /// hidden 与 paused 会连续触发，setPhase 幂等，重复调用无副作用。
  Future<void> _enterBackgroundLeasePhase() async {
    final interactive = await NativeDeviceApi.isScreenInteractive();
    // 查询是异步的：若期间用户已经切回前台（resumed 先落地），这个迟到的结果
    // 不能再把相位改回后台，否则前台会错误地挂在 15/30 分钟的宽限档上。
    if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
      return;
    }
    await _ble.setLifecyclePhase(
      interactive ? BleLeasePhase.background : BleLeasePhase.screenOff,
    );
  }

  Future<void> _resumeBleSession() async {
    try {
      await _ble.setLifecyclePhase(BleLeasePhase.foreground);
      await _ble.reconcileConnections();
      _state.reconcileConnectionFlags();
    } catch (_) {}
  }

  /// 上次异常退出的崩溃日志弹窗：读原生 CrashLogger 落盘的现场，展示 + 一键复制。
  /// 「清除并关闭」后不再弹；日志留在弹窗里未清除时下次启动会再次提示。
  Future<void> _maybeShowCrashReport() async {
    final log = await NativeDeviceApi.getLastCrashLog();
    if (log == null || log.trim().isEmpty || !mounted) {
      return;
    }
    // 等 MaterialApp/Navigator 就绪后再弹（闪屏刚切走的同帧 Navigator 可能还没挂上）。
    await WidgetsBinding.instance.endOfFrame;
    final context = _navigatorKey.currentState?.overlay?.context;
    if (context == null || !mounted) {
      return;
    }
    final l10n = AppL10n.of(context);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.crashReportTitle),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.crashReportHint, style: const TextStyle(fontSize: 12)),
              const SizedBox(height: 10),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 300),
                child: SingleChildScrollView(
                  child: SelectableText(
                    log,
                    style: const TextStyle(
                      fontSize: 11,
                      fontFamily: 'monospace',
                      height: 1.3,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: log));
              if (dialogContext.mounted) {
                AppToast.show(dialogContext, l10n.crashReportCopied);
              }
            },
            child: Text(l10n.crashReportCopy),
          ),
          TextButton(
            onPressed: () {
              unawaited(NativeDeviceApi.clearCrashLog());
              Navigator.of(dialogContext).pop();
            },
            child: Text(l10n.crashReportClose),
          ),
        ],
      ),
    );
  }

  /// 主题在 App 生命周期内不变：缓存一份实例。之前写在 build 里的
  /// `buildAppTheme()` 会在每次 state notify（全局 42 处）时重跑
  /// `ColorScheme.fromSeed` 的调色板推导并让 MaterialApp 全量重建，纯属浪费。
  final ThemeData _theme = buildAppTheme();

  @override
  Widget build(BuildContext context) {
    // 重建收窄：MaterialApp 本体只随 setState（闪屏结束/切 tab）重建；
    // state 的高频 notify 只驱动两处局部 AnimatedBuilder——
    //   ① home: 可见 tab 子树（HomePage/MinePage 自身不监听 state，数据新鲜度
    //      依赖这里的重建，不能收得更窄）；
    //   ② builder: 语言作用域（InheritedWidget，child 实例不变时语言不变则零开销）。
    return MaterialApp(
      navigatorKey: _navigatorKey,
      debugShowCheckedModeBanner: false,
      title: 'BoltStar',
      theme: _theme,
      // Material 内建组件文案（文本选择菜单/返回键无障碍标签等）跟随 App 语言，
      // 否则中文/日文界面下长按菜单永远是英文 Copy/Paste。
      locale: _locale,
      supportedLocales: const [
        Locale('zh'),
        Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
        Locale('en'),
        Locale('ja'),
      ],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      // 强制登录：未登录时根页面就是登录页，登录成功前进不到任何业务页面。
      // 这是 App 与小程序的**有意差异**——小程序有游客模式（未登录也能逛首页），
      // App 不做游客态。登录态变化会经由 home 的 AnimatedBuilder 重建，自动在
      // 登录页 / 主壳层之间切换，所以登录成功、退出登录都**不需要**手动导航。
      //
      // 注意：登出/注销时只能 `popUntil(isFirst)` 回到根，不要用
      // `pushNamedAndRemoveUntil(auth, (route) => false)` —— 那会把根路由一起清掉，
      // 栈里只剩一个 /auth，登录成功后根节点即便换成主壳层也已不在栈中，用户会卡在登录页。
      home: AnimatedBuilder(
        animation: _state,
        builder: (context, _) => AnimatedSwitcher(
          duration: const Duration(milliseconds: 350),
          child: _showSplash
              ? const SplashPage()
              : _state.isLoggedIn
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
        ),
      ),
      // 全局路由观察者：让图库/投屏记录等页在被覆盖页 pop 回来时重入刷新。
      navigatorObservers: [appRouteObserver],
      // 命名路由仍复用同一个 `_state`，避免页面之间出现两份业务数据。
      onGenerateRoute: (settings) =>
          AppRoutes.onGenerateRoute(settings: settings, state: _state),
      // 语言作用域置于 Navigator 之上：切换语言时所有路由（含 push 出来的业务页）随之重译。
      // child（Navigator）实例稳定，这层 AnimatedBuilder 每次 notify 只重建
      // AppLocalizationsScope 一个 InheritedWidget；语言没变时不通知任何依赖者。
      // withClampedTextScaling：全 App 大量 Figma 定宽定高排版，系统字号 >1.3x
      // 会挤爆固定容器，钳制到 1.3x 作为止血（长期应把固定高改 minHeight）。
      builder: (context, child) => MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.3,
        // 全局「点空白处收起键盘」：置于 Navigator 之上，覆盖所有页面（含对话框/弹层）。
        // 手势竞技场里可交互组件（按钮/输入框/列表项）总是赢家，只有无人认领的
        // 空白点击才会落到这层 onTap —— 不会拦截或延迟任何现有交互。
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
          child: AnimatedBuilder(
            animation: _state,
            builder: (context, _) => AppLocalizationsScope(
              language: _state.language,
              child: child ?? const SizedBox.shrink(),
            ),
          ),
        ),
      ),
    );
  }
}
