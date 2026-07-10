import 'package:flutter/material.dart';

import '../../../state.dart';
import '../../home/presentation/home_page.dart';
import '../../mine/presentation/mine_page.dart';

/// 应用主框架壳层：在「首页 / 我的」两个 tab 之间切换（对齐小程序 app.json 的两个 tabBar）。
///
/// 首页与我的各自渲染自定义底部 tab 栏（`_HomeTabBar` / `_MineTabBar`，样式与小程序一致），
/// 通过 [onIndexChanged] 回调切换当前 tab；壳层本身不再额外绘制一层 NavigationBar。
class AppShell extends StatelessWidget {
  const AppShell({
    super.key,
    required this.state,
    required this.currentIndex,
    required this.onIndexChanged,
  });

  final PhotoFrameState state;
  final int currentIndex;
  final ValueChanged<int> onIndexChanged;

  @override
  Widget build(BuildContext context) {
    if (currentIndex == 1) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: MinePage(state: state, onOpenHome: () => onIndexChanged(0)),
      );
    }
    return Scaffold(
      backgroundColor: Colors.white,
      body: HomePage(state: state, onOpenMine: () => onIndexChanged(1)),
    );
  }
}
