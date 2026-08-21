// 进度条平滑渲染（lib/src/features/cast/smooth_progress.dart）。
// 与小程序 tests/smooth-progress.test.js 同口径。
//
// 背景：BLE 图传的真实进度天生跳变——固件每 10 包才回一次 0x23 累计应答，窗口 50 包时
// 一次应答推进几十包。直接透传就是「冲一段→停 0.2s→再冲一段」。
// 解法不是提高刷新频率（会抢主 isolate、拖慢图传本身），而是减小每次更新的幅度。
import 'package:flutter_test/flutter_test.dart';
import 'package:BoltStar/src/features/cast/smooth_progress.dart';

const int kLeadMax = 3; // 与实现里的 _leadMax 同步；改实现须同步改这里

void main() {
  group('SmoothProgress', () {
    test('一次大跳被拆成多次递进，且不超过 目标+LEAD_MAX', () async {
      final rendered = <int>[];
      final p = SmoothProgress(
        tick: const Duration(milliseconds: 10),
        onRender: rendered.add,
      );
      p.setTarget(40);
      await Future<void>.delayed(const Duration(milliseconds: 700));
      p.dispose();

      expect(rendered.length, greaterThanOrEqualTo(5), reason: '应被拆成多次递进');
      expect(rendered.last, greaterThanOrEqualTo(40), reason: '最终至少追平目标');
      expect(
        rendered.every((v) => v <= 40 + kLeadMax),
        isTrue,
        reason: '显示值不得超过 目标+LEAD_MAX：$rendered',
      );
      for (var i = 1; i < rendered.length; i++) {
        expect(rendered[i], greaterThanOrEqualTo(rendered[i - 1]),
            reason: '显示值必须单调不减');
      }
    });

    test('增量铺开到整个间隔，而不是几拍冲完就干等（v1 的核心缺陷）', () async {
      final p = SmoothProgress(
        tick: const Duration(milliseconds: 20),
        onRender: (_) {},
      );
      // 模拟真机节奏：每 200ms 一次目标更新、每次 +7%（窗口 50 包 / 共 668 包的推进量）
      p.setTarget(7);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      p.setTarget(14); // 第二次更新到达，此时才建立起间隔观测
      final samples = <int>[];
      for (var i = 0; i < 5; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 40));
        samples.add(p.current);
      }
      p.dispose();
      var moved = 0;
      for (var i = 1; i < samples.length; i++) {
        if (samples[i] > samples[i - 1]) moved++;
      }
      expect(moved, greaterThanOrEqualTo(3),
          reason: '应持续增长而不是冲完就停：$samples');
    });

    test('更新停止后前瞻打满即停表，不空转', () async {
      var renders = 0;
      final p = SmoothProgress(
        tick: const Duration(milliseconds: 10),
        onRender: (_) => renders++,
      );
      p.setTarget(5);
      await Future<void>.delayed(const Duration(milliseconds: 1400));
      final settled = renders;
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(renders, settled, reason: '前瞻打满后不应再有任何渲染');
      expect(p.current, greaterThanOrEqualTo(5));
      expect(p.current, lessThanOrEqualTo(5 + kLeadMax));
      p.dispose();
    });

    test('目标只增不减', () async {
      final p = SmoothProgress(
        tick: const Duration(milliseconds: 10),
        onRender: (_) {},
      );
      p.setTarget(50);
      await Future<void>.delayed(const Duration(milliseconds: 900));
      final settled = p.current;
      p.setTarget(20); // 倒退的目标应被忽略
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(p.current, greaterThanOrEqualTo(settled));
      p.dispose();
    });

    test('jumpTo 立即到位并停表；reset 归零后仍能递进', () async {
      final rendered = <int>[];
      final p = SmoothProgress(
        tick: const Duration(milliseconds: 10),
        onRender: rendered.add,
      );
      p.setTarget(30);
      p.jumpTo(100);
      expect(p.current, 100);
      final afterJump = rendered.length;
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(rendered.length, afterJump, reason: 'jumpTo 之后必须已停表');

      p.reset();
      expect(p.current, 0);
      p.setTarget(10);
      await Future<void>.delayed(const Duration(milliseconds: 600));
      expect(p.current, greaterThanOrEqualTo(10));
      p.dispose();
    });

    test('dispose 后不再产生任何渲染', () async {
      var renders = 0;
      final p = SmoothProgress(
        tick: const Duration(milliseconds: 10),
        onRender: (_) => renders++,
      );
      p.setTarget(80);
      p.dispose();
      final atDispose = renders;
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(renders, atDispose);
    });

    test('落后不得超过 MAX_LAG（传输突然提速时不拖后腿）', () async {
      final p = SmoothProgress(
        tick: const Duration(milliseconds: 10),
        onRender: (_) {},
      );
      p.setTarget(5);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      p.setTarget(10); // 建立「间隔约 300ms」的观测
      await Future<void>.delayed(const Duration(milliseconds: 30));
      p.setTarget(100); // 传输突然提速
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(100 - p.current, lessThanOrEqualTo(12),
          reason: '落后不得超过 MAX_LAG=12（实际 ${100 - p.current}）');
      p.dispose();
    });

    test('失败即冻结（落后段）：报错后绝不继续往前爬', () async {
      var renders = 0;
      final p = SmoothProgress(
        tick: const Duration(milliseconds: 10),
        onRender: (_) => renders++,
      );
      p.setTarget(60);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(p.current, lessThan(60), reason: '前提：此时还没铺完');
      p.freeze();
      final atFreeze = p.current;
      final countAtFreeze = renders;
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(p.current, atFreeze, reason: 'freeze 后显示值必须钉住');
      expect(renders, countAtFreeze, reason: 'freeze 后不应再有渲染');
      p.dispose();
    });

    test('失败即冻结（前瞻段）：领先出去的部分必须收回到真实目标', () async {
      final p = SmoothProgress(
        tick: const Duration(milliseconds: 10),
        onRender: (_) {},
      );
      p.setTarget(30);
      await Future<void>.delayed(const Duration(milliseconds: 700));
      expect(p.current, greaterThan(30), reason: '前提：此刻确实在领先真实目标');
      p.freeze();
      expect(p.current, lessThanOrEqualTo(30),
          reason: '「允许造一点假」的对价条款：失败瞬间必须把领先部分还回去');
      p.dispose();
    });

    test('未真实完成前永不显示 100%（100 只能来自 jumpTo）', () async {
      final rendered = <int>[];
      final p = SmoothProgress(
        tick: const Duration(milliseconds: 10),
        onRender: rendered.add,
      );
      p.setTarget(98);
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      expect(rendered.every((v) => v <= 99), isTrue,
          reason: '99 封顶等真实完成，保证终点时刻与设备一致：${rendered.last}');
      expect(p.current, lessThanOrEqualTo(99));
      p.dispose();
    });
  });
}
