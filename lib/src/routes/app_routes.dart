import 'package:flutter/material.dart';

import '../features/album/presentation/album_page.dart';
import '../features/auth/presentation/auth_page.dart';
import '../features/cast/presentation/cast_management_page.dart';
import '../features/devices/presentation/devices_page.dart';
import '../features/guide/presentation/guide_page.dart';
import '../features/mine/presentation/profile_page.dart';
import '../features/settings/presentation/settings_page.dart';
import '../state.dart';

/// 统一维护 App 内部命名路由。
///
/// 新增页面时只需要在这里补充 path 常量和 switch 分支，页面继续接收根组件传入的
/// `PhotoFrameState`，避免每个页面各自初始化演示数据。
class AppRoutes {
  const AppRoutes._();

  static const auth = '/auth';
  static const profile = '/profile';
  static const album = '/album';
  static const devices = '/devices';
  static const castManagement = '/cast-management';
  static const guide = '/guide';
  static const settings = '/settings';

  static Route<dynamic> onGenerateRoute({
    required RouteSettings settings,
    required PhotoFrameState state,
  }) {
    late final WidgetBuilder builder;

    // 路由表只负责页面分发，不在这里处理业务判断；登录态、权限等逻辑放回页面或状态层。
    switch (settings.name) {
      case AppRoutes.auth:
        builder = (_) => AuthPage(state: state);
        break;
      case AppRoutes.profile:
        builder = (_) => ProfilePage(state: state);
        break;
      case AppRoutes.album:
        builder = (_) => AlbumPage(state: state);
        break;
      case AppRoutes.devices:
        builder = (_) => DevicesPage(state: state);
        break;
      case AppRoutes.castManagement:
        builder = (_) => CastManagementPage(state: state);
        break;
      case AppRoutes.guide:
        builder = (_) => GuidePage(state: state);
        break;
      case AppRoutes.settings:
        builder = (_) => SettingsPage(state: state);
        break;
      default:
        builder = (_) => _UnknownRoutePage(routeName: settings.name);
        break;
    }

    return MaterialPageRoute<dynamic>(settings: settings, builder: builder);
  }
}

class _UnknownRoutePage extends StatelessWidget {
  const _UnknownRoutePage({required this.routeName});

  final String? routeName;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Route not found')),
      body: Center(child: Text(routeName ?? 'unknown')),
    );
  }
}
