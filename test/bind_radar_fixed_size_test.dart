import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 绑定设备三页雷达尺寸不变（2026-11-10，同小程序 `bind.wxss` `.radar-wrap`）。
///
/// 缺陷：发现页搜索结束（勾选设备 / 结束搜索 / 立即绑定都会停扫）时，雷达按「4.5 张卡」
/// 的账让位给列表，gif 换成静态图的同时缩小；另外静态图是代码画的雷达，和 gif 视觉大小不一。
/// 现在三页都是同一个 280 框、`BoxFit.contain`，只按状态换图片。
///
/// ⚠️ 只做源码静态核对（读源码、剥注释），版式效果仍需真机回归。
void main() {
  String source(String path) => File(path)
      .readAsStringSync()
      .replaceAll(RegExp(r'//[^\n]*'), '');

  const dir = 'lib/src/features/devices/presentation';

  test('发现页雷达尺寸不随 scanning 变化', () {
    final found = source('$dir/bind_device_found.dart');
    final radar = RegExp(r'final double radarSize = ([^;]+);').firstMatch(found);
    expect(radar, isNotNull, reason: '找不到 radarSize 的计算');
    expect(radar!.group(1), isNot(contains('scanning')),
        reason: '雷达尺寸不能按 scanning 分支：停扫换图时会缩小');
    expect(radar.group(1), isNot(contains('_kListViewport')),
        reason: '雷达不再给列表让位');
    expect(found, contains('const double _kRadarMax = 280;'),
        reason: '上限与搜索中页 280 一致');
    expect(found, contains("'assets/images/search-devices.gif'"));
    expect(found, contains("'assets/images/device_found_art.png'"));
    expect(found, isNot(contains('FigmaBluetoothRadar(')),
        reason: '已搜到改用与小程序同一张图，不再用代码画的雷达');
  });

  test('搜索中页 / 未发现页同为 280 框 + contain 图片', () {
    for (final entry in {
      'bind_device_searching.dart': 'search-devices.gif',
      'bind_device_not_found.dart': 'device_not_found_art.png',
    }.entries) {
      final page = source('$dir/${entry.key}');
      expect(
        RegExp(
          r'width: 280,\s*height: 280,\s*child: Image\(\s*image: AssetImage\('
          "'assets/images/${RegExp.escape(entry.value)}'"
          r'\),\s*fit: BoxFit\.contain,',
        ).hasMatch(page),
        isTrue,
        reason: '${entry.key} 雷达要是 280×280 的 ${entry.value}（contain）',
      );
      expect(page, isNot(contains('FigmaDeviceRadar(')));
    }
  });
}
