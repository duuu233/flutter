import 'package:flutter_test/flutter_test.dart';

import 'package:BoltStar/src/features/star/star_coin_api.dart';
import 'package:BoltStar/src/features/star/star_purchase.dart';

/// 星币购买链路（2026-08-27 安卓 PayPal）里**不依赖网络与平台**的那几条口径。
///
/// 对照小程序 `photo-album/tests/token-pay.test.js`：那边钉的是「查单查的是 orderNo + payType」，
/// 这边钉的是同一批容易被人按旧文档改错的常量与归一口径。
void main() {
  group('payType 按端分工', () {
    // ⚠️ 这三个数是**后端 swagger 的取值**，不是端上的排序。历史上文档一直写着
    // 「App 两端都走 IAP」，照那份文档改这里就会把安卓的 3 改成 2。
    test('1=微信支付 2=IOS内购 3=payPal', () {
      expect(StarPayType.wechat, 1);
      expect(StarPayType.apple, 2);
      expect(StarPayType.paypal, 3);
    });
  });

  group('套餐归一', () {
    test('字段映射与「含赠送」的合计口径', () {
      final package = StarPackage.fromJson(const {
        'goodsId': 7,
        'goodsName': '进阶包',
        'num': 200,
        'giveNum': 50,
        'amount': 90,
        'wxProductId': 'wx-prod-1',
        'appleProductId': 'apple-prod-1',
      });

      expect(package.goodsId, 7);
      expect(package.name, '进阶包');
      expect(package.tokens, 200);
      expect(package.gift, 50);
      expect(package.price, 90);
      expect(package.wxProductId, 'wx-prod-1');
      expect(package.appleProductId, 'apple-prod-1');
      // 合计 = 基础 + 赠送
      expect(package.totalTokens, 250);
    });

    test('单价按含赠送总数算（否则赠送多的档位反而显得更贵）', () {
      // 90 / (200 + 50) = 0.36，而不是 90 / 200 = 0.45
      final package = StarPackage.fromJson(const {
        'goodsId': 7,
        'num': 200,
        'giveNum': 50,
        'amount': 90,
      });
      expect(package.unitPrice, '0.36');
    });

    test('总数为 0 时不做除法（后端脏数据不该把页面炸成 NaN/Infinity）', () {
      final package = StarPackage.fromJson(const {
        'goodsId': 9,
        'num': 0,
        'giveNum': 0,
        'amount': 30,
      });
      expect(package.unitPrice, '0.00');
    });

    test('字符串数字与缺字段都能吃（后端这几个字段的类型不稳）', () {
      final package = StarPackage.fromJson(const {
        'goodsId': '11',
        'num': '100',
        'amount': '19.9',
      });
      expect(package.goodsId, 11);
      expect(package.tokens, 100);
      expect(package.gift, 0);
      expect(package.price, 19.9);
      expect(package.name, '');
    });
  });

  group('建单出参', () {
    test('orderNo 原样落地，payType 由调用方带入', () {
      final order = StarOrder.fromJson(const {
        'orderNo': 'BF20260827000001',
        'orderId': '10086',
        'amount': 90,
      }, payType: StarPayType.paypal);

      expect(order.orderNo, 'BF20260827000001');
      expect(order.orderId, '10086');
      expect(order.amount, 90);
      expect(order.payType, 3);
    });
  });

  group('创建支付出参', () {
    test('只落地 PayPal 那两个字段 + 异常信息', () {
      final creation = StarPayCreation.fromJson(const {
        'payPalApproveUrl': 'https://www.sandbox.paypal.com/checkoutnow?token=ABC',
        'payPalOrderId': 'ABC',
        // 微信那一串同壳字段端上不认（App 不走微信支付），有值也不该影响 PayPal 分支
        'wxPayAppId': 'wxdeadbeef',
        'wxPayPrepayId': 'prepay_id=xxx',
        'exceptionMsg': '',
      });

      expect(
        creation.payPalApproveUrl,
        'https://www.sandbox.paypal.com/checkoutnow?token=ABC',
      );
      expect(creation.payPalOrderId, 'ABC');
      expect(creation.exceptionMsg, '');
    });

    test('缺 approveUrl 时是空串（调用方据此报「未能拉起支付」而不是跳一个空地址）', () {
      final creation = StarPayCreation.fromJson(const {
        'payPalOrderId': 'ABC',
        'exceptionMsg': 'PAYPAL_CREATE_FAILED',
      });
      expect(creation.payPalApproveUrl, isEmpty);
      expect(creation.exceptionMsg, 'PAYPAL_CREATE_FAILED');
    });
  });

  group('查单', () {
    // ⚠️ payState 的枚举后端至今没给。端上只认 1=已支付，其余一律「结果确认中」——
    // 改成 `payState != 0` 之类的宽松判定，会把「用户取消」说成「已付款」。
    test('只有 payState==1 算已支付', () {
      expect(StarPayQuery.fromJson(const {'payState': 1}).paid, isTrue);
      expect(StarPayQuery.fromJson(const {'payState': 0}).paid, isFalse);
      expect(StarPayQuery.fromJson(const {'payState': 2}).paid, isFalse);
      expect(StarPayQuery.fromJson(const {}).paid, isFalse);
    });

    test('payState 是字符串也认（后端这类字段常给 String）', () {
      expect(StarPayQuery.fromJson(const {'payState': '1'}).paid, isTrue);
    });
  });

  group('到账轮询节奏', () {
    test('与小程序 CONFIRM_DELAYS 逐值相同，总时长约 9.4s', () {
      expect(
        StarPurchase.confirmDelays.map((d) => d.inMilliseconds).toList(),
        [900, 1200, 1800, 2500, 3000],
      );
      final total = StarPurchase.confirmDelays.fold<int>(
        0,
        (sum, d) => sum + d.inMilliseconds,
      );
      expect(total, 9400);
    });
  });
}
