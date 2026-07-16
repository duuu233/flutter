enum FrameScreenType { inch37, inch589, inch73 }

enum FramePlaybackMode { sequence, random, manual }

enum FrameImageFormat { sixColorRaw, rleCompressed }

enum FrameProtocolResultCode {
  success,
  parameterError,
  lengthError,
  crcError,
  flashWriteFailed,
  imageMissing,
  storageFull,
  maskMismatch,
  unsupportedCommand,
  transferInterrupted,
  checksumFailed,
  busy,
}

class FrameProtocolConfig {
  const FrameProtocolConfig._();

  // TODO(hardware): confirm whether these are complete 16-bit UUIDs or
  // project-specific 128-bit UUIDs before wiring the real BLE plugin.
  static const businessServiceUuid = '0xFF00';
  static const commandCharacteristicUuid = '0xFF01';
  static const notifyCharacteristicUuid = '0xFF02';

  static const otaServiceUuid = '0xFF10';
  static const otaDataCharacteristicUuid = '0xFF11';
  static const otaDebugCharacteristicUuid = '0xFF12';

  static const frameHeader = 0xAA;
  static const maxImages = 32;
  static const mtu = 247;
  static const gattPayloadBytes = 244;
  static const dataBytesPerPacket = 238;
  static const transferWindowSize = 5;
  static const ackTimeout = Duration(seconds: 1);
  // 未从真机读到间隔时的兜底=2h，对齐小程序 slideshow.js/detail.js 的 intervalHours 默认(2h)。
  // 正常路径连接后会用真机上报的 intervalSeconds 覆盖，兜底仅在从未读到时命中。
  static const defaultCarouselIntervalSeconds = 2 * 60 * 60;
}

class FrameCommand {
  const FrameCommand._();

  static const getDeviceInfo = 0x01;
  static const getPlaybackConfig = 0x02;
  static const getSoftwareVersion = 0x03;
  static const getBatteryInfo = 0x04;
  static const setPlaybackConfig = 0x10;
  static const setSystemTime = 0x11;
  static const deleteImage = 0x12;
  static const startTransfer = 0x20;
  static const transferData = 0x21;
  static const finishTransfer = 0x22;
  static const transferAck = 0x23;
  static const refreshScreen = 0x24;
  static const genericAck = 0x7F;
}

class FrameDeviceInfoSnapshot {
  const FrameDeviceInfoSnapshot({
    required this.deviceId,
    required this.hardwareVersion,
    required this.firmwareVersion,
    required this.imageMask,
    required this.batteryLevel,
    required this.charging,
    required this.playbackMode,
    required this.intervalSeconds,
    required this.screenType,
    required this.currentImageIndex,
  });

  final String deviceId;
  final String hardwareVersion;
  final String firmwareVersion;
  final int imageMask;
  final int batteryLevel;
  final bool charging;
  final FramePlaybackMode playbackMode;
  final int intervalSeconds;
  final FrameScreenType screenType;
  final int currentImageIndex;

  int get imageCount => FrameDeviceProtocol.countImages(imageMask);

  int get storageFreeBytes =>
      FrameDeviceProtocol.estimateStorageFreeBytes(imageMask, screenType);
}

class FrameImageTransferPlan {
  const FrameImageTransferPlan({
    required this.imageIndex,
    required this.sourceWidth,
    required this.sourceHeight,
    required this.targetWidth,
    required this.targetHeight,
    required this.format,
    required this.dataSize,
    required this.crc32,
  });

  final int imageIndex;
  final int sourceWidth;
  final int sourceHeight;
  final int targetWidth;
  final int targetHeight;
  final FrameImageFormat format;
  final int dataSize;
  final int crc32;

  int get packetCount =>
      (dataSize + FrameProtocolConfig.dataBytesPerPacket - 1) ~/
      FrameProtocolConfig.dataBytesPerPacket;
}

class FrameImageTransferResult {
  const FrameImageTransferResult({
    required this.resultCode,
    required this.imageMask,
    required this.imageCount,
    required this.currentImageIndex,
    required this.storageFreeBytes,
  });

  final FrameProtocolResultCode resultCode;
  final int imageMask;
  final int imageCount;
  final int currentImageIndex;
  final int storageFreeBytes;

  bool get success => resultCode == FrameProtocolResultCode.success;
}

extension FrameScreenTypeDetails on FrameScreenType {
  int get code {
    switch (this) {
      case FrameScreenType.inch37:
        return 0x01;
      case FrameScreenType.inch589:
        return 0x02;
      case FrameScreenType.inch73:
        return 0x03;
    }
  }

