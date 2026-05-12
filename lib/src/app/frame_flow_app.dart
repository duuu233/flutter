import 'package:flutter/material.dart';

import '../features/shell/presentation/shell_page.dart';
import '../routes/app_routes.dart';
import '../state.dart';
import 'app_theme.dart';

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
          title: _state.tr(zh: '相框投屏', en: 'Frame Cast', ja: 'フレーム投影'),
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
          onGenerateRoute: (settings) =>
              AppRoutes.onGenerateRoute(settings: settings, state: _state),
        );
      },
    );
  }
}



  // | 行 | 作用 |
  // |---|---|
  // | 1 | 引入 Flutter Material 组件库，提供 StatefulWidget、State、BuildContext、MaterialApp、AnimatedBuilder 等。 |
  // | 2 | 空行，用于分隔第三方包 import 和项目内部 import。 |
  // | 3 | 引入 AppShell，也就是首页的外壳页面，里面包含首页/我的两个底部导航页。 |
  // | 4 | 引入 AppRoutes，用于处理命名路由跳转，比如 /profile、/album、/settings。 |
  // | 5 | 引入 PhotoFrameState，这是项目里的全局业务状态，包含用户、设备、相册、权限、语言、投屏记录等数据。 |
  // | 6 | 引入 buildAppTheme()，用于构建整个应用统一的 Material 主题。 |
  // | 7 | 空行，分隔 import 和类声明。 |
  // | 8 | 声明 FrameFlowApp，它是一个 StatefulWidget。这里不用 StatelessWidget，因为它内部需要保存 _currentIndex 和 _state。 |
  // | 9 | 构造函数，const 允许在 runApp(const FrameFlowApp()) 中创建常量组件；super.key 把 key 传给父类。 |
  // | 10 | 空行。 |
  // | 11 | @override 表示重写父类方法。 |
  // | 12 | 创建这个组件对应的状态对象 _FrameFlowAppState。 |
  // | 13 | 结束 FrameFlowApp 类。 |
  // | 14 | 空行。 |
  // | 15 | 声明私有状态类。下划线开头表示只在当前 Dart 文件内可见。 |
  // | 16 | 创建应用级状态 _state，使用 PhotoFrameState.seeded() 初始化一份演示数据。全项目很多页面都通过它读写业务数据。 |
  // | 17 | 保存底部导航当前选中的 tab，下标 0 通常是首页，1 是我的。 |
  // | 18 | 空行。 |
  // | 19 | @override，重写生命周期方法。 |
  // | 20 | dispose() 在组件销毁时调用。 |
  // | 21 | 释放 _state。因为 PhotoFrameState 继承自 ChangeNotifier，用完要 dispose，避免监听器泄漏。 |
  // | 22 | 调用父类的 dispose()，完成 Flutter 框架自己的清理。 |
  // | 23 | 结束 dispose()。 |
  // | 24 | 空行。 |
  // | 25 | @override，重写构建 UI 的方法。 |
  // | 26 | build(BuildContext context) 返回这个组件的界面树。 |
  // | 27 | 返回 AnimatedBuilder，它会监听某个 Listenable，这里监听的是 _state。 |
  // | 28 | 指定监听对象为 _state。当 _state.notifyListeners() 被调用时，builder 会重新执行。 |
  // | 29 | builder 是重建 UI 的函数；第二个参数 _ 是未使用的 child。 |
  // | 30 | 返回 MaterialApp，这是 Material 风格 Flutter 应用的顶层容器。 |
  // | 31 | 关闭右上角 debug 标识。 |
  // | 32 | 设置应用标题，会根据 _state.tr(...) 当前语言返回中文、英文或日文标题。注意这里源码里的中文/日文看起来已经是乱码，可能会影响真实显示。 |
  // | 33 | 设置全局主题，来自 app_theme.dart 的 buildAppTheme()。 |
  // | 34 | 设置应用首页为 AppShell。 |
  // | 35 | 把全局业务状态 _state 传给 AppShell，再由它继续传给首页、我的等页面。 |
  // | 36 | 把当前底部导航下标传给 AppShell。 |
  // | 37 | 传入 tab 切换回调，当用户点击底部导航时执行。 |
  // | 38 | 调用 setState()，通知 Flutter 当前 widget 的本地状态变了。 |
  // | 39 | 更新 _currentIndex，使底部导航和 IndexedStack 切换到对应页面。 |
  // | 40 | 结束 setState 回调。 |
  // | 41 | 结束 onIndexChanged。 |
  // | 42 | 结束 AppShell 参数。 |
  // | 43 | 配置命名路由生成器。 |
  // | 44 | 把路由请求交给 AppRoutes.onGenerateRoute，并把同一份 _state 传给目标页面。 |
  // | 45 | 结束 MaterialApp。 |
  // | 46 | 结束 AnimatedBuilder.builder。 |
  // | 47 | 结束 AnimatedBuilder。 |
  // | 48 | 结束 build()。 |
  // | 49 | 结束 _FrameFlowAppState 类。 |

  // 它在项目中的作用

  // 这个文件是项目的“应用装配层”：main.dart 启动它，它创建唯一的 PhotoFrameState，挂载全局主题，设置首页壳层 AppShell，并统一管理命名路由。

  // 简单说：业务数据从这里创建，页面从这里进入，主题从这里生效，路由从这里分发。它不是具体业务页面，而是整个 App 的根容器和状态中枢。
