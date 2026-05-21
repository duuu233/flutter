import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_application_2/src/device/frame_device_protocol.dart';

void main() {
  test('finds free slot and updates image mask after transfer', () {
    const initialMask = 0x00000003;
    final imageIndex = FrameDeviceProtocol.firstFreeIndex(initialMask);

    expect(imageIndex, 2);

    final plan = FrameDeviceProtocol.buildTransferPlan(
      imageIndex: imageIndex!,
      sourceWidth: 3024,
      sourceHeight: 4032,
      screenType: FrameScreenType.inch589,
    );
    final result = FrameDeviceProtocol.simulateImageTransfer(
      imageMask: initialMask,
      screenType: FrameScreenType.inch589,
      plan: plan,
    );

    expect(result.success, isTrue);
    expect(result.imageMask, 0x00000007);
    expect(result.currentImageIndex, 2);
    expect(plan.targetWidth, 600);
    expect(plan.targetHeight, 448);
    expect(plan.packetCount, greaterThan(0));
  });

  test('delete command clears requested mask bits', () {
    final result = FrameDeviceProtocol.simulateDeleteImages(
      imageMask: 0x00000007,
      deleteMask: FrameDeviceProtocol.bitForIndex(0) |
          FrameDeviceProtocol.bitForIndex(2),
      screenType: FrameScreenType.inch73,
      currentImageIndex: 2,
    );

    expect(result.success, isTrue);
    expect(result.imageMask, 0x00000002);
    expect(result.currentImageIndex, 1);
  });

  test('full image mask rejects new transfer', () {
    final plan = FrameDeviceProtocol.buildTransferPlan(
      imageIndex: 0,
      sourceWidth: 2400,
      sourceHeight: 3200,
      screenType: FrameScreenType.inch37,
    );
    final result = FrameDeviceProtocol.simulateImageTransfer(
      imageMask: 0xFFFFFFFF,
      screenType: FrameScreenType.inch37,
      plan: plan,
    );

    expect(result.success, isFalse);
    expect(result.resultCode, FrameProtocolResultCode.maskMismatch);
  });
}
