import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:BoltStar/src/device/ble/ota_ble.dart';

/// 升级包本地预检与面板换算（[inspectOtaHeader] / [otaPanelOfDevice]，规格书 §6.3.4 字段表）。
///
/// 2026-08-11 真机踩坑后补：刷错固件不可逆，「传错文件 / 下载截断 / 刷错面板」必须在
/// 发第一帧之前就本地拦住，而不是刷到设备上再等它回错误码。
/// 与小程序 `tests/ota-dfu-transfer.test.js` 的第 ⑨⑩ 组用例同源，两端口径必须一致。
///
/// ⚠️ CRC16 / CRC32 **不做本地拦截**：规格书没写这两个校验的多项式口径，本地算法与固件
/// 不一致时误拦会把好包挡在门外；这两项本就由设备校验（0x0D / 0x09）。
void main() {
  const headerSize = 128;

  /// 按 §6.3.4 字段表拼一个合法的 128 字节头信息 + payload。
  Uint8List buildPackage(
    int payloadSize, {
    String magic = 'OTAINFO',
    int panel = 2,
    int? headerLength,
    int? binSize,
    String version = 'BR1601A02_260702_r8285_5139_5D89_V100',
  }) {
    final file = Uint8List(headerSize + payloadSize);
    for (int i = 0; i < magic.length && i < 7; i++) {
      file[i] = magic.codeUnitAt(i);
    }
    file[7] = 0x00;
    file[8] = 1; // 头部格式版本
    file[9] = panel; // 1=3D7 / 2=5D89
    final hl = headerLength ?? headerSize;
    file[10] = hl & 0xFF;
    file[11] = (hl >> 8) & 0xFF;
    final bs = binSize ?? payloadSize;
    file[12] = bs & 0xFF;
    file[13] = (bs >> 8) & 0xFF;
    file[14] = (bs >> 16) & 0xFF;
    file[15] = (bs >> 24) & 0xFF;
    file[20] = version.length & 0xFF;
    file[21] = (version.length >> 8) & 0xFF;
    for (int i = 0; i < version.length; i++) {
      file[24 + i] = version.codeUnitAt(i);
    }
    return file;
  }

  test('合法包：字段逐个解出来', () {
    final header = inspectOtaHeader(buildPackage(4096));

    expect(header.magicOk, isTrue);
    expect(header.headerVersion, 1);
    expect(header.panel, 2);
    expect(header.headerLength, headerSize);
    expect(header.binSize, 4096);
    expect(header.version, 'BR1601A02_260702_r8285_5139_5D89_V100');
  });

  test('不是 OTA 包（缺 OTAINFO 标识）——最典型的「传错文件」', () {
    final header = inspectOtaHeader(buildPackage(4096, magic: ''));
    expect(header.magicOk, isFalse);
  });

  test('下载截断：头信息声明的 bin 大小与实际文件对不上', () {
    final header = inspectOtaHeader(buildPackage(4096, binSize: 4096 + 512));
    // 预检据此拦截：声明 4608、实际 4096
    expect(header.binSize, 4608);
    expect(header.magicOk, isTrue);
  });

  test('面板换算：screenCode 与分辨率两条路都要认，判不出返回 0', () {
    expect(otaPanelOfDevice(screenCode: 2), 2);
    expect(otaPanelOfDevice(width: 680, height: 960), 2);
    expect(otaPanelOfDevice(width: 960, height: 680), 2, reason: '横竖屏不影响');
    expect(otaPanelOfDevice(width: 480, height: 720), 1);
    expect(otaPanelOfDevice(), 0, reason: '判不出必须返回 0，不参与拦截');
  });

  test('结果码文案：0x05 是设备状态、0x0A~0x0E 才是包的问题', () {
    // 故障归属就靠这条分界：出现 0x0A~0x0E 查包，出现 0x05 或不应答查设备状态。
    expect(otaResultText(0x05), contains('状态'));
    expect(otaResultText(0x0A), contains('非 OTA 包'));
    expect(otaResultText(0x0C), contains('面板'));
    expect(otaResultText(0x09), '参数错误');
  });

  test('OtaException 分类：只有这两类允许断链复位后整轮重来', () {
    expect(
      OtaException('x', kind: OtaFailureKind.startRejectedBusy).isWedgedSession,
      isTrue,
    );
    expect(
      OtaException('x', kind: OtaFailureKind.headerStuck).isWedgedSession,
      isTrue,
    );
    expect(OtaException('x').isWedgedSession, isFalse);
    expect(OtaAbortedException().isWedgedSession, isFalse);
  });
}
