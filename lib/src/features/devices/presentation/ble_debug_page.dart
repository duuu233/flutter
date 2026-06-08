// BLE 图传调试页：对标微信小程序版 `subpackages/device/debug`，把能联调的功能做成按钮，
// 点一下发一条 BLE 指令，下方实时打印收发的 16 进制原始字节，方便和硬件侧日志对照排查。
//
// 本页独有：上传图片前可一键请求「短连接间隔(高优先级)」、传完恢复「省电(低功耗)」，
// 图传时也会自动套用同样的连接间隔策略——这是微信小程序做不到、用来解决图传卡死的关键。

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../../../device/ble/device_ble.dart';
import '../../../device/ble/frame_protocol.dart';
import '../../../device/ble/image_codec.dart';
import '../../../native_device_api.dart';

class BleDebugPage extends StatefulWidget {
  const BleDebugPage({super.key});

  @override
  State<BleDebugPage> createState() => _BleDebugPageState();
}

class _LogEntry {
  _LogEntry(this.time, this.type, this.text);
  final String time;
  final String type; // tx / rx / act / ok / err
  final String text;
}

class _BleDebugPageState extends State<BleDebugPage> {
  final FrameBleClient _client = FrameBleClient();

  bool _scanning = false;
  bool _connecting = false;
  bool _connected = false;
  bool _busy = false;
  bool _uploading = false;

  List<ScanResult> _devices = [];
  String _deviceName = '';
  FrameDeviceInfo? _info;

  int _pace = 45; // 每包发送间隔(ms)
  double _uploadPercent = 0;
  String _uploadStatus = '';

  // 六色量化调参（仅相册图生效，可在真机上实时 A/B，把上传图与原图差距调到最小）。
  bool _dither = true;
  double _contrast = 1.12;
  double _saturation = 1.28;

  final List<_LogEntry> _logs = [];
  final TextEditingController _intervalCtrl = TextEditingController(text: '60');
  final TextEditingController _switchCtrl = TextEditingController(text: '0');
  final TextEditingController _deleteCtrl = TextEditingController();
  final TextEditingController _uploadIndexCtrl = TextEditingController();
  String _playMode = 'order';

  @override
  void initState() {
    super.initState();
    _client.onMonitor = _onMonitor;
  }

  @override
  void dispose() {
    _client.disconnect();
    _intervalCtrl.dispose();
    _switchCtrl.dispose();
    _deleteCtrl.dispose();
    _uploadIndexCtrl.dispose();
    super.dispose();
  }

  // ── 日志 ────────────────────────────────────────────────
  String _now() {
    final d = DateTime.now();
    String p2(int n) => n.toString().padLeft(2, '0');
    String p3(int n) => n.toString().padLeft(3, '0');
    return '${p2(d.hour)}:${p2(d.minute)}:${p2(d.second)}.${p3(d.millisecond)}';
  }

  void _log(String type, String text) {
    if (!mounted) return;
    setState(() {
      _logs.insert(0, _LogEntry(_now(), type, text));
      if (_logs.length > 300) _logs.removeRange(300, _logs.length);
    });
  }

  void _onMonitor(BleMonitorRecord r) {
    final cmdHex = r.cmd.toRadixString(16).padLeft(2, '0').toUpperCase();
    final arrow = r.dir == 'TX' ? '▶ 发送' : '◀ 接收';
    final note = r.note.isNotEmpty ? '[${r.note}] ' : '';
    _log(r.dir == 'TX' ? 'tx' : 'rx', '$arrow CMD=0x$cmdHex $note${r.hex}');
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
  }

  // ── 扫描 / 连接 ─────────────────────────────────────────
  Future<bool> _ensurePermission() async {
    final status = await NativeDeviceApi.requestBluetoothPermissions();
    if (!status.bluetoothPermissionGranted) {
      _toast('请先授予蓝牙权限');
      return false;
    }
    if (!status.bluetoothEnabled) {
      _toast('请先打开手机蓝牙');
      return false;
    }
    return true;
  }

