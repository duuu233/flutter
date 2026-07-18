import 'dart:async';

/// App 生命周期相位（决定空闲租约的宽限时长）。
///
/// [background] 与 [screenOff] 的区分在进入 paused 那一刻由原生查询屏幕亮灭
/// 判定（见 bolt_star_app）：亮屏时 paused = 用户切出 App；灭屏时 paused =
/// 按电源键息屏、App 仍在前台栈顶。产品要求两者宽限不同：切出 15 分钟、
/// 息屏 30 分钟。
enum BleLeasePhase { foreground, background, screenOff }

/// Manages when an existing BLE session may be released.
///
/// This class deliberately knows nothing about scanning, connecting, GATT, or
/// reconnection. It only owns the idle timers around an already established
/// connection so the transport strategy remains unchanged.
///
/// ## 2026-07-19：修「租约从来没到期过、进程从来没被回收过」
///
/// 到期依赖 Dart 的 [Timer]，而 Timer 只在 isolate 真的在跑的时候才会触发。
/// 三个漏洞叠在一起，导致 15/30 分钟的到期点在真机上几乎走不到：
///
/// 1. **相位没变化时 [setPhase] 直接 return**，连墙钟复核都跳过了。回前台恰恰是
///    进程从挂起 / Doze 中恢复的时刻——挂起期间 Timer 不会触发，「其实早该断了」
///    只能靠这一次复核发现。现在无论相位是否变化都先复核。
/// 2. **相位变化时无条件重新计时**。`hidden` 与 `paused` 会连续触发两次
///    （见 bolt_star_app 的生命周期分发），第二次白白把租约续了一整期。
///    现在相位没有真正变化就不重新计时。
/// 3. **进程在 Doze 里根本不跑**。这条不在 Dart 侧解决——`BleConnectionService`
///    现在与连接同生命周期持一个 PARTIAL_WAKE_LOCK（见该文件注释）。
///
/// 另外加了一条低频[_sweepInterval]墙钟巡检：一次性 Timer 在挂起后按「剩余时长」
/// 续跑，等于把挂起的这段时间白送给租约；巡检按绝对时刻复核，使恢复后最迟一个
/// 巡检周期内就能发现已经到期。
class BleConnectionLease {
  BleConnectionLease({
    required bool Function() isConnected,
    required bool Function() isBusy,
    required Future<void> Function() disconnect,
    this.foregroundIdleTimeout = const Duration(minutes: 10),
    this.backgroundGracePeriod = const Duration(minutes: 15),
    this.screenOffGracePeriod = const Duration(minutes: 30),
    this.postTransferGracePeriod = const Duration(minutes: 5),
    DateTime Function()? now,
  }) : _isConnected = isConnected,
       _isBusy = isBusy,
       _disconnect = disconnect,
       _now = now ?? DateTime.now;

  final bool Function() _isConnected;
  final bool Function() _isBusy;
  final Future<void> Function() _disconnect;
  final DateTime Function() _now;

  final Duration foregroundIdleTimeout;
  final Duration backgroundGracePeriod;
  final Duration screenOffGracePeriod;
  final Duration postTransferGracePeriod;

  /// 墙钟巡检周期（见类注释）。
  static const Duration _sweepInterval = Duration(seconds: 60);

  Timer? _timer;
  Timer? _sweepTimer;
  DateTime? _deadline;
  BleLeasePhase _phase = BleLeasePhase.foreground;
  bool _disconnecting = false;

  /// 当前租约到期时刻（无活动租约时为 null）。供调试与测试断言。
  DateTime? get deadline => _deadline;

  /// Starts or refreshes the lease after a successful BLE interaction.
  void noteActivity({bool afterTransfer = false}) {
    if (!_isConnected()) {
      linkEnded();
      return;
    }
    if (_isBusy()) {
      _cancelTimers(clearDeadline: true);
      return;
    }
    _schedule(afterTransfer: afterTransfer);
  }

  /// Pauses idle release while a user-visible BLE task is running.
  void taskStarted() => _cancelTimers(clearDeadline: true);

  /// Restarts the appropriate grace period after the protected task ends.
  void taskFinished({bool afterTransfer = true}) {
    noteActivity(afterTransfer: afterTransfer);
  }

