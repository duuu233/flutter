import '../../device/ble/device_ble.dart';
import '../../device/ble/frame_protocol.dart';
import '../../device/serial_match.dart';

/// 本次投屏实际使用的设备参数：尺寸来自设备列表记录（或旧型号表），型号与掩码来自 0x01。
class ProjectionTransferInfo {
  const ProjectionTransferInfo({
    required this.width,
    required this.height,
    required this.capacity,
    required this.slotLimit,
    required this.fromDeviceList,
  });

  final int width;
  final int height;

  /// 已知的设备图片容量；新尺寸未知时为 0，不虚构张数。
  final int capacity;

  /// 选空闲槽位的上限：已知容量，否则 12 字节 IMG_MASK 可寻址的槽位数（最多 96）。
  /// ⚠️ 它不是设备实际存储容量，存储不足仍以固件拒绝为准。
  final int slotLimit;

  /// true = 尺寸取自设备列表记录；false = 记录没下发宽高，兼容旧的 0x01 型号表。
  final bool fromDeviceList;
}

/// 投屏尺寸取设备列表记录；0x01 只提供固件型号/身份/图片掩码（2026-10-22 同步小程序
/// `utils/projection-device.js resolveTransferInfo`，两端逐条对齐）。
///
/// 旧实现只认 0x01 型号表，EB-169 这类新尺寸（400×400）读出 0×0，被当成「未连接」报给用户。
/// 现在尺寸、型号、身份问题各报各的原因，不再统一说成未连接（kind 均为 [FrameBleErrorKind.unsupported]）。
ProjectionTransferInfo resolveProjectionTransfer({
  required String expectedSerial,
  required FrameDeviceInfo info,
  int deviceWidth = 0,
  int deviceHeight = 0,
  int? shapeType,
}) {
  // 尺寸来自哪条后台记录，必须由刚读回的完整硬件 ID 确认；临时 BLE 句柄和广播名不能证明身份。
  final expected = canonicalDeviceSerial(expectedSerial);
  final actual = canonicalDeviceSerial(info.deviceId);
  if (actual.isEmpty || actual != expected) {
    throw FrameBleException(
      '所选电子纸设备与连接电子纸设备ID不一致，请重新连接后重试',
      kind: FrameBleErrorKind.unsupported,
    );
  }
  if (info.screenType < 0 || info.screenType > 0xFF) {
    throw FrameBleException(
      '电子纸设备返回的屏幕型号无效，请检查设备协议',
      kind: FrameBleErrorKind.unsupported,
    );
  }
  final fromDeviceList = deviceWidth > 0 || deviceHeight > 0;
  final width = fromDeviceList ? deviceWidth : info.width;
  final height = fromDeviceList ? deviceHeight : info.height;
  bool valid(int value) => value > 0 && value <= 0xFFFF;
  if (!valid(width) || !valid(height)) {
    throw FrameBleException(
      '电子纸设备分辨率未配置或无效，请检查设备信息后重试',
      kind: FrameBleErrorKind.unsupported,
    );
  }
  if (shapeType == 1 && width != height) {
    throw FrameBleException(
      '圆形电子纸设备分辨率须为正方形，请检查设备配置',
      kind: FrameBleErrorKind.unsupported,
    );
  }
  // 12 字节 IMG_MASK 最多表达 96 个槽位，不把这个上限宣称为设备实际存储容量。
  final maskSlots = info.imgMask.length * 8;
  final maskSlotLimit = maskSlots < 96 ? maskSlots : 96;
  if (maskSlotLimit == 0) {
    throw FrameBleException(
      '电子纸设备图片槽位信息无效，请重新读取设备信息',
      kind: FrameBleErrorKind.unsupported,
    );
  }
  bool sameSize(int w, int h) =>
      (w == width && h == height) || (w == height && h == width);
  int legacyCapacity() {
    for (final screen in FrameProtocol.screenTypes.values) {
      if (screen.width > 0 &&
          screen.height > 0 &&
          sameSize(screen.width, screen.height)) {
        return screen.capacity;
      }
    }
    return 0;
  }

  final known = sameSize(info.width, info.height) && info.capacity > 0
      ? info.capacity
      : legacyCapacity();
  final capacity = known < maskSlotLimit ? known : maskSlotLimit;
  return ProjectionTransferInfo(
    width: width,
    height: height,
    capacity: capacity,
    slotLimit: capacity > 0 ? capacity : maskSlotLimit,
    fromDeviceList: fromDeviceList,
  );
}
