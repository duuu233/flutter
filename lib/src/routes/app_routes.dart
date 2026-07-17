import 'package:flutter/material.dart';

import '../features/account/presentation/bind_email_incomplete_page.dart';
import '../features/account/presentation/forgot_password.dart';
import '../features/account/presentation/modify_email_page.dart';
import '../features/account/presentation/modify_password.dart';
import '../features/account/presentation/profile_page.dart';
import '../features/account/presentation/register_page.dart';
import '../features/cast/presentation/cast_failed_page.dart';
import '../features/cast/presentation/cast_management_figma_page.dart';
import '../features/cast/presentation/cast_success_page.dart';
import '../features/cast/presentation/casting_progress_page.dart';
import '../features/cast/presentation/photo_preview_adjust_image_page.dart';
import '../features/cast/presentation/photo_preview_saved_page.dart';
import '../features/devices/presentation/bind_device_flow.dart';
import '../features/devices/presentation/bind_device_found.dart';
import '../features/devices/presentation/bind_device_not_found.dart';
import '../features/devices/presentation/bind_device_scan_help.dart';
import '../features/devices/presentation/ble_debug_page.dart';
import '../features/devices/presentation/carousel_settings_page.dart';
import '../features/devices/presentation/delete_device_flow.dart';
import '../features/devices/presentation/device_clear_confirm_page.dart';
import '../features/devices/presentation/device_details_page.dart';
import '../features/devices/presentation/devices_page.dart';
import '../features/gallery/presentation/gallery_page.dart';
import '../features/guide/presentation/guide_page.dart';
import '../features/settings/presentation/language_settings_page.dart';
import '../features/settings/presentation/privacy_policy_page.dart';
import '../features/settings/presentation/settings_page.dart';
import '../features/settings/presentation/update_boltstar_page.dart';
import '../features/devices/presentation/ota_upgrade_page.dart';
import '../features/settings/presentation/user_agreement_page.dart';
import '../shared/l10n/app_l10n.dart';
import '../shared/widgets/app_toast.dart';
import '../state.dart';

/// 全局路由观察者：供页面实现 [RouteAware] 感知「被覆盖的页 pop 回来」(didPopNext)，
/// 从而在重入时回后端刷新（对齐小程序 onShow 每次重入都重拉）。在 MaterialApp.navigatorObservers 注册。
final RouteObserver<PageRoute<dynamic>> appRouteObserver =
    RouteObserver<PageRoute<dynamic>>();

/// 统一维护 App 内部命名路由。
///
/// 新增页面时只需要在这里补充 path 常量和 switch 分支，页面继续接收根组件传入的
/// `PhotoFrameState`，避免每个页面各自初始化演示数据。
class AppRoutes {
  const AppRoutes._();

  static const profile = '/profile';
  static const guide = '/guide';
  static const settings = '/settings';
  static const bleDebug = '/ble-debug';
  static const figmaForgotPassword = '/figma/forgot-password';
  static const figmaModifyPassword = '/figma/modify-password';
  static const figmaRegister = '/figma/register';
  static const figmaGallery = '/figma/gallery';
  static const figmaCastManagement = '/figma/cast/management';
  static const figmaBindDeviceSearching = '/figma/bind-device/searching';
  static const figmaBindDeviceFound = '/figma/bind-device/found';
  static const figmaBindDeviceNotFound = '/figma/bind-device/not-found';
  static const figmaBindDeviceScanHelp = '/figma/bind-device/scan-help';
  static const figmaPhotoPreviewAdjustImage = '/figma/photo-preview/adjust';
  static const figmaPhotoPreviewSaved = '/figma/photo-preview/saved';
  static const figmaCastingProgress = '/figma/cast/progress';
  static const figmaCastSuccess = '/figma/cast/success';
  static const figmaCastFailed = '/figma/cast/failed';
  static const figmaBindEmailIncomplete =
      '/figma/profile/bind-email/incomplete';
  static const figmaModifyEmail = '/figma/profile/modify-email';
  static const figmaMyDevices = '/figma/devices/my-devices';
  static const figmaDeviceDetails = '/figma/devices/detail';
  static const figmaDeviceOta = '/figma/devices/ota';
  static const figmaDeviceClearConfirm = '/figma/devices/clear-confirm';
  static const figmaCarouselSettings = '/figma/devices/carousel-settings';
  static const figmaLanguageSettings = '/figma/settings/language';
  static const figmaPrivacyPolicy = '/figma/settings/privacy-policy';
  static const figmaUserAgreement = '/figma/settings/user-agreement';
  static const figmaUpdateBoltStar = '/figma/settings/update';
  static const figmaUpdateBoltStarAvailable =
      '/figma/settings/update/available';
  static const figmaUpdateBoltStarProgress = '/figma/settings/update/progress';

