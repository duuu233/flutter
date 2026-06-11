import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../native_device_api.dart';
import 'ble/device_ble.dart';
import 'ble/frame_protocol.dart';
import 'ble/image_codec.dart';

/// 全局 BLE 会话控制器（单例）。
///
/// 持有唯一的 [FrameBleClient]，让「已连接设备」跨页面存活：绑定页连接后，
/// 首页 / 投屏页直接复用同一连接做图传，无需重连。
///
/// 调用序列严格对齐已验证的调试页 `ble_debug_page.dart`：
/// 权限 → 扫描 → 连接 → 读设备信息 → 图传。UI 页面只读这里的状态并触发动作，
/// 不直接持有 [FrameBleClient]。
class BleController extends ChangeNotifier {
  BleController._();

  static final BleController instance = BleController._();

  final FrameBleClient _client = FrameBleClient();

  FrameBleClient get client => _client;

  bool scanning = false;
  bool connecting = false;
  String deviceName = '';
  FrameDeviceInfo? info;
  List<ScanResult> results = const [];

  bool uploading = false;
  double uploadPercent = 0;
  String uploadStatus = '';

  bool get connected => _client.connected;

  /// 扫描结果的展示名：platformName → 广播名 → MAC。
  static String displayName(ScanResult result) {
    if (result.device.platformName.isNotEmpty) {
      return result.device.platformName;
    }
    if (result.advertisementData.advName.isNotEmpty) {
      return result.advertisementData.advName;
    }
    return result.device.remoteId.str;
  }

  /// 请求蓝牙权限并确认已开启。返回 false 表示不可用（调用方提示后中止）。
  Future<bool> ensurePermission() async {
    final status = await NativeDeviceApi.requestBluetoothPermissions();
    return status.bluetoothPermissionGranted && status.bluetoothEnabled;
  }

  /// 扫描附近设备（去重 + 按信号强度排序）。
  Future<List<ScanResult>> scan({
    Duration timeout = const Duration(seconds: 8),
  }) async {
    if (scanning) {
      return results;
    }
    scanning = true;
    notifyListeners();
    try {
      results = await FrameBleClient.scan(timeout: timeout);
      return results;
    } finally {
      scanning = false;
      notifyListeners();
    }
  }

  /// 连接设备并读取设备信息。成功返回 null，失败返回错误文案。
  Future<String?> connect(ScanResult result) async {
    connecting = true;
    deviceName = displayName(result);
    notifyListeners();
    try {
      await _client.connect(result.device);
      try {
        info = await _client.readDeviceInfo();
      } catch (_) {
        // 设备信息读取失败不阻断连接，后续可重试。
        info = null;
      }
      notifyListeners();
      return null;
    } catch (error) {
      info = null;
      notifyListeners();
      return error.toString();
    } finally {
      connecting = false;
      notifyListeners();
    }
  }

  /// 重新读取设备信息（图传前后刷新容量 / IMG_MASK）。
  Future<void> refreshInfo() async {
    try {
      info = await _client.readDeviceInfo();
      notifyListeners();
    } catch (_) {}
  }

  Future<void> disconnect() async {
    await _client.disconnect();
    info = null;
    deviceName = '';
    uploading = false;
    uploadPercent = 0;
    uploadStatus = '';
    notifyListeners();
  }

  /// 把已解码裁剪到设备分辨率的 RGBA 像素六色量化后上传到指定槽位。
  ///
  /// [index] 为空时自动选第一个空位；满了抛 [FrameBleException]。
  /// 成功返回设备回报的结束信息（现存张数 / 剩余空间）。
  Future<FrameImgEnd> uploadRgba(
    Uint8List rgba, {
    int? index,
    bool dither = true,
    double contrast = 1.12,
    double saturation = 1.28,
  }) async {
    final i = info;
    if (i == null || i.width == 0) {
      throw FrameBleException('设备信息未就绪，请重新连接设备');
    }
    if (rgba.length != i.width * i.height * 4) {
      throw FrameBleException('图片尺寸与设备分辨率不一致');
    }
    final target = index ?? FrameProtocol.firstFreeIndex(i.imgMask, i.capacity);
    if (target < 0) {
      throw FrameBleException('设备已存满，请先删除照片或一键清空');
    }
    final frame = FrameImageCodec.fromRgba(
      rgba,
      i.width,
      i.height,
      dither: dither,
      contrast: contrast,
      saturation: saturation,
    );
    uploading = true;
    uploadPercent = 0;
    uploadStatus = '传输中…';
    notifyListeners();
    try {
      final end = await _client.uploadImage(
        screenType: i.screenType,
        index: target,
        width: i.width,
        height: i.height,
        data: frame.data,
        onProgress: (done, total, phase, {stuckAt, retries}) {
          uploadPercent = total == 0 ? 0 : done / total;
          uploadStatus = phase == 'retry'
              ? '传输卡顿，正在重试…'
              : '传输中 $done/$total';
          notifyListeners();
        },
      );
      await _client.refreshScreen(target);
      await refreshInfo();
      uploadStatus = '图传完成';
      uploadPercent = 1;
      notifyListeners();
      return end;
    } finally {
      uploading = false;
      notifyListeners();
    }
  }
}
