import 'package:flutter/material.dart';

import '../device/ble_controller.dart';
import '../features/shell/presentation/shell_page.dart';
import '../routes/app_routes.dart';
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _state.dispose();
    super.dispose();
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
          debugShowCheckedModeBanner: false,
          title: 'BoltStar',
          theme: buildAppTheme(),
          home: AppShell(
            state: _state,
            currentIndex: _currentIndex,
            onIndexChanged: (index) {
              setState(() {
                _currentIndex = index;
              });
            },
          ),
          // 命名路由仍复用同一个 `_state`，避免页面之间出现两份业务数据。
          onGenerateRoute: (settings) =>
              AppRoutes.onGenerateRoute(settings: settings, state: _state),
        );
      },
    );
  }
}
