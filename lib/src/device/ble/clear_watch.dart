import 'dart:async';

/// [ClearWatch.deleteAll] 的结果：设备删除后的 IMG_MASK，以及是不是靠回读 0x01 确认的。
class ClearWatchResult {
  const ClearWatchResult(this.mask, {this.confirmedByPoll = false});

  /// 0x12 应答带回的掩码；[confirmedByPoll] 时是回读 0x01 读到的掩码。
  final List<int> mask;

  /// true：0x12 应答还没回来，回读 0x01 已确认设备一张不剩，于是不再等应答。
  final bool confirmedByPoll;
}

/// 一键清空：等 0x12「删除全部」应答的同时回读 0x01，设备上一张都不剩了就算清完（2026-09-21）。
///
/// 报障原话（小程序先报的，App 是同一套等法）：「清除后，设备都刷出默认图片了，还在转圈圈」。
/// 0x12 是设备**全删完才回一次**应答，所以等应答的预算按张数给（每张 2s、下限 6s、封顶 180s，
/// 见 [FrameBleClient.deleteImage]）。这份预算只在「设备真的还没删完」时有意义；设备早就删完、
/// 屏幕都刷成默认图了，而那一次应答迟到或丢了，转圈就要一直转到预算用完——几十张就是一两分钟，
/// 之后还要再走一轮失败回读。
///
/// 做法：发出 0x12 后等 [pollStart]，之后每隔 [pollGap] 读一次 0x01 看还剩几张：
/// - 剩 0 张 → 设备已清空，立刻按成功收尾，不再等 0x12（cancelDelete 收回那条 pending，
///   否则它会一直占着 0x12 直到超时，期间再删图会被拒成「正在等待应答」）；
/// - 读不到（设备正忙回 0x0B / 应答超时）或还有剩余 → 设备还在擦，下一拍再看；
/// - 0x12 自己先回来了（成功或失败）→ 以它为准，停止回读；失败原样抛给调用方，
///   由它原来那套「回读核对」处理。
///
/// 这是协议允许的：设备处理指令期间收到新指令会回 0x0B「设备繁忙」（规格书 v1.5 §6.6.1），
/// 各指令的应答按命令字分别配对，0x01 与在途的 0x12 互不干扰。
/// 对齐小程序 utils/clear-watch.js；依赖全部由调用方传入，便于单测。
class ClearWatch {
  ClearWatch._();

  /// 发出 0x12 后多久开始回读（删得快的设备这之前应答早就回来了，一次都不用读）。
  static const Duration pollStart = Duration(seconds: 5);

  /// 两次回读之间的间隔。
  static const Duration pollGap = Duration(seconds: 3);

  static Future<ClearWatchResult> deleteAll({
    required Future<List<int>> Function() deleteAll,
    required Future<List<int>> Function() readMask,
    required int Function(List<int> mask) remainingOf,
    required void Function() cancelDelete,
    void Function(String stage)? mark,
    Duration start = pollStart,
    Duration gap = pollGap,
  }) {
    final done = Completer<ClearWatchResult>();
    Timer? timer;

    void finish(void Function() settle) {
      if (done.isCompleted) {
        return;
      }
      timer?.cancel();
      timer = null;
      // 0x12 已经回来时这里是空操作；回读先确认清空时，收回那条还在等的 0x12
      // （它随后以 aborted 失败，done 已完成，被上面那句挡掉）。
      cancelDelete();
      settle();
    }

    Future<void> poll() async {
      timer = null;
      if (done.isCompleted) {
        return;
      }
      try {
        final mask = await readMask();
        if (done.isCompleted) {
          return;
        }
        final remaining = remainingOf(mask);
        mark?.call('clear-poll-0x01-remaining-$remaining');
        if (remaining == 0) {
          finish(
            () => done.complete(ClearWatchResult(mask, confirmedByPoll: true)),
          );
          return;
        }
      } catch (_) {
        if (done.isCompleted) {
          return;
        }
        // 设备正忙着擦（0x0B）/ 应答超时 / 0x01 撞车：下一拍再看。
        mark?.call('clear-poll-0x01-failed');
      }
      if (!done.isCompleted) {
        timer = Timer(gap, () => unawaited(poll()));
      }
    }

    unawaited(
      Future<List<int>>.sync(deleteAll).then(
        (mask) => finish(() => done.complete(ClearWatchResult(mask))),
        onError: (Object error, StackTrace stack) =>
            finish(() => done.completeError(error, stack)),
      ),
    );
    timer = Timer(start, () => unawaited(poll()));
    return done.future;
  }
}
