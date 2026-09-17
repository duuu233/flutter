import 'package:flutter_test/flutter_test.dart';
import 'package:BoltStar/src/device/frame_device_protocol.dart';
import 'package:BoltStar/src/state.dart';

/// 圆屏产品（后台「形状类型 = 圆形」→ `shapeType` 1）。
///
/// 2026-09-17 产品定稿：**预览裁成圆、导出还是方的** —— 设备屏幕是圆的，方框四角那一圈
/// 本来就显示不出来，预览裁圆才是所见即所得；帧数据仍按方形矩阵传（四角留白）。
///
/// 这里守的是**判据**那一半：`shapeType` → `roundScreen`，以及
/// ⚠️ **没下发 / 非法值一律当方形** —— 绝大多数产品是方形，那条路必须和加这个字段之前
/// 完全一样（产品原话：千万别改动到现有方形的逻辑和代码）。
/// 裁框那一半在 `cast_preview_page.dart` 的 `_ScreenClip`。
void main() {
  group('DeviceItem.roundScreen', () {
    test('1 = 圆形', () {
      expect(_device(shapeType: 1).roundScreen, isTrue);
    });

    test('0 = 方形，而且这是默认值（后端没下发时就是它）', () {
      expect(_device(shapeType: 0).roundScreen, isFalse);
      // 不传 shapeType：构造出来必须是方形，不是圆形也不是别的什么。
      expect(_device().shapeType, 0);
      expect(_device().roundScreen, isFalse);
    });

    test('后端给了没见过的值也当方形，不当圆形', () {
      // 形状枚举以后可能加值（圆角矩形之类）。没实现的形状**退回方形**，
      // 绝不能因为「不等于 0」就当成圆的裁掉四角。
      for (final value in <int>[2, 9, -1]) {
        expect(
          _device(shapeType: value).roundScreen,
          isFalse,
          reason: 'shapeType $value',
        );
      }
    });
  });
}

DeviceItem _device({int shapeType = 0}) => DeviceItem(
  id: 'dev-1',
  name: '相框',
  kind: '',
  screenType: FrameScreenType.inch589,
  batteryLevel: 50,
  charging: false,
  connected: false,
  role: DeviceRole.owner,
  serialNumber: 'AA:BB:CC:DD:EE:FF',
  hardwareVersion: 'HW-1.0',
  firmwareVersion: '1.0.0',
  imageMask: 0,
  currentImageIndex: 0,
  playbackMode: FramePlaybackMode.sequence,
  carouselIntervalSeconds: 3600,
  carouselEnabled: true,
  shapeType: shapeType,
);