  String get label {
    switch (this) {
      case FrameScreenType.inch37:
        return '3.7 inch';
      case FrameScreenType.inch589:
        return '5.89 inch';
      case FrameScreenType.inch73:
        return '7.3 inch';
    }
  }

  int get width {
    switch (this) {
      case FrameScreenType.inch37:
        return 416;
      case FrameScreenType.inch589:
        return 600;
      case FrameScreenType.inch73:
        return 800;
    }
  }

  int get height {
    switch (this) {
      case FrameScreenType.inch37:
        return 240;
      case FrameScreenType.inch589:
        return 448;
      case FrameScreenType.inch73:
        return 480;
    }
  }

  int get frameBufferBytes {
    switch (this) {
      case FrameScreenType.inch37:
        return 48832;
      case FrameScreenType.inch589:
        return 131300;
      case FrameScreenType.inch73:
        return 187500;
    }
  }
}

extension FramePlaybackModeDetails on FramePlaybackMode {
  int get code {
    switch (this) {
      case FramePlaybackMode.sequence:
        return 0x00;
      case FramePlaybackMode.random:
        return 0x01;
      case FramePlaybackMode.manual:
        return 0x02;
    }
  }

  String get labelZh {
    switch (this) {
      case FramePlaybackMode.sequence:
        return '顺序轮播';
      case FramePlaybackMode.random:
        return '随机轮播';
      case FramePlaybackMode.manual:
        return '单张显示';
    }
  }
}

extension FrameImageFormatDetails on FrameImageFormat {
  int get code {
    switch (this) {
      case FrameImageFormat.sixColorRaw:
        return 0x01;
      case FrameImageFormat.rleCompressed:
        return 0x02;
    }
  }

  String get labelZh {
    switch (this) {
      case FrameImageFormat.sixColorRaw:
        return '六色原始帧缓存';
      case FrameImageFormat.rleCompressed:
        return 'RLE 压缩';
    }
  }
}

extension FrameProtocolResultDetails on FrameProtocolResultCode {
  int get code {
    switch (this) {
      case FrameProtocolResultCode.success:
        return 0x00;
      case FrameProtocolResultCode.parameterError:
        return 0x01;
      case FrameProtocolResultCode.lengthError:
        return 0x02;
      case FrameProtocolResultCode.crcError:
        return 0x03;
      case FrameProtocolResultCode.flashWriteFailed:
        return 0x04;
      case FrameProtocolResultCode.imageMissing:
        return 0x05;
      case FrameProtocolResultCode.storageFull:
        return 0x06;
      case FrameProtocolResultCode.maskMismatch:
        return 0x07;
      case FrameProtocolResultCode.unsupportedCommand:
        return 0x08;
      case FrameProtocolResultCode.transferInterrupted:
        return 0x09;
      case FrameProtocolResultCode.checksumFailed:
        return 0x0A;
      case FrameProtocolResultCode.busy:
        return 0x0B;
    }
  }

  String get labelZh {
    switch (this) {
      case FrameProtocolResultCode.success:
        return '成功';
      case FrameProtocolResultCode.parameterError:
        return '参数错误';
      case FrameProtocolResultCode.lengthError:
        return '长度错误';
      case FrameProtocolResultCode.crcError:
        return 'CRC 错误';
      case FrameProtocolResultCode.flashWriteFailed:
        return 'Flash 写入失败';
      case FrameProtocolResultCode.imageMissing:
        return '图片不存在';
      case FrameProtocolResultCode.storageFull:
        return '存储空间不足';
      case FrameProtocolResultCode.maskMismatch:
        return '掩码不一致';
      case FrameProtocolResultCode.unsupportedCommand:
        return '不支持的命令';
      case FrameProtocolResultCode.transferInterrupted:
        return '传输中断';
      case FrameProtocolResultCode.checksumFailed:
        return '校验失败';
      case FrameProtocolResultCode.busy:
        return '设备忙';
    }
  }

  /// 英文档位（供 en 语言的用户文案；此前 EN/JA 句子里拼的是 labelZh，英文夹中文词）。
  String get labelEn {
    switch (this) {
      case FrameProtocolResultCode.success:
        return 'Success';
      case FrameProtocolResultCode.parameterError:
        return 'Parameter error';
      case FrameProtocolResultCode.lengthError:
        return 'Length error';
      case FrameProtocolResultCode.crcError:
        return 'CRC error';
      case FrameProtocolResultCode.flashWriteFailed:
        return 'Flash write failed';
      case FrameProtocolResultCode.imageMissing:
        return 'Image missing';
      case FrameProtocolResultCode.storageFull:
        return 'Storage full';
      case FrameProtocolResultCode.maskMismatch:
        return 'Mask mismatch';
      case FrameProtocolResultCode.unsupportedCommand:
        return 'Unsupported command';
      case FrameProtocolResultCode.transferInterrupted:
        return 'Transfer interrupted';
      case FrameProtocolResultCode.checksumFailed:
        return 'Checksum failed';
      case FrameProtocolResultCode.busy:
        return 'Device busy';
    }
  }

