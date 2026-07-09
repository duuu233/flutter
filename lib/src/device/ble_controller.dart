import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../native_device_api.dart';
import 'ble/device_ble.dart';
import 'ble/frame_protocol.dart';
import 'ble/image_codec.dart';
import 'ble/ota_ble.dart';
import 'serial_match.dart';

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

  /// 当前会话连接时从广播解析到的 4 字节 Device_ID（无广播数据则为空串）。
  /// 与固件 0x01 读到的 6 字节 Device_ID 一起构成会话登记的序列号，
  /// 供跨页面/改名/重拉列表后按序列号交叉认领这条活动会话（对齐小程序
  /// device-ble 会话登记 + active-device.findConnectedDeviceId）。
  String broadcastDeviceId = '';

  /// 当前会话连接时从广播解析到的屏幕类型码（0=未知）。与序列号一起用于「跨型号串台」防护：
  /// 交叉匹配设备记录与活动会话时，型号(尺寸)对不上直接一票否决。
  int broadcastScreenType = 0;

  bool uploading = false;
  double uploadPercent = 0;
  String uploadStatus = '';

  bool get connected => _client.connected;

  /// 当前会话登记的序列号（广播 4 字节 + 固件 6 字节，可能只有其一）。
  List<String> get sessionSerials => [
        if (broadcastDeviceId.isNotEmpty) broadcastDeviceId,
        if ((info?.deviceId ?? '').isNotEmpty) info!.deviceId,
      ];

  /// 当前活动会话的屏幕类型码：优先固件 0x01 读到的，其次连接时广播里的（都没有则 0=未知）。
  int get sessionScreenCode =>
      info != null ? info!.screenType : broadcastScreenType;

  /// 这台后端记录的序列号是否指向当前活动会话（容错交叉匹配：
  /// 广播 4 字节 vs 后端 6 字节互为子串也算同一台）。
  /// [screenCode]：设备记录的屏幕类型码（FrameScreenType.code）。传入后先按型号一票否决，
  /// 防「序列号 4/6 字节偶合」把不同型号设备误认成当前会话（跨型号串台）。
  bool sessionMatchesSerial(String serial, {int screenCode = 0}) {
    if (!connected || serial.isEmpty) {
      return false;
    }
    if (!sameScreenCode(screenCode, sessionScreenCode)) {
      return false;
    }
    return sessionSerials.any((s) => serialsMatch(s, serial));
  }

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

  /// 解析扫描结果广播里的厂商数据（Screen_Type + 4 字节 Device_ID + 电量）。
  /// flutter_blue_plus 把厂商数据按 Company_ID 拆成 map，这里还原成
  /// [CompanyID(2 小端), ...payload] 的原始字节序喂给协议层（小程序侧拿到的就是这个布局）。
  static FrameAdvertising? advertisingOf(ScanResult result) {
    for (final entry in result.advertisementData.manufacturerData.entries) {
      final parsed = FrameProtocol.parseAdvertising([
        entry.key & 0xFF,
        (entry.key >> 8) & 0xFF,
        ...entry.value,
      ]);
      if (parsed != null) {
        return parsed;
      }
    }
    return null;
  }

  /// 把后端已绑定设备(只有序列号/名称)和扫描结果匹配，返回该设备的 [ScanResult]。
  /// 移植小程序 active-device.matchScannedDevice + list/detail 兜底规则：
  /// 序列号用 serialsMatch 容错比对（广播 4 字节 vs 后端 6 字节互为子串也算同一台）；
  /// 连接已绑定设备不按名称匹配——设备名可随意改，广播名始终是产品名（EF6-370 等），
  /// 按名匹配在改名后必然「搜不到设备/连接不上」，且同型号广播名相同可能连错台。
  /// 名称兜底仅限没有序列号的老记录。
  static ScanResult? matchScannedDevice(
    List<ScanResult> found, {
    required String serial,
    String name = '',
    int screenCode = 0,
  }) {
    if (serial.trim().isNotEmpty) {
      for (final result in found) {
        final ad = advertisingOf(result);
        if (ad == null) {
          continue;
        }
        // 型号(尺寸)对不上直接跳过，防扫描重连时把不同型号设备误配上（跨型号串台）。
        if (!sameScreenCode(screenCode, ad.screenType)) {
          continue;
        }
        if (serialsMatch(ad.deviceId, serial)) {
          return result;
        }
      }
      return null;
    }
    final target = name.trim();
    if (target.isEmpty) {
      return null;
    }
    for (final result in found) {
      if (displayName(result).trim() == target) {
        return result;
      }
    }
    return null;
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
    // 会话登记广播 4 字节 Device_ID：连接后广播就停了，此刻不记就再也拿不到
    broadcastDeviceId = advertisingOf(result)?.deviceId ?? '';
    broadcastScreenType = advertisingOf(result)?.screenType ?? 0;
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
    broadcastDeviceId = '';
    broadcastScreenType = 0;
    uploading = false;
    uploadPercent = 0;
    uploadStatus = '';
    notifyListeners();
  }

  /// 连接一台已绑定设备（移植小程序 active-device.ensureDeviceConnected 语义）。
  /// ① 已有活动会话且序列号交叉匹配 → 直接复用（切页/改名/重拉列表后不再重扫，
  ///    否则设备被自己这条会话占线不广播，重扫必然搜不到）；
  /// ② 否则扫描 → 只按序列号容错匹配（见 [matchScannedDevice]）→ 连接并读设备信息。
  /// 成功返回 null，失败返回错误文案。
  Future<String?> connectBoundDevice({
    required String serial,
    String name = '',
    int screenCode = 0,
  }) async {
    if (sessionMatchesSerial(serial, screenCode: screenCode)) {
      return null;
    }
    if (!await ensurePermission()) {
      return '蓝牙不可用：请开启蓝牙并授予“附近的设备”权限';
    }
    // 单连接模型：正连着别的设备时先断开，避免底层双连接互相干扰。
    if (connected) {
      await disconnect();
    }
    final found = await scan(timeout: const Duration(seconds: 6));
    final target = matchScannedDevice(
      found,
      serial: serial,
      name: name,
      screenCode: screenCode,
    );
    if (target == null) {
      return '未搜索到该设备，请确认设备已开机并在附近';
    }
    return connect(target);
  }

  /// 回前台「连接体检」（移植小程序 device-ble.reconcileConnections）：
  /// 系统在后台挂起蓝牙时，断开事件可能不补发，内存会话会假报「已连接」——
  /// 下次操作复用死会话导致写失败/超时。这里用系统「已连接设备」列表对账，
  /// 已断的清掉，使 connected 恢复如实；不主动重连（连接保持「按需手动」）。
  /// 返回 true 表示清理掉了一条死会话。查询异常时保守不动，留待下次操作真实校验。
  Future<bool> reconcileConnections() async {
    final dev = _client.device;
    if (dev == null || !_client.connected) {
      return false; // 没有会话，零开销
    }
    try {
      final alive = FlutterBluePlus.connectedDevices
          .any((d) => d.remoteId == dev.remoteId);
      if (alive) {
        return false;
      }
      await disconnect();
      return true;
    } catch (_) {
      return false;
    }
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

  bool otaInProgress = false;

  /// 设备固件 OTA(DFU) 升级。复用图传已建立的连接（OTA 走独立的 FF10 服务）。
  ///
  /// [dryRun]=true 时不连蓝牙，纯本地校验编码/分包（无硬件或无固件时用）。
  /// 真实升级要求当前已连接设备（[connected]），否则抛 [OtaException]。
  Future<OtaResult> upgradeFirmware(
    OtaFirmwarePackage pkg, {
    void Function(OtaProgress)? onProgress,
    bool Function()? shouldAbort,
    void Function(String dir, String hex)? onMonitor,
    bool dryRun = false,
    int pace = 20,
  }) async {
    if (dryRun) {
      return FrameOtaClient.dryRunUpgrade(
        pkg,
        onProgress: onProgress,
        shouldAbort: shouldAbort,
      );
    }

    final dev = _client.device;
    if (dev == null || !_client.connected) {
      throw OtaException('设备未连接，请先在详情页连接设备后再升级');
    }

    final ota = FrameOtaClient(dev)..onMonitor = onMonitor;
    otaInProgress = true;
    notifyListeners();
    try {
      return await ota.upgradeFirmware(
        pkg,
        onProgress: onProgress,
        shouldAbort: shouldAbort,
        pace: pace,
      );
    } finally {
      // 只取消 OTA 自身的 FF11 通知订阅；物理连接由 _client 持有（升级后设备多半已重启断开）。
      await ota.disconnect();
      otaInProgress = false;
      notifyListeners();
    }
  }
}
