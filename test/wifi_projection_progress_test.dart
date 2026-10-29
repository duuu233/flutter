import 'package:flutter_test/flutter_test.dart';

import 'package:BoltStar/src/features/wifi/wifi_projection.dart';

/// WiFi 投屏进度条（2026-10-29 同步小程序 `tests/wifi-projection.test.js`）：上传折算到前半段，
/// 处理阶段按时间渐近爬向 99、只增不减、不到 100；100% 只在接口返回 SENT / UPLOADED 时给出。
void main() {
  test('处理阶段从 50 起只增不减，永不到 100', () {
    var last = WifiProjection.uploadShare;
    for (final ms in [0, 200, 1000, 3000, 8000, 60000]) {
      final value = WifiProjection.processingProgress(WifiProjection.uploadShare, ms);
      expect(value, greaterThanOrEqualTo(last));
      expect(value, lessThan(100));
      last = value;
    }
    expect(WifiProjection.processingProgress(50, 1000), 63);
    expect(WifiProjection.processingProgress(50, 3000), 80);
  });

  test('接口 status 归一', () {
    expect(WifiProjection.resultStatus({'status': 'DOWNLOADING'}, true), 'SENT');
    expect(WifiProjection.resultStatus({'status': 'FAILED'}, true), 'FAILED');
    expect(WifiProjection.resultStatus(const {}, false), 'UPLOADED');
  });
}
