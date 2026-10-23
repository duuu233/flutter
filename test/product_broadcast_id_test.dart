import 'package:flutter_test/flutter_test.dart';

import 'package:BoltStar/src/device/ble/frame_protocol.dart';
import 'package:BoltStar/src/device/device_thumb.dart';
import 'package:BoltStar/src/device/product_broadcast_id.dart';

/// 设备记录 → 机型广播名（2026-10-23，与小程序 `tests/device-thumb.test.js` 同口径）：
/// 记录自带且认得 → 原样；否则按 productId 回查产品列表；都不行为空串，由 state 再按详情接口补。
///
/// 锁住：EC-370 的列表记录没有可用 productId / broadcastId 时认不出（空串，交给详情补），
/// 详情带着 productId 17 时认得出，设备图与最多照片数随之是 EC-370 的。
void main() {
  // 后台实际产品列表（2026-10-23），EB-169 的 broadcastId 带尾随空格
  const catalog = {18: 'EB-169 ', 17: 'EC-370', 15: 'EF6-589', 9: 'EF6-370'};

  test('记录自带且认得：原样，不被 productId 覆盖', () {
    expect(
      ProductBroadcastId.resolve(
        broadcastId: 'EC-370',
        productId: 18,
        catalog: catalog,
      ),
      'EC-370',
    );
    expect(
      ProductBroadcastId.resolve(
        broadcastId: 'eb-169',
        productId: 0,
        catalog: catalog,
      ),
      'eb-169',
    );
  });

  test('没带或认不出：按 productId 回查，去首尾空白', () {
    expect(
      ProductBroadcastId.resolve(
        broadcastId: '',
        productId: 17,
        catalog: catalog,
      ),
      'EC-370',
    );
    expect(
      ProductBroadcastId.resolve(
        broadcastId: '37:0B:00:D0:44:5A',
        productId: 18,
        catalog: catalog,
      ),
      'EB-169',
    );
  });

  test('都认不出为空串（交给详情接口补），不拿别的字段猜', () {
    expect(
      ProductBroadcastId.resolve(
        broadcastId: '',
        productId: 0,
        catalog: catalog,
      ),
      '',
    );
    expect(
      ProductBroadcastId.resolve(
        broadcastId: '',
        productId: 99,
        catalog: catalog,
      ),
      '',
    );
    expect(
      ProductBroadcastId.resolve(
        broadcastId: '',
        productId: 17,
        catalog: const {},
      ),
      '',
    );
  });

  test('详情补到 EC-370 后设备图与最多照片数是 EC-370 的', () {
    final fromDetail = ProductBroadcastId.resolve(
      broadcastId: '',
      productId: 17,
      catalog: catalog,
    );
    expect(
      DeviceThumb.ofRecord(broadcastId: fromDetail),
      DeviceThumb.rectangleAsset,
    );
    expect(FrameProtocol.capacityOf(fromDetail), 11);
    // 列表认不出时的原样：默认图、按屏型才有容量
    expect(DeviceThumb.ofRecord(broadcastId: ''), DeviceThumb.defaultAsset);
    expect(FrameProtocol.capacityOf(''), 0);
  });
}
