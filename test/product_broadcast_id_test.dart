import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:BoltStar/src/device/ble/frame_protocol.dart';
import 'package:BoltStar/src/device/device_thumb.dart';
import 'package:BoltStar/src/device/product_broadcast_id.dart';

/// 已绑定设备的机型（2026-11-14 起）：设备列表接口直接下发 `productId` / `broadcastId`，
/// 设备图与最多照片数按记录自带的 broadcastId 区分；不再等产品列表回查、不再逐台调详情补机型
/// （原 `ProductBroadcastId.resolve` 及其用例有意删除，同小程序 `tests/device-thumb.test.js`）。
void main() {
  test('列表记录自带的 broadcastId 决定设备图与最多照片数', () {
    expect(DeviceThumb.ofRecord(broadcastId: 'EC-370'), DeviceThumb.rectangleAsset);
    expect(FrameProtocol.capacityOf('EC-370'), 11);
    expect(DeviceThumb.ofRecord(broadcastId: 'EF6-370'), DeviceThumb.defaultAsset);
    // 没带 broadcastId：默认图，按屏型才有容量（不再回查）
    expect(DeviceThumb.ofRecord(broadcastId: ''), DeviceThumb.defaultAsset);
    expect(FrameProtocol.capacityOf(''), 0);
  });

  test('刷新设备列表不再等产品列表、不逐台调详情', () {
    final source = File('lib/src/state.dart').readAsStringSync().replaceAll(RegExp(r'//[^\n]*'), '');
    final start = source.indexOf('Future<ActionFeedback> refreshDevices()');
    final body = source.substring(start, source.indexOf('Future<', start + 10));
    expect(body.contains('getUserProductDetail'), isFalse);
    expect(body.contains('_loadProductBroadcastIds'), isFalse);
    expect(source.contains('_fillBroadcastIds'), isFalse);
    expect(source.contains('_detailBroadcastId'), isFalse);
    expect(source, contains("broadcastId: (data['broadcastId'] ?? '').toString().trim(),"));
    expect(source, contains("productId: _asInt(data['productId']),"));
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
