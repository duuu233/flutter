import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../native_device_api.dart';
import '../network/boltfox_api.dart';
import '../shared/l10n/app_l10n.dart';
import '../state.dart' show AppLanguage;
import 'ble/ble_direct_connect_cache.dart';
import 'ble/device_ble.dart';
import 'ble/frame_protocol.dart';
import 'ble/ota_ble.dart';
import 'ble_connection_lease.dart';
import 'device_interaction_trace.dart';
import 'serial_match.dart';

/// 蓝牙信号档位（由 UI 层按当前语言渲染文字，见 [BleController.rssiToSignalLevel]）。
enum BleSignalLevel { veryStrong, strong, normal, weak, veryWeak }

/// 这个异常是不是「超时」类（2026-08-01，对齐小程序 `active-device.isConnectTimeoutMessage`）。
///
/// flutter_blue_plus 的连接超时既可能抛 [TimeoutException]，也可能抛 `FlutterBluePlusException`
/// 且消息里带 timeout / time out；两种都要认，否则中文用户会看到英文原文
/// （`TimeoutException after 0:00:08.000000: Future not completed`）。
bool isBleTimeoutError(Object? error) {
  if (error is TimeoutException) {
    return true;
  }
  final text = error?.toString().toLowerCase() ?? '';
  return text.contains('timeout') || text.contains('time out');
}

/// 直连快路径的结果，见 `BleController._tryDirectConnect`。
enum _DirectConnectOutcome {
  /// 已连上并通过 0x01 完整 ID 验身。
  verified,

  /// 探测过但没成（连不上或验身不过）——回落完整扫描。
  missed,

  /// 没有可用缓存 / 快路径已停用，本次压根没探测。
  skipped,
}

/// 「弱信号不抢第一帧」闸门（移植小程序 `active-device.scanForTarget`）。
///
/// 扫描一命中就发起连接，抓到的往往是整个窗口里信号最差的那一帧——本相框广播间隔约 3s，
/// 第一帧擦边收到时链路质量最差，CONNECT_IND 极易丢，正是「-67~-78dBm 区间经常连不上」
/// 的成因。信号弱时先不连，给一个短窗口等更强的一帧；期间来一帧达标的立刻连，
/// 等满了也照常连——**绝不因为信号弱就不让用户连**。
class _WeakSignalGate {
  final Stopwatch _waited = Stopwatch();

