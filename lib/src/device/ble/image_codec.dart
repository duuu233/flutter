// 图片编解码层：把 RGBA 像素/测试图转换成电子相框需要的「六色 4bpp 原始帧缓存」。
// 由微信小程序版 `utils/image-codec.js` 移植到 Dart，逻辑一致：
//   · 每像素 4bit，本屏只用 6 个值(黑0x0/白0x1/黄0x2/红0x3/蓝0x5/绿0x6，对应 PRD FORMAT=0x01)。
//   · 两个像素拼 1 字节(高 4 位=左像素)。一张 680×960 图 = 680×960÷2 = 326400 字节。
//   · 量化默认带 Floyd–Steinberg 抖动 + 量化前对比度/饱和度增强，缓解 6 色硬量化的色块/发灰。
//   · 整图 CRC32-MPEG2 复用 FrameProtocol.crc32Mpeg2。

import 'dart:typed_data';

import 'frame_protocol.dart';

/// 调色板项。nibble = 写入帧缓存的 4bit 值(对应 PRD，【不可改】)；
/// rgb = 仅用于「最近颜色匹配 + 抖动误差」的参照，应尽量等于真机实际显示色。
class PaletteEntry {
  const PaletteEntry(this.nibble, this.r, this.g, this.b, this.name);
  final int nibble;
  final int r;
  final int g;
  final int b;
  final String name;
}

/// 一帧六色帧缓存。
class FrameBuffer {
  const FrameBuffer(this.data, this.width, this.height);
  final Uint8List data;
  final int width;
  final int height;
  int get dataSize => data.length;
}

class FrameImageCodec {
  FrameImageCodec._();

  /// 六色调色板。rgb 为贴近真机的经验近似值(真机六色偏暗、不饱和)；要最准就传彩条图拍屏取色后替换。
  static const List<PaletteEntry> palette = [
    PaletteEntry(0x0, 0, 0, 0, '黑'), // 黑、白保留纯值作无彩色锚点
    PaletteEntry(0x1, 255, 255, 255, '白'),
    PaletteEntry(0x2, 235, 215, 35, '黄'),
    PaletteEntry(0x3, 180, 45, 40, '红'),
    PaletteEntry(0x5, 45, 65, 145, '蓝'),
    PaletteEntry(0x6, 55, 120, 70, '绿'),
  ];

  /// true：每字节高 4 位放「左边/靠前」的像素；颜色左右镜像/错位时改它。
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

  /// 找出与给定 RGB 最接近的调色板下标(欧氏距离最近)。入参用 double 以支持抖动累加的误差值。
  static int _nearestIndex(double r, double g, double b) {
    int best = 0;
    double bestDist = double.infinity;
    for (int i = 0; i < palette.length; i++) {
      final p = palette[i];
      final dr = r - p.r;
      final dg = g - p.g;
      final db = b - p.b;
      final dist = dr * dr + dg * dg + db * db;
      if (dist < bestDist) {
        bestDist = dist;
        best = i;
      }
    }
    return best;
  }

  static double _clamp(double v) => v < 0 ? 0 : (v > 255 ? 255 : v);

  /// 量化前观感增强：先围绕中灰(128)提对比度，再围绕感知亮度提饱和度。值=1 即不变。
  static List<double> _enhance(
      double r, double g, double b, double contrast, double saturation) {
    r = (r - 128) * contrast + 128;
    g = (g - 128) * contrast + 128;
    b = (b - 128) * contrast + 128;
    final lum = 0.299 * r + 0.587 * g + 0.114 * b;
    r = lum + (r - lum) * saturation;
    g = lum + (g - lum) * saturation;
    b = lum + (b - lum) * saturation;
    return [_clamp(r), _clamp(g), _clamp(b)];
  }

  /// 把误差按权重 wt 扩散到 (x,y) 的浮点缓存上(越界丢弃)。
  static void _spread(Float32List buf, int x, int y, int w, int h, double er,
      double eg, double eb, double wt) {
    if (x < 0 || x >= w || y < 0 || y >= h) return;
    final i = (y * w + x) * 3;
    buf[i] += er * wt;
    buf[i + 1] += eg * wt;
    buf[i + 2] += eb * wt;
  }

  /// 生成彩条测试图：屏幕按宽度等分 6 段，依次铺 黑/白/黄/红/蓝/绿。
  /// 联调首选——不依赖任何照片，尺寸天生正确，肉眼即可核对颜色与左右方向。
  static FrameBuffer buildColorBars(int width, int height) {
    final nibbles = Uint8List(width * height);
    final bandWidth = width / palette.length;
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        var band = (x / bandWidth).floor();
        if (band > palette.length - 1) band = palette.length - 1;
        nibbles[y * width + x] = palette[band].nibble;
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

  /// 把 RGBA 像素([r,g,b,a, ...]，长度 = width×height×4)量化成六色帧缓存。
  /// dither=true 走 Floyd–Steinberg 抖动；contrast/saturation 控制量化前增强(=1 关闭)。
  static FrameBuffer fromRgba(
    Uint8List rgba,
    int width,
    int height, {
    bool dither = true,
    double contrast = 1.12,
    double saturation = 1.28,
  }) {
    final count = width * height;
    final nibbles = Uint8List(count);

    if (!dither) {
      for (int i = 0; i < count; i++) {
        final p = _enhance(rgba[i * 4].toDouble(), rgba[i * 4 + 1].toDouble(),
            rgba[i * 4 + 2].toDouble(), contrast, saturation);
        nibbles[i] = palette[_nearestIndex(p[0], p[1], p[2])].nibble;
      }
      return FrameBuffer(packNibbles(nibbles), width, height);
    }

    // 误差会累加成负数/超过 255，必须用浮点缓存。填充时即应用增强。
    final buf = Float32List(count * 3);
    for (int i = 0; i < count; i++) {
      final p = _enhance(rgba[i * 4].toDouble(), rgba[i * 4 + 1].toDouble(),
          rgba[i * 4 + 2].toDouble(), contrast, saturation);
      buf[i * 3] = p[0];
      buf[i * 3 + 1] = p[1];
      buf[i * 3 + 2] = p[2];
    }

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final i = y * width + x;
        final r = buf[i * 3];
        final g = buf[i * 3 + 1];
        final b = buf[i * 3 + 2];
        final pi = _nearestIndex(r, g, b);
        final pe = palette[pi];
        nibbles[i] = pe.nibble;
        final er = r - pe.r;
        final eg = g - pe.g;
        final eb = b - pe.b;
        _spread(buf, x + 1, y, width, height, er, eg, eb, 7 / 16); // 右
        _spread(buf, x - 1, y + 1, width, height, er, eg, eb, 3 / 16); // 左下
        _spread(buf, x, y + 1, width, height, er, eg, eb, 5 / 16); // 下
        _spread(buf, x + 1, y + 1, width, height, er, eg, eb, 1 / 16); // 右下
      }
    }

    return FrameBuffer(packNibbles(nibbles), width, height);
  }

  /// 整图 CRC32-MPEG2(6.8.1 的 IMG_CRC32)。
  static int crc32(List<int> data) => FrameProtocol.crc32Mpeg2(data);
}
