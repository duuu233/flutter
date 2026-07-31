// 投屏性能自检页（**正式包内可用**的隐藏诊断入口）。
//
// 存在理由：iOS 端的性能问题原本在打好的包里完全是黑箱——
//   · CoreBluetooth **没有任何 API 能读连接间隔**，App 无法自证「0x13 请求的 15ms 生没生效」；
//   · 0x05 回读的可能只是固件保存的配置值，不代表链路实时参数（见 device_ble 注释）；
//   · CrashLogger 只有 Android 实现，iOS 没有任何应用内日志文件；
//   · release 包的 debugPrint 不输出，没有 Mac 就拿不到 Xcode / Console 日志。
// 于是本页把三件事搬进 App：① 链路事实（MTU/分包/写方式）；② 连接间隔的**间接实测**
// （RTT 探针，见 FrameBleClient.probeCommandRtt）；③ 一次纯 BLE 的吞吐测速（不走网络、
// 不依赖后端转码，把「上传+转码」这个大头完全排除，测出来的就是链路本身）。
//
// 入口：设置 → 更新 BoltStar → 连点版本号 7 次（见 update_boltstar_page.dart）。
// 本页刻意**不接 i18n**：与 ble_debug_page 同属工程内部诊断工具，只给开发/测试看。

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import '../../../device/ble/ble_ab_benchmark.dart';
import '../../../device/ble/ble_tuning.dart';
import '../../../device/ble/device_ble.dart';
import '../../../device/ble/frame_protocol.dart';
import '../../../device/ble/image_codec.dart';
import '../../../device/ble_controller.dart';

class BlePerfPage extends StatefulWidget {
  const BlePerfPage({super.key});

  @override
  State<BlePerfPage> createState() => _BlePerfPageState();
}

class _BlePerfPageState extends State<BlePerfPage> {
  BleController get _ctrl => BleController.instance;
  FrameBleClient get _client => _ctrl.client;

  bool _busy = false;
  String _status = '';

  // ── ⚠️ 临时：安卓原生 vs 现有(FBP) 连接对照实验 ──────────────
  // 定版选定一种实现后，本区块所有字段/方法/`_abCard()` 与 ble_ab_benchmark.dart
  // 一并删除（清单见 docs/history/2026-07/2026-07-30-安卓原生连接AB对比.md）。
  BleAbTarget? _abTarget;
  final BleTrialStats _abFbp = BleTrialStats('fbp');
  final BleTrialStats _abNative = BleTrialStats('native');
  BleTrialResult? _abLast;
  bool _abBusy = false;

  /// 每轮先清直连缓存，逼 FBP 走完整扫描——否则它命中快路径几乎瞬时完成，
  /// 与原生探针的完整扫描不在同一起跑线，混在一起统计没有意义。
  bool _abClearCache = true;

  /// 原生侧旋钮：硬件 ScanFilter（+ MATCH_MODE_AGGRESSIVE 才生效）。
  bool _abUseFilter = false;

  /// 原生侧旋钮：一上来就 autoConnect（弱信号唯一真正管用的牌，现有实现排在最后打）。
  bool _abAutoConnect = false;

  /// 原生侧旋钮：复现现有实现「停扫后 120ms 沉淀」的那段延迟；关掉即「扫到即连」。
  bool _abSettle = false;

  // 连接间隔自检结果
  BleRttStats? _rttIdle;
  BleRttStats? _rttFast;
  String _rttVerdict = '';

  // 吞吐测速结果
  String _throughputResult = '';

  bool _cleanupAfterSpeedTest = true;

  @override
  void initState() {
    super.initState();
    BlePerfLog.instance.addListener(_onPerfLog);
  }

  @override
  void dispose() {
    BlePerfLog.instance.removeListener(_onPerfLog);
    super.dispose();
  }

  void _onPerfLog() {
    if (mounted) setState(() {});
  }

  void _setStatus(String s) {
    if (mounted) setState(() => _status = s);
  }

  bool _requireConnected() {
    if (!_ctrl.connected) {
      _setStatus('未连接设备：请先回首页连接相框，再进来自检。');
      return false;
    }
    return true;
  }

