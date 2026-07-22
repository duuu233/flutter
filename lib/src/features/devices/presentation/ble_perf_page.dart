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

  // ── UI ─────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('投屏性能自检')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 40),
        children: [
          if (_busy || _status.isNotEmpty) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF3E8),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  if (_busy) ...[
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
          options: const {
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
          options: const {0.0: '0（默认）', 1.0: '1ms', 2.0: '2ms'},
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
