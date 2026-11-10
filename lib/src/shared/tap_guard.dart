/// 防重复点击（2026-11-04 同小程序 `utils/tap-guard.js`，先覆盖所有「投屏」相关按钮）。
///
/// 规则（同一个 owner、同一个 key 共用一把锁）：
///   · 上一次还没执行完（连接设备、选图、下载、跳转前的准备）——后续调用直接忽略，不提示；
///   · 执行完后再冷却 [cooldown]，挡住转场期间的连点（两次 push 会叠两层页面）；
///   · 兜底：一次执行超过 [maxHold] 还没结束（异常挂住）就不再拦，避免按钮永久失灵。
///
/// ⚠️ 锁只覆盖 task 自己返回的 Future：task 里调后续流程要 await，否则锁会提前放开。
///    同一调用链上的方法不要用同一个 key 分别包（外层持锁时内层会被当成重复点击忽略）。
abstract final class TapGuard {
  static const Duration cooldown = Duration(milliseconds: 500);
  static const Duration maxHold = Duration(seconds: 60);

  static final Expando<Map<String, _Lock>> _locks = Expando<Map<String, _Lock>>('tapGuard');

  /// 在 [owner]（页面 State 等）上按 [key] 执行 [task]；正在执行或冷却中直接返回（不执行）。
  static Future<void> run(Object owner, String key, Future<void> Function() task) async {
    final locks = _locks[owner] ??= <String, _Lock>{};
    final now = DateTime.now();
    final current = locks[key];
    if (current != null && current.blocks(now)) {
      return;
    }
    final lock = _Lock(now);
    locks[key] = lock;
    try {
      await task();
    } finally {
      if (identical(locks[key], lock)) {
        lock.release();
      }
    }
  }
}

class _Lock {
  _Lock(this.since);

  final DateTime since;
  bool running = true;
  DateTime until = DateTime.fromMillisecondsSinceEpoch(0);

  bool blocks(DateTime now) =>
      running ? now.difference(since) < TapGuard.maxHold : now.isBefore(until);

  void release() {
    running = false;
    until = DateTime.now().add(TapGuard.cooldown);
  }
}