  /// 日文档位。
  String get labelJa {
    switch (this) {
      case FrameProtocolResultCode.success:
        return '成功';
      case FrameProtocolResultCode.parameterError:
        return 'パラメータエラー';
      case FrameProtocolResultCode.lengthError:
        return '長さエラー';
      case FrameProtocolResultCode.crcError:
        return 'CRCエラー';
      case FrameProtocolResultCode.flashWriteFailed:
        return 'Flash書き込み失敗';
      case FrameProtocolResultCode.imageMissing:
        return '画像がありません';
      case FrameProtocolResultCode.storageFull:
        return '空き容量不足';
      case FrameProtocolResultCode.maskMismatch:
        return 'マスク不一致';
      case FrameProtocolResultCode.unsupportedCommand:
        return '未対応のコマンド';
      case FrameProtocolResultCode.transferInterrupted:
        return '転送中断';
      case FrameProtocolResultCode.checksumFailed:
        return 'チェックサム失敗';
      case FrameProtocolResultCode.busy:
        return 'デバイスビジー';
    }
  }
}

class FrameDeviceProtocol {
  const FrameDeviceProtocol._();

  static int normalizeMask(int mask) => mask & 0xFFFFFFFF;

  static int bitForIndex(int imageIndex) {
    if (imageIndex < 0 || imageIndex >= FrameProtocolConfig.maxImages) {
      throw RangeError.range(
        imageIndex,
        0,
        FrameProtocolConfig.maxImages - 1,
        'imageIndex',
      );
    }
    return 1 << imageIndex;
  }

  static bool hasImage(int imageMask, int imageIndex) {
    return (normalizeMask(imageMask) & bitForIndex(imageIndex)) != 0;
  }

  static int countImages(int imageMask) {
    var mask = normalizeMask(imageMask);
    var count = 0;
    while (mask != 0) {
      count += mask & 1;
      mask >>= 1;
    }
    return count;
  }

  static int? firstFreeIndex(int imageMask) {
    final mask = normalizeMask(imageMask);
    for (var index = 0; index < FrameProtocolConfig.maxImages; index += 1) {
      if ((mask & (1 << index)) == 0) {
        return index;
      }
    }
    return null;
  }

  static int setImageBit(int imageMask, int imageIndex) {
    return normalizeMask(imageMask | bitForIndex(imageIndex));
  }

  static int clearImageMask(int imageMask, int deleteMask) {
    return normalizeMask(imageMask & ~deleteMask);
  }

  static String maskHex(int imageMask) {
    return '0x${normalizeMask(imageMask).toRadixString(16).padLeft(8, '0').toUpperCase()}';
  }

  static int estimateStorageFreeBytes(
    int imageMask,
    FrameScreenType screenType,
  ) {
    final freeSlots = FrameProtocolConfig.maxImages - countImages(imageMask);
    return freeSlots * screenType.frameBufferBytes;
  }

  static FrameDeviceInfoSnapshot readDeviceInfo({
    required String deviceId,
    required String hardwareVersion,
    required String firmwareVersion,
    required int imageMask,
    required int batteryLevel,
    required bool charging,
    required FramePlaybackMode playbackMode,
    required int intervalSeconds,
    required FrameScreenType screenType,
    required int currentImageIndex,
  }) {
    return FrameDeviceInfoSnapshot(
      deviceId: deviceId,
      hardwareVersion: hardwareVersion,
      firmwareVersion: firmwareVersion,
      imageMask: normalizeMask(imageMask),
      batteryLevel: batteryLevel.clamp(0, 100),
      charging: charging,
      playbackMode: playbackMode,
      intervalSeconds: intervalSeconds,
      screenType: screenType,
      currentImageIndex: currentImageIndex,
    );
  }