  // ── ① 连接间隔自检（RTT 探针）────────────────────────────
  //
  // 做法：同一条最轻的指令(0x04)，先在**空闲档 100ms** 下采一组 RTT，再在**图传档**
  // (Android 7.5 / iOS 15ms) 下采一组，比较两组的**最小值**。
  // RTT ≈ k×连接间隔 + 固件处理时间，取最小值把抖动挤掉后由连接间隔主导：
  //   两组拉开数倍 → 0x13 真的改变了链路参数 → 15ms 生效；
  //   两组几乎相等 → 0x13 对链路无作用（固件没发参数更新请求，或参数违反 Apple 规范被 iOS 拒绝）。
  // 之所以拿 100ms 而不是文档里的 30ms 当对照：100 vs 15 是 6~7 倍差，比 2 倍差好判读得多，
  // 不会被一次偶发重传糊掉。
  Future<void> _runConnIntervalSelfTest() async {
    if (_busy || !_requireConnected()) return;
    setState(() {
      _busy = true;
      _rttIdle = null;
      _rttFast = null;
      _rttVerdict = '';
    });
    try {
      _setStatus('第 1/2 组：把连接间隔设到 100ms（空闲档）…');
      final okIdle = await _trySetInterval(FrameBleClient.idleConnIntervalMs);
      if (!okIdle) {
        _setStatus('设备不认 0x13（老固件）：本项自检无法进行，'
            '说明 App 侧怎么调都改不了连接间隔，请找固件确认是否实现了 0x13。');
        return;
      }
      // 参数更新要走几个连接事件才落定，别立刻开测。
      await Future<void>.delayed(const Duration(milliseconds: 500));
      _setStatus('第 1/2 组：采样中（100ms 档）…');
      final idle = await _client.probeCommandRtt(samples: 16);

      final target = FrameBleClient.transferConnIntervalMs;
      _setStatus('第 2/2 组：把连接间隔设到 ${target}ms（图传档）…');
      await _trySetInterval(target);
      await Future<void>.delayed(const Duration(milliseconds: 500));
      _setStatus('第 2/2 组：采样中（${target}ms 档）…');
      final fast = await _client.probeCommandRtt(samples: 16);

      // 测完回落省电档，别把链路留在费电的极速间隔上。
      await _client.applyIdleConnectionInterval();

      if (idle.isEmpty || fast.isEmpty) {
        _setStatus('采样为空（可能刚好断连或设备一直回忙），请重试。');
        return;
      }
      final ratio = fast.minMs <= 0 ? 0.0 : idle.minMs / fast.minMs;
      final String verdict;
      if (ratio >= 2.5) {
        verdict = '✅ 0x13 生效：改连接间隔确实改变了链路（最小 RTT 快了 '
            '${ratio.toStringAsFixed(1)} 倍）。图传档估算链路间隔约 '
            '${(fast.minMs / 2).toStringAsFixed(0)}ms 量级。';
      } else if (ratio <= 1.3) {
        verdict = '❌ 0x13 对链路无效：两档最小 RTT 基本一样'
            '（${idle.minMs.toStringAsFixed(1)} vs ${fast.minMs.toStringAsFixed(1)}ms）。'
            '固件要么没真的发起连接参数更新，要么发的参数被系统拒绝'
            '（Apple 规范要求 IntervalMax ≥ IntervalMin + 15ms、Timeout ≤ 6s）。'
            'App 侧再怎么调都没用，请找固件。';
      } else {
        verdict = '⚠️ 不确定（${ratio.toStringAsFixed(1)} 倍）：差异存在但不明显。'
            '请远离其它蓝牙设备、贴近相框重测 2~3 次取一致结果。';
      }
      BlePerfLog.instance.add(
        'rtt',
        'connInterval self-test idle(100ms) $idle | fast(${target}ms) $fast | ratio=${ratio.toStringAsFixed(2)}',
      );
      setState(() {
        _rttIdle = idle;
        _rttFast = fast;
        _rttVerdict = verdict;
        _status = '';
      });
    } catch (e) {
      _setStatus('自检失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _trySetInterval(double ms) async {
    try {
      await _client.setConnectionIntervalMs(ms);
      return true;
    } catch (_) {
      return false;
    }
  }

  // ── ② 纯 BLE 吞吐测速 ───────────────────────────────────
  //
  // 用本地生成的彩条测试帧（尺寸天生正确、不联网、不经后端转码），把「原图上传 + 后端转码」
  // 这个大头整个排除，测出来的 KB/s 就是链路本身的吞吐。判读基线见 docs/iOS-投屏性能测试指南.md：
  //   Android ≈ 30~40KB/s；iOS 生效 ≈ 30~35KB/s，未生效 ≈ 15~18KB/s。
  Future<void> _runThroughputTest() async {
    if (_busy || !_requireConnected()) return;
    setState(() {
      _busy = true;
      _throughputResult = '';
    });
    int? writtenIndex;
    try {
      _setStatus('读取设备信息(0x01)…');
      final info = await _client.readTransferInfo();
      if (info.width == 0 || info.height == 0 || info.screenType == 0x03) {
        _setStatus('该设备不支持图传或信息异常（${info.width}×${info.height}，'
            'screenType=0x${info.screenType.toRadixString(16)}）。');
        return;
      }
      final index = FrameProtocol.firstFreeIndex(info.imgMask, info.capacity);
      if (index < 0) {
        _setStatus('设备已存满，测速需要一个空槽位：请先删几张图再来。');
        return;
      }
      final frame = FrameImageCodec.buildColorBars(info.width, info.height);
      _setStatus('传输中…（${frame.dataSize} 字节 → 槽位 $index）');
      final sw = Stopwatch()..start();
      await _client.uploadImage(
        screenType: info.screenType,
        index: index,
        width: info.width,
        height: info.height,
        data: frame.data,
        onProgress: (done, total, phase, {stuckAt, retries}) {
          if (!mounted || total == 0) return;
          if (done % 50 != 0 && done != total) return;
          _setStatus('传输中… $done/$total 包'
              '${phase == 'retry' ? '（卡在第 $stuckAt 包，第 $retries 次重发）' : ''}');
        },
      );
      sw.stop();
      writtenIndex = index;
      // 详细数字（吞吐/包数/重传）由 uploadImage 自己写进 BlePerfLog，下方列表第一条即是。
      final latest = BlePerfLog.instance.records
          .firstWhere((r) => r.tag == 'upload', orElse: () => BlePerfRecord(DateTime.now(), 'upload', '（无记录）'));
      setState(() {
        _throughputResult = '${latest.text}\n（含 0x20/0x22 的整轮耗时 ${sw.elapsedMilliseconds}ms）';
        _status = '';
      });
    } catch (e) {
      _setStatus('测速失败：$e');
    } finally {
      // 测试图不该占用户的槽位。删除失败不影响结论，只提示。
      if (writtenIndex != null && _cleanupAfterSpeedTest) {
        try {
          await _client.deleteImage([writtenIndex]);
        } catch (_) {}
      }
      if (mounted) setState(() => _busy = false);
    }
  }

  // ── ⚠️ 临时：连接对照实验的动作 ──────────────────────────

  /// 扫一轮，让用户点选被测目标。刻意不依赖后端设备列表：对照实验只关心射频与协议栈，
  /// 少一个网络依赖就少一个干扰源。
  Future<void> _pickAbTarget() async {
    setState(() {
      _abBusy = true;
      _status = '正在扫描在场相框…';
    });
    try {
      final found = await BleAbBenchmark.discoverTargets();
      if (!mounted) return;
      if (found.isEmpty) {
        setState(() => _status = '没扫到相框。确认设备已开机、且没有被别的 App 连着。');
        return;
      }
      final picked = await showDialog<BleAbTarget>(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: const Text('选择被测设备'),
          children: [
            for (final r in found)
              SimpleDialogOption(
                onPressed: () {
                  final ad = BleController.advertisingOf(r);
                  Navigator.pop(
                    ctx,
                    BleAbTarget(
                      serial: ad?.deviceId ?? '',
                      name: BleController.displayName(r),
                      screenCode: ad?.screenType ?? 0,
                    ),
                  );
                },
                child: Text(
                  '${BleController.displayName(r)}\n'
                  '${BleController.advertisingOf(r)?.deviceId ?? '无厂商数据'}  rssi=${r.rssi}',
                  style: const TextStyle(fontSize: 13, height: 1.4),
                ),
              ),
          ],
        ),
      );
      if (!mounted || picked == null) return;
      if (picked.serial.isEmpty) {
        setState(() => _status = '这台广播里没有厂商数据，拿不到设备 ID，换一台再试。');
        return;
      }
      setState(() {
        _abTarget = picked;
        _status = '目标已选定：${picked.label}';
      });
    } catch (error) {
      if (mounted) setState(() => _status = '扫描失败：$error');
    } finally {
      if (mounted) setState(() => _abBusy = false);
    }
  }

  /// 跑一次对照。[native] 决定走哪条路径——页面上就是两个按钮。
  Future<void> _runAbTrial({required bool native}) async {
    final target = _abTarget;
    if (target == null || _abBusy) return;
    setState(() {
      _abBusy = true;
      _status = native ? '原生路径连接中…' : '现有路径连接中…';
    });
    try {
      final result = native
          ? await BleAbBenchmark.runNativeTrial(
              target: target,
              useScanFilter: _abUseFilter,
              autoConnect: _abAutoConnect,
              settleMs: _abSettle ? 120 : 0,
            )
          : await BleAbBenchmark.runFbpTrial(
              target: target,
              clearDirectCache: _abClearCache,
            );
      if (!mounted) return;
      setState(() {
        (native ? _abNative : _abFbp).results.add(result);
        _abLast = result;
        _status = result.summary;
      });
    } finally {
      if (mounted) setState(() => _abBusy = false);
    }
  }

  void _clearAbStats() {
    setState(() {
      _abFbp.clear();
      _abNative.clear();
      _abLast = null;
      _status = '对照数据已清空';
    });
  }

  Future<void> _copyAbReport() async {
    await Clipboard.setData(
      ClipboardData(
        text: BleAbBenchmark.report(
          target: _abTarget,
          fbp: _abFbp,
          native: _abNative,
        ),
      ),
    );
    if (mounted) setState(() => _status = '对照报告已复制到剪贴板');
  }

  // ── UI ─────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('投屏性能自检')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 40),
        children: [
          if (_busy || _abBusy || _status.isNotEmpty) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF3E8),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  if (_busy || _abBusy) ...[
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: Text(
                      _status.isEmpty ? '进行中…' : _status,
                      style: const TextStyle(fontSize: 13, height: 1.5),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          _abCard(),
          const SizedBox(height: 12),
          _linkCard(),
          const SizedBox(height: 12),
          _connIntervalCard(),
          const SizedBox(height: 12),
          _throughputCard(),
          const SizedBox(height: 12),
          _tuningCard(),
          const SizedBox(height: 12),
          _logCard(),
        ],
      ),
    );
  }

  Widget _card({required String title, required List<Widget> children}) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _kv(String k, String v, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 96, child: Text(k, style: const TextStyle(fontSize: 13, color: Color(0xFF808690)))),
          Expanded(
            child: Text(v, style: TextStyle(fontSize: 13, color: color ?? const Color(0xFF2A2D32))),
          ),
        ],
      ),
    );
  }

  /// ⚠️ 临时：安卓原生 vs 现有(FBP) 连接对照。定版后整卡删除。
  ///
  /// 用法：选目标 → 交替按两个按钮各若干次 → 看成功率与「失败停在哪一步」。
  /// **两个按钮要交替按、不要一口气按满一边**：射频环境是会漂的，
  /// 分段按能让两条路径共享同一段环境，否则比的是「前五分钟 vs 后五分钟」。
  Widget _abCard() {
    final target = _abTarget;
    final canRun = target != null && !_abBusy;
    return _card(
      title: '⓪ 连接对照实验（临时）',
      children: [
        _kv('被测目标', target?.label ?? '未选择'),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton(
            onPressed: _abBusy ? null : _pickAbTarget,
            child: Text(target == null ? '扫描并选择设备' : '重新选择'),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: FilledButton(
                onPressed: canRun ? () => _runAbTrial(native: false) : null,
                child: const Text('现有路径'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton.tonal(
                onPressed: canRun && BleAbBenchmark.nativeSupported
                    ? () => _runAbTrial(native: true)
                    : null,
                child: const Text('原生路径'),
              ),
            ),
          ],
        ),
        if (!BleAbBenchmark.nativeSupported)
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text(
              '原生探针仅安卓可用（iOS 的 connect 本身就是「一直等到连上」语义，没有对应旋钮）。',
              style: TextStyle(fontSize: 12, color: Color(0xFF808690), height: 1.5),
            ),
          ),
        const SizedBox(height: 12),
        _abStatsRow('现有(FBP)', _abFbp),
        _abStatsRow('原生', _abNative),
        const SizedBox(height: 8),
        const Text(
          '开关（改完从下一次点击起生效）',
          style: TextStyle(fontSize: 12, color: Color(0xFF808690)),
        ),
        _abSwitch(
          '每轮先清直连缓存',
          '让现有路径也走完整扫描，与原生同起跑线；缓存下次正常连接后自动重建。',
          _abClearCache,
          (v) => setState(() => _abClearCache = v),
        ),
        _abSwitch(
          '原生：硬件扫描过滤 + AGGRESSIVE',
          '让控制器在射频侧丢掉非相框广播。代价是广播必须每包都带厂商数据，真机未必如此——'
              '这正是要测的。MATCH_MODE_AGGRESSIVE 只在带过滤时生效。',
          _abUseFilter,
          (v) => setState(() => _abUseFilter = v),
        ),
        _abSwitch(
          '原生：直接用 autoConnect',
          '现有实现把 autoConnect 排在超时阶梯最后（正常信号要先白等 13.4s）。'
              '打开这个即「一上来就打这张牌」。',
          _abAutoConnect,
          (v) => setState(() => _abAutoConnect = v),
        ),
        _abSwitch(
          '原生：复现 120ms 停扫沉淀',
          '关闭 = 扫到即连（原生独有的零延迟）。打开则与现有实现同样先沉淀 120ms，'
              '用来判断这段延迟到底值不值。',
          _abSettle,
          (v) => setState(() => _abSettle = v),
        ),
        if (_abLast != null) ...[
          const SizedBox(height: 10),
          const Text('最近一次', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          SelectableText(
            _abLast!.log.isEmpty
                ? _abLast!.summary
                : '${_abLast!.summary}\n${_abLast!.log.join('\n')}',
            style: const TextStyle(fontSize: 11, height: 1.5, fontFamily: 'monospace'),
          ),
        ],
        const SizedBox(height: 10),
        Row(
          children: [
            OutlinedButton(
              onPressed: _abBusy ? null : _copyAbReport,
              child: const Text('复制报告'),
            ),
            const SizedBox(width: 10),
            OutlinedButton(
              onPressed: _abBusy ? null : _clearAbStats,
              child: const Text('清空'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _abStatsRow(String label, BleTrialStats stats) {
    final failures = stats.failureStages;
    final detail = StringBuffer()
      ..write('${stats.success}/${stats.total}（${stats.successRate}）');
    if (stats.medianMs != null) {
      detail.write('  中位 ${stats.medianMs}ms');
      detail.write('  ${stats.minMs}~${stats.maxMs}ms');
    }
    if (failures.isNotEmpty) {
      detail.write(
        '  失败：${failures.entries.map((e) => '${e.key}×${e.value}').join('，')}',
      );
    }
    return _kv(label, detail.toString());
  }

  Widget _abSwitch(
    String title,
    String hint,
    bool value,
    ValueChanged<bool> onChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 13)),
                Text(
                  hint,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF808690),
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          Switch(value: value, onChanged: _abBusy ? null : onChanged),
        ],
      ),
    );
  }

  Widget _linkCard() {
    final connected = _ctrl.connected;
    final chunk = _client.dataChunk;
    // 172KB(480×720 4bpp) 一帧要多少包——直观显示分包大小的代价。
    final packets = chunk > 0 ? (172800 / chunk).round() : 0;
    return _card(
      title: '① 链路事实',
      children: [
        _kv('连接状态', connected ? '已连接' : '未连接',
            color: connected ? const Color(0xFF2E7D32) : const Color(0xFFD32F2F)),
        _kv('设备', _ctrl.info?.deviceId ?? '—'),
        _kv('MTU', '${_client.mtu}'),
        _kv('每包数据', '$chunk 字节（172KB 一帧约 $packets 包）',
            color: chunk < 100 ? const Color(0xFFD32F2F) : null),
        _kv('写方式', _client.writeWithoutResponse ? '无应答写' : '有应答写'),
        _kv('图传档请求', BleTuning.skipConnIntervalRequest
            ? '不下发 0x13（阴性对照）'
            : '${FrameBleClient.transferConnIntervalMs}ms'),
        if (chunk < 100)
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text(
              '⚠️ 每包字节异常偏低，说明 MTU 没协商上来。这会让包数暴涨十几倍，'
              '是比连接间隔严重得多的问题——先解决它，再看下面两项。',
              style: TextStyle(fontSize: 12, color: Color(0xFFD32F2F), height: 1.5),
            ),
          ),
      ],
    );
  }

  Widget _connIntervalCard() {
    return _card(
      title: '② 连接间隔自检（判断 0x13 是否真的生效）',
      children: [
        const Text(
          '同一条最轻的指令，先在 100ms 档采 16 次往返、再在图传档采 16 次，比最小往返时间。'
          'iOS 上这是 App 内唯一可信的判据——CoreBluetooth 没有读连接间隔的 API，0x05 回读的'
          '可能只是固件保存的配置值。约需 20 秒，请贴近相框、避开其它蓝牙设备。',
          style: TextStyle(fontSize: 12, color: Color(0xFF808690), height: 1.5),
        ),
        const SizedBox(height: 10),
        FilledButton(
          onPressed: _busy ? null : _runConnIntervalSelfTest,
          child: const Text('开始自检'),
        ),
        if (_rttIdle != null) ...[
          const SizedBox(height: 10),
          _kv('100ms 档', '$_rttIdle'),
          _kv('图传档', '$_rttFast'),
        ],
        if (_rttVerdict.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(_rttVerdict, style: const TextStyle(fontSize: 13, height: 1.6)),
        ],
      ],
    );
  }

  Widget _throughputCard() {
    return _card(
      title: '③ 纯 BLE 吞吐测速',
      children: [
        const Text(
          '本地生成一张彩条测试帧直传设备：不联网、不经后端转码，测的就是链路本身。'
          '基线：Android 约 30~40KB/s；iOS 若 15ms 生效约 30~35KB/s，未生效约 15~18KB/s。',
          style: TextStyle(fontSize: 12, color: Color(0xFF808690), height: 1.5),
        ),
        Row(
          children: [
            Checkbox(
              value: _cleanupAfterSpeedTest,
              onChanged: _busy ? null : (v) => setState(() => _cleanupAfterSpeedTest = v ?? true),
            ),
            const Expanded(
              child: Text('测完自动删除这张测试图', style: TextStyle(fontSize: 13)),
            ),
          ],
        ),
        FilledButton(
          onPressed: _busy ? null : _runThroughputTest,
          child: const Text('开始测速'),
        ),
        if (_throughputResult.isNotEmpty) ...[
          const SizedBox(height: 8),
          SelectableText(_throughputResult,
              style: const TextStyle(fontSize: 12, height: 1.5, fontFamily: 'monospace')),
        ],
      ],
    );
  }

  Widget _tuningCard() {
    return _card(
      title: '④ 调优旋钮（改完立即生效，跨启动保留）',
      children: [
        const Text(
          '正常投屏也会用这里的值——调完可以直接回去投一批真图体验。'
          '拿不准就点「恢复默认」。',
          style: TextStyle(fontSize: 12, color: Color(0xFF808690), height: 1.5),
        ),
        const SizedBox(height: 8),
        _choiceRow<double?>(
          label: '图传连接间隔',
          current: BleTuning.skipConnIntervalRequest ? -1.0 : BleTuning.connIntervalOverrideMs,
          // 注意：double key 没有 primitive equality，不能用 const map（AOT 编译会报错）
          options: {
            null: '平台默认',
            15.0: '15ms',
            30.0: '30ms',
            100.0: '100ms',
            -1.0: '不下发',
          },
          onPick: (v) {
            BleTuning.skipConnIntervalRequest = v == -1.0;
            BleTuning.connIntervalOverrideMs = (v == -1.0) ? null : v;
          },
        ),
        _choiceRow<double>(
          label: '发送地板 pace',
          current: BleTuning.paceFloorMs,
          options: {0.0: '0（默认）', 1.0: '1ms', 2.0: '2ms'},
          onPick: (v) => BleTuning.paceFloorMs = v,
        ),
        _choiceRow<int>(
          label: '滑窗大小',
          current: BleTuning.windowPackets,
          options: const {10: '10（默认）', 6: '6', 3: '3', 1: '1'},
          onPick: (v) => BleTuning.windowPackets = v,
        ),
        _choiceRow<bool>(
          label: '数据包写方式',
          current: BleTuning.forceAckedWrite,
          options: const {false: '无应答（默认）', true: '有应答'},
          onPick: (v) => BleTuning.forceAckedWrite = v,
        ),
        _choiceRow<AndroidConnectStrategy>(
          label: '安卓建连预算',
          current: BleTuning.androidConnectStrategy,
          options: const {
            AndroidConnectStrategy.directFirst: '长直连优先（默认）',
            AndroidConnectStrategy.autoConnectFirst: '早切 autoConnect（旧）',
          },
          onPick: (v) => BleTuning.androidConnectStrategy = v,
        ),
        const SizedBox(height: 8),
        const Text(
          '「安卓建连预算」两档的总时长几乎一样，差别只在钱花在哪：\n'
          '· 长直连优先＝弱 12s / 极弱 16s 常规定向连接（控制器占空比≈50%），autoConnect 只留 5~8s 兜底；\n'
          '· 早切 autoConnect＝弱 5s 后就切、极弱直接切，把 15~20s 全给 autoConnect（占空比≈0.9%）。\n'
          '在同一个弱信号位置交替切换、各连 8~10 次比成功率与耗时，别一口气测完一档再测另一档。',
          style: TextStyle(fontSize: 12, color: Color(0xFF808690), height: 1.5),
        ),
        const SizedBox(height: 8),
        const Text(
          '「有应答写」只用来证伪：它每包都等设备确认，一定更慢，但绝不静默丢包。'
          '若切过去之后 retries 从一堆变成 0，就说明无应答写在 iOS 上丢包（缺背压）。',
          style: TextStyle(fontSize: 12, color: Color(0xFF808690), height: 1.5),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: _busy
              ? null
              : () async {
                  await BleTuning.resetToDefaults();
                  if (mounted) setState(() {});
                },
          child: const Text('恢复默认'),
        ),
      ],
    );
  }

  Widget _choiceRow<T>({
    required String label,
    required T current,
    required Map<T, String> options,
    required void Function(T value) onPick,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 96, child: Text(label, style: const TextStyle(fontSize: 13, color: Color(0xFF808690)))),
          Expanded(
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              children: options.entries.map((e) {
                return ChoiceChip(
                  label: Text(e.value, style: const TextStyle(fontSize: 12)),
                  selected: current == e.key,
                  onSelected: _busy
                      ? null
                      : (_) async {
                          onPick(e.key);
                          await BleTuning.save();
                          if (mounted) setState(() {});
                        },
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _logCard() {
    final records = BlePerfLog.instance.records;
    return _card(
      title: '⑤ 埋点记录（最新在前，共 ${records.length} 条）',
      children: [
        Row(
          children: [
            OutlinedButton(
              onPressed: records.isEmpty
                  ? null
                  : () async {
                      await Clipboard.setData(
                        ClipboardData(text: BlePerfLog.instance.exportText()),
                      );
                      if (mounted) _setStatus('已复制 ${records.length} 条到剪贴板');
                    },
              child: const Text('复制全部'),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: records.isEmpty ? null : () => BlePerfLog.instance.clear(),
              child: const Text('清空'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (records.isEmpty)
          const Text('还没有记录：连接一次设备、或投一张图就会有。',
              style: TextStyle(fontSize: 12, color: Color(0xFF808690)))
        else
          ...records.take(60).map(
                (r) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: SelectableText(
                    '${r.stamp} [${r.tag}] ${r.text}',
                    style: TextStyle(
                      fontSize: 11,
                      height: 1.45,
                      fontFamily: 'monospace',
                      color: r.tag == 'warn' ? const Color(0xFFD32F2F) : const Color(0xFF2A2D32),
                    ),
                  ),
                ),
              ),
      ],
    );
  }
}
