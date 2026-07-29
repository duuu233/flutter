import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../native_device_api.dart';
import '../network/boltfox_api.dart';
import '../shared/l10n/app_l10n.dart';
import '../state.dart' show AppLanguage;
import 'ble/device_ble.dart';
import 'ble/frame_protocol.dart';
import 'ble/ota_ble.dart';
import 'ble_connection_lease.dart';
import 'device_interaction_trace.dart';
import 'serial_match.dart';

/// 蓝牙信号档位（由 UI 层按当前语言渲染文字，见 [BleController.rssiToSignalLevel]）。
enum BleSignalLevel { veryStrong, strong, normal, weak, veryWeak }

/// 全局 BLE 会话控制器（单例）。
///
/// 持有唯一的 [FrameBleClient]，让「已连接设备」跨页面存活：绑定页连接后，
/// 首页 / 投屏页直接复用同一连接做图传，无需重连。
///
/// 调用序列严格对齐已验证的调试页 `ble_debug_page.dart`：
/// 权限 → 扫描 → 连接 → 读设备信息 → 图传。UI 页面只读这里的状态并触发动作，
/// 不直接持有 [FrameBleClient]。
class BleController extends ChangeNotifier {
  BleController._() {
    _connectionLease = BleConnectionLease(
      isConnected: () => connected,
      isBusy: () => _hasActiveTask,
      disconnect: disconnect,
    );
    _client.onActivity = _connectionLease.noteActivity;
    _client.onLinkStateChanged = _handleLinkStateChanged;
    _client.onTransferSessionChanged = _handleTransferSessionChanged;
  }

  static final BleController instance = BleController._();

  /// 由状态层注入的语言解析器：BLE 层没有 BuildContext，用户可见文案经此本地化。
  /// PhotoFrameState 构造时赋值；未注入时兜底简体中文。
  AppLanguage Function()? languageResolver;

  /// 用户可见文案按当前语言取（connectBySerial 的错误提示等直达 toast）。
  AppL10n get _l10n => AppL10n(languageResolver?.call() ?? AppLanguage.zh);

  final FrameBleClient _client = FrameBleClient();
  late final BleConnectionLease _connectionLease;
  bool _transferInProgress = false;

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

  bool get _hasActiveTask => connecting || _transferInProgress || otaInProgress;

  /// Applies only the outer session lease. Scan, connect, reconnect, MTU,
  /// connection interval, and protocol behavior remain owned by FrameBleClient.
  /// 相位由 App 生命周期层判定：前台 / 切出（宽限 15 分钟）/ 息屏未切出（30 分钟）。
  Future<void> setLifecyclePhase(BleLeasePhase phase) =>
      _connectionLease.setPhase(phase);

  void _handleLinkStateChanged(bool alive) {
    if (alive) {
      _connectionLease.noteActivity();
      _startKeepAlive();
      // 连接保活前台服务与连接同生命周期（连接必然发生在 App 前台，
      // 不触碰 Android 12+ 的后台启动前台服务限制）。进程优先级提到前台服务档，
      // 切出/息屏后进程才能活到租约到期（15/30 分钟），而不是被 ROM 秒杀。
      unawaited(
        NativeDeviceApi.startConnectionKeepAliveService(
          title: 'BoltStar',
          text: _l10n.bleKeepAliveNotification,
        ),
      );
      return;
    }
    _stopKeepAlive();
    // 断开（含租约到期主动断开）即撤前台服务，进程回到可回收状态。
    unawaited(NativeDeviceApi.stopConnectionKeepAliveService());
    _transferInProgress = false;
    _connectionLease.linkEnded();
    _clearConnectionState();
    notifyListeners();
  }

