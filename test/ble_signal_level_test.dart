import 'package:flutter_test/flutter_test.dart';

import 'package:BoltStar/src/device/ble_controller.dart';

void main() {
  group('BleController.rssiToSignalLevel', () {
    test('keeps invalid RSSI unknown', () {
      expect(BleController.rssiToSignalLevel(0), isNull);
      expect(BleController.rssiToSignalLevel(1), isNull);
    });

    test('uses the conservative one-level-lower display scale', () {
      expect(BleController.rssiToSignalLevel(-40), BleSignalLevel.strong);
      expect(BleController.rssiToSignalLevel(-55), BleSignalLevel.strong);
      expect(BleController.rssiToSignalLevel(-56), BleSignalLevel.normal);
      expect(BleController.rssiToSignalLevel(-67), BleSignalLevel.normal);
      expect(BleController.rssiToSignalLevel(-68), BleSignalLevel.weak);
      expect(BleController.rssiToSignalLevel(-78), BleSignalLevel.weak);
      expect(BleController.rssiToSignalLevel(-79), BleSignalLevel.veryWeak);
      expect(BleController.rssiToSignalLevel(-100), BleSignalLevel.veryWeak);
    });
  });

  // 「弱信号不抢第一帧」闸门：命中即停扫会在刚擦边收到第一帧时就发起连接，
  // 而那一帧往往是整个窗口里信号最差的时刻。这里锁住三条底线：
  // 够强立刻连、读不到 RSSI 按原行为连、等满窗口无论多弱都必须连。
  group('BleController.shouldConnectAtRssi', () {
    test('信号够强：不等，立刻连', () {
      expect(BleController.shouldConnectAtRssi(-40, Duration.zero), isTrue);
      expect(
        BleController.shouldConnectAtRssi(
          BleController.weakSignalRssi,
          Duration.zero,
        ),
        isTrue,
      );
    });

    test('机型不上报 RSSI(0)：无从判断，按原行为立刻连', () {
      expect(BleController.shouldConnectAtRssi(0, Duration.zero), isTrue);
    });

    test('信号偏弱：先等更强的一帧', () {
      expect(
        BleController.shouldConnectAtRssi(
          BleController.weakSignalRssi - 1,
          Duration.zero,
        ),
        isFalse,
      );
      expect(
        BleController.shouldConnectAtRssi(
          -90,
          BleController.weakSignalWait - const Duration(milliseconds: 1),
        ),
        isFalse,
      );
    });

    test('等满窗口：再弱也照常连，绝不因信号弱阻断用户', () {
      expect(
        BleController.shouldConnectAtRssi(-95, BleController.weakSignalWait),
        isTrue,
      );
      expect(
        BleController.shouldConnectAtRssi(-95, const Duration(seconds: 5)),
        isTrue,
      );
    });

    test('连接阈值用原始 RSSI，与保守下调过的展示档位互不牵连', () {
      // -68dBm 展示为「弱」，但对建连来说够强：不该被拦下来等。
      expect(BleController.rssiToSignalLevel(-68), BleSignalLevel.weak);
      expect(BleController.shouldConnectAtRssi(-68, Duration.zero), isTrue);
    });
  });
}
