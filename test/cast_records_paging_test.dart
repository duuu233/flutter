import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 「我的上传」分页（2026-11-14，同小程序每页 21）：本页按 21 条一页加载；投屏返回后不再在首页 / 我的设备 /
/// 蓝牙详情全局重拉投屏记录（原默认每页 100 条、不带筛选，会覆盖「我的上传」共用的列表）。
void main() {
  test('我的上传每页 21；没有不带参数的全局重拉', () {
    final gallery = File('lib/src/features/gallery/presentation/gallery_page.dart').readAsStringSync();
    expect(gallery.contains('static const int _pageSize = 21;'), isTrue);
    for (final path in [
      'lib/src/features/home/presentation/home_page.dart',
      'lib/src/features/devices/presentation/devices_page.dart',
      'lib/src/features/devices/presentation/device_details_page.dart',
    ]) {
      expect(File(path).readAsStringSync().contains('refreshCastRecords()'), isFalse, reason: path);
    }
  });
}