  /// Applies the phase-specific lease without relying on a timer firing
  /// while the app is suspended. On resume, an elapsed deadline is checked
  /// against wall-clock time before a new lease is granted.
  Future<void> setPhase(BleLeasePhase phase) async {
    final previous = _phase;
    _phase = phase;

    if (!_isConnected()) {
      linkEnded();
      return;
    }
    if (_isBusy()) {
      _cancelTimers(clearDeadline: true);
      return;
    }

    // ① 先按墙钟复核旧租约——不分相位、也不管相位是否变化（见类注释漏洞 1）。
    final deadline = _deadline;
    if (deadline != null && !_now().isBefore(deadline)) {
      await _expire();
      return;
    }
    // ② 相位没有真正变化就不重新计时（见类注释漏洞 2）。既有的定时器继续走，
    //    只补一下巡检，保证恢复后仍有墙钟兜底。没有活动租约时不要凭空起巡检
    //    ——那是个没有东西可查的空定时器（在 widget 测试里还会变成 pending timer）。
    if (previous == phase) {
      if (_deadline != null) {
        _ensureSweep();
      }
      return;
    }
    _schedule(afterTransfer: false);
  }

  /// Cancels all lease state when the physical link has already ended.
  void linkEnded() => _cancelTimers(clearDeadline: true);

  /// Releases the connection immediately for explicit session-ending events
  /// such as logout, account deletion, or app detachment.
  Future<void> disconnectNow() async {
    _cancelTimers(clearDeadline: true);
    if (!_isConnected() || _disconnecting) {
      return;
    }
    _disconnecting = true;
    try {
      await _disconnect();
    } finally {
      _disconnecting = false;
    }
  }

  void dispose() => _cancelTimers(clearDeadline: true);

  Duration _timeout({required bool afterTransfer}) {
    switch (_phase) {
      case BleLeasePhase.background:
        return backgroundGracePeriod;
      case BleLeasePhase.screenOff:
        return screenOffGracePeriod;
      case BleLeasePhase.foreground:
        return afterTransfer ? postTransferGracePeriod : foregroundIdleTimeout;
    }
  }

  void _schedule({required bool afterTransfer}) {
    _timer?.cancel();
    final timeout = _timeout(afterTransfer: afterTransfer);
    _deadline = _now().add(timeout);
    _timer = Timer(timeout, () => unawaited(_expire()));
    _ensureSweep();
  }

  /// 墙钟巡检：只在存在活动租约时运行，[_cancelTimers] 会一并停掉。
  void _ensureSweep() {
    _sweepTimer ??= Timer.periodic(
      _sweepInterval,
      (_) => unawaited(_expire()),
    );
  }

  Future<void> _expire() async {
    if (_disconnecting) {
      return;
    }
    if (!_isConnected()) {
      _cancelTimers(clearDeadline: true);
      return;
    }
    if (_isBusy()) {
      _cancelTimers(clearDeadline: true);
      return;
    }

    final deadline = _deadline;
    if (deadline == null) {
      _cancelTimers(clearDeadline: true);
      return;
    }
    final now = _now();
    if (now.isBefore(deadline)) {
      // 还没到点（巡检打进来，或一次性定时器被系统提前唤醒）：把定时器对准
      // 剩余时长后继续等。
      _timer?.cancel();
      _timer = Timer(deadline.difference(now), () => unawaited(_expire()));
      _ensureSweep();
      return;
    }

    _cancelTimers(clearDeadline: true);
    _disconnecting = true;
    try {
      await _disconnect();
    } catch (_) {
      // 断开失败不能让异常逃出去：本方法的两个调用点都是 `unawaited(_expire())`
      // （定时器与巡检），抛出去就是一个没人接的异步错误，会被
      // PlatformDispatcher.onError 当成崩溃写进 last_crash.txt。
      // 下面的复核会给还活着的链路重新起一轮租约，等下次到期再试。
    } finally {
      _disconnecting = false;
      // 断开期间可能又发生过活动（noteActivity 在 _disconnecting 时是空转的），
      // 或者 _disconnect 失败、链路其实还在。再复核一次，避免留下一个
      // 「有连接却没有任何定时器」的状态——那正是「永远不会被回收」的样子。
      if (_isConnected() && _deadline == null) {
        noteActivity();
      }
    }
  }

  void _cancelTimers({required bool clearDeadline}) {
    _timer?.cancel();
    _timer = null;
    _sweepTimer?.cancel();
    _sweepTimer = null;
    if (clearDeadline) {
      _deadline = null;
    }
  }
}