  // ── 空闲保活心跳 ─────────────────────────────────────────
  //
  // 相框固件对空闲链路有自己的断链超时（1~2 分钟无流量即设备侧断开），
  // 「场景策略」里的前台 10 分钟/后台宽限 3 分钟只有靠心跳把链路喂活才成立。
  // 心跳只在连接存活期间跑：链路建立启动、断开即停；租约到期断开后自然停止。
  // 图传/OTA 期间跳过（本就有持续流量，且不能往停等协议里插帧）。
  // 心跳不刷新租约（countsAsActivity=false），空闲满时长照常断开。

  Timer? _keepAliveTimer;
  static const Duration _keepAlivePeriod = Duration(seconds: 25);

  void _startKeepAlive() {
    _keepAliveTimer?.cancel();
    _keepAliveTimer = Timer.periodic(_keepAlivePeriod, (_) {
      if (!connected || _hasActiveTask) {
        return;
      }
      unawaited(_client.keepAlivePing());
    });
  }

  void _stopKeepAlive() {
    _keepAliveTimer?.cancel();
    _keepAliveTimer = null;
  }

  void _handleTransferSessionChanged(bool active) {
    _transferInProgress = active;
    uploading = active;
    if (active) {
      _connectionLease.taskStarted();
    } else {
      _connectionLease.taskFinished();
    }
    notifyListeners();
  }

  void _clearConnectionState() {
    info = null;
    deviceName = '';
    broadcastDeviceId = '';
    broadcastScreenType = 0;
    uploading = false;
    uploadPercent = 0;
    uploadStatus = '';
  }

  /// 当前会话登记的序列号（广播短 ID + 固件完整 ID，可能只有其一）。
  ///
  /// 广播短 ID 仅供扫描候选筛选；[sessionMatchesSerial] 会过滤它，只允许
  /// 0x01 完整 ID 认领后端记录。
  List<String> get sessionSerials => [
    if (broadcastDeviceId.isNotEmpty) broadcastDeviceId,
    if ((info?.deviceId ?? '').isNotEmpty) info!.deviceId,
  ];

  /// 当前活动会话的屏幕类型码：优先固件 0x01 读到的，其次连接时广播里的（都没有则 0=未知）。
  int get sessionScreenCode =>
      info != null ? info!.screenType : broadcastScreenType;

