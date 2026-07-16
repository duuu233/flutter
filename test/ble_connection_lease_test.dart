import 'package:BoltStar/src/device/ble_connection_lease.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('disconnects after foreground idle timeout', () async {
    var connected = true;
    var disconnects = 0;
    final lease = BleConnectionLease(
      isConnected: () => connected,
      isBusy: () => false,
      disconnect: () async {
        disconnects++;
        connected = false;
      },
      foregroundIdleTimeout: const Duration(milliseconds: 20),
    );
    addTearDown(lease.dispose);

    lease.noteActivity();
    await Future<void>.delayed(const Duration(milliseconds: 80));

    expect(disconnects, 1);
  });

  test('BLE activity refreshes the foreground lease', () async {
    var connected = true;
    var disconnects = 0;
    final lease = BleConnectionLease(
      isConnected: () => connected,
      isBusy: () => false,
      disconnect: () async {
        disconnects++;
        connected = false;
      },
      foregroundIdleTimeout: const Duration(milliseconds: 60),
    );
    addTearDown(lease.dispose);

    lease.noteActivity();
    await Future<void>.delayed(const Duration(milliseconds: 35));
    lease.noteActivity();
    await Future<void>.delayed(const Duration(milliseconds: 35));
    expect(disconnects, 0);

    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(disconnects, 1);
  });

  test('background uses the shorter grace period', () async {
    var connected = true;
    var disconnects = 0;
    final lease = BleConnectionLease(
      isConnected: () => connected,
      isBusy: () => false,
      disconnect: () async {
        disconnects++;
        connected = false;
      },
      foregroundIdleTimeout: const Duration(seconds: 1),
      backgroundGracePeriod: const Duration(milliseconds: 20),
    );
    addTearDown(lease.dispose);

    lease.noteActivity();
    await lease.setPhase(BleLeasePhase.background);
    await Future<void>.delayed(const Duration(milliseconds: 80));

    expect(disconnects, 1);
  });

  test('screen-off phase uses its own longer grace period', () async {
    var connected = true;
    var disconnects = 0;
    final lease = BleConnectionLease(
      isConnected: () => connected,
      isBusy: () => false,
      disconnect: () async {
        disconnects++;
        connected = false;
      },
      foregroundIdleTimeout: const Duration(seconds: 1),
      backgroundGracePeriod: const Duration(milliseconds: 20),
      screenOffGracePeriod: const Duration(milliseconds: 60),
    );
    addTearDown(lease.dispose);

    lease.noteActivity();
    await lease.setPhase(BleLeasePhase.screenOff);
    // 息屏宽限尚未到期：比 background 的 20ms 长，40ms 时必须仍在连接。
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(disconnects, 0);

    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(disconnects, 1);
  });

  test('active task pauses release and gets post-transfer grace', () async {
    var connected = true;
    var busy = true;
    var disconnects = 0;
    final lease = BleConnectionLease(
      isConnected: () => connected,
      isBusy: () => busy,
      disconnect: () async {
        disconnects++;
        connected = false;
      },
      foregroundIdleTimeout: const Duration(milliseconds: 20),
      postTransferGracePeriod: const Duration(milliseconds: 30),
    );
    addTearDown(lease.dispose);

    lease.taskStarted();
    lease.noteActivity();
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(disconnects, 0);

    busy = false;
    lease.taskFinished();
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(disconnects, 1);
  });

  test(
    'resume checks an elapsed background deadline using wall clock',
    () async {
      var connected = true;
      var disconnects = 0;
      var now = DateTime(2026, 7, 16, 12);
      final lease = BleConnectionLease(
        isConnected: () => connected,
        isBusy: () => false,
        disconnect: () async {
          disconnects++;
          connected = false;
        },
        backgroundGracePeriod: const Duration(minutes: 3),
        now: () => now,
      );
      addTearDown(lease.dispose);

      lease.noteActivity();
      await lease.setPhase(BleLeasePhase.background);
      now = now.add(const Duration(minutes: 4));
      await lease.setPhase(BleLeasePhase.foreground);

      expect(disconnects, 1);
    },
  );
}
