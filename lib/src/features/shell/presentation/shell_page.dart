import 'package:flutter/material.dart';

import '../../../shared/shared.dart';
import '../../../state.dart';
import '../../home/presentation/home_page.dart';
import '../../mine/presentation/mine_page.dart';
import '../../demo/presentation/demo_page.dart';

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
    if (currentIndex == 0) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: HomePage(state: state, onOpenMine: () => onIndexChanged(1)),
      );
    }
    if (currentIndex == 1) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: MinePage(state: state, onOpenHome: () => onIndexChanged(0)),
      );
    }

    return Scaffold(
      extendBody: false,
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: Stack(
        children: [
          const AtmosphereBackground(),
          SafeArea(
            bottom: false,
            child: IndexedStack(
              index: currentIndex - 2,
              children: [DemoPage(state: state)],
            ),
          ),
        ],
      ),
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(
            top: BorderSide(color: Colors.black.withValues(alpha: 0.08)),
          ),
          boxShadow: [
            BoxShadow(
              blurRadius: 20,
              offset: const Offset(0, -8),
              color: Colors.black.withValues(alpha: 0.06),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: NavigationBar(
            selectedIndex: currentIndex,
            height: 72,
            backgroundColor: Colors.white,
            surfaceTintColor: Colors.white,
            indicatorColor: Theme.of(
              context,
            ).colorScheme.primary.withValues(alpha: 0.12),
            onDestinationSelected: onIndexChanged,
            destinations: [
              NavigationDestination(
                icon: const Icon(Icons.cast_connected_outlined),
                selectedIcon: const Icon(Icons.cast_connected),
                label: state.tr(zh: '首页', en: 'Home', ja: 'ホーム'),
              ),
              NavigationDestination(
                icon: const Icon(Icons.person_outline),
                selectedIcon: const Icon(Icons.person),
                label: state.tr(zh: '我的', en: 'Mine', ja: 'マイ'),
              ),
              NavigationDestination(
                icon: const Icon(Icons.person_outline),
                selectedIcon: const Icon(Icons.person),
                label: state.tr(zh: 'demo', en: 'demo-en', ja: 'demo-日语'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
