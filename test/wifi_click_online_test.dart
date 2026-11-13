import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// WiFi 版点击入口要在线（2026-11-14 产品要求，同小程序 tests/wifi-sleeping-status.test.js「点击入口要在线」）：
/// 投屏、轮播设置、固件升级、优雅刷新升级点击时都先 [requireWifiOnline]，不在线不能进；TF卡切换在开关里本就现查在线；
/// 一键清空、删除设备、解绑设备不判断。蓝牙版不动。
void main() {
  String read(String path) => File(path).readAsStringSync();

  test('判断规则：已知不可操作直接拦，已知在线放行（fresh 现查），其余现查只放行在线', () {
    final status = read('lib/src/features/wifi/wifi_status.dart');
    final fn = status.substring(status.indexOf('Future<bool> requireWifiOnline('), status.indexOf('/// 接口回 4041 时补查一次在线状态'));
    expect(fn.contains('final knownTip = wifiBlockedTip(l10n, known);'), isTrue, reason: '已知离线 / 休眠 / 关机 / 本地模式先拦');
    expect(fn.contains('if (known == WifiOnlineStatus.online && !fresh) {'), isTrue, reason: '已知在线直接放行');
    expect(fn.contains('IotApi.getDeviceOnline(device.serialNumber)'), isTrue, reason: '其余现查');
    expect(fn.contains('if (state == WifiOnlineStatus.online) {\n    return true;'), isTrue, reason: '只放行在线');
    expect(fn.contains('tip.isNotEmpty ? tip : l10n.wifiNotOnlineTip'), isTrue, reason: '查不到提示设备不在线');
  });

  test('接入位置', () {
    final entry = read('lib/src/features/wifi/wifi_cast_entry.dart');
    expect(RegExp(r'Future<void> startWifiCast\([^)]*\) async \{\s*if \(!await requireWifiOnline\(context, device\)').hasMatch(entry), isTrue,
        reason: '投屏（我的设备 / WiFi 详情共用）');
    expect(RegExp(r'Future<void> openWifiSlideshow\([^)]*\) async \{\s*if \(!await requireWifiOnline\(context, device\)').hasMatch(entry), isTrue,
        reason: '轮播设置（我的设备 / WiFi 详情共用），不再「离线也能看」');
    final detail = read('lib/src/features/wifi/presentation/wifi_device_detail_page.dart');
    expect(RegExp(r'Future<void> _openOta\(\) async \{\s*if \(!await requireWifiOnline\(context, _device, fresh: true\)').hasMatch(detail), isTrue,
        reason: '固件升级：点击现查在线');
    final info = read('lib/src/features/wifi/presentation/wifi_device_info_page.dart');
    expect(RegExp(r'Future<void> _openFpga\(\) async \{\s*if \(!await requireWifiOnline\(context, widget\.state\.deviceById\(widget\.deviceId\), fresh: true\)')
        .hasMatch(info), isTrue, reason: '优雅刷新升级：点击现查在线');
    expect(read('lib/src/features/home/presentation/home_page.dart').contains('requireWifiOnline(context, activeDevice, fresh: true, useKnown: false)'), isTrue,
        reason: '首页拍照 / 相册（WiFi 版）：现查在线');
    expect(read('lib/src/features/wifi/presentation/wifi_cast_result_page.dart').contains('requireWifiOnline(context, widget.device, fresh: true, useKnown: false)'),
        isTrue, reason: '结果页继续投屏：现查在线');
    expect(read('lib/src/features/wifi/presentation/wifi_tf_page.dart').contains('l10n.wifiNotOnlineTip'), isTrue, reason: 'TF卡切换：开启前现查只放行在线（原有）');
    // 一键清空 / 解除绑定 / 删除设备不判断在线
    final actions = detail.substring(detail.indexOf('Widget _buildActions('), detail.indexOf('Widget build(BuildContext context)'));
    expect(actions.contains('requireWifiOnline'), isFalse);
  });
}
