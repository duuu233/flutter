import 'dart:async';
import 'dart:convert';

import 'package:BoltStar/src/features/star/apple_iap.dart';
import 'package:BoltStar/src/features/star/star_coin_api.dart';
import 'package:BoltStar/src/network/api_client.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:BoltStar/src/features/star/apple_iap_diagnostics.dart';
import 'package:BoltStar/src/features/star/presentation/star_purchase_page.dart';
import 'package:BoltStar/src/shared/l10n/app_l10n.dart';
import 'package:BoltStar/src/state.dart';
import 'package:BoltStar/src/shared/widgets/figma_common.dart';
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

  Future<void> pumpPage(
    WidgetTester tester, {
    Size size = const Size(375, 812),
    double scale = 1,
  }) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: AppLocalizationsScope(
          language: AppLanguage.zh,
          child: StarPurchasePage(package: _package, appleIap: controller),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  String pageDetails(WidgetTester tester) => tester
      .widget<SelectableText>(
        find.byKey(const Key('apple-product-diagnostics-text')),
      )
      .data!;

  testWidgets('底部显示任意商品错误详情，失败不再显示价格加载中，复制已脱敏', (tester) async {
    native = (call) async {
      if (call.method == 'initialize') {
        return {'canMakePayments': true, 'bundleId': 'com.boltfox.boltstar'};
      }
      throw PlatformException(
        code: 'product_unavailable',
        message: 'StoreKit unavailable',
        details: {
          'invalidProductIds': ['xb2'],
          'nativeErrorCode': 500,
          'newAppleFailureReason': 'Storefront unavailable',
          'userToken': 'secret-user',
          'receiptData': 'secret-receipt',
        },
      );
    };
    await pumpPage(tester);
    expect(find.text('苹果支付诊断详情'), findsOneWidget);
    expect(find.text('价格获取失败'), findsOneWidget);
    expect(find.text('正在获取价格…'), findsNothing);
    final details = pageDetails(tester);
    expect(details, contains('xb2'));
    expect(details, contains('product_unavailable'));
    expect(details, contains('newAppleFailureReason'));
    expect(details, contains('Storefront unavailable'));
    expect(details, isNot(contains('secret-user')));
    expect(details, isNot(contains('secret-receipt')));
    expect(
      tester
          .widget<FigmaPrimaryButton>(find.byType(FigmaPrimaryButton))
          .onPressed,
      isNull,
    );
    String? copied;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map)['text'] as String;
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );
    await tester.tap(find.byKey(const Key('copy-apple-product-diagnostics')));
    await tester.pump();
    expect(copied, details);
    await tester.pump(const Duration(seconds: 4));
    debugDefaultTargetPlatformOverride = null;
    debugPrint = tester.binding.debugPrintOverride;
    expect(tester.takeException(), isNull);
  });

  testWidgets('重试替换上次详情，缓存初始化仍能看到BundleID，成功显示苹果价格', (tester) async {
    var failed = true;
    native = (call) async {
      if (call.method == 'initialize') {
        return {'canMakePayments': true, 'bundleId': 'com.boltfox.boltstar'};
      }
      if (failed) {
        throw PlatformException(
          code: 'product_timeout',
          details: {'reason': 'storekit_product_timeout'},
        );
      }
      return {'productId': 'xb2', 'localizedPrice': r'$15.99'};
    };
    await pumpPage(tester);
    expect(pageDetails(tester), contains('storekit_product_timeout'));
    failed = false;
    await tester.tap(find.text('重新获取商品'));
    await tester.pumpAndSettle();
    expect(find.text(r'$15.99'), findsOneWidget);
    expect(find.text('价格获取失败'), findsNothing);
    expect(pageDetails(tester), contains('com.boltfox.boltstar'));
    expect(pageDetails(tester), contains('product.response'));
    expect(pageDetails(tester), isNot(contains('storekit_product_timeout')));
    debugDefaultTargetPlatformOverride = null;
    debugPrint = tester.binding.debugPrintOverride;
    expect(tester.takeException(), isNull);
  });

  testWidgets('短屏大字体与长系统错误：底部可滚动，购买及复制按钮不溢出', (tester) async {
    native = (call) async {
      if (call.method == 'initialize') return {'canMakePayments': true};
      throw PlatformException(
        code: 'unknown_store_error',
        message: List.filled(100, 'long native error').join(' '),
      );
    };
    await pumpPage(tester, size: const Size(375, 568), scale: 1.8);
    expect(pageDetails(tester), contains('unknown_store_error'));
    expect(
      tester.getRect(find.byKey(const Key('apple-product-diagnostics'))).bottom,
      lessThan(568),
    );
    expect(tester.getRect(find.text('立即购买')).bottom, lessThanOrEqualTo(568));
    await tester.drag(
      find.byKey(const Key('apple-product-diagnostics-scroll')),
      const Offset(0, -250),
    );
    await tester.pumpAndSettle();
    debugDefaultTargetPlatformOverride = null;
    debugPrint = tester.binding.debugPrintOverride;
    expect(tester.takeException(), isNull);
  });

  testWidgets('退出页面后查询才返回，不更新已销毁的页面', (tester) async {
    final pending = Completer<Object?>();
    native = (call) async => call.method == 'initialize'
        ? {'canMakePayments': true}
        : pending.future;
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Text('root'))),
    );
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    unawaited(
      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) =>
              StarPurchasePage(package: _package, appleIap: controller),
        ),
      ),
    );
    await tester.pumpAndSettle();
    navigator.pop();
    await tester.pumpAndSettle();
    pending.complete({'productId': 'xb2', 'localizedPrice': r'$15.99'});
    await tester.pump();
    expect(find.text('root'), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
    debugPrint = tester.binding.debugPrintOverride;
    expect(tester.takeException(), isNull);
  });

  test('采集不依赖控制台，异步请求隔离，结束后不再持有页面回调', () async {
    final first = <String>[];
    final second = <String>[];
    final pending = Completer<void>();
    final late = Completer<void>();
    final request = AppleIapDiagnostics.capture(() async {
      AppleIapDiagnostics.log('product.request', {'productId': 'first'});
      unawaited(
        late.future.then(
          (_) => AppleIapDiagnostics.log('late', {'productId': 'first'}),
        ),
      );
      await pending.future;
      AppleIapDiagnostics.log('product.response', {'productId': 'first'});
    }, onEntry: first.add);
    await AppleIapDiagnostics.capture(() async {
      AppleIapDiagnostics.log('product.request', {'productId': 'second'});
    }, onEntry: second.add);
    pending.complete();
    await request;
    late.complete();
    await Future<void>.delayed(Duration.zero);
    expect(first, hasLength(2));
    expect(first.join(), isNot(contains('second')));
    expect(second, hasLength(1));
    expect(second.single, contains('second'));
  });

  test('完整未知错误与长描述保留，敏感嵌套字段继续脱敏，四语文案完整', () {
    final description = List.filled(100, 'native failure').join(' ');
    final text = AppleIapDiagnostics.describeError(
      PlatformException(
        code: 'new_code',
        message: description,
        details: {
          'vendorExtra': {
            'futureField': 'retain me',
            'applicationUsername': 'secret-account',
            'userToken': 'secret-token',
          },
          'receiptData': 'secret-receipt',
          'futureJson':
              '{"userToken":"secret-json-token","receiptData":"secret-json-receipt"}',
        },
      ),
    );
    expect(text, contains(description));
    expect(text, contains('retain me'));
    for (final secret in [
      'secret-account',
      'secret-token',
      'secret-receipt',
      'secret-json-token',
      'secret-json-receipt',
    ]) {
      expect(text, isNot(contains(secret)));
    }
    expect(
      AppleIapDiagnostics.describeError(StateError('initialization failed')),
      contains('initialization failed'),
    );
    for (final language in AppLanguage.values) {
      final l10n = AppL10n(language);
      expect(l10n.starApplePriceUnavailable, isNotEmpty);
      expect(l10n.starAppleDiagnosticsTitle, isNotEmpty);
      expect(l10n.starAppleDiagnosticsWaiting, isNotEmpty);
    }
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
