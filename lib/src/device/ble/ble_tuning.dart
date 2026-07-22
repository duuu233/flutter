import 'package:shared_preferences/shared_preferences.dart';

/// 图传发送参数的**运行时旋钮**——正式包（release / TestFlight）里也可调。
///
/// 为什么要有这个文件：iOS 侧没有任何应用内日志（`CrashLogger` 只有 Android 实现），
/// 正式包又拿不到 Xcode / Console 输出。要判断「0x13 请求的 15ms 连接间隔到底生没生效」
/// 只能做**对照实验**（见 `docs/iOS-投屏性能测试指南.md` 第 6 节），而对照实验原本要求
/// 「改常数 → 重新出包」三轮。把这些常数变成可在 App 内切换的旋钮后，一个包就能跑完
/// A/B/C 三组，结果直接显示在「投屏性能自检」页上。
///
/// 全部旋钮落 SharedPreferences：调好的值跨启动保留，方便按最优配置连续体验几天。
/// [resetToDefaults] 一键回到出厂值——线上默认值永远等于下面这组 `default*` 常量。
class BleTuning {
  BleTuning._();

  // ── 出厂默认（= 与小程序逐字节对齐的那组参数）────────────────
  /// 发送节奏上界（ms）。对齐小程序 `PACKET_PACE_MS`。
  static const int defaultPaceMs = 3;

  /// AIMD 下探的地板：0 = 允许探到「不再主动 sleep」。
  ///
  /// iOS 专属风险：CoreBluetooth 的 `writeValue(type:.withoutResponse)` 是 fire-and-forget，
  /// 队列满时**静默丢包且不抛异常**。若 flutter_blue_plus 的 darwin 侧没有 gate 在
  /// `canSendWriteWithoutResponse`，探到 0 就会大量丢包 → 600ms ACK 超时 → 窗口缩到 1 → 极慢，
  /// 体感正是「传一段停一下」。怀疑这条时把地板抬到 1.0~2.0ms 对照一次即可证伪。
  static const double defaultPaceFloorMs = 0.0;

  /// 滑窗大小。固件收包缓冲就是 10 包，再大也无意义（会被 [FrameBleClient] 夹回）。
  static const int defaultWindowPackets = 10;

  // ── 当前生效值 ───────────────────────────────────────────
  static int paceMs = defaultPaceMs;
  static double paceFloorMs = defaultPaceFloorMs;
  static int windowPackets = defaultWindowPackets;

  /// 图传前 0x13 请求的连接间隔（ms）；null = 按平台默认（Android 7.5 / iOS 15）。
  /// 自检页用它跑对照组：15（A 组）/ 30（C 组）/ 100（= 空闲档，差异最大最好判读）。
  static double? connIntervalOverrideMs;

  /// 完全不发 0x13（阴性对照 B 组）：链路跑在系统自选参数上。
  static bool skipConnIntervalRequest = false;

  /// 图传数据包改用「有应答写」。
  ///
  /// 有应答写每包都等外设确认，天然有背压、绝不静默丢包，但每包多一个往返（会更慢）。
  /// 它的用途不是提速，而是**证伪**：若切成有应答写后 `retries` 从一堆变成 0，
  /// 就证明无应答写在丢包（对应上面 [defaultPaceFloorMs] 注释里的 iOS 风险）。
  /// 特征不支持有应答写时 [FrameBleClient] 会忽略本开关。
  static bool forceAckedWrite = false;

  static bool get isDefault =>
      paceMs == defaultPaceMs &&
      paceFloorMs == defaultPaceFloorMs &&
      windowPackets == defaultWindowPackets &&
      connIntervalOverrideMs == null &&
      !skipConnIntervalRequest &&
      !forceAckedWrite;

  static const String _kPace = 'ble_tuning_pace_ms';
  static const String _kPaceFloor = 'ble_tuning_pace_floor_ms';
  static const String _kWindow = 'ble_tuning_window';
  static const String _kConnInterval = 'ble_tuning_conn_interval_ms';
  static const String _kSkipConn = 'ble_tuning_skip_conn_interval';
  static const String _kAckedWrite = 'ble_tuning_acked_write';

  /// 冷启动时读回上次调好的值。失败（prefs 不可用）静默保持默认值——
  /// 这只是调优旋钮，绝不能因为读不到偏好就影响正常投屏。
  static Future<void> load() async {
    try {
      final sp = await SharedPreferences.getInstance();
      paceMs = sp.getInt(_kPace) ?? defaultPaceMs;
      paceFloorMs = sp.getDouble(_kPaceFloor) ?? defaultPaceFloorMs;
      windowPackets = sp.getInt(_kWindow) ?? defaultWindowPackets;
      connIntervalOverrideMs = sp.getDouble(_kConnInterval);
      skipConnIntervalRequest = sp.getBool(_kSkipConn) ?? false;
      forceAckedWrite = sp.getBool(_kAckedWrite) ?? false;
    } catch (_) {
      // 保持默认
    }
  }

  static Future<void> save() async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setInt(_kPace, paceMs);
      await sp.setDouble(_kPaceFloor, paceFloorMs);
      await sp.setInt(_kWindow, windowPackets);
      final ci = connIntervalOverrideMs;
      if (ci == null) {
        await sp.remove(_kConnInterval);
      } else {
        await sp.setDouble(_kConnInterval, ci);
      }
      await sp.setBool(_kSkipConn, skipConnIntervalRequest);
      await sp.setBool(_kAckedWrite, forceAckedWrite);
    } catch (_) {}
  }

  static Future<void> resetToDefaults() async {
    paceMs = defaultPaceMs;
    paceFloorMs = defaultPaceFloorMs;
    windowPackets = defaultWindowPackets;
    connIntervalOverrideMs = null;
    skipConnIntervalRequest = false;
    forceAckedWrite = false;
    await save();
  }

  /// 一行摘要，进埋点日志用（每次图传都会带上，方便回看当时跑的是哪组参数）。
  static String describe() {
    if (isDefault) return 'default';
    return 'pace=$paceMs floor=$paceFloorMs win=$windowPackets '
        'conn=${skipConnIntervalRequest ? 'skip' : (connIntervalOverrideMs?.toString() ?? 'auto')} '
        'ackedWrite=$forceAckedWrite';
  }
}