  /// 这台后端记录的序列号是否指向当前活动会话。
  /// 后端记录与会话都必须有 6 字节完整 ID 并精确相等；
  /// 不能仅凭可能重复的广播 4 字节短 ID 复用会话。
  /// [screenCode]：设备记录的屏幕类型码（FrameScreenType.code）。传入后先按型号一票否决，
  /// 防「序列号 4/6 字节偶合」把不同型号设备误认成当前会话（跨型号串台）。
  bool sessionMatchesSerial(String serial, {int screenCode = 0}) {
    if (!connected || !isCompleteDeviceSerial(serial)) {
      return false;
    }
    if (!sameScreenCode(screenCode, sessionScreenCode)) {
      return false;
    }
    return sessionSerialsMatch(sessionSerials, serial);
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

  /// 把蓝牙信号强度(RSSI，单位 dBm，越接近 0 越强)归到用户能看懂的档位，
  /// 对齐小程序 `utils/bluetooth.js rssiToSignalText` 的五档划分。
  /// 文字由 UI 层按当前语言渲染（见 bind_device_flow 的 signal 映射）；
  /// RSSI 缺省(0)或非法(≥0)时返回 null，由页面兜底成「--」。
  static BleSignalLevel? rssiToSignalLevel(int rssi) {
    if (rssi == 0 || rssi >= 0) {
      return null;
    }
    if (rssi >= -55) {
      return BleSignalLevel.veryStrong;
    }
    if (rssi >= -67) {
      return BleSignalLevel.strong;
    }
    if (rssi >= -78) {
      return BleSignalLevel.normal;
    }
    if (rssi >= -88) {
      return BleSignalLevel.weak;
    }
    return BleSignalLevel.veryWeak;
  }

  /// 扫描结果广播里解析到的屏幕尺寸文字（如 `3.7寸`/`5.89寸`）；无广播厂商数据时返回空串。
  static String screenLabelOf(ScanResult result) {
    final ad = advertisingOf(result);
    if (ad == null) {
      return '';
    }
    return FrameProtocol.screenTypes[ad.screenType]?.label ?? '';
  }

  /// 扫描结果广播里解析到的电量（0-100）；无广播厂商数据时返回 null。
  static int? batteryOf(ScanResult result) => advertisingOf(result)?.battery;

  /// 扫描结果广播里解析到的产品型号（如 `EF6-370`）；无广播厂商数据时返回空串。
  /// 供绑定时按机型匹配产品列表解析 productId（对齐小程序 `productScore` 的 model 维度）。
  static String modelOf(ScanResult result) {
    final ad = advertisingOf(result);
    if (ad == null) {
      return '';
    }
    return FrameProtocol.screenTypes[ad.screenType]?.model ?? '';
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
  /// 没有完整序列号的历史记录不再按名称兜底；需要删除记录后重新绑定。
  static ScanResult? matchScannedDevice(
    List<ScanResult> found, {
    required String serial,
    String name = '',
    int screenCode = 0,
    Set<String> excludedDeviceIds = const {},
  }) {
    if (isCompleteDeviceSerial(serial)) {
      for (final result in found) {
        if (excludedDeviceIds.contains(result.device.remoteId.str)) {
          continue;
        }
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
    return null;
  }

  /// 请求蓝牙权限并确认已开启。返回 false 表示不可用（调用方提示后中止）。
  Future<bool> ensurePermission() async {
    final status = await NativeDeviceApi.requestBluetoothPermissions();
    return status.bluetoothPermissionGranted && status.bluetoothEnabled;
  }

  /// 内置广播名兜底白名单：拉产品列表失败/为空时用它，保证 3.7 寸 EF6-370 / 5.89 寸 EF6-589
  /// 两款目标相框仍能被搜到（对齐小程序 `bluetooth.js FALLBACK_BROADCAST_IDS`）。
  static const List<String> _fallbackBroadcastIds = ['EF6-370', 'EF6-589'];

  /// 产品列表 broadcastId 白名单缓存：首次扫描拉取后整次会话复用；失败不缓存，便于下次重试
  /// （对齐小程序 `bluetooth.js cachedBroadcastIds`）。
  List<String>? _cachedBroadcastIds;

  /// 取允许的 broadcastId 白名单：优先产品列表接口返回的（带缓存）；拉不到/为空退回内置兜底。
  Future<List<String>> _loadAllowedBroadcastIds() async {
    final cached = _cachedBroadcastIds;
    if (cached != null && cached.isNotEmpty) {
      return cached;
    }
    try {
      final ids = await BoltFoxApi.getProductBroadcastIds();
      if (ids.isNotEmpty) {
        _cachedBroadcastIds = ids;
        return ids;
      }
    } catch (_) {
      // 拉产品列表失败（未登录/网络异常）：退回内置广播名，扫描照常进行。
    }
    return _fallbackBroadcastIds;
  }

  /// 扫描附近设备（去重 + 按信号强度排序）。
  ///
  /// [allowAll]=false（默认）：按产品列表 broadcastId 白名单只保留目标相框（兜底 EF6-370/EF6-589
  /// 两个尺寸），对齐小程序 `discoverDevices` 默认过滤——绑定/列表/详情/自动重连都只显示/匹配目标相框，
  /// 而不是把周围所有蓝牙设备都列出来。[allowAll]=true 放开过滤（硬件调试台排查用）。
  /// [onUpdate]：增量回调「当前已搜到的列表」，供绑定页「搜出一个显示一个」，不必等满 timeout。
  Future<List<ScanResult>> scan({
    Duration timeout = const Duration(seconds: 8),
    bool allowAll = false,
    void Function(List<ScanResult> devices)? onUpdate,
    bool Function(List<ScanResult> devices)? until,
  }) async {
    // 在任何 await 之前先换代：这不仅作废已经进入底层的旧扫描，也能作废仍卡在
    // 产品白名单接口上的旧调用。否则页面退出时底层尚未起扫，stopScan 无从可停；
    // 等接口回包后旧页面反而会在后台新开一轮扫描，重进/刷新便再次互相干扰。
    final generation = ++_scanGeneration;
    // 已有在途扫描：**接管**它——先停掉、等它收网，再起自己这一轮。
    //
    // 旧实现是 `if (scanning) return results;`，即拿上一轮的存量结果直接返回。
    // 这正是「退出搜索页再进来搜不了、点刷新也没反应」的成因：从发现页按返回键
    // 出去时没人停扫（页面此前也没有 dispose），20s 窗口还在跑，重进来的这一轮
    // 于是原地返回上一轮的旧列表——页面瞬间画出一模一样的内容、`_scanning` 立刻置
    // false，看上去就是「刷新键是死的」。而一旦上一轮因为任何原因永远结束不了，
    // 这个标记就永久为真，只能杀进程（用户反馈的正是这个）。
    // 现在：新一轮总是真的开始，且 [FrameBleClient.scan] 的收网不再依赖平台状态流。
    await _supersedeRunningScan();
    if (generation != _scanGeneration) {
      return const <ScanResult>[];
    }
    scanning = true;
    // 上一轮的扫描结果必须清空后再扫。留着的话，「刚断开→立刻重连」这种时序里
    // matchScannedDevice 会匹配到上一轮的 ScanResult，把一个已失效的
    // BluetoothDevice 句柄交给 connect()，连接必然失败——正是「断开再连要点两次」
    // 的另一半成因。
    results = const [];
    notifyListeners();
    Future<List<ScanResult>>? run;
    try {
      final allowedNames = allowAll ? null : await _loadAllowedBroadcastIds();
      if (generation != _scanGeneration) {
        return const <ScanResult>[];
      }
      run = FrameBleClient.scan(
        timeout: timeout,
        allowedNames: allowedNames,
        onUpdate: (list) {
          if (generation != _scanGeneration) {
            return;
          }
          results = list;
          notifyListeners();
          if (onUpdate != null) {
            onUpdate(list);
          }
        },
        until: until,
      );
      _runningScan = run;
      final scanned = await run;
      if (generation != _scanGeneration) {
        return const <ScanResult>[];
      }
      results = scanned;
      return results;
    } finally {
      if (run != null && identical(_runningScan, run)) {
        _runningScan = null;
      }
      // 旧轮次晚到的 finally 不能把新一轮的扫描状态关掉。
      if (generation == _scanGeneration) {
        scanning = false;
        notifyListeners();
      }
    }
  }

  /// 在途扫描的 future；[_supersedeRunningScan] 靠它等上一轮真正收网。
  Future<List<ScanResult>>? _runningScan;

  /// 扫描代次：新扫描/主动停扫都会递增，用于作废网络等待期和 BLE 等待期的旧调用。
  int _scanGeneration = 0;

  /// 停掉在途扫描并等它收完（无在途扫描时零开销）。
  ///
  /// 兜底超时是最后一道防线：万一 [FrameBleClient.scan] 因平台异常仍然挂住，
  /// 也只是这一次多等 2 秒，绝不能重演「`scanning` 永久为真、必须杀进程」。
  Future<void> _supersedeRunningScan() async {
    final running = _runningScan;
    if (running == null) {
      return;
    }
    try {
      await FrameBleClient.stopScan().timeout(const Duration(seconds: 2));
    } catch (_) {
      // 底层先同步触发 Dart 收网，再等待原生停扫；即便个别 ROM 的原生回调挂住，
      // 也不能让刷新按钮永远卡死。
    }
    try {
      await running.timeout(const Duration(seconds: 2));
    } catch (_) {
      // 上一轮自己的 finally 会归位状态；等不到也照常开新一轮。
    }
  }

  /// 立刻停止在途扫描，保留已搜到的 [results]。
  ///
  /// 在途的 [scan] 会因此提前 return（已搜到的照常返回），它自己的 finally 负责把
  /// `scanning` 归位并 notify，这里不抢着改状态。
  /// 不再用 `scanning` 做前置短路：那个标记只反映**本控制器**发起的扫描，
  /// 而停扫的意图是「让射频安静下来」，无条件下发才对（底层 stopScan 本身幂等）。
  Future<void> stopScan() async {
    final generation = ++_scanGeneration;
    final running = _runningScan;
    try {
      await FrameBleClient.stopScan().timeout(const Duration(seconds: 2));
    } catch (_) {
      // stopScan 的 Dart 收网动作已同步执行；原生层不回调时最多等到这里，不能永久锁住 UI。
    }
    if (running != null) {
      try {
        await running.timeout(const Duration(seconds: 2));
      } catch (_) {}
    }
    if (running != null && identical(_runningScan, running)) {
      _runningScan = null;
    }
    // 若停扫期间已有更新一代的新扫描启动，不能用旧 stop 的收尾覆盖它。
    if (generation == _scanGeneration) {
      scanning = false;
      notifyListeners();
    }
  }

  /// 连接设备并读取设备信息。成功返回 null，失败返回错误文案。
  Future<String?> connect(ScanResult result) async {
    // 重入护栏：并发连接（列表快速双击 / 自动重连撞上手动点连接）会让两次
    // _client.connect 交错覆盖 _device/订阅/_writeChar，且 broadcastDeviceId 与
    // 实际连上的设备错位——这正是序列号交叉认领最怕的输入。第二路直接拒绝。
    if (connecting) {
      return _l10n.bleBusyConnecting;
    }
    final trace = DeviceInteractionTrace('connect-device');
    connecting = true;
    _connectionLease.taskStarted();
    deviceName = displayName(result);
    // 会话登记广播 4 字节 Device_ID：连接后广播就停了，此刻不记就再也拿不到
    broadcastDeviceId = advertisingOf(result)?.deviceId ?? '';
    broadcastScreenType = advertisingOf(result)?.screenType ?? 0;
    notifyListeners();
    try {
      await trace.measure('gatt-connect-and-discover', () async {
        await _client.connect(result.device);
      });
      try {
        // 连接成功只同步页面需要的 0x01 核心信息。固件版本 0x03 不应挡在
        // loading 结束前；OTA 页面有独立的版本接口，详情已有后端版本兜底。
        info = await trace.measure(
          'read-core-info-0x01',
          _client.readTransferInfo,
        );
      } catch (_) {
        // 设备信息读取失败不阻断连接，后续可重试。
        info = null;
      }
      notifyListeners();
      trace.finish(success: true);
      return null;
    } catch (error) {
      info = null;
      notifyListeners();
      trace.finish(success: false);
      // 原始异常（含 android-code:133 / ANDROID_SPECIFIC_ERROR 等）只写日志，
      // 返回给 UI 的是本地化友好文案——避免把技术异常串直接弹进 toast，也让提示跟随语种。
      debugPrint('BLE connect failed: $error');
      return _l10n.bleConnectFailed;
    } finally {
      connecting = false;
      _connectionLease.taskFinished(afterTransfer: false);
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
    _stopKeepAlive();
    unawaited(NativeDeviceApi.stopConnectionKeepAliveService());
    _connectionLease.linkEnded();
    await _client.disconnect();
    _transferInProgress = false;
    _clearConnectionState();
    notifyListeners();
  }

  /// 对已建立的 GATT 会话做最终身份确认。
  ///
  /// 扫描广播只有 4 字节短 ID，同尺寸设备可能相同；必须读取 0x01 的 6 字节完整
  /// Device_ID 后再与用户点击的后端记录核对。名称是可编辑展示字段，不参与物理身份。
  Future<bool> _verifyBoundDeviceIdentity({
    required String serial,
    required int screenCode,
  }) async {
    if (!isCompleteDeviceSerial(serial)) {
      return false;
    }
    if (!sameScreenCode(screenCode, sessionScreenCode)) {
      return false;
    }
    var actual = info?.deviceId ?? '';
    if (actual.isEmpty) {
      try {
        info = await _client.readTransferInfo();
        actual = info?.deviceId ?? '';
        notifyListeners();
      } catch (error) {
        debugPrint(
          '[BLE identity] failed to read 0x01 expected=$serial error=$error',
        );
        return false;
      }
    }
    final matched = verifiedDeviceSerialMatch(serial, actual);
    if (!matched) {
      debugPrint(
        '[BLE identity] mismatch expected=${normalizeSerial(serial)} '
        'actual=${normalizeSerial(actual)} '
        'broadcast=${normalizeSerial(broadcastDeviceId)} '
        'name=$deviceName',
      );
    }
    return matched;
  }

  /// 连接一台已绑定设备（移植小程序 active-device.ensureDeviceConnected 语义）。
  /// ① 已有活动会话且完整身份匹配 → 直接复用（切页/改名/重拉列表后不再重扫，
  ///    否则设备被自己这条会话占线不广播，重扫必然搜不到）；
  /// ② 否则扫描广播只筛候选 → 建连读取 0x01 完整 ID 严格确认；
  /// ③ 身份不符则断开、排除该 BLE 候选并继续扫描，绝不把 B 会话认领给 A。
  /// 成功返回 null，失败返回错误文案。
  Future<String?> connectBoundDevice({
    required String serial,
    String name = '',
    int screenCode = 0,
  }) async {
    // 同 [connect] 的重入护栏：连接编排进行中不接受第二路。
    if (connecting) {
      return _l10n.bleBusyConnecting;
    }
    if (!isCompleteDeviceSerial(serial)) {
      return _l10n.bleIncompleteDeviceIdentity;
    }
    final trace = DeviceInteractionTrace('connect-bound-device');
    if (sessionMatchesSerial(serial, screenCode: screenCode)) {
      _connectionLease.noteActivity();
      trace.mark('reuse-active-session');
      trace.finish(success: true);
      return null;
    }
    // 现有会话可能只登记到广播短 ID（此前 0x01 读取失败）。如果它看起来像目标，
    // 先补读 0x01 验身；确认成功即可复用，失败再断开重扫。
    if (connected &&
        sameScreenCode(screenCode, sessionScreenCode) &&
        sessionSerials.any((value) => serialsMatch(value, serial))) {
      if (await _verifyBoundDeviceIdentity(
        serial: serial,
        screenCode: screenCode,
      )) {
        _connectionLease.noteActivity();
        trace.mark('reuse-verified-active-session');
        trace.finish(success: true);
        return null;
      }
    }
    final permitted = await trace.measure('permission', ensurePermission);
    if (!permitted) {
      trace.finish(success: false, stage: 'permission-denied');
      return _l10n.bleUnavailable;
    }
    // 单连接模型：正连着别的设备时先断开，避免底层双连接互相干扰。
    if (connected) {
      await trace.measure('disconnect-previous-session', disconnect);
    }
    final excludedDeviceIds = <String>{};
    String? lastConnectError;
    // 同短 ID 设备通常为两台；最多核验 4 个候选，避免异常广播环境下无限循环。
    for (var attempt = 0; attempt < 4; attempt += 1) {
      final found = await trace.measure(
        'scan-${attempt + 1}',
        () => scan(
          // 12 秒（原 6 秒）：相框被 GATT 占着时不广播，断开后要好几秒才恢复广播。
          // 排除已验错候选后继续扫，直到找到另一个同短 ID、同尺寸候选。
          timeout: const Duration(seconds: 12),
          until: (list) =>
              matchScannedDevice(
                list,
                serial: serial,
                name: name,
                screenCode: screenCode,
                excludedDeviceIds: excludedDeviceIds,
              ) !=
              null,
        ),
      );
      final target = matchScannedDevice(
        found,
        serial: serial,
        name: name,
        screenCode: screenCode,
        excludedDeviceIds: excludedDeviceIds,
      );
      if (target == null) {
        break;
      }
      final remoteId = target.device.remoteId.str;
      final error = await trace.measure(
        'connect-and-read-info-${attempt + 1}',
        () => connect(target),
      );
      if (error != null) {
        lastConnectError = error;
        excludedDeviceIds.add(remoteId);
        if (connected) {
          await disconnect();
        }
        continue;
      }
      if (await _verifyBoundDeviceIdentity(
        serial: serial,
        screenCode: screenCode,
      )) {
        trace.finish(success: true, stage: 'identity-verified');
        return null;
      }
      excludedDeviceIds.add(remoteId);
      await disconnect();
      trace.mark('identity-mismatch-excluded-$remoteId');
    }
    trace.finish(success: false, stage: 'verified-target-not-found');
    return lastConnectError ?? _l10n.bleDeviceNotFound;
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
      // 问 **OS** 的真实已连接表（systemDevices），而不是 FlutterBluePlus 自己的
      // 内存镜像（connectedDevices）——后者恰恰由「可能没补发的断开事件」驱动更新，
      // 本方法要治理的死会话场景下它会和 _client.connected 一起谎报 true，
      // 体检就成了恒 false 的空转。iOS 要求按服务过滤，传相框主服务 FF00。
      final sys = await FlutterBluePlus.systemDevices([
        Guid(FrameProtocol.serviceUuid),
      ]);
      final alive = sys.any((d) => d.remoteId == dev.remoteId);
      if (alive) {
        return false;
      }
      await disconnect();
      return true;
    } catch (_) {
      // 查询异常保守不动（维持原语义），留待下次操作时真实校验。
      return false;
    }
  }

  bool otaInProgress = false;

  /// 设备固件 OTA(DFU) 升级。复用图传已建立的连接（OTA 走独立的 FF10 服务）。
  ///
  /// [dryRun]=true 时不连蓝牙，纯本地校验编码/分包（无硬件或无固件时用）。
  /// 真实升级要求当前已连接设备（[connected]），否则抛 [OtaException]。
  Future<OtaResult> upgradeFirmware(
    OtaFirmwarePackage pkg, {
    String expectedSerial = '',
    int expectedScreenCode = 0,
    void Function(OtaProgress)? onProgress,
    bool Function()? shouldAbort,
    void Function(String dir, String hex)? onMonitor,
    bool dryRun = false,
    int pace = 3,
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
    if (expectedSerial.isEmpty ||
        !sessionMatchesSerial(expectedSerial, screenCode: expectedScreenCode)) {
      throw OtaException('当前连接的不是要升级的设备，请返回详情页重新连接');
    }

    final ota = FrameOtaClient(dev)..onMonitor = onMonitor;
    otaInProgress = true;
    _connectionLease.taskStarted();
    notifyListeners();
    try {
      // OTA 与图传共用同一物理连接：升级前同样切到极速连接间隔（0x13 + HIGH 优先级），
      // 结束后回落空闲档。否则整轮 OTA 跑在 100ms 空闲间隔上，PRN=3 的停等每次
      // ACK 往返最多白等 ~100ms，240KB 固件要多花约 1 分钟。
      await _client.beginTransferSession();
      return await ota.upgradeFirmware(
        pkg,
        onProgress: onProgress,
        shouldAbort: shouldAbort,
        pace: pace,
      );
    } finally {
      // 只取消 OTA 自身的 FF11 通知订阅；物理连接由 _client 持有（升级后设备多半已重启断开）。
      await ota.disconnect();
      // 回落空闲连接间隔。升级成功设备会复位重启断开连接——endTransferSession
      // 对已断链是安全的 best-effort（内部检查 _linkAlive 并吞掉 0x13 失败）。
      await _client.endTransferSession();
      otaInProgress = false;
      _connectionLease.taskFinished();
      notifyListeners();
    }
  }
}
