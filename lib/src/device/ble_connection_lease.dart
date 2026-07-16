import 'dart:async';

/// Manages when an existing BLE session may be released.
///
/// This class deliberately knows nothing about scanning, connecting, GATT, or
/// reconnection. It only owns the idle timers around an already established
/// connection so the transport strategy remains unchanged.
class BleConnectionLease {
  BleConnectionLease({
    required bool Function() isConnected,
    required bool Function() isBusy,
    required Future<void> Function() disconnect,
    this.foregroundIdleTimeout = const Duration(minutes: 10),
    this.backgroundGracePeriod = const Duration(minutes: 3),
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
  final Duration postTransferGracePeriod;

  Timer? _timer;
  DateTime? _deadline;
  bool _inBackground = false;
  bool _disconnecting = false;

  /// Starts or refreshes the lease after a successful BLE interaction.
  void noteActivity({bool afterTransfer = false}) {
    if (!_isConnected()) {
      linkEnded();
      return;
    }
    if (_isBusy()) {
      _cancelTimer(clearDeadline: true);
      return;
    }
    _schedule(afterTransfer: afterTransfer);
  }

  /// Pauses idle release while a user-visible BLE task is running.
  void taskStarted() => _cancelTimer(clearDeadline: true);

  /// Restarts the appropriate grace period after the protected task ends.
  void taskFinished({bool afterTransfer = true}) {
    noteActivity(afterTransfer: afterTransfer);
  }

  /// Applies the foreground/background lease without relying on a timer firing
  /// while the app is suspended. On resume, an elapsed background deadline is
  /// checked against wall-clock time before a new foreground lease is granted.
  Future<void> setInBackground(bool value) async {
    if (_inBackground == value) {
      return;
    }
    _inBackground = value;

    if (!_isConnected()) {
      linkEnded();
      return;
    }
    if (_isBusy()) {
      _cancelTimer(clearDeadline: true);
      return;
    }

    final deadline = _deadline;
    if (!value && deadline != null && !_now().isBefore(deadline)) {
      await _expire();
      return;
    }
    _schedule(afterTransfer: false);
  }

  /// Cancels all lease state when the physical link has already ended.
  void linkEnded() => _cancelTimer(clearDeadline: true);

  /// Releases the connection immediately for explicit session-ending events
  /// such as logout, account deletion, or app detachment.
  Future<void> disconnectNow() async {
    _cancelTimer(clearDeadline: true);
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

  void dispose() => _cancelTimer(clearDeadline: true);

  Duration _timeout({required bool afterTransfer}) {
    if (_inBackground) {
      return backgroundGracePeriod;
    }
    return afterTransfer ? postTransferGracePeriod : foregroundIdleTimeout;
  }

  void _schedule({required bool afterTransfer}) {
    _timer?.cancel();
    final timeout = _timeout(afterTransfer: afterTransfer);
    _deadline = _now().add(timeout);
    _timer = Timer(timeout, () => unawaited(_expire()));
  }

  Future<void> _expire() async {
    _timer?.cancel();
    _timer = null;
    if (_disconnecting) {
      return;
    }
    if (!_isConnected()) {
      _deadline = null;
      return;
    }
    if (_isBusy()) {
      _deadline = null;
      return;
    }

    final deadline = _deadline;
    final now = _now();
    if (deadline != null && now.isBefore(deadline)) {
      _timer = Timer(deadline.difference(now), () => unawaited(_expire()));
      return;
    }

    _deadline = null;
    _disconnecting = true;
    try {
      await _disconnect();
    } finally {
      _disconnecting = false;
    }
  }

  void _cancelTimer({required bool clearDeadline}) {
    _timer?.cancel();
    _timer = null;
    if (clearDeadline) {
      _deadline = null;
    }
  }
}
