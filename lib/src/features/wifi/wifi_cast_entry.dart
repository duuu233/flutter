import 'package:flutter/material.dart';

import '../../routes/app_routes.dart';
import '../../shared/l10n/app_l10n.dart';
import '../../shared/widgets/app_toast.dart';
import '../../state.dart';
import '../cast/cast_photo_picker.dart';
import '../cast/presentation/cast_preview_page.dart';
import 'presentation/wifi_slideshow_page.dart';
import 'wifi_l10n.dart';
import 'wifi_status.dart';

/// WiFi 版「投屏」入口（我的设备卡片 / WiFi 设备详情共用，同小程序 list.startWifiProjection /
/// wifi-detail.startProjection）：不连蓝牙，离线 / 休眠 / 关机先拦；在线 / 状态未知照常弹「拍照 / 相册」
/// （未知时让接口裁决，离线会返回 4041）；选图后进同一个预览页构图，预览页认出 WiFi 版、导出后去
/// WiFi 投屏结果页。不改当前选中设备：首页等蓝牙链路仍按原选中设备走。
Future<void> startWifiCast(BuildContext context, PhotoFrameState state, DeviceItem device) async {
  final l10n = AppL10n.of(context);
  final blocked = wifiBlockedTip(l10n, WifiStatusStore.instance.of(device.id).status);
  if (blocked.isNotEmpty) {
    AppToast.warn(context, blocked);
    return;
  }
  final source = await CastPhotoPicker.chooseSource(context);
  if (source == null || !context.mounted) {
    return;
  }
  List<String> imagePaths;
  try {
    imagePaths = source == ImageSourceType.camera
        ? await CastPhotoPicker.takePhoto()
        : await CastPhotoPicker.pickFromAlbum();
  } catch (_) {
    if (context.mounted) {
      AppToast.warn(context, l10n.devicesReadPhotoFailed);
    }
    return;
  }
  if (!context.mounted || imagePaths.isEmpty) {
    return;
  }
  await Navigator.of(context).push<void>(
    AppPageRoute(
      builder: (_) => CastPreviewPage(state: state, device: device, imagePaths: imagePaths),
    ),
  );
}

/// WiFi 版「轮播设置」入口（我的设备卡片 / WiFi 设备详情共用）：查询只要权限、离线也能看，不拦离线；
/// 本地模式（2026-10-29）按钮可点，只提示「当前设备状态：本地模式，请恢复设备网络再试」。保存时轮播页再判断状态。
void openWifiSlideshow(BuildContext context, PhotoFrameState state, DeviceItem device) {
  if (WifiStatusStore.instance.of(device.id).status == WifiOnlineStatus.local) {
    AppToast.warn(context, AppL10n.of(context).wifiLocalTip);
    return;
  }
  Navigator.of(context).push<void>(
    AppPageRoute(builder: (_) => WifiSlideshowPage(state: state, deviceId: device.id)),
  );
}
