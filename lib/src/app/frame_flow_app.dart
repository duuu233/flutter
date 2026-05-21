import 'package:flutter/material.dart';

import '../features/shell/presentation/shell_page.dart';
import '../routes/app_routes.dart';
import '../state.dart';
import 'app_theme.dart';

/// 应用根组件。
///
/// 这里集中创建全局业务状态、挂载主题、配置首页壳层和命名路由。
/// 具体页面不要再各自创建 `PhotoFrameState`，统一从这里向下传递。
class FrameFlowApp extends StatefulWidget {
  const FrameFlowApp({super.key});

  @override
  State<FrameFlowApp> createState() => _FrameFlowAppState();
}

class _FrameFlowAppState extends State<FrameFlowApp> {
  final PhotoFrameState _state = PhotoFrameState.seeded();
  int _currentIndex = 0;

  @override
  void dispose() {
    _state.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _state,
      builder: (context, _) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: _state.tr(zh: '鐩告鎶曞睆', en: 'Frame Cast', ja: '銉曘儸銉笺儬鎶曞奖'),
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
