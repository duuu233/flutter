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

  group('搜索列表尺寸：按广播名匹配产品的 sizeModel（2026-10-23，同小程序 scanSizeModel）', () {
    const products = <ProductSizeModel>[
      (broadcastId: 'EF6-370', sizeModel: '3.7寸'),
      (broadcastId: 'EF6-589', sizeModel: ' 5.89寸 '),
      (broadcastId: 'EC-370', sizeModel: '3.6寸'),
      (broadcastId: 'EB-169 ', sizeModel: ''),
      (broadcastId: '', sizeModel: '9.9寸'),
    ];

    test('广播名包含匹配：带后缀、大小写不同、尺寸去空白', () {
      expect(ProductBroadcastId.sizeModelOfScan('EC-370', products), '3.6寸');
      expect(ProductBroadcastId.sizeModelOfScan('ec-370-0B37 ', products), '3.6寸');
      expect(ProductBroadcastId.sizeModelOfScan(' EF6-589', products), '5.89寸');
    });

    test('没配、匹配不到、产品列表为空都不展示（不再按屏型猜）', () {
      expect(ProductBroadcastId.sizeModelOfScan('EB-169', products), '');
      expect(ProductBroadcastId.sizeModelOfScan('XX-001', products), '');
      expect(ProductBroadcastId.sizeModelOfScan('EC-370', const []), '');
    });

    test('多个命中取更具体（更长）的广播名', () {
      expect(
        ProductBroadcastId.sizeModelOfScan('EF6-370-PRO', [
          ...products,
          (broadcastId: 'EF6-370-PRO', sizeModel: '4.0寸'),
        ]),
        '4.0寸',
      );
    });
  });
}
