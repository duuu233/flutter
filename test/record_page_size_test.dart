import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 投屏记录按需加载（2026-11-14）：一次只取一屏（21 条，同「我的上传」），不再一次传 100。
void main() {
  String read(String path) => File(path).readAsStringSync();

  test('「我的」页张数统计单页 21，保险丝 100 页', () {
    final state = read('lib/src/state.dart');
    final fn = state.substring(state.indexOf('Future<ActionFeedback> refreshMineCastSuccessCount()'));
    expect(fn.contains('const pageSize = 21;'), isTrue);
    expect(fn.contains('const maxPages = 100;'), isTrue);
  });

  test('投屏返回后的刷新只取首屏 21 条', () {
    for (final path in [
      'lib/src/features/home/presentation/home_page.dart',
      'lib/src/features/devices/presentation/devices_page.dart',
      'lib/src/features/devices/presentation/device_details_page.dart',
    ]) {
      final source = read(path);
      expect(source.contains('refreshCastRecords(pageSize: 21);'), isTrue, reason: path);
      expect(source.contains('refreshCastRecords();'), isFalse, reason: path);
    }
    expect(read('lib/src/features/gallery/presentation/gallery_page.dart').contains('static const int _pageSize = 21;'), isTrue, reason: '我的上传每页 21');
  });
}
