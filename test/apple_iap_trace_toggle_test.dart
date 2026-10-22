import 'dart:async';
import 'dart:convert';

import 'package:BoltStar/src/features/star/apple_iap.dart';
import 'package:BoltStar/src/features/star/apple_iap_diagnostics.dart';
import 'package:BoltStar/src/network/api_client.dart';
import 'package:BoltStar/src/shared/l10n/app_l10n.dart';
import 'package:BoltStar/src/state.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'apple_iap_test.dart' as fixtures;
import 'apple_iap_reorder_test.dart' show pumpPurchase;

class ReceiptBridge extends fixtures.FakeBridge {
  int missingReads = 0;
  String value = base64Encode([1, 2, 3]);
  bool failRefresh = false;
  @override
  Future<String> receipt({required bool refreshIfMissing}) async {
    receiptRefreshes.add(refreshIfMissing);
    if (refreshIfMissing && failRefresh) {
      throw PlatformException(
        code: 'receipt_failed',
        details: {
          'nativeErrorDomain': 'ASDErrorDomain',
          'nativeErrorCode': 21104,
        },
      );
    }
    if (missingReads-- > 0) throw PlatformException(code: 'receipt_missing');
    return value;
  }
}

class ReceiptBackend extends fixtures.FakeBackend {
  String? submittedReceipt;
  bool useHttp = false;
  @override
  Future<AppleReceiptVerification> verify({
    required String receipt,
    required String orderNo,
    required String transactionId,
  }) async {
    submittedReceipt = receipt;
    if (useHttp) {
      return ApiAppleIapBackend().verify(
        receipt: receipt,
        orderNo: orderNo,
        transactionId: transactionId,
      );
    }
    verifyCalls++;
    return AppleReceiptVerification.fromJson({
      'status': 0,
      'environment': 'Sandbox',
      'responseData': null,
      'exceptionMsg': '平台产品与凭据不符合',
    });
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('late local receipt is read passively and submitted once', () async {
    final bridge = ReceiptBridge()..missingReads = 1;
    final f = fixtures.Fixture(
      bridge: bridge,
      receiptReadDelays: const [Duration.zero, Duration.zero],
    );
    addTearDown(f.controller.dispose);
    await f.start();
    bridge.purchased();
    await f.controller.retry();
    expect(bridge.receiptRefreshes, [false, false]);
    expect(f.backend.verifyCalls, 1);
    expect(f.controller.diagnostics.join(), contains('receipt.wait'));
  });

  test(
    'manual refresh failure records Apple code without posting or finishing',
    () async {
      final bridge = ReceiptBridge()
        ..missingReads = 100
        ..failRefresh = true;
      final f = fixtures.Fixture(bridge: bridge);
      addTearDown(f.controller.dispose);
      await f.start();
      bridge.purchased();
      await f.controller.retry();
      await f.controller.retry(manual: true);
      expect(bridge.receiptRefreshes, [false, false, true]);
      expect(f.backend.verifyCalls, 0);
      expect(bridge.finishCalls, 0);
      expect(f.controller.errorCode, 'receipt_failed');
      final logs = f.controller.diagnostics.join();
      expect(logs, contains('"nativeErrorCode":21104'));
      expect(logs, contains('"backendCalled":false'));
    },
  );

  test(
    'queued manual retry is retained after an in-flight rejected verification',
    () async {
      final f = fixtures.Fixture();
      addTearDown(f.controller.dispose);
      f.backend.verification = {
        'status': 0,
        'responseData': null,
        'exceptionMsg': '平台产品与凭据不符合',
      };
      await f.start();
      f.bridge.purchased();
      f.backend.holdVerification = Completer<void>();
      f.backend.verificationStarted = Completer<void>();
      final first = f.controller.retry();
      await f.backend.verificationStarted!.future;
      f.backend.verificationStarted = null;
      await f.controller.retry(manual: true);
      f.backend.holdVerification!.complete();
      await first;
      await f.settle();
      expect(f.backend.verifyCalls, 2);
      expect(f.backend.orderCalls, 1);
      expect(f.bridge.buyCalls, 1);
      expect(f.bridge.finishCalls, 0);
      expect(f.controller.phase, AppleIapPhase.pending);
      await f.controller.retry();
      expect(f.backend.verifyCalls, 2);
    },
  );

  test(
    'HTTP response evidence proves POST and backend rejection without credentials',
    () async {
      final original = ApiClient.instance.httpClient;
      addTearDown(() => ApiClient.instance.httpClient = original);
      var requests = 0;
      ApiClient.instance.httpClient = MockClient((request) async {
        requests++;
        expect(request.method, 'POST');
        expect(jsonDecode(request.body), {
          'receiptData': base64Encode([1, 2, 3]),
          'orderNo': 'order-1',
          'transactionId': 'tx-1',
        });
        return http.Response(
          jsonEncode({
            'retCode': 200,
            'retData': {
              'status': 0,
              'environment': 'Sandbox',
              'responseData': null,
              'exceptionMsg': '平台产品与凭据不符合',
            },
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });
      final f = fixtures.Fixture(backend: ReceiptBackend()..useHttp = true);
      addTearDown(f.controller.dispose);
      await f.start();
      f.bridge.purchased();
      await f.controller.retry();
      final logs = f.controller.diagnostics.join();
      expect(logs, contains('verify.http.request'));
      expect(logs, contains('"path":"/Client/Pay/setApplePayVerifyReceipt"'));
      expect(logs, contains('"httpStatus":200,"retCode":200'));
      expect(logs, contains('平台产品与凭据不符合'));
      expect(f.controller.errorCode, 'receipt_unverified');
      expect(f.bridge.finishCalls, 0);
      await f.controller.retry();
      expect(requests, 1);
      await f.controller.retry(manual: true);
      expect(requests, 2);
    },
  );

  test(
    'transport failure is scoped, masked and never automatically reposted',
    () async {
      final original = ApiClient.instance.httpClient;
      addTearDown(() => ApiClient.instance.httpClient = original);
      var requests = 0;
      ApiClient.instance.httpClient = MockClient((request) async {
        requests++;
        throw http.ClientException(
          'secret-userToken secret-receipt',
          request.url,
        );
      });
      final events = <String>[];
      final backend = ApiAppleIapBackend();
      await expectLater(
        ApiClient.captureDiagnostics(
          () => backend.verify(
            receipt: 'secret-receipt',
            orderNo: 'order-test',
            transactionId: 'tx-test',
          ),
          onEvent: (stage, fields) => events.add(jsonEncode([stage, fields])),
        ),
        throwsException,
      );
      expect(requests, 1);
      expect(events.length, 2);
      expect(events.last, contains('connection_error'));
      expect(events.join(), isNot(contains('secret-')));
      await expectLater(
        backend.verify(
          receipt: 'another-receipt',
          orderNo: 'order-test',
          transactionId: 'tx-test',
        ),
        throwsException,
      );
      expect(events.length, 2);
    },
  );

  testWidgets(
    'receipt switch hides by default and copying follows visible complete data',
    (tester) async {
      final receipt = base64Encode(List<int>.filled(12000, 97));
      final bridge = ReceiptBridge()..value = receipt;
      final backend = ReceiptBackend();
      final f = fixtures.Fixture(bridge: bridge, backend: backend);
      addTearDown(f.controller.dispose);
      await tester.runAsync(() async {
        await f.start();
        bridge.purchased();
        await f.controller.retry();
      });
      await pumpPurchase(tester, f);
      String details() => tester
          .widget<SelectableText>(
            find.byKey(const Key('apple-product-diagnostics-text')),
          )
          .data!;
      final originalLines = List<String>.of(f.controller.diagnostics);
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      String? copied;
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
      );
      expect(details(), isNot(contains(receipt)));
      expect(details(), contains('"receiptData":"[hidden]"'));
      expect(details(), contains('"receiptLength":16000'));
      expect(details(), contains('"orderNo":"order-1"'));
      expect(details(), contains('"transactionId":"tx-1"'));
      final copy = find.byKey(const Key('copy-apple-product-diagnostics'));
      await tester.tap(copy);
      await tester.pump();
      expect(copied, details());
      final toggle = find.byKey(const Key('toggle-apple-receipt-data'));
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(details(), contains(receipt));
      await tester.tap(copy);
      await tester.pump();
      expect(copied, details());
      expect(copied, contains(receipt));
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(details(), isNot(contains(receipt)));
      expect(backend.submittedReceipt, receipt);
      expect(f.controller.diagnostics, originalLines);
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 6));
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets('clipboard platform failure gives feedback and allows retry', (
    tester,
  ) async {
    final f = fixtures.Fixture();
    addTearDown(f.controller.dispose);
    await pumpPurchase(tester, f);
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        throw PlatformException(code: 'clipboard_failed');
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );
    await tester.tap(find.byKey(const Key('copy-apple-product-diagnostics')));
    await tester.pump();
    expect(
      find.text(AppL10n(AppLanguage.zh).starAppleDiagnosticsCopyFailed),
      findsOneWidget,
    );
    expect(
      tester
          .widget<TextButton>(
            find.byKey(const Key('copy-apple-product-diagnostics')),
          )
          .onPressed,
      isNotNull,
    );
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 6));
    debugDefaultTargetPlatformOverride = null;
  });

  test(
    'hidden projection suppresses malformed receipts and retains other stages',
    () {
      const malformed = '[AppleIAP] verify.request: {"receiptData":"secret';
      expect(
        AppleIapDiagnostics.displayLine(malformed, includeReceiptData: false),
        isNot(contains('secret')),
      );
      expect(
        AppleIapDiagnostics.displayLine(malformed, includeReceiptData: true),
        malformed,
      );
      for (final language in AppLanguage.values) {
        expect(AppL10n(language).starAppleShowReceiptData, isNotEmpty);
        expect(AppL10n(language).starAppleDiagnosticsCopyFailed, isNotEmpty);
      }
    },
  );
}