  Future<void> _scan() async {
    if (_scanning) return;
    if (!await _ensurePermission()) return;
    setState(() {
      _scanning = true;
      _devices = [];
    });
    try {
      final list = await FrameBleClient.scan(timeout: const Duration(seconds: 8));
      if (!mounted) return;
      setState(() => _devices = list);
      _log('act', '扫描完成，发现 ${list.length} 个设备');
    } catch (e) {
      _toast('扫描失败：$e');
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<void> _connect(ScanResult r) async {
    final name = r.device.platformName.isNotEmpty
        ? r.device.platformName
        : (r.advertisementData.advName.isNotEmpty
            ? r.advertisementData.advName
            : r.device.remoteId.str);
    setState(() {
      _connecting = true;
      _deviceName = name;
    });
    try {
      await _client.connect(r.device);
      setState(() => _connected = true);
      _log('ok', '已连接：$name');
      _log(
          'act',
          '协商 MTU=${_client.mtu} 字节，图传每包 ${_client.dataChunk} 字节，'
          '写入方式：${_client.writeWithoutResponse ? '无应答写' : '有应答写'}');
      await _refreshInfo();
    } catch (e) {
      setState(() => _connected = false);
      _log('err', '连接失败：$e');
      _toast('连接失败：$e');
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  Future<void> _disconnect() async {
    await _client.disconnect();
    if (!mounted) return;
    setState(() {
      _connected = false;
      _info = null;
    });
    _log('act', '已断开连接');
  }

  Future<void> _refreshInfo() async {
    try {
      final info = await _client.readDeviceInfo();
      if (!mounted) return;
      setState(() => _info = info);
    } catch (_) {}
  }

  bool _requireDevice() {
    if (!_connected) {
      _toast('请先连接设备');
      return false;
    }
    return true;
  }

  Future<void> _runCommand(String label, Future<String> Function() fn,
      {bool refresh = false}) async {
    if (!_requireDevice()) return;
    if (_busy) {
      _toast('请等待上一条指令完成');
      return;
    }
    setState(() => _busy = true);
    _log('act', '点击：$label');
    try {
      final text = await fn();
      _log('ok', text);
      if (refresh) await _refreshInfo();
      _toast('指令成功');
    } catch (e) {
      _log('err', '$label 失败：$e');
      _toast('$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ── 指令 ────────────────────────────────────────────────
  void _cmdGetInfo() => _runCommand('获取设备信息(0x01)', () async {
        await _refreshInfo();
        final i = _info;
        if (i == null) return '设备信息已刷新';
        return '设备信息：电量 ${i.battery}% · ${i.screen} · 容量 ${i.capacity} · '
            '已存 ${i.imgCount} 张 · 固件 ${i.firmwareVersion.isEmpty ? '--' : i.firmwareVersion}';
      });

  void _cmdGetBattery() => _runCommand(
      '获取电量(0x04)', () async => '当前电量：${await _client.readBattery()}%');

  void _cmdGetVersion() => _runCommand(
      '获取软件版本(0x03)', () async => '固件版本：${await _client.getSwVersion()}');

  void _cmdGetPlay() => _runCommand('获取播放配置(0x02)', () async {
        final c = await _client.getPlayConfig();
        return '播放配置：${_playModeText(c.playMode)} · 间隔 ${c.intervalSeconds} 秒';
      });

  void _cmdSetPlay() {
    final interval = int.tryParse(_intervalCtrl.text) ?? -1;
    if (interval < 1) {
      _toast('请输入有效的间隔秒数');
      return;
    }
    _runCommand('设置播放配置(0x10)', () async {
      await _client.setPlayback(_playMode, interval);
      return '已设为 ${_playModeText(_playMode)} 播放 · 间隔 $interval 秒';
    }, refresh: true);
  }

  void _cmdSetTime() => _runCommand('校准时间(0x11)', () async {
        await _client.setTime(DateTime.now());
        return '已把手机当前时间同步给设备';
      });

  void _cmdSwitch() {
    final index = int.tryParse(_switchCtrl.text) ?? -1;
    if (index < 0) {
      _toast('请输入要显示的图片索引');
      return;
    }
    _runCommand('切换显示(0x24)', () async {
      final cur = await _client.refreshScreen(index);
      return '屏幕已切到索引 ${cur == 0xff ? '保持不变' : cur}';
    }, refresh: true);
  }

  void _cmdDelete() {
    final parts = _deleteCtrl.text
        .split(RegExp(r'[,，\s]+'))
        .where((s) => s.isNotEmpty)
        .map((s) => int.tryParse(s) ?? -1)
        .toList();
    if (parts.isEmpty || parts.any((n) => n < 0 || n > 95)) {
      _toast('请输入要删除的索引(0~95，逗号分隔)');
      return;
    }
    _runCommand('删除图片(0x12) 索引[${parts.join(',')}]', () async {
      final mask = await _client.deleteImage(parts);
      return '删除完成，设备现存 ${FrameProtocol.maskToIndexes(mask).length} 张';
    }, refresh: true);
  }

  String _playModeText(String m) =>
      m == 'random' ? '随机' : (m == 'manual' ? '手动' : '顺序');

  // ── 连接间隔（手动测试）────────────────────────────────
  Future<void> _setFast() async {
    if (!_requireDevice()) return;
    await _client.requestFastConnection();
    _log('act', '已请求短连接间隔(高优先级 ConnectionPriority.high)');
    _toast('已请求短连接间隔');
  }

  Future<void> _setPowerSave() async {
    if (!_requireDevice()) return;
    await _client.requestPowerSaveConnection();
    _log('act', '已请求省电连接间隔(低功耗 ConnectionPriority.lowPower)');
    _toast('已恢复省电连接间隔');
  }

  // ── 图传 ────────────────────────────────────────────────
  bool _ensureUploadReady() {
    if (!_requireDevice()) return false;
    if (_busy || _uploading) {
      _toast('请等待当前操作完成');
      return false;
    }
    final i = _info;
    if (i == null || i.width == 0) {
      _toast('请先点「获取设备信息」');
      return false;
    }
    if (i.screenType == 0x03) {
      _toast('7.3寸为占位型号，固件未实现图传');
      return false;
    }
    return true;
  }

  void _uploadColorBars() {
    if (!_ensureUploadReady()) return;
    final i = _info!;
    final frame = FrameImageCodec.buildColorBars(i.width, i.height);
    _upload(frame, '上传彩条测试图(0x20~0x22)');
  }

  void _uploadSolidWhite() {
    if (!_ensureUploadReady()) return;
    final i = _info!;
    final frame = FrameImageCodec.buildSolid(i.width, i.height, 0x1);
    _upload(frame, '上传纯白测试图(0x20~0x22)');
  }

  /// 选相册图片 → 原生解码裁剪到设备分辨率 → 六色量化 → 走图传上传。
  Future<void> _uploadFromGallery() async {
    if (!_ensureUploadReady()) return;
    final i = _info!;
    setState(() {
      _uploading = true;
      _uploadPercent = 0;
      _uploadStatus = '选择相册图片…';
    });
    try {
      final perm = await NativeDeviceApi.requestPhotoPermission();
      if (!perm.photoPermissionGranted) {
        _toast('请先授予相册权限');
        setState(() => _uploadStatus = '未授予相册权限');
        return;
      }
      final sel = await NativeDeviceApi.openGallery();
      if (sel == null) {
        setState(() => _uploadStatus = '已取消选择');
        return;
      }
      setState(() => _uploadStatus = '解码并裁剪到 ${i.width}×${i.height}…');
      final rgba = await NativeDeviceApi.decodeImageRgba(
        uri: sel.uri,
        width: i.width,
        height: i.height,
      );
      if (rgba == null || rgba.length != i.width * i.height * 4) {
        _toast('图片解码失败');
        setState(() => _uploadStatus = '图片解码失败');
        return;
      }
      _log('act',
          '相册图「${sel.title}」已解码 ${i.width}×${i.height}，量化(抖动${_dither ? '开' : '关'}/对比度${_contrast.toStringAsFixed(2)}/饱和度${_saturation.toStringAsFixed(2)})…');
      setState(() => _uploadStatus = '六色量化中…');
      final frame = FrameImageCodec.fromRgba(
        rgba,
        i.width,
        i.height,
        dither: _dither,
        contrast: _contrast,
        saturation: _saturation,
      );
      // _upload 内部自管 _uploading/进度，成功后保留其完成提示。
      await _upload(frame, '上传相册图片「${sel.title}」(0x20~0x22)');
    } catch (e) {
      _log('err', '相册上传失败：$e');
      if (mounted) setState(() => _uploadStatus = '相册上传失败：$e');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  /// 解析图传目标槽位：输入框留空=自动选第一个空位；填数字=指定槽位(0~capacity-1)。
  /// 返回 -1 表示出错(已 toast 提示)，调用方应中止本次上传。
  int _resolveUploadIndex(FrameDeviceInfo i) {
    final raw = _uploadIndexCtrl.text.trim();
    if (raw.isEmpty) {
      final auto = FrameProtocol.firstFreeIndex(i.imgMask, i.capacity);
      if (auto < 0) _toast('设备已存满，请先删除图片或在上方指定要覆盖的索引');
      return auto;
    }
    final maxIndex = (i.capacity > 0 ? i.capacity : 96) - 1;
    final n = int.tryParse(raw) ?? -1;
    if (n < 0 || n > maxIndex) {
      _toast('索引超出范围，应为 0~$maxIndex');
      return -1;
    }
    return n;
  }

  Future<void> _upload(FrameBuffer frame, String label) async {
    final i = _info!;
    final index = _resolveUploadIndex(i);
    if (index < 0) return; // 错误已在 _resolveUploadIndex 内提示
    final overwrite = FrameProtocol.maskToIndexes(i.imgMask).contains(index);
    final totalPackets = (frame.dataSize + 235) ~/ 236;
    setState(() {
      _uploading = true;
      _uploadPercent = 0;
      _uploadStatus = '传输中：槽位 $index，约 $totalPackets 包…';
    });
    _log('act',
        '$label → 槽位 $index${overwrite ? '（覆盖已有）' : ''}，数据 ${frame.dataSize} 字节');
    try {
      final summary = await _client.uploadImage(
        screenType: i.screenType,
        index: index,
        width: i.width,
        height: i.height,
        data: frame.data,
        pace: _pace,
        onProgress: (done, total, phase, {stuckAt, retries}) {
          if (!mounted) return;
          setState(() {
            _uploadPercent = total == 0 ? 0 : done / total;
            if (phase == 'retry') {
              _uploadStatus =
                  '传输卡顿：停在第 ${stuckAt ?? -1} 包，正第 ${retries ?? 0} 次重发…（此数字长时间不动多为设备/链路问题）';
            } else {
              _uploadStatus = '传输中：$done/$total 包';
            }
          });
        },
      );
      _log('ok',
          '图传完成 ✓ 设备现存 ${summary.imgCount} 张，剩余 ${summary.storageFree} 字节');
      setState(() => _uploadStatus = '图传完成 ✓ 现存 ${summary.imgCount} 张');
      await _client.refreshScreen(index);
      await _refreshInfo();
      _toast('上传成功');
    } catch (e) {
      _log('err', '图传失败：$e');
      if (mounted) setState(() => _uploadStatus = '图传失败：$e');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  // ── UI ──────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('BLE 图传调试'),
        actions: [
          if (_connected)
            TextButton(
              onPressed: _disconnect,
              child: const Text('断开', style: TextStyle(color: Colors.white)),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 40),
        children: [
          _connectCard(),
          if (!_connected) _deviceListCard(),
          if (_connected) ...[
            _infoCard(),
            _connIntervalCard(),
            _readCard(),
            _setCard(),
            _imageCard(),
          ],
          _logCard(),
        ],
      ),
    );
  }

  Widget _section(String title, List<Widget> children) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: 8),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _connectCard() {
    return _section('连接', [
      Row(children: [
        Expanded(
          child: Text(_connected
              ? '已连接：$_deviceName'
              : (_connecting ? '连接中…' : '未连接')),
        ),
        FilledButton(
          onPressed: _scanning || _connecting ? null : _scan,
          child: Text(_scanning ? '扫描中…' : '扫描设备'),
        ),
      ]),
    ]);
  }

  Widget _deviceListCard() {
    if (_devices.isEmpty) {
      return _section('设备列表', const [Text('点「扫描设备」搜索附近设备')]);
    }
    return _section('设备列表', [
      for (final r in _devices)
        ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: Text(r.device.platformName.isNotEmpty
              ? r.device.platformName
              : (r.advertisementData.advName.isNotEmpty
                  ? r.advertisementData.advName
                  : r.device.remoteId.str)),
          subtitle: Text('${r.device.remoteId.str} · RSSI ${r.rssi}'),
          trailing: const Icon(Icons.bluetooth),
          onTap: _connecting ? null : () => _connect(r),
        ),
    ]);
  }

  Widget _infoCard() {
    final i = _info;
    return _section('设备信息', [
      if (i == null)
        const Text('未读取')
      else
        Text(
            '电量 ${i.battery}% · ${i.screen}(${i.width}×${i.height}) · 容量 ${i.capacity}\n'
            '已存 ${i.imgCount} 张 · 当前显示索引 ${i.curImgIndex} · 固件 ${i.firmwareVersion.isEmpty ? '--' : i.firmwareVersion}\n'
            '已有索引：${FrameProtocol.maskToIndexes(i.imgMask).join(', ')}'),
    ]);
  }

  Widget _connIntervalCard() {
    return _section('连接间隔（手动测试）', [
      const Text('图传时会自动「先短间隔、传完恢复省电」；这里可手动验证设备是否接受参数更新。',
          style: TextStyle(fontSize: 12, color: Colors.grey)),
      const SizedBox(height: 8),
      Wrap(spacing: 10, children: [
        OutlinedButton(onPressed: _setFast, child: const Text('请求短间隔(高优先级)')),
        OutlinedButton(onPressed: _setPowerSave, child: const Text('恢复省电(低功耗)')),
      ]),
    ]);
  }

  Widget _readCard() {
    return _section('读取', [
      Wrap(spacing: 10, runSpacing: 8, children: [
        OutlinedButton(
            onPressed: _busy ? null : _cmdGetInfo, child: const Text('获取设备信息')),
        OutlinedButton(
            onPressed: _busy ? null : _cmdGetBattery, child: const Text('获取电量')),
        OutlinedButton(
            onPressed: _busy ? null : _cmdGetVersion, child: const Text('获取版本')),
        OutlinedButton(
            onPressed: _busy ? null : _cmdGetPlay, child: const Text('获取播放配置')),
      ]),
    ]);
  }

  Widget _setCard() {
    return _section('设置 / 图片', [
      Row(children: [
        const Text('播放模式：'),
        DropdownButton<String>(
          value: _playMode,
          items: const [
            DropdownMenuItem(value: 'order', child: Text('顺序')),
            DropdownMenuItem(value: 'random', child: Text('随机')),
            DropdownMenuItem(value: 'manual', child: Text('手动')),
          ],
          onChanged: (v) => setState(() => _playMode = v ?? 'order'),
        ),
      ]),
      Row(children: [
        Expanded(
          child: TextField(
            controller: _intervalCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: '切换间隔(秒)'),
          ),
        ),
        const SizedBox(width: 10),
        OutlinedButton(
            onPressed: _busy ? null : _cmdSetPlay, child: const Text('设置播放')),
      ]),
      const SizedBox(height: 6),
      OutlinedButton(
          onPressed: _busy ? null : _cmdSetTime, child: const Text('校准时间')),
      Row(children: [
        Expanded(
          child: TextField(
            controller: _switchCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: '切换到索引'),
          ),
        ),
        const SizedBox(width: 10),
        OutlinedButton(
            onPressed: _busy ? null : _cmdSwitch, child: const Text('切换显示')),
      ]),
      Row(children: [
        Expanded(
          child: TextField(
            controller: _deleteCtrl,
            decoration: const InputDecoration(labelText: '删除索引(逗号分隔)'),
          ),
        ),
        const SizedBox(width: 10),
        OutlinedButton(
            onPressed: _busy ? null : _cmdDelete, child: const Text('删除图片')),
      ]),
    ]);
  }

  Widget _imageCard() {
    final cap = _info?.capacity ?? 0;
    final maxIdx = (cap > 0 ? cap : 96) - 1;
    return _section('图传', [
      Row(children: [
        const Text('发送速度：'),
        DropdownButton<int>(
          value: _pace,
          items: const [
            DropdownMenuItem(value: 45, child: Text('稳(45ms)')),
            DropdownMenuItem(value: 20, child: Text('较快(20ms)')),
            DropdownMenuItem(value: 10, child: Text('快(10ms)')),
            DropdownMenuItem(value: 3, child: Text('极速(3ms)')),
          ],
          onChanged: (v) => setState(() => _pace = v ?? 45),
        ),
      ]),
      const SizedBox(height: 6),
      TextField(
        controller: _uploadIndexCtrl,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(
          labelText: '上传到索引（留空=自动选空位，范围 0~$maxIdx）',
          helperText: '填已占用的索引会覆盖该槽位',
          isDense: true,
        ),
      ),
      const SizedBox(height: 10),
      Wrap(spacing: 10, runSpacing: 8, children: [
        FilledButton(
          onPressed: _uploading ? null : _uploadColorBars,
          child: const Text('上传彩条测试图'),
        ),
        OutlinedButton(
          onPressed: _uploading ? null : _uploadSolidWhite,
          child: const Text('上传纯白测试图'),
        ),
      ]),
      const SizedBox(height: 6),
      FilledButton.icon(
        onPressed: _uploading ? null : _uploadFromGallery,
        icon: const Icon(Icons.photo_library_outlined, size: 18),
        label: const Text('选择相册图片上传'),
      ),
      _quantizeTuner(),
      if (_uploading || _uploadStatus.isNotEmpty) ...[
        const SizedBox(height: 10),
        LinearProgressIndicator(value: _uploading ? _uploadPercent : null),
        const SizedBox(height: 6),
        Text(_uploadStatus, style: const TextStyle(fontSize: 12)),
      ],
    ]);
  }

  /// 相册图的六色量化调参面板：抖动开关 + 量化前对比度/饱和度增强，可在真机上 A/B。
  Widget _quantizeTuner() {
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      childrenPadding: EdgeInsets.zero,
      title: const Text('六色量化调参（相册图）',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
      subtitle: const Text('量化前增强 + 抖动，缓解六色硬量化的色块/发灰',
          style: TextStyle(fontSize: 11, color: Colors.grey)),
      children: [
        SwitchListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: const Text('Floyd–Steinberg 抖动', style: TextStyle(fontSize: 13)),
          subtitle: const Text('开=渐变自然但有颗粒；关=色块硬但干净',
              style: TextStyle(fontSize: 11, color: Colors.grey)),
          value: _dither,
          onChanged: _uploading ? null : (v) => setState(() => _dither = v),
        ),
        _sliderRow('对比度', _contrast, 0.8, 1.8,
            (v) => setState(() => _contrast = v)),
        _sliderRow('饱和度', _saturation, 0.8, 2.0,
            (v) => setState(() => _saturation = v)),
      ],
    );
  }

  Widget _sliderRow(String label, double value, double min, double max,
      ValueChanged<double> onChanged) {
    return Row(children: [
      SizedBox(
          width: 48, child: Text(label, style: const TextStyle(fontSize: 13))),
      Expanded(
        child: Slider(
          value: value,
          min: min,
          max: max,
          divisions: ((max - min) / 0.02).round(),
          label: value.toStringAsFixed(2),
          onChanged: _uploading ? null : onChanged,
        ),
      ),
      SizedBox(
          width: 40,
          child: Text(value.toStringAsFixed(2),
              style: const TextStyle(fontSize: 12))),
    ]);
  }

  Widget _logCard() {
    return _section('收发日志', [
      Row(children: [
        const Spacer(),
        TextButton(
          onPressed: () => setState(() => _logs.clear()),
          child: const Text('清空'),
        ),
      ]),
      Container(
        height: 280,
        decoration: BoxDecoration(
          color: const Color(0xFF101418),
          borderRadius: BorderRadius.circular(8),
        ),
        padding: const EdgeInsets.all(8),
        child: ListView.builder(
          itemCount: _logs.length,
          itemBuilder: (context, idx) {
            final e = _logs[idx];
            return Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '${e.time}  ${e.text}',
                style: TextStyle(
                  fontSize: 11,
                  fontFamily: 'monospace',
                  color: _logColor(e.type),
                ),
              ),
            );
          },
        ),
      ),
    ]);
  }

  Color _logColor(String type) {
    switch (type) {
      case 'tx':
        return const Color(0xFF7FB2FF);
      case 'rx':
        return const Color(0xFF8BE0A0);
      case 'ok':
        return const Color(0xFF6EE7B7);
      case 'err':
        return const Color(0xFFFF8A8A);
      default:
        return const Color(0xFFD0D0D0);
    }
  }
}
