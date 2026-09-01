import 'dart:io';

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

    // 2026-08-31 核 swagger 发现的：`ClientGoodsApiOut` 一直有 `currencySymbol`
    // （描述「币种符号$,¥」），端上却写死了 ¥。PayPal 侧若收美元，表现就是最坏的那种：
    // **页面写着 ¥、PayPal 扣的是 $**。这两条钉住「符号跟着后端走」。
    test('币种符号取后端下发的 currencySymbol', () {
      final package = StarPackage.fromJson(const {
        'goodsId': 7,
        'num': 200,
        'amount': 12.99,
        'currencySymbol': r'$',
      });
      expect(package.currencySymbol, r'$');
    });

    test('后端没给币种符号时才退回 ¥', () {
      expect(
        StarPackage.fromJson(const {'goodsId': 7, 'num': 200, 'amount': 90})
            .currencySymbol,
        kStarCurrencySymbol,
      );
      expect(
        StarPackage.fromJson(const {
          'goodsId': 7,
          'num': 200,
          'amount': 90,
          'currencySymbol': '',
        }).currencySymbol,
        '¥',
      );
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

    // ⚠️ **`goodsId = 0` 是合法取值**（2026-09-01 后端确认）。归一只做类型转换，
    // 不许加「大于 0 才算数」之类的判断 —— 那会把一档合法的 0 悄悄换掉或拦掉。
    // 配套：星币页的选中态**按下标**记，不按 goodsId（0 和重复 id 会让按 id 找回
    // 选中项恒命中第一档：用户点第二档、高亮跟着走了，发出去的却是第一档）。
    test('goodsId 为 0 原样保留，不当成缺失', () {
      final package = StarPackage.fromJson(const {
        'goodsId': 0,
        'num': 100,
        'amount': 9,
      });
      expect(package.goodsId, 0);
    });

    test('goodsId 是字符串数字也认', () {
      expect(StarPackage.fromJson(const {'goodsId': '7'}).goodsId, 7);
      expect(StarPackage.fromJson(const {'goodsId': '0'}).goodsId, 0);
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

    // 2026-08-27 联调：后端可能**直接透传 PayPal Orders v2 建单的原始返回**，
    // 字段名是 id / status / links[]，不是接口文档里的 payPalOrderId / payPalApproveUrl。
    // 认错的表现是「接口 200 却提示未能拉起支付」，所以两种形状都得认。
    test('PayPal 原始返回也认：id → orderId，links[rel=approve] → approveUrl', () {
      final creation = StarPayCreation.fromJson(const {
        'id': '5O190127TN364715T',
        'status': 'CREATED',
        'links': [
          {
            'href':
                'https://api.sandbox.paypal.com/v2/checkout/orders/5O190127TN364715T',
            'rel': 'self',
            'method': 'GET',
          },
          {
            'href':
                'https://www.sandbox.paypal.com/checkoutnow?token=5O190127TN364715T',
            'rel': 'approve',
            'method': 'GET',
          },
          {
            'href':
                'https://api.sandbox.paypal.com/v2/checkout/orders/5O190127TN364715T/capture',
            'rel': 'capture',
            'method': 'POST',
          },
        ],
      });

      expect(creation.payPalOrderId, '5O190127TN364715T');
      expect(
        creation.payPalApproveUrl,
        'https://www.sandbox.paypal.com/checkoutnow?token=5O190127TN364715T',
      );
      expect(creation.status, 'CREATED');
      // ⚠️ capture 是 PayPal 的**服务端** API（要商户 secret 换的 OAuth2 token），
      // 端上既不解析也不调用——这里顺带钉住「没有把它落到任何可调用的地方」。
      expect(creation.payPalApproveUrl, isNot(contains('/capture')));
    });

    test('两种形状同时给时以后端映射过的字段为准', () {
      final creation = StarPayCreation.fromJson(const {
        'payPalApproveUrl': 'https://www.sandbox.paypal.com/checkoutnow?token=MAPPED',
        'payPalOrderId': 'MAPPED',
        'id': 'RAW',
        'links': [
          {'href': 'https://www.sandbox.paypal.com/checkoutnow?token=RAW', 'rel': 'approve'},
        ],
      });
      expect(creation.payPalOrderId, 'MAPPED');
      expect(creation.payPalApproveUrl, endsWith('token=MAPPED'));
    });

    test('links 结构不对时不炸，按「拉不起支付」处理', () {
      expect(
        StarPayCreation.fromJson(const {'id': 'X', 'links': 'not-a-list'})
            .payPalApproveUrl,
        isEmpty,
      );
      expect(
        StarPayCreation.fromJson(const {
          'id': 'X',
          'links': [
            {'rel': 'self', 'href': 'https://api.sandbox.paypal.com/x'},
          ],
        }).payPalApproveUrl,
        isEmpty,
      );
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

  // ── PayPal 支付回跳（2026-08-31 定稿）────────────────────────────────
  //
  // `setCreatePay` 的两个入参 payPalReturnUrl / payPalCancelUrl 都由端上传，传的是
  // **https 中转页**；中转页再用 boltstar:// 把 App 拉起来。两组地址职责不同，别混用。
  group('回跳地址', () {
    test('交给 PayPal 的必须是 https（中转页），不能是自定义 scheme', () {
      // ⚠️ 这条钉的是方案本身：PayPal 对 return_url 按 URI 校验，非 http(s) 收不收没有保证；
      // 而且 Chrome 会拦掉「服务端 302 直跳自定义 scheme」这种非用户手势外跳
      //（表现是停在空白页、什么都不发生且不报错）。所以中间那个 https 页不能省。
      for (final url in [StarPurchase.returnUrl, StarPurchase.cancelUrl]) {
        expect(Uri.parse(url).scheme, 'https', reason: url);
      }
    });

    test('中转页拉起 App 用的是自定义 scheme 深链', () {
      expect(StarPurchase.appReturnLink, 'boltstar://pay/paypal/return');
      expect(StarPurchase.appCancelLink, 'boltstar://pay/paypal/cancel');
    });

    // ⚠️ 这两条深链**写在两个地方**：Dart 常量与安卓清单的 intent-filter。
    // 只改一处的表现极其难查 —— setCreatePay 照常成功、PayPal 照常跳、中转页也照常跳，
    // 只是那一跳谁也接不住，用户停在中转页上，回到 App 后又被当成「结果确认中」。
    // 所以这里直接拿清单来比，别指望下一个人记得改两处。
    test('与 AndroidManifest 里 PayPalRedirectActivity 的 intent-filter 逐字一致', () {
      final manifest = File('android/app/src/main/AndroidManifest.xml');
      expect(
        manifest.existsSync(),
        isTrue,
        reason: '测试须从项目根目录跑（flutter test）',
      );
      final xml = manifest.readAsStringSync();

      for (final link in [
        StarPurchase.appReturnLink,
        StarPurchase.appCancelLink,
      ]) {
        final uri = Uri.parse(link);
        // <data android:scheme="boltstar" android:host="pay" android:path="/paypal/xxx"/>
        expect(xml, contains('android:scheme="${uri.scheme}"'), reason: link);
        expect(xml, contains('android:host="${uri.host}"'), reason: link);
        expect(xml, contains('android:path="${uri.path}"'), reason: link);
      }

      // 接收器本身与浏览器发起外跳所必需的 BROWSABLE，一并钉住。
      expect(xml, contains('android:name=".PayPalRedirectActivity"'));
      expect(xml, contains('android.intent.category.BROWSABLE'));
    });
  });

  // getPayPalNotify 的出参结构后端只说了「和其它接口一样」（retCode/retMsg/retData 那层壳），
  // retData 具体长什么样没给 —— 端上三种常见形状都认，一种都没命中时以「接口 200」为准。
  // ⚠️ 认错的表现是「付成功了却提示结果确认中」，不报错、很难查，所以逐种钉住。
  group('回跳通知出参归一', () {
    test('裸布尔', () {
      expect(StarPayNotify.fromRetData(true).paid, isTrue);
      expect(StarPayNotify.fromRetData(false).paid, isFalse);
    });

    test('与 getPayQuery 同形时沿用「只认 payState==1」的口径', () {
      expect(StarPayNotify.fromRetData(const {'payState': 1}).paid, isTrue);
      expect(StarPayNotify.fromRetData(const {'payState': 0}).paid, isFalse);
      expect(StarPayNotify.fromRetData(const {'payState': '1'}).paid, isTrue);
    });

    test('语义化布尔字段', () {
      expect(StarPayNotify.fromRetData(const {'paid': false}).paid, isFalse);
      expect(StarPayNotify.fromRetData(const {'success': true}).paid, isTrue);
    });

    test('retData 为 null / 认不出的形状 → 以「接口 200」为准', () {
      expect(StarPayNotify.fromRetData(null).paid, isTrue);
      expect(StarPayNotify.fromRetData(const {'foo': 'bar'}).paid, isTrue);
    });

    test('exceptionMsg 留给页面兜底展示', () {
      final notify = StarPayNotify.fromRetData(const {
        'payState': 0,
        'exceptionMsg': 'INSTRUMENT_DECLINED',
      });
      expect(notify.paid, isFalse);
      expect(notify.message, 'INSTRUMENT_DECLINED');
    });
  });

  // 2026-09-01：星币管理页三个数恒为 0 的那个 bug。后端这一摊数字**全是 String，
  // 且常带小数位**（`"200.0"`），而归一用的是 `int.tryParse` —— 它对 "200.0" 返回 null，
  // 被 `?? 0` 兜成 0。不报错、不空列表，只是每个数字都变成 0，所以谁也没看出是解析挂了。
  group('账户概览归一（getUserAccount）', () {
    test('String 出参转数字', () {
      final account = StarAccount.fromJson(const {
        'availableToken': '200',
        'totalToken': '500',
        'consumeToken': '300',
      });
      expect(account.balance, 200);
      expect(account.totalPurchased, 500);
      expect(account.totalSpent, 300);
    });

    test('带小数位的 String 也要认（"200.0" 不能兜成 0）', () {
      final account = StarAccount.fromJson(const {
        'availableToken': '200.0',
        'totalToken': '500.0',
        'consumeToken': '300.5',
      });
      expect(account.balance, 200);
      expect(account.totalPurchased, 500);
      // 星币按整数计价，小数位截断（不四舍五入：余额只能少报不能多报）
      expect(account.totalSpent, 300);
    });

    test('数值型与缺字段', () {
      final account = StarAccount.fromJson(const {
        'availableToken': 200,
        'totalToken': 500.0,
      });
      expect(account.balance, 200);
      expect(account.totalPurchased, 500);
      // 缺字段 = 0：这三个数是累计量，后端不给就是没有
      expect(account.totalSpent, 0);
    });
  });

  // 同一个 `_toInt` 也归一套餐/记录里的数字，那边同样可能收到 "200.0"
  group('套餐数量同样认小数位 String', () {
    test('num / giveNum 为 "200.0" / "50.0"', () {
      final package = StarPackage.fromJson(const {
        'goodsId': '7.0',
        'num': '200.0',
        'giveNum': '50.0',
        'amount': '90',
      });
      expect(package.goodsId, 7);
      expect(package.tokens, 200);
      expect(package.gift, 50);
      expect(package.totalTokens, 250);
    });
  });
}
