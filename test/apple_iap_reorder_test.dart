import 'dart:async';

import 'package:BoltStar/src/features/star/apple_iap.dart';
import 'package:BoltStar/src/features/star/presentation/star_purchase_page.dart';
import 'package:BoltStar/src/shared/l10n/app_l10n.dart';
import 'package:BoltStar/src/state.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'apple_iap_test.dart' as fixtures;

Future<fixtures.Fixture> resumablePurchase() async {
  final fixture = fixtures.Fixture();
  await fixture.start();
  fixture.bridge.rows.clear();
  await fixture.controller.retry();
  expect(fixture.controller.phase, AppleIapPhase.resume);
  return fixture;
}

Future<void> pumpPurchase(
  WidgetTester tester,
  fixtures.Fixture fixture, {
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
        child: StarPurchasePage(
          package: fixtures.package,
          appleIap: fixture.controller,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'independent manual retry in resume never creates an order or payment',
    () async {
      final fixture = await resumablePurchase();
      await fixture.controller.retry(manual: true);
      expect(fixture.backend.orderCalls, 1);
      expect(fixture.bridge.buyCalls, 1);
      expect(fixture.backend.verifyCalls, 0);
      expect(
        fixture.controller.diagnostics.join('\n'),
        contains('"manual":true'),
      );
      expect(
        fixture.controller.diagnostics.join('\n'),
        contains('"matchedCount":0'),
      );
    },
  );

  test(
    'new purchase creates order-2 and retains unmatched old order for recovery',
    () async {
      final fixture = await resumablePurchase();
      await fixture.controller.buy(fixtures.package, newOrder: true);
      expect(fixture.backend.orderCalls, 2);
      expect(fixture.bridge.buyCalls, 2);
      expect(fixture.bridge.finishCalls, 0);
      expect(fixture.store.records.map((record) => record['orderNo']), [
        'order-1',
        'order-2',
      ]);
      expect(fixture.store.records.first['supersededBy'], 'order-2');
      expect(fixture.store.records.last['supersededBy'], isNull);
      expect(fixture.controller.hasPending, isTrue);
      await fixture.controller.retry();
      expect(fixture.controller.phase, AppleIapPhase.purchasing);
      expect(
        fixture.controller.diagnostics.join('\n'),
        contains('order.superseded'),
      );
    },
  );

  for (final state in [
    'requested',
    'purchasing',
    'purchased',
    'deferred',
    'unknown',
  ]) {
    test(
      'new purchase blocked by native $state without creating or finishing',
      () async {
        final fixture = await resumablePurchase();
        fixture.bridge.rows.add({
          'state': state,
          'productId': 'another-product',
          'accountToken': 'another-account',
        });
        await fixture.controller.buy(fixtures.package, newOrder: true);
        expect(fixture.controller.errorCode, 'new_order_blocked');
        expect(fixture.backend.orderCalls, 1);
        expect(fixture.bridge.buyCalls, 1);
        expect(fixture.bridge.finishCalls, 0);
        expect(fixture.store.records.single['supersededBy'], isNull);
      },
    );
  }

  test(
    'recorded transaction or verification cannot be bypassed by empty queue',
    () async {
      final fixture = fixtures.Fixture();
      await fixture.start();
      fixture.bridge.purchased();
      await fixture.controller.retry();
      fixture.bridge.rows.clear();
      await fixture.controller.buy(fixtures.package, newOrder: true);
      expect(fixture.controller.errorCode, 'new_order_blocked');
      expect(fixture.backend.orderCalls, 1);
      expect(fixture.bridge.buyCalls, 1);
      expect(fixture.bridge.finishCalls, 0);
    },
  );

  test(
    'new order persistence failure cannot start another Apple payment',
    () async {
      final fixture = await resumablePurchase();
      fixture.store.failSave = true;
      await fixture.controller.buy(fixtures.package, newOrder: true);
      expect(fixture.backend.orderCalls, 2);
      expect(fixture.bridge.buyCalls, 1);
      expect(fixture.store.records.single['orderNo'], 'order-1');
      expect(fixture.store.records.single['supersededBy'], isNull);
      expect(
        fixture.controller.diagnostics.join('\n'),
        contains('order.persist.failed'),
      );
    },
  );

  test(
    'late old transaction is recovered without completing the new purchase UI',
    () async {
      final fixture = await resumablePurchase();
      final oldToken = fixture.store.records.single['accountToken'];
      await fixture.controller.buy(fixtures.package, newOrder: true);
      fixture.bridge.rows.add({
        'accountToken': oldToken,
        'productId': fixtures.package.appleProductId,
        'state': 'purchased',
        'transactionId': 'tx-1',
      });
      fixture.backend.paid = true;
      fixture.backend.currentBalance = 350;
      await fixture.controller.retry();
      expect(fixture.backend.verifiedOrderNo, 'order-1');
      expect(fixture.bridge.finishCalls, 1);
      expect(fixture.store.records.single['orderNo'], 'order-2');
      expect(fixture.controller.hasPending, isTrue);
      expect(fixture.controller.phase, AppleIapPhase.purchasing);
    },
  );

  test(
    'transaction UUID comparison tolerates case without weakening ownership',
    () async {
      final fixture = fixtures.Fixture();
      await fixture.start();
      fixture.bridge.purchased();
      fixture.bridge.rows.single['accountToken'] = fixture.bridge.accountToken!
          .toUpperCase();
      fixture.backend.paid = true;
      fixture.backend.currentBalance = 350;
      await fixture.controller.retry();
      expect(fixture.controller.phase, AppleIapPhase.credited);
      expect(fixture.backend.verifyCalls, 1);
      expect(fixture.bridge.finishCalls, 1);
    },
  );

  test(
    'complete purchase diagnostics distinguish receipt, verify, delivery and finish',
    () async {
      final fixture = fixtures.Fixture();
      await fixture.start();
      fixture.bridge.purchased();
      fixture.backend.paid = true;
      fixture.backend.currentBalance = 350;
      await fixture.controller.retry();
      final logs = fixture.controller.diagnostics.join('\n');
      for (final stage in [
        'order.create.request',
        'order.create.response',
        'payment.start.request',
        'recovery.queue.response',
        'transaction.purchased',
        'receipt.response',
        'verify.request',
        'verify.response',
        'delivery.order.response',
        'delivery.balance.response',
        'transaction.finished',
      ]) {
        expect(logs, contains(stage));
      }
      expect(logs, contains('order-1'));
      expect(logs, contains('tx-1'));
      expect(logs, contains('"receiptLength":4'));
      expect(logs, contains('AQID'));
      expect(logs, isNot(contains(fixture.bridge.accountToken!)));
      expect(logs, isNot(contains('user-A')));
    },
  );

  test(
    'missing receipt is visible before verify; manual retry refreshes same purchase',
    () async {
      final fixture = fixtures.Fixture();
      await fixture.start();
      fixture.bridge.purchased();
      fixture.bridge.missingReceipt = true;
      await fixture.controller.retry();
      expect(fixture.backend.verifyCalls, 0);
      expect(
        fixture.controller.diagnostics.join('\n'),
        contains('receipt.read.failed'),
      );
      expect(
        fixture.controller.diagnostics.join('\n'),
        contains('receipt_missing'),
      );
      await fixture.controller.retry(manual: true);
      expect(fixture.bridge.receiptRefreshes, [false, false, true]);
      expect(fixture.backend.verifyCalls, 1);
      expect(fixture.backend.orderCalls, 1);
      expect(fixture.bridge.buyCalls, 1);
    },
  );

  test(
    'verification response and delivery failures do not finish transactions',
    () async {
      final fixture = fixtures.Fixture();
      await fixture.start();
      fixture.bridge.purchased();
      fixture.backend.verification = {
        'status': 21007,
        'environment': 'Sandbox',
      };
      await fixture.controller.retry();
      expect(fixture.controller.errorCode, 'receipt_unverified');
      expect(
        fixture.controller.diagnostics.join('\n'),
        contains('"status":21007'),
      );
      expect(
        fixture.controller.diagnostics.join('\n'),
        contains('"environment":"Sandbox"'),
      );
      fixture.backend.verification = fixtures.verifiedReceipt();
      await fixture.controller.retry(manual: true);
      expect(fixture.controller.errorCode, 'delivery_unconfirmed');
      expect(
        fixture.controller.diagnostics.join('\n'),
        contains('"expectedBalance":350'),
      );
      expect(fixture.bridge.finishCalls, 0);
    },
  );

  test(
    'lost verify reply is not auto-resubmitted; explicit retry uses original identifiers',
    () async {
      final fixture = fixtures.Fixture();
      await fixture.start();
      fixture.bridge.purchased();
      fixture.backend.loseVerifyReply = true;
      await fixture.controller.retry();
      expect(
        fixture.controller.diagnostics.join('\n'),
        contains('verify.failed'),
      );
      await fixture.controller.retry();
      expect(fixture.backend.verifyCalls, 1);
      fixture.backend.loseVerifyReply = false;
      await fixture.controller.retry(manual: true);
      expect(fixture.backend.verifyCalls, 2);
      expect(fixture.backend.verifiedOrderNo, 'order-1');
      expect(fixture.backend.verifiedTransactionId, 'tx-1');
      expect(fixture.bridge.buyCalls, 1);
    },
  );

  test(
    'account switch drops old-user logs and ignores late verification output',
    () async {
      final fixture = fixtures.Fixture();
      await fixture.start();
      fixture.bridge.purchased();
      fixture.backend.verificationStarted = Completer<void>();
      fixture.backend.holdVerification = Completer<void>();
      final retry = fixture.controller.retry();
      await fixture.backend.verificationStarted!.future;
      fixture.controller.setUser('user-B');
      fixture.backend.holdVerification!.complete();
      await retry;
      await fixture.settle();
      expect(
        fixture.controller.diagnostics.join('\n'),
        isNot(contains('order-1')),
      );
      expect(
        fixture.controller.diagnostics.join('\n'),
        isNot(contains('tx-1')),
      );
      expect(fixture.bridge.finishCalls, 0);
    },
  );

  test('diagnostics history stays bounded', () async {
    final fixture = await resumablePurchase();
    for (var attempt = 0; attempt < 60; attempt++) {
      await fixture.controller.retry(manual: true);
    }
    expect(fixture.controller.diagnostics.length, 160);
    expect(fixture.controller.diagnostics.last, contains('phase.changed'));
  });

  testWidgets(
    'resume keeps independent retry and new-order confirmation; retry never pays',
    (tester) async {
      final fixture = await tester.runAsync(resumablePurchase);
      await pumpPurchase(tester, fixture!);
      expect(find.text('继续支付'), findsNothing);
      expect(find.text('重新确认支付'), findsOneWidget);
      expect(find.byKey(const Key('apple-new-order')), findsOneWidget);
      await tester.tap(find.text('重新确认支付'));
      await tester.pumpAndSettle();
      expect(fixture.backend.orderCalls, 1);
      expect(fixture.bridge.buyCalls, 1);
      final details = tester
          .widget<SelectableText>(
            find.byKey(const Key('apple-product-diagnostics-text')),
          )
          .data!;
      expect(details, contains('"manual":true'));
      await tester.ensureVisible(find.byKey(const Key('apple-new-order')));
      await tester.tap(find.byKey(const Key('apple-new-order')));
      await tester.pumpAndSettle();
      expect(fixture.backend.orderCalls, 1);
      await tester.tap(find.text('重新下单支付').last);
      await tester.pumpAndSettle();
      expect(fixture.backend.orderCalls, 2);
      expect(fixture.bridge.buyCalls, 2);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets(
    'cancel new-order confirmation leaves previous record unchanged',
    (tester) async {
      final fixture = await tester.runAsync(resumablePurchase);
      await pumpPurchase(tester, fixture!);
      await tester.ensureVisible(find.byKey(const Key('apple-new-order')));
      await tester.tap(find.byKey(const Key('apple-new-order')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(fixture.backend.orderCalls, 1);
      expect(fixture.store.records.single['supersededBy'], isNull);
      await tester.pumpWidget(const SizedBox());
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets(
    'blocked new order explains existing transaction and preserves native queue',
    (tester) async {
      final fixture = fixtures.Fixture();
      await tester.runAsync(fixture.start);
      await pumpPurchase(tester, fixture);
      await tester.ensureVisible(find.byKey(const Key('apple-new-order')));
      await tester.tap(find.byKey(const Key('apple-new-order')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('重新下单支付').last);
      await tester.pumpAndSettle();
      expect(find.textContaining('检测到待确认'), findsOneWidget);
      expect(fixture.backend.orderCalls, 1);
      expect(fixture.bridge.finishCalls, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets(
    'short screen and large text can use both independent actions without overflow',
    (tester) async {
      final fixture = await tester.runAsync(resumablePurchase);
      await pumpPurchase(
        tester,
        fixture!,
        size: const Size(375, 568),
        scale: 1.8,
      );
      await tester.ensureVisible(find.byKey(const Key('apple-new-order')));
      await tester.tap(find.byKey(const Key('apple-new-order')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      debugDefaultTargetPlatformOverride = null;
    },
  );

  test('new actions are localized in all four app languages', () {
    for (final language in AppLanguage.values) {
      final l10n = AppL10n(language);
      for (final text in [
        l10n.starAppleNewOrder,
        l10n.starAppleNewOrderNote,
        l10n.starAppleNewOrderConfirm,
        l10n.starAppleNewOrderBlocked,
        l10n.starAppleDiagnosticsTitle,
      ]) {
        expect(text, isNotEmpty);
        if (language == AppLanguage.en) {
          expect(text, isNot(matches(RegExp(r'[\u4e00-\u9fff]'))));
        }
      }
    }
  });
}
