import 'dart:convert';

import 'package:BoltStar/src/features/star/apple_iap.dart';
import 'package:BoltStar/src/features/star/star_coin_api.dart';
import 'package:BoltStar/src/network/api_client.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _package = StarPackage(
  goodsId: 9,
  name: '7500',
  tokens: 7500,
  gift: 0,
  price: 15.99,
  currencySymbol: r'$',
  wxProductId: 'xb2',
  appleProductId: 'xb2',
);

class _EmptyStore implements AppleIapStore {
  @override
  Future<List<Map<String, dynamic>>> load() async => [];
  @override
  Future<void> save(List<Map<String, dynamic>> rows) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late List<String> logs;
  late AppleIapController controller;
  late Future<Object?> Function(MethodCall) native;
  setUp(() {
    logs = [];
    final originalPrint = debugPrint;
    debugPrint = (message, {wrapWidth}) => logs.add(message ?? '');
    addTearDown(() => debugPrint = originalPrint);
    native = (call) async => call.method == 'initialize'
        ? {'bundleId': 'com.boltfox.boltstar', 'canMakePayments': true}
        : {'productId': 'xb2', 'localizedPrice': r'$15.99'};
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      MethodChannelAppleIapBridge.channel,
      (call) => native(call),
    );
    addTearDown(() async {
      messenger.setMockMethodCallHandler(
        MethodChannelAppleIapBridge.channel,
        null,
      );
      MethodChannelAppleIapBridge.channel.setMethodCallHandler(null);
    });
    controller = AppleIapController(supported: true, store: _EmptyStore());
    addTearDown(controller.dispose);
  });

  Map<String, dynamic> entry(String stage) {
    final prefix = '[AppleIAP] $stage: ';
    return jsonDecode(
          logs
              .singleWhere((line) => line.startsWith(prefix))
              .substring(prefix.length),
        )
        as Map<String, dynamic>;
  }

  test(
    'actual client payload keeps selected xb2 through HTTP parser and product query',
    () async {
      final original = ApiClient.instance.httpClient;
      addTearDown(() => ApiClient.instance.httpClient = original);
      ApiClient.instance.httpClient = MockClient(
        (request) async => http.Response(
          jsonEncode({
            'retCode': 200,
            'retMsg': '操作成功！',
            'retData': [
              {
                'goodsId': 8,
                'currencySymbol': r'$',
                'amount': 5.99,
                'marketAmount': 10.0,
                'goodsName': '2500',
                'num': 2500,
                'giveNum': 0,
                'wxProductId': 'xb1',
                'appleProductId': 'xb1',
              },
              {
                'goodsId': 9,
                'currencySymbol': r'$',
                'amount': 15.99,
                'marketAmount': 20.0,
                'goodsName': '7500',
                'num': 7500,
                'giveNum': 0,
                'wxProductId': 'xb2',
                'appleProductId': 'xb2',
              },
              {
                'goodsId': 10,
                'currencySymbol': r'$',
                'amount': 59.99,
                'marketAmount': 68.0,
                'goodsName': '30000',
                'num': 30000,
                'giveNum': 0,
                'wxProductId': 'xb3',
                'appleProductId': 'xb3',
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        ),
      );
      final packages = await StarCoinApi.fetchPackages();
      expect(packages.map((p) => p.appleProductId).toList(), [
        'xb1',
        'xb2',
        'xb3',
      ]);
      final product = await controller.prepare(
        packages.singleWhere((p) => p.goodsId == 9),
      );
      expect(product.id, 'xb2');
      expect(product.price, r'$15.99');
      expect(entry('prepare.request')['productId'], 'xb2');
      expect(entry('initialize.response')['bundleId'], 'com.boltfox.boltstar');
      expect(entry('product.request')['productId'], 'xb2');
      expect(entry('product.response')['returnedProductId'], 'xb2');
    },
  );

  for (final scenario in [
    (
      'product_unavailable',
      'storekit_empty_products',
      <String, Object?>{
        'requestedProductId': 'xb2',
        'returnedProductIds': <String>[],
        'invalidProductIds': ['xb2'],
      },
    ),
    (
      'product_timeout',
      'storekit_product_timeout',
      <String, Object?>{'timeoutSeconds': 30},
    ),
    (
      'product_unavailable',
      'storekit_request_failed',
      <String, Object?>{
        'nativeErrorDomain': 'NSURLErrorDomain',
        'nativeErrorCode': -1009,
        'nativeMessage': 'The Internet connection appears to be offline.',
        'underlyingErrors': [
          {'domain': 'ASDErrorDomain', 'nativeErrorCode': 500},
        ],
      },
    ),
  ]) {
    test(
      'product preflight retains ${scenario.$2} and original platform code',
      () async {
        native = (call) async {
          if (call.method == 'initialize') return {'canMakePayments': true};
          throw PlatformException(
            code: scenario.$1,
            message: 'StoreKit product failure',
            details: {
              'reason': scenario.$2,
              'bundleId': 'com.boltfox.boltstar',
              ...scenario.$3,
              'userToken': 'secret-user-token',
              'receiptData': 'secret-receipt',
              'accountToken': 'secret-account-token',
              'responseData': 'secret-response',
            },
          );
        };
        await expectLater(
          controller.prepare(_package),
          throwsA(
            isA<PlatformException>().having(
              (e) => e.code,
              'original code',
              scenario.$1,
            ),
          ),
        );
        final failure = entry('prepare.product.failed');
        expect(failure['reason'], scenario.$2);
        for (final item in scenario.$3.entries) {
          expect(failure[item.key], item.value);
        }
        final text = logs.join('\n');
        for (final secret in [
          'secret-user-token',
          'secret-receipt',
          'secret-account-token',
          'secret-response',
        ]) {
          expect(text, isNot(contains(secret)));
        }
      },
    );
  }

  test(
    'payment permission refusal is not reported as product query failure',
    () async {
      native = (call) async {
        expect(call.method, 'initialize');
        return {'canMakePayments': false, 'bundleId': 'com.boltfox.boltstar'};
      };
      await expectLater(
        controller.prepare(_package),
        throwsA(
          isA<PlatformException>().having(
            (e) => e.code,
            'code',
            'payment_not_allowed',
          ),
        ),
      );
      expect(entry('prepare.permission.failed')['code'], 'payment_not_allowed');
      expect(
        logs.any((line) => line.startsWith('[AppleIAP] product.request:')),
        isFalse,
      );
    },
  );

  test(
    'missing native bridge points to initialize stage without a product request',
    () async {
      native = (call) async => null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(MethodChannelAppleIapBridge.channel, null);
      await expectLater(
        controller.prepare(_package),
        throwsA(isA<MissingPluginException>()),
      );
      expect(
        entry('prepare.initialize.failed')['reason'],
        'native_bridge_missing',
      );
    },
  );

  for (final response in [
    {'productId': 'xb3', 'localizedPrice': r'$15.99'},
    {'productId': 'xb2', 'localizedPrice': ''},
  ]) {
    test(
      'invalid product reply distinguishes ${response['productId']}/${response['localizedPrice']}',
      () async {
        native = (call) async =>
            call.method == 'initialize' ? {'canMakePayments': true} : response;
        await expectLater(
          controller.prepare(_package),
          throwsA(isA<PlatformException>()),
        );
        expect(
          entry('prepare.product.failed')['reason'],
          response['productId'] == 'xb2'
              ? 'localized_price_empty'
              : 'product_id_mismatch',
        );
      },
    );
  }

  test(
    'system error description redacts account, URL and credential text',
    () async {
      native = (call) async {
        if (call.method == 'initialize') return {'canMakePayments': true};
        throw PlatformException(
          code: 'product_unavailable',
          details: {
            'nativeMessage':
                'Failed https://example.test/path?token=secret-url user@example.test userToken=secret-inline',
            'underlyingErrors': [
              {
                'domain': 'ASDErrorDomain',
                'nativeErrorCode': 500,
                'receiptData': 'secret-nested',
              },
            ],
          },
        );
      };
      await expectLater(
        controller.prepare(_package),
        throwsA(isA<PlatformException>()),
      );
      final text = logs.join('\n');
      for (final secret in [
        'secret-url',
        'user@example.test',
        'secret-inline',
        'secret-nested',
      ]) {
        expect(text, isNot(contains(secret)));
      }
      expect(text, contains('ASDErrorDomain'));
      expect(text, contains('[redacted]'));
    },
  );
}
