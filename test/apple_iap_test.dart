import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:BoltStar/src/features/star/presentation/star_purchase_page.dart';
import 'package:BoltStar/src/shared/l10n/app_l10n.dart';
import 'package:BoltStar/src/state.dart';
import 'package:BoltStar/src/network/api_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:BoltStar/src/features/star/apple_iap.dart';
import 'package:BoltStar/src/features/star/star_coin_api.dart';
import 'package:BoltStar/src/network/api_client.dart';
import 'package:BoltStar/src/network/boltfox_api.dart';

const package = StarPackage(
  goodsId: 7,
  name: 'Stars',
  tokens: 200,
  gift: 50,
  price: 2,
  currencySymbol: r'$',
  wxProductId: '',
  appleProductId: 'stars.200',
);

Map<String, dynamic> verifiedReceipt({
  String id = 'tx-1',
  String product = 'stars.200',
  Object? status = 0,
  bool revoked = false,
}) => {
  'status': status,
  'responseData': jsonEncode({
    'status': 0,
    'receipt': {
      'in_app': [
        {
          'transaction_id': id,
          'product_id': product,
          'quantity': '1',
          if (revoked) 'cancellation_date_ms': '123',
        },
      ],
    },
  }),
};

class FakeBridge implements AppleIapBridge {
  void Function(Map<String, dynamic>)? listener;
  bool allowed = true;
  bool missingProduct = false;
  bool lostBuyReply = false;
  bool missingReceipt = false;
  int buyCalls = 0;
  int charges = 0;
  int finishCalls = 0;
  int productCalls = 0;
  int acknowledgements = 0;
  final List<bool> receiptRefreshes = [];
  final List<Map<String, dynamic>> rows = [];
  String? accountToken;

  @override
  Future<bool> initialize(void Function(Map<String, dynamic>) onEvent) async {
    listener = onEvent;
    return allowed;
  }

  @override
  Future<AppleIapProduct> product(String productId) async {
    productCalls++;
    if (missingProduct) throw PlatformException(code: 'product_unavailable');
    return AppleIapProduct(id: productId, price: r'$1.99');
  }

  @override
  Future<void> buy(String productId, String token) async {
    buyCalls++;
    if (rows.isNotEmpty) throw PlatformException(code: 'payment_busy');
    accountToken = token;
    rows.add({
      'accountToken': token,
      'productId': productId,
      'state': 'purchasing',
    });
    charges++;
    if (lostBuyReply) throw PlatformException(code: 'channel_error');
  }

  @override
  Future<List<Map<String, dynamic>>> pending() async =>
      rows.map(Map<String, dynamic>.from).toList();
  @override
  Future<String> receipt({required bool refreshIfMissing}) async {
    receiptRefreshes.add(refreshIfMissing);
    if (missingReceipt && !refreshIfMissing) {
      throw PlatformException(code: 'receipt_missing');
    }
    return base64Encode([1, 2, 3]);
  }

  @override
  Future<void> finish(String transactionId, String accountToken) async {
    finishCalls++;
    rows.removeWhere((row) => row['transactionId'] == transactionId);
  }

  @override
  Future<void> acknowledgeFailure(String accountToken) async {
    acknowledgements++;
    rows.removeWhere((row) => row['accountToken'] == accountToken);
  }

  void purchased({String id = 'tx-1'}) {
    rows.single['state'] = 'purchased';
    rows.single['transactionId'] = id;
  }
}

class MemoryStore implements AppleIapStore {
  List<Map<String, dynamic>> records = [];
  bool failSave = false;
  @override
  Future<List<Map<String, dynamic>>> load() async =>
      records.map(Map<String, dynamic>.from).toList();
  @override
  Future<void> save(List<Map<String, dynamic>> rows) async {
    if (failSave) throw StateError('disk full');
    records = rows.map(Map<String, dynamic>.from).toList();
  }
}

class FakeBackend implements AppleIapBackend {
  int orderCalls = 0;
  int verifyCalls = 0;
  String? verifiedOrderNo;
  String? verifiedTransactionId;
  int? currentBalance = 100;
  bool paid = false;
  bool loseVerifyReply = false;
  Map<String, dynamic> verification = verifiedReceipt();
  Completer<void>? holdVerification;
  Completer<void>? verificationStarted;
  @override
  Future<StarOrder> createOrder(StarPackage package) async {
    orderCalls++;
    return StarOrder(
      orderNo: 'order-$orderCalls',
      orderId: '1',
      amount: 2,
      payType: 2,
    );
  }

