import 'package:flutter/foundation.dart';

/// Lightweight staged timing for user-triggered device interactions.
///
/// Logs contain only an operation name, an in-process sequence number and
/// elapsed milliseconds. Device identifiers, payloads and account data are
/// deliberately excluded so the output is safe to collect from `adb logcat`.
class DeviceInteractionTrace {
  DeviceInteractionTrace(this.operation)
    : id = (++_nextId).toRadixString(36),
      _total = Stopwatch()..start() {
    _write('start', durationMs: 0, status: 'started');
  }

  static int _nextId = 0;

  final String operation;
  final String id;
  final Stopwatch _total;
  bool _finished = false;

  Future<T> measure<T>(String stage, Future<T> Function() action) async {
    final watch = Stopwatch()..start();
    try {
      final result = await action();
      watch.stop();
      _write(stage, durationMs: watch.elapsedMilliseconds, status: 'ok');
      return result;
    } catch (_) {
      watch.stop();
      _write(stage, durationMs: watch.elapsedMilliseconds, status: 'failed');
      rethrow;
    }
  }

  void mark(String stage, {String status = 'ok'}) {
    _write(stage, durationMs: 0, status: status);
  }

  void finish({required bool success, String stage = 'complete'}) {
    if (_finished) return;
    _finished = true;
    _total.stop();
    _write(
      stage,
      durationMs: _total.elapsedMilliseconds,
      status: success ? 'ok' : 'failed',
    );
  }

  void _write(
    String stage, {
    required int durationMs,
    required String status,
  }) {
    debugPrint(
      '[DeviceInteraction][$operation#$id] stage=$stage status=$status '
      'durationMs=$durationMs totalMs=${_total.elapsedMilliseconds}',
    );
  }
}