  static FrameImageTransferPlan buildTransferPlan({
    required int imageIndex,
    required double sourceWidth,
    required double sourceHeight,
    required FrameScreenType screenType,
    FrameImageFormat format = FrameImageFormat.sixColorRaw,
  }) {
    final dataSize = screenType.frameBufferBytes;
    return FrameImageTransferPlan(
      imageIndex: imageIndex,
      sourceWidth: sourceWidth.round(),
      sourceHeight: sourceHeight.round(),
      targetWidth: screenType.width,
      targetHeight: screenType.height,
      format: format,
      dataSize: dataSize,
      crc32: _pseudoCrc32(
        imageIndex: imageIndex,
        sourceWidth: sourceWidth.round(),
        sourceHeight: sourceHeight.round(),
        targetWidth: screenType.width,
        targetHeight: screenType.height,
        dataSize: dataSize,
      ),
    );
  }

  static FrameImageTransferResult simulateImageTransfer({
    required int imageMask,
    required FrameScreenType screenType,
    required FrameImageTransferPlan plan,
  }) {
    if (plan.imageIndex < 0 ||
        plan.imageIndex >= FrameProtocolConfig.maxImages) {
      return _transferResult(
        resultCode: FrameProtocolResultCode.parameterError,
        imageMask: imageMask,
        screenType: screenType,
        currentImageIndex: -1,
      );
    }
    if (hasImage(imageMask, plan.imageIndex)) {
      return _transferResult(
        resultCode: FrameProtocolResultCode.maskMismatch,
        imageMask: imageMask,
        screenType: screenType,
        currentImageIndex: plan.imageIndex,
      );
    }
    if (firstFreeIndex(imageMask) == null) {
      return _transferResult(
        resultCode: FrameProtocolResultCode.storageFull,
        imageMask: imageMask,
        screenType: screenType,
        currentImageIndex: -1,
      );
    }
    final nextMask = setImageBit(imageMask, plan.imageIndex);
    return _transferResult(
      resultCode: FrameProtocolResultCode.success,
      imageMask: nextMask,
      screenType: screenType,
      currentImageIndex: plan.imageIndex,
    );
  }

  static FrameImageTransferResult simulateDeleteImages({
    required int imageMask,
    required int deleteMask,
    required FrameScreenType screenType,
    required int currentImageIndex,
  }) {
    final normalizedDeleteMask = normalizeMask(deleteMask);
    if (normalizedDeleteMask == 0) {
      return _transferResult(
        resultCode: FrameProtocolResultCode.parameterError,
        imageMask: imageMask,
        screenType: screenType,
        currentImageIndex: currentImageIndex,
      );
    }
    if ((normalizeMask(imageMask) & normalizedDeleteMask) !=
        normalizedDeleteMask) {
      return _transferResult(
        resultCode: FrameProtocolResultCode.imageMissing,
        imageMask: imageMask,
        screenType: screenType,
        currentImageIndex: currentImageIndex,
      );
    }
    final nextMask = clearImageMask(imageMask, normalizedDeleteMask);
    final deletedCurrent =
        currentImageIndex >= 0 &&
        (normalizedDeleteMask & bitForIndex(currentImageIndex)) != 0;
    return _transferResult(
      resultCode: FrameProtocolResultCode.success,
      imageMask: nextMask,
      screenType: screenType,
      currentImageIndex: deletedCurrent
          ? _firstExistingIndex(nextMask)
          : currentImageIndex,
    );
  }

  static FrameImageTransferResult _transferResult({
    required FrameProtocolResultCode resultCode,
    required int imageMask,
    required FrameScreenType screenType,
    required int currentImageIndex,
  }) {
    final normalizedMask = normalizeMask(imageMask);
    return FrameImageTransferResult(
      resultCode: resultCode,
      imageMask: normalizedMask,
      imageCount: countImages(normalizedMask),
      currentImageIndex: currentImageIndex,
      storageFreeBytes: estimateStorageFreeBytes(normalizedMask, screenType),
    );
  }

  static int _firstExistingIndex(int imageMask) {
    final normalizedMask = normalizeMask(imageMask);
    for (var index = 0; index < FrameProtocolConfig.maxImages; index += 1) {
      if ((normalizedMask & (1 << index)) != 0) {
        return index;
      }
    }
    return -1;
  }

  // Placeholder until hardware confirms the exact image bytes and CRC32-MPEG2
  // parameters. It is deterministic so app-side records can be tested now.
  static int _pseudoCrc32({
    required int imageIndex,
    required int sourceWidth,
    required int sourceHeight,
    required int targetWidth,
    required int targetHeight,
    required int dataSize,
  }) {
    var value = 0xFFFFFFFF;
    for (final item in <int>[
      imageIndex,
      sourceWidth,
      sourceHeight,
      targetWidth,
      targetHeight,
      dataSize,
    ]) {
      value ^= item & 0xFFFFFFFF;
      value = ((value << 5) | (value >> 27)) & 0xFFFFFFFF;
    }
    return value;
  }
}
