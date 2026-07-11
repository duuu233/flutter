import 'dart:typed_data';

import 'frame_protocol.dart';

/// 设备帧工具（六色 4bpp）。
///
/// ⚠️ 端上「照片六色量化(调色)」已移除：投屏统一走**后端转码** —— 原图传接口，后端按设备宽高
/// 转成六色 4bpp 帧(.raw/.bin)，App 下载后字节直传设备（见 `features/cast/projection_service.dart`）。
/// 与小程序一致，App 不再自研调色。本类只保留：
///   · 硬件联调用的固定测试帧（彩条 / 纯色）；
///   · 4bpp 打包与整图 CRC32（图传协议层复用）。
class FrameBuffer {
  const FrameBuffer(this.data, this.width, this.height);
  final Uint8List data;
  final int width;
  final int height;
  int get dataSize => data.length;
}

class FrameImageCodec {
  FrameImageCodec._();

  /// 六色 nibble 码（写入帧缓存的 4bit 值，对应 PRD FORMAT=0x01）：黑0/白1/黄2/红3/蓝5/绿6。
  static const List<int> _sixColorNibbles = [0x0, 0x1, 0x2, 0x3, 0x5, 0x6];

  /// true：每字节高 4 位放「左边/靠前」的像素。
  static const bool highNibbleFirst = true;

  /// 一张图需要多少字节 = 宽 × 高 ÷ 2。
  static int bytesPerImage(int width, int height) => (width * height + 1) ~/ 2;

  /// 把一串 nibble(每元素 0~15)打包成 4bpp 字节流(每 2 像素 1 字节)。
  static Uint8List packNibbles(List<int> nibbles) {
    final out = Uint8List((nibbles.length + 1) ~/ 2);
    for (int i = 0; i < out.length; i++) {
      final a = nibbles[i * 2] & 0x0F;
      final b = (i * 2 + 1 < nibbles.length ? nibbles[i * 2 + 1] : 0) & 0x0F;
      out[i] = highNibbleFirst ? ((a << 4) | b) : ((b << 4) | a);
    }
    return out;
  }

  /// 生成彩条测试图：屏幕按宽度等分 6 段，依次铺 黑/白/黄/红/蓝/绿。
  /// 硬件联调首选——不依赖任何照片，尺寸天生正确，肉眼即可核对颜色与左右方向。
  static FrameBuffer buildColorBars(int width, int height) {
    final nibbles = Uint8List(width * height);
    final bands = _sixColorNibbles.length;
    final bandWidth = width / bands;
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        var band = (x / bandWidth).floor();
        if (band > bands - 1) band = bands - 1;
        nibbles[y * width + x] = _sixColorNibbles[band];
      }
    }
    return FrameBuffer(packNibbles(nibbles), width, height);
  }

  /// 生成纯色测试图(例如整屏白)，用于最小化验证刷新是否生效。
  static FrameBuffer buildSolid(int width, int height, int nibble) {
    final nibbles = Uint8List(width * height);
    final v = nibble & 0x0F;
    for (int i = 0; i < nibbles.length; i++) {
      nibbles[i] = v;
    }
    return FrameBuffer(packNibbles(nibbles), width, height);
  }

  /// 整图 CRC32-MPEG2(6.8.1 的 IMG_CRC32)。
  static int crc32(List<int> data) => FrameProtocol.crc32Mpeg2(data);
}
