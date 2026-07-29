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
}
