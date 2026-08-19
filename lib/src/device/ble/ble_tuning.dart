import 'package:shared_preferences/shared_preferences.dart';

/// 安卓建连预算的两种分配方式（见 `BleConnectPlan`）。
///
/// 这个旋钮存在的唯一理由：两种分配的优劣**只能在真实弱信号现场用成功率分辨**，
/// 而每换一版就重新出一个包、隔几天再测，环境早漂了，比出来的东西不作数。
/// 放进正式包后可以在同一段时间、同一个位置交替切换对照。
enum AndroidConnectStrategy {
  /// 默认（2026-08-01 起）：长直连优先，autoConnect 只当末位兜底。
  directFirst,

  /// 旧分配（2026-07-30 版）：弱信号尽早切 autoConnect 并给它大头预算。
  autoConnectFirst,
}

/// 图传发送参数与安卓建连策略的**运行时旋钮**——正式包（release / TestFlight）里也可调。
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

  /// 滑窗大小。2026-08-14 由 10 提到 50：固件那轮传输优化把收包缓冲扩到 50 包
  /// （配套 0x21 数据 236→489 字节、MTU 500），与小程序 `DEFAULT_TRANSFER_WINDOW` 同步。
  ///
  /// ⚠️ 这里填的是**上限**不是定值：[FrameBleClient] 的 AIMD 卡顿时会把窗口减半、
  /// 稳定后再涨回，并用「丢包记忆」钉住上限。窗口 50 与 AIMD 是**同一个决定的两半，
  /// 回滚必须一起回**——老策略在大窗口下会退化成「灌满→缓冲溢出丢包→其后整窗按序作废→
  /// 等满超时→整窗重发」的死循环，窗口越大每转一圈代价越大。
  static const int defaultWindowPackets = 50;

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

  /// 安卓建连预算的分配方式。默认 [AndroidConnectStrategy.directFirst]；
  /// 切到 `autoConnectFirst` 即整体退回 2026-07-30 那一版的阶梯与兜底时长。
  /// iOS 忽略（那边 autoConnect 兜底本就是空操作）。
  static AndroidConnectStrategy androidConnectStrategy =
      AndroidConnectStrategy.directFirst;

  static bool get isDefault =>
      paceMs == defaultPaceMs &&
      paceFloorMs == defaultPaceFloorMs &&
      windowPackets == defaultWindowPackets &&
      connIntervalOverrideMs == null &&
      !skipConnIntervalRequest &&
      !forceAckedWrite &&
      androidConnectStrategy == AndroidConnectStrategy.directFirst;

  static const String _kPace = 'ble_tuning_pace_ms';
  static const String _kPaceFloor = 'ble_tuning_pace_floor_ms';
  static const String _kWindow = 'ble_tuning_window';
  static const String _kConnInterval = 'ble_tuning_conn_interval_ms';
  static const String _kSkipConn = 'ble_tuning_skip_conn_interval';
  static const String _kAckedWrite = 'ble_tuning_acked_write';
  static const String _kConnectStrategy = 'ble_tuning_android_connect_strategy';

  /// 旋钮口径版本戳。**默认值改动时同步升版**：版本不匹配的旧存储值一律作废、回落到当前
  /// 出厂值，不必要求用户去自检页手动 [resetToDefaults]。
  ///
  /// 为什么必须有（2026-08-14 小程序侧真机踩过的坑）：小程序把默认窗口从 10 提到 50 后，
  /// 早先在调试台存过「窗口 10」的手机升级后仍按 10 跑，新默认**等于从没生效过**，
  /// 排查时还一度误判成「50 包把设备压垮了」。这边 [load] 同样会把旧的 window=10 读回来，
  /// 同款问题，同款解法。
  static const String _kEpoch = 'ble_tuning_epoch';
  static const String _epoch = '2026-08-14-w50';

  /// 冷启动时读回上次调好的值。失败（prefs 不可用）静默保持默认值——
  /// 这只是调优旋钮，绝不能因为读不到偏好就影响正常投屏。
  static Future<void> load() async {
    try {
      final sp = await SharedPreferences.getInstance();
      // 口径版本不匹配 = 上个默认值口径的遗留旋钮，整组作废并清掉，让当前出厂值真正生效。
      if (sp.getString(_kEpoch) != _epoch) {
        await _clearStaleTuning(sp);
        return;
      }
      paceMs = sp.getInt(_kPace) ?? defaultPaceMs;
      paceFloorMs = sp.getDouble(_kPaceFloor) ?? defaultPaceFloorMs;
      windowPackets = sp.getInt(_kWindow) ?? defaultWindowPackets;
      connIntervalOverrideMs = sp.getDouble(_kConnInterval);
      skipConnIntervalRequest = sp.getBool(_kSkipConn) ?? false;
      forceAckedWrite = sp.getBool(_kAckedWrite) ?? false;
      // 按名字读回，别用 index：枚举以后加一项就会把旧偏好读成另一种策略。
      final strategy = sp.getString(_kConnectStrategy);
      androidConnectStrategy = AndroidConnectStrategy.values.firstWhere(
        (v) => v.name == strategy,
        orElse: () => AndroidConnectStrategy.directFirst,
      );
    } catch (_) {
      // 保持默认
    }
  }

  /// 清掉上个口径遗留的旋钮值，并把内存值复位到出厂默认（不写回，等用户真正调过再落盘）。
  static Future<void> _clearStaleTuning(SharedPreferences sp) async {
    paceMs = defaultPaceMs;
    paceFloorMs = defaultPaceFloorMs;
    windowPackets = defaultWindowPackets;
    connIntervalOverrideMs = null;
    skipConnIntervalRequest = false;
    forceAckedWrite = false;
    androidConnectStrategy = AndroidConnectStrategy.directFirst;
    for (final key in <String>[
      _kPace,
      _kPaceFloor,
      _kWindow,
      _kConnInterval,
      _kSkipConn,
      _kAckedWrite,
      _kConnectStrategy,
    ]) {
      await sp.remove(key);
    }
  }

  static Future<void> save() async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(_kEpoch, _epoch); // 本次显式保存盖上当前口径戳
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
      await sp.setString(_kConnectStrategy, androidConnectStrategy.name);
    } catch (_) {}
  }

  static Future<void> resetToDefaults() async {
    paceMs = defaultPaceMs;
    paceFloorMs = defaultPaceFloorMs;
    windowPackets = defaultWindowPackets;
    connIntervalOverrideMs = null;
    skipConnIntervalRequest = false;
    forceAckedWrite = false;
    androidConnectStrategy = AndroidConnectStrategy.directFirst;
    await save();
  }

  /// 一行摘要，进埋点日志用（每次图传都会带上，方便回看当时跑的是哪组参数）。
  static String describe() {
    if (isDefault) return 'default';
    return 'pace=$paceMs floor=$paceFloorMs win=$windowPackets '
        'conn=${skipConnIntervalRequest ? 'skip' : (connIntervalOverrideMs?.toString() ?? 'auto')} '
        'ackedWrite=$forceAckedWrite connect=${androidConnectStrategy.name}';
  }
}
