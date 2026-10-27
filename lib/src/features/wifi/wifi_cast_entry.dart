import 'package:flutter/material.dart';

import '../../routes/app_routes.dart';
import '../../shared/l10n/app_l10n.dart';
import '../../shared/widgets/app_toast.dart';
import '../../state.dart';
import '../cast/cast_photo_picker.dart';
import '../cast/presentation/cast_preview_page.dart';
import 'wifi_l10n.dart';
import 'wifi_status.dart';

/// WiFi 版「投屏」入口（我的设备卡片 / WiFi 设备详情共用，同小程序 list.startWifiProjection /
/// wifi-detail.startProjection）：不连蓝牙，离线先拦；在线 / 状态未知照常弹「拍照 / 相册」
/// （未知时让接口裁决，离线会返回 4041）；选图后进同一个预览页构图，预览页认出 WiFi 版、导出后去
/// WiFi 投屏结果页。不改当前选中设备：首页等蓝牙链路仍按原选中设备走。
Future<void> startWifiCast(BuildContext context, PhotoFrameState state, DeviceItem device) async {
  final l10n = AppL10n.of(context);
  if (WifiStatusStore.instance.of(device.id).status == WifiOnlineStatus.offline) {
    AppToast.warn(context, l10n.wifiOfflineTip);
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