  @override
  Future<int?> balance() async => currentBalance;
  @override
  Future<bool> orderPaid(String orderNo) async => paid;
  @override
  Future<AppleReceiptVerification> verify({
    required String receipt,
    required String orderNo,
    required String transactionId,
  }) async {
    expect(base64Decode(receipt), [1, 2, 3]);
    verifyCalls++;
    verifiedOrderNo = orderNo;
    verifiedTransactionId = transactionId;
    expect(orderNo, 'order-1');
    expect(transactionId, 'tx-1');
    verificationStarted?.complete();
    if (holdVerification != null) await holdVerification!.future;
    if (loseVerifyReply) throw TimeoutException('lost reply');
    return AppleReceiptVerification.fromJson(verification);
  }
}

class Fixture {
  Fixture() {
    controller = AppleIapController(
      bridge: bridge,
      store: store,
      backend: backend,
      supported: true,
      confirmationDelays: const [Duration.zero],
    );
  }
  final bridge = FakeBridge();
  final store = MemoryStore();
  final backend = FakeBackend();
  late final AppleIapController controller;
  Future<void> login([String user = 'user-A']) async {
    controller.setUser(user);
    await settle();
  }

  Future<void> settle() async {
    for (var i = 0; i < 30 && controller.busy; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(controller.busy, isFalse);
  }

  Future<void> start() async {
    await login();
    await controller.buy(package);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'receipt success requires a matching, unrevoked individual transaction',
    () {
      expect(
        AppleReceiptVerification.fromJson(
          verifiedReceipt(),
        ).matches('tx-1', 'stars.200'),
        isTrue,
      );
      for (final invalid in [
        verifiedReceipt(id: 'other'),
        verifiedReceipt(product: 'other'),
        verifiedReceipt(status: null),
        verifiedReceipt(status: 21007),
        verifiedReceipt(revoked: true),
        {'status': 0, 'responseData': 'not JSON'},
      ]) {
        expect(
          AppleReceiptVerification.fromJson(
            invalid,
          ).matches('tx-1', 'stars.200'),
          isFalse,
        );
      }
    },
  );

  test(
    'unavailable product and disallowed payments never create orders',
    () async {
      final f = Fixture();
      await f.login();
      f.bridge.missingProduct = true;
      await f.controller.buy(package);
      expect(f.backend.orderCalls, 0);
      expect(f.bridge.charges, 0);
      final blocked = Fixture()..bridge.allowed = false;
      await blocked.login();
      await blocked.controller.buy(package);
      expect(blocked.backend.orderCalls, 0);
    },
  );

  test('persisted UUID and order precede the native purchase', () async {
    final f = Fixture();
    await f.start();
    expect(f.store.records.single['userId'], 'user-A');
    expect(f.store.records.single['orderNo'], 'order-1');
    expect(f.store.records.single['accountToken'], f.bridge.accountToken);
    expect(
      f.bridge.accountToken,
      matches(
        RegExp(
          r'^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$',
        ),
      ),
    );
    expect(f.store.records.single.containsKey('receiptData'), isFalse);
  });

  test(
    'storage failure blocks charging, and continuing persists before charging',
    () async {
      final f = Fixture();
      await f.login();
      f.store.failSave = true;
      await f.controller.buy(package);
      expect(f.bridge.charges, 0);
      await f.controller.buy(package);
      expect(f.bridge.charges, 0);
      f.store.failSave = false;
      await f.controller.buy(package);
      expect(f.bridge.charges, 1);
      expect(f.backend.orderCalls, 1);
      expect(f.store.records, hasLength(1));
    },
  );

  test('lost native reply does not create a second order or charge', () async {
    final f = Fixture()..bridge.lostBuyReply = true;
    await f.start();
    await f.controller.buy(package);
    expect(f.backend.orderCalls, 1);
    expect(f.bridge.charges, 1);
    expect(f.controller.hasPending, isTrue);
  });

  test(
    'validation alone leaves delivery pending and transaction unfinished',
    () async {
      final f = Fixture();
      await f.start();
      f.bridge.purchased();
      await f.controller.retry();
      expect(f.backend.verifyCalls, 1);
      expect(f.controller.phase, AppleIapPhase.pending);
      expect(f.bridge.finishCalls, 0);
      expect(f.store.records.single['receiptVerified'], isTrue);
      await f.controller.retry();
      expect(f.backend.verifyCalls, 1);
    },
  );

  test(
    'unrelated balance increase cannot establish delivery without the order',
    () async {
      final f = Fixture();
      await f.start();
      f.bridge.purchased();
      f.backend.currentBalance = 500;
      await f.controller.retry();
      expect(f.bridge.finishCalls, 0);
      expect(f.controller.phase, AppleIapPhase.pending);
    },
  );

  test('paid order and the complete token increase finish once', () async {
    final f = Fixture();
    await f.start();
    f.bridge.purchased();
    f.backend.paid = true;
    f.backend.currentBalance = 349;
    await f.controller.retry();
    expect(f.bridge.finishCalls, 0);
    f.backend.currentBalance = 350;
    await f.controller.retry();
    expect(f.controller.phase, AppleIapPhase.credited);
    expect(f.controller.creditedTokens, 250);
    expect(f.bridge.finishCalls, 1);
    expect(f.store.records, isEmpty);
    await f.controller.retry();
    expect(f.bridge.finishCalls, 1);
    expect(f.backend.verifyCalls, 1);
  });

  test(
    'missing baseline never treats an existing balance as delivery',
    () async {
      final f = Fixture()..backend.currentBalance = null;
      await f.start();
      f.bridge.purchased();
      f.backend.paid = true;
      f.backend.currentBalance = 1000;
      await f.controller.retry();
      expect(f.bridge.finishCalls, 0);
    },
  );

  test('lost verification reply requires explicit retry', () async {
    final f = Fixture()..backend.loseVerifyReply = true;
    await f.start();
    f.bridge.purchased();
    await f.controller.retry();
    await f.controller.retry();
    expect(f.backend.verifyCalls, 1);
    f.backend.loseVerifyReply = false;
    await f.controller.retry(manual: true);
    expect(f.backend.verifyCalls, 2);
  });

  test('missing receipt refresh prompts only after explicit retry', () async {
    final f = Fixture()..bridge.missingReceipt = true;
    await f.start();
    f.bridge.purchased();
    await f.controller.retry();
    expect(f.backend.verifyCalls, 0);
    await f.controller.retry(manual: true);
    expect(f.bridge.receiptRefreshes, [false, true]);
    expect(f.backend.verifyCalls, 1);
  });

  test(
    'deferred purchase stays pending without receipt verification',
    () async {
      final f = Fixture();
      await f.start();
      f.bridge.rows.single['state'] = 'deferred';
      await f.controller.retry();
      expect(f.controller.phase, AppleIapPhase.deferred);
      expect(f.backend.verifyCalls, 0);
      expect(f.bridge.finishCalls, 0);
    },
  );

  test(
    'cancellation clears only its mapping and acknowledges native failure',
    () async {
      final f = Fixture();
      await f.start();
      f.bridge.rows.single['state'] = 'canceled';
      await f.controller.retry();
      expect(f.controller.phase, AppleIapPhase.canceled);
      expect(f.store.records, isEmpty);
      expect(f.bridge.acknowledgements, 1);
      expect(f.backend.verifyCalls, 0);
    },
  );

  test(
    'restart replays the correct owner; other accounts cannot verify',
    () async {
      final f = Fixture();
      await f.start();
      f.bridge.purchased();
      final restarted = AppleIapController(
        bridge: f.bridge,
        store: f.store,
        backend: f.backend,
        supported: true,
        confirmationDelays: const [Duration.zero],
      );
      restarted.setUser('user-B');
      while (restarted.busy) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(f.backend.verifyCalls, 0);
      restarted.setUser('user-A');
      while (restarted.busy) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(f.backend.verifyCalls, 1);
      expect(f.backend.orderCalls, 1);
    },
  );

  test(
    'account switch during verification cannot query or finish under new user',
    () async {
      final f = Fixture();
      await f.start();
      f.bridge.purchased();
      f.backend.holdVerification = Completer();
      f.backend.verificationStarted = Completer();
      final checking = f.controller.retry();
      await f.backend.verificationStarted!.future;
      f.controller.setUser('user-B');
      f.backend.holdVerification!.complete();
      await checking;
      await f.settle();
      expect(f.bridge.finishCalls, 0);
      expect(f.store.records.single['userId'], 'user-A');
      expect(f.store.records.single['receiptVerified'], isFalse);
    },
  );

  test('simultaneous recovery and repeated callbacks submit once', () async {
    final f = Fixture();
    await f.start();
    f.bridge.purchased();
    final first = f.controller.retry();
    f.bridge.listener!({});
    await f.controller.retry();
    await first;
    await f.settle();
    expect(f.backend.verifyCalls, 1);
  });

  test(
    'verification HTTP body uses legacy Base64 and no automatic connection retry',
    () async {
      final original = ApiClient.instance.httpClient;
      addTearDown(() => ApiClient.instance.httpClient = original);
      var calls = 0;
      final receipt = base64Encode([1, 2, 3]);
      ApiClient.instance.httpClient = MockClient((request) async {
        calls++;
        expect(request.url.path, '/Client/Pay/setApplePayVerifyReceipt');
        expect(jsonDecode(request.body), {
          'receiptData': receipt,
          'orderNo': 'order-1',
          'transactionId': 'tx-1',
        });
        throw http.ClientException('connection interrupted');
      });
      await expectLater(
        BoltFoxApi.setApplePayVerifyReceipt(
          receiptData: receipt,
          orderNo: 'order-1',
          transactionId: 'tx-1',
        ),
        throwsA(anything),
      );
      expect(calls, 1);
      final description = ApiClient.instance.describeRequest(
        'POST',
        '/Client/Pay/setApplePayVerifyReceipt',
        body: {'receiptData': receipt},
      );
      expect(description, isNot(contains(receipt)));
      expect(description, contains('[redacted]'));
      final originalPrint = debugPrint;
      final logs = <String>[];
      debugPrint = (message, {wrapWidth}) => logs.add(message ?? '');
      try {
        ApiClient.instance.httpClient = MockClient((request) async {
          return http.Response(
            jsonEncode({
              'retCode': 200,
              'retData': {
                'status': 0,
                'latestReceipt': receipt,
                'responseData': jsonEncode({'latest_receipt': receipt}),
              },
            }),
            200,
          );
        });
        final data = await BoltFoxApi.setApplePayVerifyReceipt(
          receiptData: receipt,
          orderNo: 'order-1',
          transactionId: 'tx-1',
        );
        expect((data as Map)['latestReceipt'], receipt);
        expect(logs.join('\n'), isNot(contains(receipt)));
        expect(logs.join('\n'), contains('redacted Apple receipt response'));
      } finally {
        debugPrint = originalPrint;
      }
    },
  );

  testWidgets(
    'iOS confirms App Store price and Chinese purchases bypass PayPal restriction',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final f = Fixture();
      await tester.runAsync(f.login);
      await tester.pumpWidget(
        MaterialApp(
          home: AppLocalizationsScope(
            language: AppLanguage.zh,
            child: StarPurchasePage(package: package, appleIap: f.controller),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(r'$1.99'), findsOneWidget);
      expect(find.text(r'$2.00'), findsNothing);
      expect(find.text('PayPal'), findsNothing);
      await tester.tap(find.text('立即购买'));
      await tester.pumpAndSettle();
      expect(f.backend.orderCalls, 1);
      expect(f.bridge.charges, 1);
      expect(find.text('重新确认支付'), findsOneWidget);
      expect(find.textContaining('不支持人民币'), findsNothing);
      f.bridge.rows.single['state'] = 'canceled';
      await tester.tap(find.text('重新确认支付'));
      await tester.pumpAndSettle();
      expect(find.text('已取消支付'), findsOneWidget);
      expect(f.store.records, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      debugDefaultTargetPlatformOverride = null;
    },
  );

  test(
    'native bridge initializes machine and preserves legacy receipt bytes',
    () async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(MethodChannelAppleIapBridge.channel, (
        call,
      ) async {
        calls.add(call);
        switch (call.method) {
          case 'initialize':
            return {'canMakePayments': true, 'device': 'iPhone14,5'};
          case 'product':
            return {'productId': 'stars.200', 'localizedPrice': r'$1.99'};
          case 'receipt':
            return base64Encode([1, 2, 3]);
          case 'pendingTransactions':
            return <dynamic>[];
          default:
            return null;
        }
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(
          MethodChannelAppleIapBridge.channel,
          null,
        ),
      );
      final bridge = MethodChannelAppleIapBridge();
      expect(await bridge.initialize((_) {}), isTrue);
      expect(ApiSession.instance.device, 'iPhone14,5');
      expect((await bridge.product('stars.200')).price, r'$1.99');
      expect(base64Decode(await bridge.receipt(refreshIfMissing: false)), [
        1,
        2,
        3,
      ]);
      await bridge.buy('stars.200', 'uuid');
      expect(calls.last.arguments, {
        'productId': 'stars.200',
        'accountToken': 'uuid',
      });
      await bridge.finish('tx-1', 'uuid');
      expect(calls.last.arguments, {
        'transactionId': 'tx-1',
        'accountToken': 'uuid',
      });
      ApiSession.instance.device = '';
    },
  );

  test('new App Store messages are localized in all four languages', () {
    for (final language in AppLanguage.values) {
      final l10n = AppL10n(language);
      for (final text in [
        l10n.starApplePurchase,
        l10n.starApplePending,
        l10n.starAppleDeferred,
        l10n.starAppleRetry,
        l10n.starAppleContinue,
      ]) {
        expect(text, isNotEmpty);
        if (language == AppLanguage.en) {
          expect(text, isNot(matches(RegExp(r'[\u4e00-\u9fff]'))));
        }
      }
    }
  });
}
