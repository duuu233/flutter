import 'package:flutter/services.dart';

class DevicePermissionStatus {
  const DevicePermissionStatus({
    required this.bluetoothAvailable,
    required this.bluetoothEnabled,
    required this.bluetoothPermissionGranted,
    required this.locationPermissionGranted,
    required this.photoPermissionGranted,
    required this.cameraPermissionGranted,
  });

  final bool bluetoothAvailable;
  final bool bluetoothEnabled;
  final bool bluetoothPermissionGranted;
  final bool locationPermissionGranted;
  final bool photoPermissionGranted;
  final bool cameraPermissionGranted;

  bool get bluetoothReady =>
      bluetoothAvailable && bluetoothEnabled && bluetoothPermissionGranted;

  factory DevicePermissionStatus.fromMap(Map<dynamic, dynamic>? value) {
    final map = value ?? const <dynamic, dynamic>{};
    return DevicePermissionStatus(
      bluetoothAvailable: map['bluetoothAvailable'] == true,
      bluetoothEnabled: map['bluetoothEnabled'] == true,
      bluetoothPermissionGranted: map['bluetoothPermissionGranted'] == true,
      locationPermissionGranted: map['locationPermissionGranted'] == true,
      photoPermissionGranted: map['photoPermissionGranted'] == true,
      cameraPermissionGranted: map['cameraPermissionGranted'] == true,
    );
  }
}

class GallerySelection {
  const GallerySelection({
    required this.uri,
    required this.title,
    required this.width,
    required this.height,
  });

  final String uri;
  final String title;
  final double width;
  final double height;

  factory GallerySelection.fromMap(Map<dynamic, dynamic> value) {
    return GallerySelection(
      uri: (value['uri'] ?? '').toString(),
      title: (value['title'] ?? '相册图片').toString(),
      width: _numberToDouble(value['width'], 3024),
      height: _numberToDouble(value['height'], 4032),
    );
  }

  static double _numberToDouble(Object? value, double fallback) {
    if (value is num && value > 0) {
      return value.toDouble();
    }
    return fallback;
  }
}

class NativeDeviceApi {
  NativeDeviceApi._();

  static const MethodChannel _channel = MethodChannel(
    'com.boltfox.boltstar/device_api',
  );

  static Future<DevicePermissionStatus> getStatus() async {
    final result = await _channel.invokeMapMethod<String, dynamic>('getStatus');
    return DevicePermissionStatus.fromMap(result);
  }

  static Future<DevicePermissionStatus> requestBluetoothPermissions() async {
    // 通道异常（方法未实现的平台 / PlatformException）不能冒泡：
    // ensurePermission 等调用方没有兜底 try/catch，会直接崩掉连接流程。
    // 失败按「全不可用」返回，调用方走既有的「蓝牙不可用」提示分支。
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'requestBluetoothPermissions',
      );
      return DevicePermissionStatus.fromMap(result);
    } catch (_) {
      return DevicePermissionStatus.fromMap(null);
    }
  }

  static Future<DevicePermissionStatus> requestLocationPermission() async {
    final result = await _channel.invokeMapMethod<String, dynamic>(
      'requestLocationPermission',
    );
    return DevicePermissionStatus.fromMap(result);
  }

  static Future<DevicePermissionStatus> requestPhotoPermission() async {
    final result = await _channel.invokeMapMethod<String, dynamic>(
      'requestPhotoPermission',
    );
    return DevicePermissionStatus.fromMap(result);
  }

  static Future<DevicePermissionStatus> requestCameraPermission() async {
    final result = await _channel.invokeMapMethod<String, dynamic>(
      'requestCameraPermission',
    );
    return DevicePermissionStatus.fromMap(result);
  }

  static Future<GallerySelection?> openGallery() async {
    final result = await _channel.invokeMapMethod<String, dynamic>(
      'openGallery',
    );
    if (result == null || result.isEmpty) {
      return null;
    }
    return GallerySelection.fromMap(result);
  }

  /// 把相册图片(content:// uri)解码并中心裁剪到设备分辨率，返回 RGBA 像素
  /// (长度 = width×height×4)。失败返回 null。解码/缩放在原生后台线程完成。
  static Future<Uint8List?> decodeImageRgba({
    required String uri,
    required int width,
    required int height,
  }) async {
    return _channel.invokeMethod<Uint8List>('decodeImageRgba', {
      'uri': uri,
      'width': width,
      'height': height,
    });
  }

  /// 屏幕是否处于亮屏可交互状态。用于在 App 进入 paused 时区分
  /// 「切出 App」（亮屏，BLE 宽限 15 分钟）与「息屏未切出」（灭屏，宽限 30 分钟）。
  /// 通道不可用（iOS/异常）时按亮屏处理——宁可用更短的宽限，不给更长的。
  static Future<bool> isScreenInteractive() async {
    try {
      final result = await _channel.invokeMethod<bool>('isScreenInteractive');
      return result ?? true;
    } catch (_) {
      return true;
    }
  }

  /// 启动 BLE 连接保活前台服务（Android）。连接建立时调用，挂常驻通知把进程
  /// 优先级提到前台服务档，防止切出后进程被 ROM 秒杀连带断开 BLE。
  /// iOS 无此机制，通道未实现时静默跳过。
  static Future<void> startConnectionKeepAliveService({
    required String title,
    required String text,
  }) async {
    try {
      await _channel.invokeMethod<void>('startConnectionService', {
        'title': title,
        'text': text,
      });
    } catch (_) {}
  }

  /// 停止 BLE 连接保活前台服务：连接断开（含租约到期主动断开）时调用，
  /// 让进程回到可回收状态。
  static Future<void> stopConnectionKeepAliveService() async {
    try {
      await _channel.invokeMethod<void>('stopConnectionService');
    } catch (_) {}
  }

  /// 打开系统蓝牙设置。绑定引导页的点按入口，通道异常时静默跳过（不崩）。
  static Future<void> openBluetoothSettings() async {
    try {
      await _channel.invokeMethod<void>('openBluetoothSettings');
    } catch (_) {}
  }

  /// 打开本 App 的系统设置页。同上，通道异常时静默跳过。
  static Future<void> openAppSettings() async {
    try {
      await _channel.invokeMethod<void>('openAppSettings');
    } catch (_) {}
  }
}
