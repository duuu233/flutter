import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:BoltStar/src/device/ble/clear_watch.dart';

/// 一键清空：等 0x12「删除全部」应答的同时回读 0x01，设备一张不剩就算清完（2026-09-21 报障：
/// 「清除后，设备都刷出默认图片了，还在转圈圈」）。对齐小程序 tests/clear-watch.test.js。
///
/// 用 testWidgets：回读节奏是 5 秒起、3 秒一拍，假时钟下 `tester.pump(duration)` 一步跳过去。
void main() {
  int remainingOf(List<int> mask) => mask.where((byte) => byte != 0).length;

  testWidgets('0x12 先回来：以它为准，一次都不回读', (tester) async {
    var reads = 0;
    var cancels = 0;
    final future = ClearWatch.deleteAll(
      deleteAll: () async => <int>[0, 0],
      readMask: () async {
        reads++;
        return <int>[0];
      },
      remainingOf: remainingOf,
      cancelDelete: () => cancels++,
    );
    await tester.pump();
    final result = await future;
    expect(result.confirmedByPoll, isFalse);
    expect(result.mask, <int>[0, 0]);
    await tester.pump(const Duration(seconds: 10));
    expect(reads, 0);
    // 收尾时照例调一次——真实实现里 0x12 已回来时它是空操作
    expect(cancels, 1);
  });

  testWidgets('0x12 迟迟不回：回读看到清空就收尾，并收回还在等的 0x12', (tester) async {
    final pending = Completer<List<int>>();
    final masks = <List<int>>[
      <int>[1],
      <int>[0],
    ];
    var reads = 0;
    var cancelled = false;
    ClearWatchResult? result;
    unawaited(
      ClearWatch.deleteAll(
        deleteAll: () => pending.future,
        readMask: () async => masks[reads++ < 1 ? 0 : 1],
        remainingOf: remainingOf,
        cancelDelete: () {
          cancelled = true;
          // 真实实现：收回 pending 后，等待方以 aborted 失败
          pending.completeError(StateError('cancelled'));
        },
      ).then((value) => result = value),
    );

    await tester.pump(const Duration(seconds: 4));
    expect(reads, 0, reason: '5 秒之前不回读');
    await tester.pump(const Duration(seconds: 1));
    expect(reads, 1);
    expect(result, isNull, reason: '还剩 1 张，接着等');
    await tester.pump(const Duration(seconds: 3));
    expect(reads, 2);
    expect(result, isNotNull);
    expect(result!.confirmedByPoll, isTrue);
    expect(result!.mask, <int>[0]);
    expect(cancelled, isTrue);
    // 收尾之后不再回读
    await tester.pump(const Duration(seconds: 10));
    expect(reads, 2);
  });

  testWidgets('回读失败（设备正忙）不误判，接着读到清空照样收尾', (tester) async {
    final pending = Completer<List<int>>();
    var reads = 0;
    ClearWatchResult? result;
    unawaited(
      ClearWatch.deleteAll(
        deleteAll: () => pending.future,
        readMask: () async {
          reads++;
          if (reads < 3) {
            throw StateError('当前电子纸设备繁忙，请稍后重试');
          }
          return <int>[0];
        },
        remainingOf: remainingOf,
        cancelDelete: () => pending.completeError(StateError('cancelled')),
      ).then((value) => result = value),
    );
    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(seconds: 3));
    expect(result, isNull);
    await tester.pump(const Duration(seconds: 3));
    expect(reads, 3);
    expect(result?.confirmedByPoll, isTrue);
  });

  testWidgets('0x12 自己失败：原样抛给调用方，之后不再回读', (tester) async {
    final pending = Completer<List<int>>();
    final failure = StateError('指令 0x12 应答超时');
    var reads = 0;
    Object? caught;
    unawaited(
      ClearWatch.deleteAll(
        deleteAll: () => pending.future,
        readMask: () async {
          reads++;
          return <int>[7];
        },
        remainingOf: remainingOf,
        cancelDelete: () {},
      ).then<void>((_) {}, onError: (Object error) => caught = error),
    );
    await tester.pump(const Duration(seconds: 6));
    expect(reads, 1);
    pending.completeError(failure);
    await tester.pump();
    expect(caught, same(failure));
    await tester.pump(const Duration(seconds: 10));
    expect(reads, 1);
  });
}