  /// 现在就该发起连接吗？[rssi] 是本次命中候选的原始 RSSI。
  bool shouldConnectNow(int rssi) {
    if (!_waited.isRunning) {
      _waited.start();
    }
    return BleController.shouldConnectAtRssi(rssi, _waited.elapsed);
  }
}

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

  /// 把蓝牙信号强度(RSSI，单位 dBm，越接近 0 越强)归到用户能看懂的展示档位。
  ///
  /// 现场 RSSI 容易受瞬时尖峰影响，展示口径与小程序统一保守下调一级：
  /// 原「极强」显示为「强」，其余依次下调，最弱档仍封底为「弱」。
  /// 此方法只供 UI 展示，不参与连接门槛或重试策略。
  /// 文字由 UI 层按当前语言渲染（见 bind_device_flow 的 signal 映射）；
  /// RSSI 缺省(0)或非法(≥0)时返回 null，由页面兜底成「--」。
  static BleSignalLevel? rssiToSignalLevel(int rssi) {
    if (rssi == 0 || rssi >= 0) {
      return null;
    }
    if (rssi >= -55) {
      return BleSignalLevel.strong;
    }
    if (rssi >= -67) {
      return BleSignalLevel.normal;
    }
    if (rssi >= -78) {
      return BleSignalLevel.weak;
    }
    return BleSignalLevel.veryWeak;
  }

  /// 连接前的信号闸阈值（原始 RSSI，dBm）：命中候选弱于此值时先等更强的一帧。
  /// -70dBm 取在原始 RSSI 的 -67~-78dBm 区间靠前位置，与小程序
  /// `active-device.WEAK_SIGNAL_RSSI` 同值。**与展示档位无关**——展示文案保守下调过一级
  /// （见 [rssiToSignalLevel]），但连接策略必须用原始 RSSI。
  static const int weakSignalRssi = -70;

  /// 弱信号最多等多久。广播间隔约 3s，1.5s 意味着「等下一帧再决定」；
  /// 等满仍不达标也照常连，绝不因信号弱阻断用户。
  static const Duration weakSignalWait = Duration(milliseconds: 1500);

  /// 弱信号闸的判据（[_WeakSignalGate] 与单测共用）。
  /// [rssi] 为 0 或非法（≥0）= 该机型没上报信号强度，无从判断，按原行为立即连。
  static bool shouldConnectAtRssi(int rssi, Duration waited) {
    if (rssi >= weakSignalRssi) {
      return true;
    }
    return waited >= weakSignalWait;
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
  Future<String?> connect(ScanResult result) {
    final ad = advertisingOf(result);
    return _connectDevice(
      result.device,
      traceName: 'connect-device',
      label: displayName(result),
      // 会话登记广播 4 字节 Device_ID：连接后广播就停了，此刻不记就再也拿不到
      broadcastId: ad?.deviceId ?? '',
      screenType: ad?.screenType ?? 0,
      attemptTimeouts: _attemptTimeoutsForRssi(result.rssi),
    );
  }

  /// 按候选的**原始** RSSI 选建连阶梯。返回 null = 用默认阶梯。
  ///
  /// 三档（仅 Android；iOS 的 `connect` 本身就是「一直等到连上」的语义，
  /// 缩短阶梯只会帮倒忙，一律返回 null）：
  ///
  /// | 档位 | 判据 | 阶梯 |
  /// | --- | --- | --- |
  /// | 正常 | ≥ -70dBm | 5s → 8s → autoConnect 15s |
  /// | 弱 | < -70dBm | 5s → autoConnect 15s（第二次 8s 长试命中率太低，不值得） |
  /// | 极弱 | < -80dBm | 常规一档都不走 → autoConnect 20s |
  ///
  /// 极弱档是本轮新增：-80dBm 以下常规 `connectGatt` 的 CONNECT_IND 命中率接近于零，
  /// 那 5 秒是纯白等。省下来的时间原样加给 autoConnect，**总预算不变**，
  /// 只是全花在真正管用的机制上（见 `FrameBleClient.veryWeakSignalAttemptTimeouts`）。
  ///
  /// `rssi == 0`（读不到）天然落进「正常」档：0 不小于任何一个负阈值。
  static List<Duration>? _attemptTimeoutsForRssi(int rssi) {
    if (!Platform.isAndroid) {
      return null;
    }
    if (rssi < FrameBleClient.veryWeakSignalRssi) {
      return FrameBleClient.veryWeakSignalAttemptTimeouts;
    }
    if (rssi < weakSignalRssi) {
      return FrameBleClient.weakSignalAttemptTimeouts;
    }
    return null;
  }

  /// 按 remoteId 直接建连（**不经扫描**），供直连快路径使用。
  ///
  /// 没有 ScanResult 也就没有广播厂商数据：`broadcastDeviceId`/`broadcastScreenType`
  /// 留空，会话身份完全由建连后读到的 0x01 完整 ID 提供——这不降低安全性，
  /// 因为广播短 ID 本来就只能筛候选、不能验身（见 `BLE_CONNECTION_AND_IDENTITY.md`）。
  Future<String?> connectByRemoteId(String remoteId, {String name = ''}) {
    return _connectDevice(
      BluetoothDevice.fromId(remoteId),
      traceName: 'connect-direct',
      label: name,
      broadcastId: '',
      screenType: 0,
      // 快路径是「赌一把」：赌不中必须马上回落扫描，既不重试也不走 autoConnect 兜底。
      attemptTimeouts: const <Duration>[FrameBleClient.directConnectProbeTimeout],
      allowAutoConnectFallback: false,
    );
  }

  Future<String?> _connectDevice(
    BluetoothDevice device, {
    required String traceName,
    required String label,
    required String broadcastId,
    required int screenType,
    List<Duration>? attemptTimeouts,
    bool allowAutoConnectFallback = true,
  }) async {
    // 重入护栏：并发连接（列表快速双击 / 自动重连撞上手动点连接）会让两次
    // _client.connect 交错覆盖 _device/订阅/_writeChar，且 broadcastDeviceId 与
    // 实际连上的设备错位——这正是序列号交叉认领最怕的输入。第二路直接拒绝。
    if (connecting) {
      return _l10n.bleBusyConnecting;
    }
    final trace = DeviceInteractionTrace(traceName);
    connecting = true;
    _connectionLease.taskStarted();
    deviceName = label;
    broadcastDeviceId = broadcastId;
    broadcastScreenType = screenType;
    notifyListeners();
    try {
      await trace.measure('gatt-connect-and-discover', () async {
        await _client.connect(
          device,
          attemptTimeouts: attemptTimeouts,
          allowAutoConnectFallback: allowAutoConnectFallback,
        );
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
      // 记住这台设备的 remoteId，下次复连可整段跳过扫描（见 [connectByRemoteId]）。
      // 写入点收敛在这里一处，绑定页/详情页/自动重连三条入口自动全覆盖；
      // 键用 0x01 自报的完整 ID —— 它就是后端记录的稳定身份，串台不了。
      final learned = info?.deviceId ?? '';
      if (isCompleteDeviceSerial(learned)) {
        unawaited(
          BleDirectConnectCache.instance.put(learned, device.remoteId.str),
        );
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
      // 超时单独成句（2026-08-01）：等一会儿再试比「靠近设备」更贴合超时的成因，
      // 且必须走 _l10n 才能跟随语种（TimeoutException 的 toString 恒为英文）。
      return isBleTimeoutError(error)
          ? _l10n.bleConnectTimeout
          : _l10n.bleConnectFailed;
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
    // 同一个 remoteId 已经连失败几次。连接失败**不等于**「这台不是我要的」：
    // 句柄可能刚失效（设备重启/安卓随机地址轮换）、也可能就是一次瞬时抖动，
    // 重扫拿到新鲜句柄再连往往就成了。所以只有反复失败才把它排除掉。
    final connectFailures = <String, int>{};
    String? lastConnectError;

    // ① 系统已连接表兜底：设备被系统层占着时**它不广播**，扫描永远搜不到。
    if (await _tryConnectSystemDevice(
      serial: serial,
      name: name,
      screenCode: screenCode,
      trace: trace,
      excludedDeviceIds: excludedDeviceIds,
    )) {
      trace.finish(success: true, stage: 'system-device-verified');
      return null;
    }

    // ② 直连快路径：命中本机缓存就短超时直连上次的 remoteId，成功即整段跳过扫描。
    final directProbed = await _tryDirectConnect(
      serial: serial,
      name: name,
      screenCode: screenCode,
      trace: trace,
      excludedDeviceIds: excludedDeviceIds,
    );
    if (directProbed == _DirectConnectOutcome.verified) {
      trace.finish(success: true, stage: 'direct-connect-verified');
      return null;
    }

    // ③ 完整扫描 → 筛候选 → 建连 → 0x01 验身。
    // 同短 ID 设备通常为两台，且每台允许一次「换新句柄重连」，最多 4 轮，
    // 避免异常广播环境下无限循环。
    for (var attempt = 0; attempt < 4; attempt += 1) {
      // 弱信号不抢第一帧：命中即停会在「刚擦边收到第一帧」时就发起连接，而那一帧往往是
      // 整个窗口里信号最差的时刻，连接成功率最低（现场表现正是高 RSSI 一点就连上、
      // -67~-78dBm 区间经常连不上）。信号够强/读不到 RSSI 时行为完全不变：扫到即走。
      final gate = _WeakSignalGate();
      // 闸门放行的那一台**就地捕获**，不再等扫描返回后重新 match 一遍。两个理由：
      // ① 同短 ID 的两台都在场时，窗口末尾按 RSSI 重排后「第一个匹配」可能已经换了一台，
      //    于是连的不是闸门放行的那一台；
      // ② 建连阶梯是按「开闸那一刻那一帧的 RSSI」选的（见 [_attemptTimeoutsForRssi]），
      //    重新 match 拿到的是最后一包的 RSSI，两者对不上时会选错档位。
      ScanResult? gated;
      final found = await trace.measure(
        'scan-${attempt + 1}',
        () => scan(
          // 12 秒（原 6 秒）：相框被 GATT 占着时不广播，断开后要好几秒才恢复广播。
          // 排除已验错候选后继续扫，直到找到另一个同短 ID、同尺寸候选。
          timeout: const Duration(seconds: 12),
          until: (list) {
            final hit = matchScannedDevice(
              list,
              serial: serial,
              name: name,
              screenCode: screenCode,
              excludedDeviceIds: excludedDeviceIds,
            );
            if (hit == null || !gate.shouldConnectNow(hit.rssi)) {
              return false;
            }
            gated = hit;
            return true;
          },
        ),
      );
      // 闸门没开过（等满整窗才收网）时才回落到「在最终列表里找」。
      final target =
          gated ??
          matchScannedDevice(
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
      // 扫描与 GATT 建连抢同一路射频：等停扫真正沉淀下来再连（弱信号下这是主因之一）。
      await FrameBleClient.settleAfterScan();
      final error = await trace.measure(
        'connect-and-read-info-${attempt + 1}',
        () => connect(target),
      );
      if (error != null) {
        lastConnectError = error;
        final failures = (connectFailures[remoteId] ?? 0) + 1;
        connectFailures[remoteId] = failures;
        // 只有同一台反复连不上才排除；否则下一轮重扫拿新鲜句柄再连——这一层
        // 专治「句柄已失效」，那类失败在同一个句柄上重试多少次都是超时。
        if (failures >= _maxConnectFailuresPerCandidate) {
          excludedDeviceIds.add(remoteId);
          trace.mark('connect-failed-excluded-$remoteId');
        } else {
          trace.mark('connect-failed-will-rescan-$remoteId');
        }
        if (connected) {
          await disconnect();
        }
        continue;
      }
      if (await _verifyBoundDeviceIdentity(
        serial: serial,
        screenCode: screenCode,
      )) {
        if (directProbed == _DirectConnectOutcome.missed) {
          // 直连没连上、扫描却连上了同一台 ⇒ 设备本来就够得着，是直连这条路不通。
          _noteDirectConnectMiss();
        }
        trace.finish(success: true, stage: 'identity-verified');
        return null;
      }
      excludedDeviceIds.add(remoteId);
      // 身份不符：这个句柄绝不能再留在直连缓存里，否则每次复连都先串一次台。
      await BleDirectConnectCache.instance.remove(serial);
      await disconnect();
      trace.mark('identity-mismatch-excluded-$remoteId');
    }
    trace.finish(success: false, stage: 'verified-target-not-found');
    return lastConnectError ?? _l10n.bleDeviceNotFound;
  }

  /// 同一个 remoteId 允许连失败几次才把它排除出候选。
  static const int _maxConnectFailuresPerCandidate = 2;

  /// 系统已连接表里最多试几个候选（每个都要花一次短超时建连，必须夹住）。
  static const int _maxSystemDeviceCandidates = 2;

  /// 系统已连接表兜底：**扫描治不了的那一类「搜不到」**。
  ///
  /// BLE 设备一旦被连上就停止广播。所以只要相框此刻被系统层占着——微信小程序还连着、
  /// 上一个进程被杀时 GATT 没收干净、或别的 App 连过——扫描窗口开到 60 秒也一台都搜不到，
  /// 用户看到的是「设备明明开着、就是搜不到」，还会被引到「是不是没开机」的错误方向。
  /// 这类情况下设备就躺在系统的已连接表里，直接拿它建连几乎瞬时完成（ACL 链路已经在了，
  /// 只是我们这个 App 还没有自己的 GATT 客户端）。
  ///
  /// 安全边界：
  /// ① Android 的 `systemDevices` 会把**所有** GATT 已连接设备都返回（服务过滤只在 iOS 生效），
  ///    耳机/手表都在里面。所以先用扫描同款的广播名白名单筛一遍——名字取不到就直接跳过，
  ///    宁可放弃这次提速，也绝不拿 3 秒超时去连用户的耳机。
  /// ② 白名单只筛「是不是相框」，**认不认领由 0x01 完整 ID 说了算**，与扫描路径同一把尺子。
  /// ③ 候选数量夹在 [_maxSystemDeviceCandidates]，最坏多花两次短超时。
  ///
  /// 返回 true 表示已连上并通过验身，调用方可直接成功返回。
  Future<bool> _tryConnectSystemDevice({
    required String serial,
    required String name,
    required int screenCode,
    required DeviceInteractionTrace trace,
    required Set<String> excludedDeviceIds,
  }) async {
    List<BluetoothDevice> candidates;
    try {
      // 只用**已缓存**的白名单，绝不在这里 await 产品列表接口：那是一次网络请求，
      // 弱网下能卡好几秒——快路径一旦要等网络就不再是快路径了（扫描那一步本来就会拉，
      // 拉到后整次会话复用）。没缓存就退回内置的两款相框广播名，够用且零开销。
      final allow = (_cachedBroadcastIds ?? _fallbackBroadcastIds)
          .map((s) => s.trim().toUpperCase())
          .where((s) => s.isNotEmpty)
          .toList();
      if (allow.isEmpty) {
        return false; // 没有白名单就没有安全的筛选依据，直接放弃这条快路径。
      }
      final sys = await FlutterBluePlus.systemDevices([
        Guid(FrameProtocol.serviceUuid),
      ]);
      candidates = sys
          .where((device) {
            if (excludedDeviceIds.contains(device.remoteId.str)) {
              return false;
            }
            final platformName = device.platformName.toUpperCase();
            return allow.any((allowed) => platformName.contains(allowed));
          })
          .take(_maxSystemDeviceCandidates)
          .toList();
    } catch (_) {
      return false; // 查询失败不影响主链：照常走扫描。
    }
    if (candidates.isEmpty) {
      return false;
    }
    for (final device in candidates) {
      final remoteId = device.remoteId.str;
      final error = await trace.measure(
        'system-device-connect',
        () => _connectDevice(
          device,
          traceName: 'connect-system-device',
          label: name,
          // 没有 ScanResult 就没有广播厂商数据；身份完全由 0x01 提供（同直连快路径）。
          broadcastId: '',
          screenType: 0,
          // 链路已经在了，连不上多半是刚被放掉：短超时快速失败、回落扫描。
          attemptTimeouts: const <Duration>[
            FrameBleClient.directConnectProbeTimeout,
          ],
          allowAutoConnectFallback: false,
        ),
      );
      if (error == null &&
          await _verifyBoundDeviceIdentity(
            serial: serial,
            screenCode: screenCode,
          )) {
        return true;
      }
      if (error == null) {
        // 是相框但不是这一台：排除，别让紧接着的扫描再连一遍。
        excludedDeviceIds.add(remoteId);
        trace.mark('system-device-identity-mismatch-$remoteId');
        // 刚用 0x01 证明了这个句柄不是本设备。若直连缓存正好指着它，那条记录
        // 已被证伪，立刻删掉——留着只会让下次复连先白花一次 3s 探测。
        if (await BleDirectConnectCache.instance.get(serial) == remoteId) {
          await BleDirectConnectCache.instance.remove(serial);
        }
      }
      if (connected) {
        await disconnect();
      }
    }
    return false;
  }

  /// 直连快路径连续「设备够得着、但直连不通」几次后，本进程内不再尝试快路径。
  ///
  /// 这条自适应闸门是为 iOS 准备的：Android 的 remoteId 就是 MAC，不扫描直接连是
  /// 标准用法；iOS 的 remoteId 是系统给外设生成的 UUID，能否不扫描直连取决于插件
  /// 底层有没有走 `retrievePeripherals(withIdentifiers:)`。若这条路在某个平台/版本上
  /// 根本不通，探测就会变成每次复连白花 3 秒——累计两次即自动关掉，不留长期回归。
  static const int _directConnectMissLimit = 2;
  int _directConnectMisses = 0;
  bool _directConnectDisabled = false;

  void _noteDirectConnectMiss() {
    if (_directConnectDisabled) {
      return;
    }
    _directConnectMisses += 1;
    if (_directConnectMisses >= _directConnectMissLimit) {
      _directConnectDisabled = true;
      debugPrint(
        '[BLE direct] 连续 $_directConnectMisses 次「直连失败但扫描成功」，'
        '本次进程内停用直连快路径',
      );
    }
  }

  /// 直连快路径：命中缓存就按上次的 remoteId 短超时直连，跳过整段扫描。
  ///
  /// 三种结果：[_DirectConnectOutcome.verified] 已连上并通过 0x01 验身（调用方可直接返回成功）；
  /// [_DirectConnectOutcome.missed] 探测过但没成（调用方回落扫描，并在扫描成功时记一次 miss）；
  /// [_DirectConnectOutcome.skipped] 没有可用缓存 / 已停用（不计 miss）。
  Future<_DirectConnectOutcome> _tryDirectConnect({
    required String serial,
    required String name,
    required int screenCode,
    required DeviceInteractionTrace trace,
    required Set<String> excludedDeviceIds,
  }) async {
    if (_directConnectDisabled) {
      return _DirectConnectOutcome.skipped;
    }
    final cachedId = await BleDirectConnectCache.instance.get(serial);
    if (cachedId.isEmpty || excludedDeviceIds.contains(cachedId)) {
      return _DirectConnectOutcome.skipped;
    }
    final error = await trace.measure(
      'direct-connect-probe',
      () => connectByRemoteId(cachedId, name: name),
    );
    if (error == null &&
        await _verifyBoundDeviceIdentity(
          serial: serial,
          screenCode: screenCode,
        )) {
      _directConnectMisses = 0;
      return _DirectConnectOutcome.verified;
    }
    // 连上了但验身没过（缓存串台）：排除这个句柄并清掉缓存，别让它下次再来一遍。
    if (error == null) {
      excludedDeviceIds.add(cachedId);
      trace.mark('direct-connect-identity-mismatch');
    }
    // 赌不中就必须把缓存删掉：留着的话，设备真的离线/换了地址时，
    // 每次复连都要先白花一次探测超时。下一次扫描连上后会重新写入。
    await BleDirectConnectCache.instance.remove(serial);
    if (connected) {
      await disconnect();
    }
    return _DirectConnectOutcome.missed;
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
