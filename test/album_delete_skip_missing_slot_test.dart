// 「我的相册」删除：待删槽位怎么解析（2026-08-17）+ 跳过设备上已经没有的槽位（2026-08-10 产品口径）。
// 对齐小程序 tests/album-slot-index.test.js 的同名分支。
//
// 场景：同一台设备被两部手机连过，另一端删掉了某张，本机记录还在 → 那个 imgIndex 在设备上
// 已是空槽位。空槽位一起进 0x12 的掩码，固件回 0x07，**整批**删除被打回。
import 'dart:ui' show Color;

import 'package:flutter_test/flutter_test.dart';

import 'package:BoltStar/src/device/ble/device_ble.dart';
import 'package:BoltStar/src/device/ble/frame_protocol.dart';
import 'package:BoltStar/src/state.dart';

/// 只喂 [PhotoFrameState.resolveDeleteSlots] 关心的字段：投屏记录自己的 `imgIndex`。
CastRecord _record(String id, {int? imageIndex}) => CastRecord(
  id: id,
  title: '',
  deviceId: 'dev-1',
  ownerUserId: '',
  status: CastStatus.success,
  source: ImageSourceType.album,
  color: const Color(0xFF000000),
  width: 0,
  height: 0,
  message: '',
  createdAt: DateTime.utc(2026, 8, 17),
  imageIndex: imageIndex,
);

void main() {
  // 2026-08-17：图库列表下线后，待删槽位的唯一来源是**投屏记录自己的 imgIndex**
  // （对齐小程序 album/list.js resolveDeleteTargets，待删目标由 {id, photoId, slot} 收成 {id, slot}）。
  group('resolveDeleteSlots', () {
    test('全部记录都有索引：按记录顺序返回，重复槽位去重', () {
      final slots = PhotoFrameState.resolveDeleteSlots([
        _record('a', imageIndex: 2),
        _record('b', imageIndex: 0),
        _record('c', imageIndex: 2),
      ]);

      expect(slots, [2, 0]);
    });

    test('槽位 0 是合法槽位，不被当成「没有索引」', () {
      expect(PhotoFrameState.resolveDeleteSlots([_record('a', imageIndex: 0)]), [
        0,
      ]);
    });

    test('任意一条缺索引 → 整批终止（返回 null），绝不推算', () {
      // 缺索引时按设备掩码/列表顺序猜位置只会删掉别人的图，宁可整批不删。
      expect(
        PhotoFrameState.resolveDeleteSlots([
          _record('a', imageIndex: 1),
          _record('b'),
        ]),
        isNull,
      );
    });

    test('越界索引（IMG_MASK 只有 96 位）同样整批终止', () {
      // indexesToMask 会静默丢掉越界位：放行就变成「记录删了、图还留在设备上」。
      expect(
        PhotoFrameState.resolveDeleteSlots([_record('a', imageIndex: 96)]),
        isNull,
      );
      expect(
        PhotoFrameState.resolveDeleteSlots([_record('a', imageIndex: -1)]),
        isNull,
      );
    });

    test('没有选中任何记录时返回 null', () {
      expect(PhotoFrameState.resolveDeleteSlots(const []), isNull);
    });
  });

  group('splitSlotsByDeviceMask', () {
    test('掩码里没有的槽位判为 gone，不进 0x12', () {
      // 设备上只剩 1、2（另一端把 0 删了），本机选中 0、1、2 三张。
      final split = PhotoFrameState.splitSlotsByDeviceMask([0, 1, 2], [1, 2]);

      expect(split.onDevice, [1, 2]);
      expect(split.gone, [0]);
    });

    test('掩码读不到(null)时一张都不判 gone，整批按原样下发', () {
      // 回读失败还判 gone 的话，会退化成「记录全删了、图还留在设备上」。
      final split = PhotoFrameState.splitSlotsByDeviceMask([0, 1, 2], null);

      expect(split.onDevice, [0, 1, 2]);
      expect(split.gone, isEmpty);
    });

    test('设备真的一张图都没有(空掩码)：全判 gone，整条 0x12 都不发', () {
      // 与「掩码读不到」不同——12 个 0 是合法掩码，全跳过正是对的。
      final split = PhotoFrameState.splitSlotsByDeviceMask([0, 1], const []);

      expect(split.onDevice, isEmpty);
      expect(split.gone, [0, 1]);
    });

    test('槽位 0 是合法槽位，不被当成「没有索引」丢掉', () {
      final split = PhotoFrameState.splitSlotsByDeviceMask([0], [0, 3]);

      expect(split.onDevice, [0]);
      expect(split.gone, isEmpty);
    });
  });

  group('0x12 的良性结果码', () {
    test('只放行 0x05 图片不存在 / 0x07 掩码不一致', () {
      expect(FrameProtocol.isSkippableDeleteResult(0x05), isTrue);
      expect(FrameProtocol.isSkippableDeleteResult(0x07), isTrue);

      // 这几类代表「设备可能真的没删掉」，放行会留下孤儿槽位。
      for (final code in [0x00, 0x01, 0x04, 0x06, 0x09, 0x0a, 0x0b]) {
        expect(
          FrameProtocol.isSkippableDeleteResult(code),
          isFalse,
          reason: '结果码 0x${code.toRadixString(16)} 不该被放行',
        );
      }
    });

    test('优先认结果码，不受文案前缀/改写影响', () {
      final error = FrameBleException(
        '电子纸设备-未知提示',
        resultCode: 0x07,
      );

      expect(FrameBleException.isSkippableDelete(error), isTrue);
    });

    test('设备忙(0x0B)带着结果码也不放行', () {
      final busy = FrameBleException(
        FrameProtocol.busyMessage,
        kind: FrameBleErrorKind.busy,
        resultCode: FrameProtocol.busyResult,
      );

      expect(FrameBleException.isSkippableDelete(busy), isFalse);
    });

    test('没有结果码时退回文案匹配（老链路/被包装过的错误）', () {
      expect(
        FrameBleException.isSkippableDelete(
          Exception(FrameProtocol.resultText(0x05)),
        ),
        isTrue,
      );
      expect(
        FrameBleException.isSkippableDelete(
          Exception(FrameProtocol.resultText(0x07)),
        ),
        isTrue,
      );
      expect(
        FrameBleException.isSkippableDelete(Exception('image not found')),
        isTrue,
      );
      // 传输中断(0x09)/Flash 写入失败(0x04) 的文案不能被误放行。
      expect(
        FrameBleException.isSkippableDelete(
          Exception(FrameProtocol.resultText(0x09)),
        ),
        isFalse,
      );
      expect(
        FrameBleException.isSkippableDelete(
          Exception(FrameProtocol.resultText(0x04)),
        ),
        isFalse,
      );
      expect(FrameBleException.isSkippableDelete(null), isFalse);
    });
  });
}
