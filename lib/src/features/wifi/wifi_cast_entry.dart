import 'package:flutter/material.dart';

import '../../routes/app_routes.dart';
import '../../shared/l10n/app_l10n.dart';
import '../../shared/widgets/app_toast.dart';
import '../../state.dart';
import '../cast/cast_photo_picker.dart';
import '../cast/presentation/cast_preview_page.dart';
import 'presentation/wifi_slideshow_page.dart';
import 'wifi_status.dart';

/// WiFi 版「投屏」入口（我的设备卡片 / WiFi 设备详情共用，同小程序 list.startWifiProjection /
/// wifi-detail.startProjection）：不连蓝牙；2026-11-14 起点击要在线（[requireWifiOnline]：离线 / 休眠 / 关机 / 本地模式
/// 直接提示，状态未知现查一次，在线才弹「拍照 / 相册」）；选图后进同一个预览页构图，预览页认出 WiFi 版、导出后去
/// WiFi 投屏结果页。不改当前选中设备：首页等蓝牙链路仍按原选中设备走。
Future<void> startWifiCast(BuildContext context, PhotoFrameState state, DeviceItem device) async {
  if (!await requireWifiOnline(context, device) || !context.mounted) {
    return;
  }
  final l10n = AppL10n.of(context);
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

/// WiFi 版「轮播设置」入口（我的设备卡片 / WiFi 设备详情共用）：2026-11-14 起点击要在线（原「离线也能看」撤掉），
/// 离线 / 休眠 / 关机 / 本地模式提示不进，状态未知现查一次（[requireWifiOnline]）。保存时轮播页仍会再判断状态。
/// 返回的 Future 在轮播页关闭后完成（调用方据此重查轮播中标记）。
Future<void> openWifiSlideshow(BuildContext context, PhotoFrameState state, DeviceItem device) async {
  if (!await requireWifiOnline(context, device) || !context.mounted) {
    return;
  }
  await Navigator.of(context).push<void>(
    AppPageRoute(builder: (_) => WifiSlideshowPage(state: state, deviceId: device.id)),
  );
}
