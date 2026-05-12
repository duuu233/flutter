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
    'com.flutter.duu233/device_api',
  );

  static Future<DevicePermissionStatus> getStatus() async {
    final result = await _channel.invokeMapMethod<String, dynamic>('getStatus');
    return DevicePermissionStatus.fromMap(result);
  }

  static Future<DevicePermissionStatus> requestBluetoothPermissions() async {
    final result = await _channel.invokeMapMethod<String, dynamic>(
      'requestBluetoothPermissions',
    );
    return DevicePermissionStatus.fromMap(result);
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

  static Future<void> openBluetoothSettings() async {
    await _channel.invokeMethod<void>('openBluetoothSettings');
  }

  static Future<void> openAppSettings() async {
    await _channel.invokeMethod<void>('openAppSettings');
  }
}
