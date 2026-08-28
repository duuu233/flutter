import 'dart:async';

/// 把「跳变的目标进度」渲染成连续增长的平滑进度。
/// 与小程序 `utils/smooth-progress.js` 同源同口径（含四版演进的全部教训）。
///
/// 为什么需要：BLE 图传的真实进度天生**跳变**——固件每 10 包才回一次 0x23 累计应答，
/// 窗口 50 包时一次应答就推进几十包，进度条于是一段一段往前蹦。
///
/// 直觉做法是提高刷新频率，但那正是**不能做**的事：小程序侧 `setData` 跨线程会占住 JS 线程、
/// 推迟 0x23 处理，越刷越慢；Flutter 侧虽无跨线程开销，但每次 emit 都会重建订阅方 Widget，
/// 同样没必要。方向是**减小每次更新的幅度**而不是提高频率：只在取整值变化时对外发一次，
/// 整场传输 ≤101 次。
///
/// ── 四版演进（每一步都是真机/仿真实测出来的教训）────────────────────────────────
///   v1 追平即停表 → 「0→7% 丝滑、停 0.2s、再 7→14%」：增量几拍冲完就干等。
///      那 7% 正是「窗口 50 包 / 共 668 包 = 7.5%」跑满一个窗口的推进量，0.2s 是设备消化
///      50 包并回 0x23 的真实耗时——**传输节奏是对的，错的是「冲完就停」的渲染方式**。
///   v2 按预计间隔铺开 → 段间不停了，但 ACK 稍晚仍会先走完停一下。
///   v3 计划超前 [_planAhead]=1.5 + 仅逾期才吸附 → 每段只走 2/3、剩 1/3 作缓冲吸抖动
///      （jitter buffer 思路）。稳态滞后 = 1.5×单次推进量，与 [_maxLag] 配套推导。
///   v4 受控前瞻（产品拍板「可酌情浮动百分之几、失败必须立即停」）→ 允许领先真实目标
///      ≤[_leadMax]，锥减速率渐近逼近、永不画到 100、失败瞬间连领先部分一起收回。
///
/// 不变量：
///   · 显示值 ≤ 真实目标 + [_leadMax]，且**未真实完成前永不显示 100%**——100% 只能由
///     真实完成 [jumpTo] 给出（产品口径：99% 处可以停顿等设备真到 100%，保证终点时刻一致）；
///   · 单调不减（[freeze] 是唯一例外）；
///   · 落后不超过 [_maxLag]（传输突然提速时补齐超出部分，不拖后腿）；
///   · 失败即 [freeze]：连领先的部分一起钳回真实目标——这是「允许造一点假」的对价条款，
///     失败画面上停着比真实更高的数字就是在骗用户；
///   · 无处可走时停表，不空转。
class SmoothProgress {
  SmoothProgress({required this.onRender, this.tick = _defaultTick});

  /// 显示值（整数百分比）变化时回调。调用方据此刷新 UI。
  final void Function(int value) onRender;

  /// 渲染节拍。默认 33ms（约 30 次/秒）；真正对外回调只在取整值变化时发生。
  final Duration tick;

  static const Duration _defaultTick = Duration(milliseconds: 33);

  /// 还没有观测值时假设的目标更新间隔（宁可估长：估短会先冲完再等）。
  static const double _defaultIntervalMs = 300;

  /// 目标更新已逾期时，把剩余增量收拢完的最短时间。
  static const double _minRemainingMs = 40;

  /// 新观测在间隔/速率均值里的权重。
  static const double _emaWeight = 0.3;

  /// 计划超前系数：把「走完当前段」的截止时间**故意**定在预计下一次更新的这个倍数处。
  /// 定在 1.0 意味着估准了刚好走完——ACK 稍晚就先走完停一下。定在 1.5 后每段只走 2/3，
  /// 剩下 1/3 是缓冲：ACK 晚到 50% 以内都有存量可走，运动不断流。
  static const double _planAhead = 1.5;

  /// 允许领先真实目标的最大格数。3 是「用户看不出来」与「失败时要收回多少」的折衷。
  static const double _leadMax = 3;

  /// 允许落后真实进度的最大格数。落后是**故意**的（铺开才能连续增长），但传输突然提速时
  /// 要补齐超出部分，否则进度条会明显拖后腿。与 [_planAhead] 配套推导（1.5×整窗 7.5%≈11.3%）。
  static const double _maxLag = 12;

  static const double _max = 100;

  double _target = 0;
  double _shown = 0; // 内部保留小数，避免每拍不足 1% 时永远走不动
  int _painted = -1; // 上一次真正对外回调的整数值
  Timer? _timer;
  int _lastTargetAtMs = 0;
  double _intervalEma = 0; // 实测「两次目标更新的间隔」
  double _rateEma = 0; // 实测真实推进速率（%/ms）——前瞻段的速度基准
  int _lastTickAtMs = 0;

  final Stopwatch _clock = Stopwatch()..start();
  int get _nowMs => _clock.elapsedMilliseconds;

  /// 当前显示值（整数）。
  int get current => _shown.floor();

