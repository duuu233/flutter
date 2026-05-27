import 'package:flutter/material.dart';

import '../features/album/presentation/album_page.dart';
import '../features/auth/presentation/auth_page.dart';
import '../features/cast/presentation/cast_management_page.dart';
import '../features/devices/presentation/devices_page.dart';
import '../features/figma_generated/figma_generated_pages.dart';
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
  static const figmaForgotPassword = '/figma/forgot-password';
  static const figmaLoginPassword = '/figma/login-password';
  static const figmaLoginPasswordError = '/figma/login-password/error';
  static const figmaModifyPassword = '/figma/modify-password';
  static const figmaRegister = '/figma/register';
  static const figmaWechatLogin = '/figma/wechat-login';
  static const figmaGallery = '/figma/gallery';
  static const figmaCastManagement = '/figma/cast/management';
  static const figmaHomeUnbound = '/figma/home/unbound';
  static const figmaHomeUnboundBindNow = '/figma/home/unbound/bind-now';
  static const figmaHomeUnboundReconnect = '/figma/home/unbound/reconnect';
  static const figmaHomeBound = '/figma/home/bound';
  static const figmaHomeBoundPicker = '/figma/home/bound/picker';
  static const figmaBindDeviceSearching = '/figma/bind-device/searching';
  static const figmaBindDeviceFound = '/figma/bind-device/found';
  static const figmaBindDeviceNotFound = '/figma/bind-device/not-found';
  static const figmaBindDeviceScanHelp = '/figma/bind-device/scan-help';
  static const figmaPhotoPreviewAdjustImage = '/figma/photo-preview/adjust';
  static const figmaPhotoPreviewSaved = '/figma/photo-preview/saved';
  static const figmaCastingProgress = '/figma/cast/progress';
  static const figmaCastSuccess = '/figma/cast/success';
  static const figmaCastFailed = '/figma/cast/failed';
  static const figmaProfileUnboundEmail = '/figma/profile/unbound-email';
  static const figmaProfileBoundEmail = '/figma/profile/bound-email';
  static const figmaBindEmailIncomplete =
      '/figma/profile/bind-email/incomplete';
  static const figmaBindEmailComplete = '/figma/profile/bind-email/complete';
  static const figmaModifyEmail = '/figma/profile/modify-email';
  static const figmaMyDevices = '/figma/devices/my-devices';
  static const figmaDeviceDetails = '/figma/devices/detail';
  static const figmaDeviceDeleteConfirm = '/figma/devices/delete-confirm';
  static const figmaDeviceClearConfirm = '/figma/devices/clear-confirm';
  static const figmaCarouselSettings = '/figma/devices/carousel-settings';
  static const figmaLanguageSettings = '/figma/settings/language';
  static const figmaPrivacyPolicy = '/figma/settings/privacy-policy';
  static const figmaUserAgreement = '/figma/settings/user-agreement';
  static const figmaUpdateBoltStar = '/figma/settings/update';
  static const figmaUpdateBoltStarAvailable = '/figma/settings/update/available';
  static const figmaUpdateBoltStarProgress = '/figma/settings/update/progress';

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
      case AppRoutes.figmaForgotPassword:
        builder = (_) => const ForgotPassword();
        break;
      case AppRoutes.figmaLoginPassword:
        builder = (_) => const LoginPasswordPage();
        break;
      case AppRoutes.figmaLoginPasswordError:
        builder = (_) => const LoginPasswordPage(initialShowErrors: true);
        break;
      case AppRoutes.figmaModifyPassword:
        builder = (_) => const ModifyPassword();
        break;
      case AppRoutes.figmaRegister:
        builder = (context) => RegisterPage(
          onRegistered: () => Navigator.maybePop(context),
          onBackToLogin: () => Navigator.maybePop(context),
        );
        break;
      case AppRoutes.figmaWechatLogin:
        builder = (_) => const WechatLoginPage();
        break;
      case AppRoutes.figmaGallery:
        builder = (_) => GalleryPage(state: state);
        break;
      case AppRoutes.figmaCastManagement:
        builder = (_) => CastManagementFigmaPage(state: state);
        break;
      case AppRoutes.figmaHomeUnbound:
        builder = (_) => const FigmaHomeUnboundDevicePage();
        break;
      case AppRoutes.figmaHomeUnboundBindNow:
        builder = (_) => const FigmaHomeUnboundDevicePage(
          sheet: FigmaHomeUnboundSheet.bindNow,
        );
        break;
      case AppRoutes.figmaHomeUnboundReconnect:
        builder = (_) => const FigmaHomeUnboundDevicePage(
          sheet: FigmaHomeUnboundSheet.reconnect,
        );
        break;
      case AppRoutes.figmaHomeBound:
        builder = (_) => const FigmaHomeBoundDevicePage();
        break;
      case AppRoutes.figmaHomeBoundPicker:
        builder = (_) => const FigmaHomeBoundDevicePage(showCastSheet: true);
        break;
      case AppRoutes.figmaBindDeviceSearching:
        builder = (_) => const BindDeviceSearching();
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
      case AppRoutes.figmaProfileUnboundEmail:
        builder = (context) => ProfileUnboundEmailPage(
          onBindEmail: () {
            Navigator.of(
              context,
            ).pushNamed<void>(AppRoutes.figmaBindEmailIncomplete);
          },
        );
        break;
      case AppRoutes.figmaProfileBoundEmail:
        builder = (context) => ProfileBoundEmailPage(
          onModifyEmail: () {
            Navigator.of(context).pushNamed<void>(AppRoutes.figmaModifyEmail);
          },
        );
        break;
      case AppRoutes.figmaBindEmailIncomplete:
        builder = (_) => const BindEmailIncompletePage();
        break;
      case AppRoutes.figmaBindEmailComplete:
        builder = (_) => const BindEmailCompletePage();
        break;
      case AppRoutes.figmaModifyEmail:
        builder = (_) => const ModifyEmailPage();
        break;
      case AppRoutes.figmaMyDevices:
        builder = (context) => MyDevicesPage(
          onAddDevice: () {
            Navigator.of(
              context,
            ).pushNamed<void>(AppRoutes.figmaBindDeviceSearching);
          },
          onOpenDetail: (_) {
            Navigator.of(context).pushNamed<void>(AppRoutes.figmaDeviceDetails);
          },
          onCarouselSettings: (_) {
            Navigator.of(
              context,
            ).pushNamed<void>(AppRoutes.figmaCarouselSettings);
          },
        );
        break;
      case AppRoutes.figmaDeviceDetails:
        builder = (context) => DeviceDetailsPage(
          onCarouselSettings: () {
            Navigator.of(
              context,
            ).pushNamed<void>(AppRoutes.figmaCarouselSettings);
          },
          onClearDevice: () {
            Navigator.of(
              context,
            ).pushNamed<void>(AppRoutes.figmaDeviceClearConfirm);
          },
          onDeleteDevice: () {
            Navigator.of(
              context,
            ).pushNamed<void>(AppRoutes.figmaDeviceDeleteConfirm);
          },
        );
        break;
      case AppRoutes.figmaDeviceDeleteConfirm:
        builder = (_) => const DeviceDeleteConfirmPage();
        break;
      case AppRoutes.figmaDeviceClearConfirm:
        builder = (_) => const DeviceClearConfirmPage();
        break;
      case AppRoutes.figmaCarouselSettings:
        builder = (_) => const CarouselSettingsPage();
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
        builder = (_) => const UpdateBoltStarPage(
          stage: BoltStarUpdateStage.downloading,
        );
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