  static Route<dynamic> onGenerateRoute({
    required RouteSettings settings,
    required PhotoFrameState state,
  }) {
    late final WidgetBuilder builder;

    // 路由表只负责页面分发，不在这里处理业务判断；登录态、权限等逻辑放回页面或状态层。
    switch (settings.name) {
      case AppRoutes.profile:
        builder = (_) => ProfilePage(state: state);
        break;
      case AppRoutes.guide:
        builder = (_) => GuidePage(state: state);
        break;
      case AppRoutes.settings:
        builder = (_) => SettingsPage(state: state);
        break;
      case AppRoutes.bleDebug:
        // 硬件调试台仅 debug 构建可达：它能对设备发任意指令（含删除类）且未接 i18n。
        // release 下唯一入口 BindDebugEntryCard 已渲染为空，此处兜底为可返回的空页
        //（而不是 return null——无 onUnknownRoute 时那会直接抛「未知路由」异常）。
        builder = kDebugMode
            ? (_) => const BleDebugPage()
            : (_) => const Scaffold(body: SizedBox.shrink());
        break;
      case AppRoutes.figmaForgotPassword:
        builder = (_) => ForgotPassword(state: state);
        break;
      case AppRoutes.figmaModifyPassword:
        builder = (_) => ModifyPassword(state: state);
        break;
      case AppRoutes.figmaRegister:
        builder = (context) => RegisterPage(
          state: state,
          onRegistered: () => Navigator.maybePop(context),
          onBackToLogin: () => Navigator.maybePop(context),
        );
        break;
      case AppRoutes.figmaGallery:
        builder = (_) => GalleryPage(state: state);
        break;
      case AppRoutes.figmaCastManagement:
        builder = (_) => CastManagementFigmaPage(state: state);
        break;
      case AppRoutes.figmaBindDeviceSearching:
        builder = (_) => BindDeviceFlowPage(state: state);
        break;
      case AppRoutes.figmaBindDeviceFound:
        builder = (_) => const BindDeviceFound();
        break;
      case AppRoutes.figmaBindDeviceNotFound:
        builder = (_) => const BindDeviceNotFound();
        break;
      case AppRoutes.figmaBindDeviceScanHelp:
        builder = (_) => const BindDeviceScanHelp();
        break;
      case AppRoutes.figmaPhotoPreviewAdjustImage:
        builder = (_) => const PhotoPreviewAdjustImagePage();
        break;
      case AppRoutes.figmaPhotoPreviewSaved:
        builder = (_) => const PhotoPreviewSavedPage();
        break;
      case AppRoutes.figmaCastingProgress:
        builder = (_) => const CastingProgressPage();
        break;
      case AppRoutes.figmaCastSuccess:
        builder = (_) => const CastSuccessPage();
        break;
      case AppRoutes.figmaCastFailed:
        builder = (_) => const CastFailedPage();
        break;
      case AppRoutes.figmaBindEmailIncomplete:
        builder = (_) => BindEmailIncompletePage(state: state);
        break;
      case AppRoutes.figmaModifyEmail:
        builder = (_) => ModifyEmailPage(state: state);
        break;
      case AppRoutes.figmaMyDevices:
        builder = (_) => DevicesPage(state: state);
        break;
      case AppRoutes.figmaDeviceDetails:
        builder = (context) => DeviceDetailsPage(
          state: state,
          onCarouselSettings: () {
            // 对齐小程序 detail.js goSlideshow：入口时未连接直接拦截；若进入后链路掉线，
            // 设置页提交时仍会按 ensureConnectedForAction 自动重连。
            if (!state.selectedDevice.connected) {
              AppToast.show(context, AppL10n.of(context).devConnectFirst);
              return;
            }
            Navigator.of(
              context,
            ).pushNamed<void>(AppRoutes.figmaCarouselSettings);
          },
          onClearDevice: () {
            Navigator.of(
              context,
            ).pushNamed<void>(AppRoutes.figmaDeviceClearConfirm);
          },
          // 删除设备完整流程抽在 delete_device_flow.dart（与 startOtaFlow 同模式），
          // 路由表只做页面分发，不再内嵌业务编排。
          onDeleteDevice: () => startDeleteDeviceFlow(context, state),
          onOtaUpgrade: () {
            // 对齐小程序 goOtaUpgrade：未连接拦截/自动连 + 二次查版本 + 确认弹窗 + 确认后自动开始。
            startOtaFlow(context, state);
          },
        );
        break;
      case AppRoutes.figmaDeviceOta:
        builder = (_) => OtaUpgradePage(state: state);
        break;
      case AppRoutes.figmaDeviceClearConfirm:
        builder = (_) => DeviceClearConfirmPage(state: state);
        break;
      case AppRoutes.figmaCarouselSettings:
        builder = (_) => CarouselSettingsPage(state: state);
        break;
      case AppRoutes.figmaLanguageSettings:
        builder = (_) => LanguageSettingsPage(state: state);
        break;
      case AppRoutes.figmaPrivacyPolicy:
        builder = (_) => const PrivacyPolicyPage();
        break;
      case AppRoutes.figmaUserAgreement:
        builder = (_) => const UserAgreementPage();
        break;
      case AppRoutes.figmaUpdateBoltStar:
        builder = (_) => const UpdateBoltStarPage();
        break;
      case AppRoutes.figmaUpdateBoltStarAvailable:
        builder = (_) => const UpdateBoltStarPage(
          stage: BoltStarUpdateStage.updateAvailable,
        );
        break;
      case AppRoutes.figmaUpdateBoltStarProgress:
        builder = (_) =>
            const UpdateBoltStarPage(stage: BoltStarUpdateStage.downloading);
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