  /// 当前真实目标。
  int get target => _target.floor();

  /// 可画上限：真实目标 + [_leadMax]，且未真实完成前 99 封顶；
  /// 目标本身到了 100（真实完成信号）才放行到 100。
  double get _upperBound {
    if (_target >= _max) return _max;
    final lead = _target + _leadMax;
    return lead < _max - 1 ? lead : _max - 1;
  }

  void _paint() {
    final value = _shown.floor().clamp(0, _max.toInt());
    if (value != _painted) {
      _painted = value;
      onRender(value);
    }
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
  }

  void _start() {
    if (_timer == null && _shown < _upperBound) {
      _lastTickAtMs = _nowMs;
      _timer = Timer.periodic(tick, (_) => _onTick());
    }
  }

  void _onTick() {
    final now = _nowMs;
    final dt = (now - _lastTickAtMs).toDouble().clamp(1.0, double.infinity);
    _lastTickAtMs = now;

    var gap = _target - _shown;
    // 落后过多先补齐超出部分：真实传输提速（窗口涨回、设备吃满）时旧节奏铺不过来。
    if (gap > _maxLag) {
      _shown = _target - _maxLag;
      gap = _maxLag;
    }
    final upper = _upperBound;
    final room = upper - _shown;
    if (room <= 0.05) {
      _stop(); // 前瞻打满：没有可画的了（新目标到达会重新开表）
      return;
    }

    // 每拍步长取两条腿的较大者——这是「全程不断流」的关键：
    //   · 计划腿：把落后增量摊到「预计下次更新的 _planAhead 倍时刻」，段末自然衰减为 0；
    //   · 速率腿：按实测真实速率前进，随「距上限的余量」锥减，计划腿衰减后无缝接管、
    //     滚入前瞻区，到顶前渐近减速绝不急停。
    // ⚠️ 写成互斥分支是走过的弯路：前瞻只在「恰好追平」才切入，中段几乎不会发生，
    //    仿真实测最大领先 0.0%——取较大者合并才真正生效。
    var planStep = 0.0;
    if (gap > 0) {
      final expected =
          (_intervalEma > 0 ? _intervalEma : _defaultIntervalMs) * _planAhead;
      final remainingRaw = _lastTargetAtMs + expected - now;
      final remaining = remainingRaw < _minRemainingMs
          ? _minRemainingMs
          : remainingRaw;
      final ratio = dt / remaining;
      planStep = gap * (ratio > 1 ? 1 : ratio);
    }
    final velStep = _rateEma * dt * (room / _leadMax).clamp(0.0, 1.0);
    final step = planStep > velStep ? planStep : velStep;
    if (step <= 0) {
      _stop(); // 无速率依据也无落后增量：无处可画
      return;
    }
    _shown = (_shown + step) > upper ? upper : (_shown + step);
    _paint();
  }

  /// 设定真实目标（由 BLE 进度回调驱动）。只增不减，避免回退造成的抖动。
  void setTarget(int value) {
    final next = value.clamp(0, _max.toInt()).toDouble();
    if (next <= _target) return;
    final now = _nowMs;
    if (_lastTargetAtMs > 0) {
      // 观测间隔与速率：前者是落后段铺开增量的依据，后者是前瞻段的速度基准
      final delta = (now - _lastTargetAtMs).toDouble().clamp(
        1.0,
        double.infinity,
      );
      _intervalEma = _intervalEma > 0
          ? _intervalEma * (1 - _emaWeight) + delta * _emaWeight
          : delta;
      final sampleRate = (next - _target) / delta;
      _rateEma = _rateEma > 0
          ? _rateEma * (1 - _emaWeight) + sampleRate * _emaWeight
          : sampleRate;
    } else {
      // 首个目标还没有观测值：按缺省间隔假设一个保守速率，让前瞻段起步时有依据
      _rateEma = next / _defaultIntervalMs;
    }
    _lastTargetAtMs = now;
    _target = next;
    _start();
  }

  /// 就地冻结（用于**图传失败**）：立刻停表，并把显示值**钳回真实目标**——
  /// 前瞻段领先出去的那几格是借来的观感，失败瞬间必须还回去。
  void freeze() {
    _stop();
    final clamped = _shown < _target ? _shown : _target;
    _target = clamped.floorToDouble();
    _shown = _target;
    _paint();
  }

  /// 立刻跳到某个值并停表（用于本张收尾 100%），不再做递进动画。
  void jumpTo(int value) {
    final next = value.clamp(0, _max.toInt()).toDouble();
    _stop();
    _target = next;
    _shown = next;
    _paint();
  }

  /// 新的一张开始：清零重来（间隔/速率观测一并重置，避免把上一张的节奏带过来）。
  void reset() {
    _stop();
    _target = 0;
    _shown = 0;
    _painted = -1;
    _lastTargetAtMs = 0;
    _intervalEma = 0;
    _rateEma = 0;
    _paint();
  }

  /// 释放定时器。页面/服务销毁时务必调用。
  void dispose() {
    _stop();
    _clock.stop();
  }
}
