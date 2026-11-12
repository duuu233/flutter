import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 首页点设备卡进「我的设备」默认停在那台所属的 Tab（2026-11-12，同小程序 `device/list?tab=`）：
/// 点 WiFi 版卡 → WiFi版 Tab，点蓝牙版卡 → 蓝牙版 Tab；按「用户选过」处理，列表刷新不被默认规则改掉，
/// 该类没有设备时显示该 Tab 的空态。六宫格「我的设备」、我的页入口不带参数，仍按默认规则。
///
/// ⚠️ 只做源码静态核对（读源码、剥注释），实际跳转与 Tab 停留需真机回归。
void main() {
  String read(String path) => File(path).readAsStringSync().replaceAll(RegExp(r'//[^\n]*'), '');
  final home = read('lib/src/features/home/presentation/home_page.dart');
  final mainView = read('lib/src/features/home/presentation/home_main_view.dart');
  final widgets = read('lib/src/features/home/presentation/home_widgets.dart');
  final routes = read('lib/src/routes/app_routes.dart');
  final devices = read('lib/src/features/devices/presentation/devices_page.dart');
  final page = read('lib/src/features/devices/presentation/my_devices_page.dart');
  final mine = read('lib/src/features/mine/presentation/mine_page.dart');

  test('首页：设备卡按类型带 Tab，六宫格入口不带', () {
    expect(home, contains('onOpenDevices: _openDeviceList,'));
    expect(home, contains('tab: device.isWifi ? MyDevicesTab.wifi : MyDevicesTab.ble'));
    expect(home, contains('pushNamed<void>(AppRoutes.figmaMyDevices, arguments: tab)'));
    expect(mainView, contains('onOpenDevice: onOpenDeviceCard,'));
    expect(mainView, contains('onTap: onOpenDevices,'), reason: '六宫格「我的设备」仍走无参入口');
    expect(widgets, contains('onOpenDevices: () => widget.onOpenDevice('));
  });

  test('路由与列表页：参数是 MyDevicesTab 才认，进页按用户选过处理', () {
    expect(routes, contains('settings.arguments is MyDevicesTab'));
    expect(routes, contains('DevicesPage(state: state, initialTab: devicesTab)'));
    expect(devices, contains('initialTab: widget.initialTab,'));
    final init = page.substring(page.indexOf('void initState()'), page.indexOf('void _switchTab('));
    expect(init, contains('_wifiTab = tab == MyDevicesTab.wifi;'));
    expect(init, contains('_tabChosen = true;'));
    expect(page, contains('if (!_tabChosen) {\n      _wifiTab = _defaultWifiTab(wifiCount, bleCount);'),
        reason: '选过之后 build 不再按默认规则改');
    expect(mine, contains('pushNamed<void>(AppRoutes.figmaMyDevices);'), reason: '我的页入口不带参数');
  });
}
