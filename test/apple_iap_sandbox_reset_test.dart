import 'dart:async';

import 'package:BoltStar/src/features/star/apple_iap.dart';
import 'package:BoltStar/src/features/star/presentation/star_purchase_page.dart';
import 'package:BoltStar/src/shared/l10n/app_l10n.dart';
import 'package:BoltStar/src/state.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'apple_iap_test.dart' as fixtures;

Map<String, dynamic> saved({
  String user = 'user-A',
  String token = 'ours',
  String product = 'stars.200',
}) => {
  'userId': user,
  'accountToken': token,
  'orderNo': 'old-$token',
  'productId': product,
  'tokens': 250,
  'baseline': 100,
  'verificationAttempted': false,
  'receiptVerified': false,
  'credited': false,
};

class SandboxBridge extends fixtures.FakeBridge
    implements AppleIapSandboxReset {
  @override
  bool isSandbox = true;
  int resets = 0;
  List<String> protected = [];
  Completer<void>? holdReset;
  @override
  Future<Map<String, dynamic>> resetSandbox({
    required String productId,
    required List<String> protectedAccountTokens,
  }) async {
    resets++;
    protected = protectedAccountTokens;
    if (!isSandbox) throw PlatformException(code: 'sandbox_reset_unavailable');
    final selected = rows
        .where(
          (row) =>
              row['productId'] == productId &&
              !protected.contains(row['accountToken']),
        )
        .toList();
    if (selected.any(
      (row) => row['state'] == 'purchasing' || row['state'] == 'deferred',
    )) {
      throw PlatformException(code: 'sandbox_reset_active');
    }
    if (holdReset != null) await holdReset!.future;
    rows.removeWhere(selected.contains);
    return {
      'finishedCount': selected.length,
      'clearedRequestCount': 0,
      'clearedFailureCount': 0,
    };
  }
}

class ResetFixture {
  final bridge = SandboxBridge();
  final store = fixtures.MemoryStore();
  final backend = fixtures.FakeBackend();
  late final controller = AppleIapController(
    bridge: bridge,
    store: store,
    backend: backend,
    supported: true,
    confirmationDelays: const [Duration.zero],
  );
  Future<void> start() async {
    controller.setUser('user-A');
    await settle();
  }

  Future<void> settle() async {
    for (var i = 0; i < 50 && controller.busy; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(controller.busy, false);
  }

  void orphan({
    String state = 'purchased',
    String product = 'stars.200',
    String token = 'orphan',
  }) => bridge.rows.add({
    'source': 'storekit',
    'state': state,
    'productId': product,
    'accountToken': token,
    'transactionId': 'old-transaction',
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'unmatched queue blocks ordinary purchase before creating an order',
    () async {
      final f = ResetFixture();
      await f.start();
      f.orphan();
      await f.controller.buy(fixtures.package);
      expect(f.backend.orderCalls, 0);
      expect(f.bridge.buyCalls, 0);
      expect(f.controller.errorCode, 'payment_busy');
      expect(
        f.controller.diagnostics.join('\n'),
        contains('"source":"storekit"'),
      );
      expect(f.controller.diagnostics.join('\n'), contains('"matchedCount":0'));
      expect(
        f.controller.diagnostics.join('\n'),
        isNot(contains('"accountToken"')),
      );
    },
  );

  test(
    'sandbox reset clears orphan, archives own product only and permits a fresh purchase',
    () async {
      final f = ResetFixture();
      f.store.records.addAll([
        saved(),
        saved(user: 'user-B', token: 'theirs'),
        {
          ...saved(token: 'other-product', product: 'other.sku'),
          'sandboxDiscarded': true,
        },
      ]);
      await f.start();
      f.orphan();
      expect(await f.controller.resetSandbox(fixtures.package), true);
      expect(f.bridge.rows, isEmpty);
      expect(f.bridge.protected, ['theirs']);
      expect(f.store.records.first['sandboxDiscarded'], true);
      expect(f.store.records[1]['sandboxDiscarded'], isNull);
      expect(f.store.records[2]['sandboxDiscarded'], true);
      expect(f.store.records.first['orderNo'], 'old-ours');
      expect(f.controller.phase, AppleIapPhase.idle);
      expect(f.backend.verifyCalls, 0);
      expect(f.backend.orderCalls, 0);
      expect(f.controller.creditedTokens, 0);
      expect(
        f.controller.diagnostics.join('\n'),
        contains('sandbox.reset.completed'),
      );
      expect(f.controller.diagnostics.join('\n'), contains('"pendingCount":0'));
      // The unrelated local purchase still exists; use a new fixture to check restart.
    },
  );

  test(
    'archived records stay inactive after restart and do not block a new purchase',
    () async {
      final f = ResetFixture();
      f.store.records.add(saved());
      await f.start();
      f.orphan();
      expect(await f.controller.resetSandbox(fixtures.package), true);
      expect(f.controller.hasPending, false);
      final restarted = AppleIapController(
        bridge: f.bridge,
        store: f.store,
        backend: f.backend,
        supported: true,
      );
      restarted.setUser('user-A');
      for (var i = 0; i < 50 && restarted.busy; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(restarted.hasPending, false);
      await restarted.buy(fixtures.package, newOrder: true);
      expect(f.backend.orderCalls, 1);
      expect(f.bridge.buyCalls, 1);
      expect(f.store.records.first['sandboxDiscarded'], true);
      expect(f.backend.verifyCalls, 0);
    },
  );

  test(
    'production guard refuses reset without touching queued or saved records',
    () async {
      final f = ResetFixture();
      f.bridge.isSandbox = false;
      f.store.records.add(saved());
      await f.start();
      f.orphan();
      expect(f.controller.canResetSandbox, false);
      expect(await f.controller.resetSandbox(fixtures.package), false);
      expect(f.bridge.resets, 0);
      expect(f.bridge.rows, hasLength(1));
      expect(f.store.records.single['sandboxDiscarded'], isNull);
      expect(f.controller.errorCode, 'sandbox_reset_unavailable');
    },
  );

  for (final state in ['purchasing', 'deferred']) {
    test('$state is refused, leaving records intact', () async {
      final f = ResetFixture();
      f.store.records.add(saved());
      await f.start();
      f.orphan(state: state);
      expect(await f.controller.resetSandbox(fixtures.package), false);
      expect(f.controller.errorCode, 'sandbox_reset_active');
      expect(f.bridge.rows, hasLength(1));
      expect(f.store.records.single['sandboxDiscarded'], isNull);
    });
  }

  test(
    'another account transaction is retained and prevents false success',
    () async {
      final f = ResetFixture();
      f.store.records.addAll([saved(), saved(user: 'user-B', token: 'theirs')]);
      await f.start();
      f.orphan(token: 'theirs');
      expect(await f.controller.resetSandbox(fixtures.package), false);
      expect(f.controller.errorCode, 'sandbox_reset_incomplete');
      expect(f.bridge.rows, hasLength(1));
      expect(
        f.store.records.every((row) => row['sandboxDiscarded'] != true),
        true,
      );
      expect(
        f.controller.diagnostics.join('\n'),
        isNot(contains('sandbox.reset.completed')),
      );
    },
  );

  test('another product is untouched and prevents false success', () async {
    final f = ResetFixture();
    await f.start();
    f.orphan(product: 'other.sku');
    expect(await f.controller.resetSandbox(fixtures.package), false);
    expect(f.bridge.rows.single['productId'], 'other.sku');
    expect(f.controller.errorCode, 'sandbox_reset_incomplete');
  });

  test(
    'failed persistence retains recovery record and can be retried',
    () async {
      final f = ResetFixture();
      f.store.records.add(saved());
      await f.start();
      f.orphan();
      f.store.failSave = true;
      expect(await f.controller.resetSandbox(fixtures.package), false);
      expect(f.store.records.single['sandboxDiscarded'], isNull);
      expect(f.controller.hasPending, true);
      f.store.failSave = false;
      expect(await f.controller.resetSandbox(fixtures.package), true);
      expect(f.controller.hasPending, false);
    },
  );

  test(
    'reset serializes purchase and retry, including an account change',
    () async {
      final f = ResetFixture();
      f.store.records.addAll([saved(), saved(user: 'user-B', token: 'theirs')]);
      await f.start();
      f.orphan();
      f.bridge.holdReset = Completer<void>();
      final resetting = f.controller.resetSandbox(fixtures.package);
      while (f.bridge.resets == 0) {
        await Future<void>.delayed(Duration.zero);
      }
      await f.controller.buy(fixtures.package);
      expect(await f.controller.resetSandbox(fixtures.package), false);
      f.controller.setUser('user-B');
      f.bridge.holdReset!.complete();
      expect(await resetting, true);
      await f.settle();
      expect(f.store.records.first['sandboxDiscarded'], true);
      expect(f.store.records[1]['sandboxDiscarded'], isNull);
      expect(f.backend.orderCalls, 0);
    },
  );

  test(
    'method channel forwards product/protected mappings and reads native capability',
    () async {
      final bridge = MethodChannelAppleIapBridge();
      final calls = <MethodCall>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(MethodChannelAppleIapBridge.channel, (
        call,
      ) async {
        calls.add(call);
        if (call.method == 'initialize') {
          return {'canMakePayments': true, 'sandboxResetAvailable': true};
        }
        return {'finishedCount': 1};
      });
      addTearDown(() {
        messenger.setMockMethodCallHandler(
          MethodChannelAppleIapBridge.channel,
          null,
        );
        MethodChannelAppleIapBridge.channel.setMethodCallHandler(null);
      });
      await bridge.initialize((_) {});
      expect(bridge.isSandbox, true);
      expect(
        await bridge.resetSandbox(
          productId: 'stars.200',
          protectedAccountTokens: ['theirs'],
        ),
        {'finishedCount': 1},
      );
      expect(calls.last.arguments, {
        'productId': 'stars.200',
        'protectedAccountTokens': ['theirs'],
      });
    },
  );

  Future<void> page(
    WidgetTester tester,
    ResetFixture f, {
    double scale = 1,
  }) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(375, 668);
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
            appleIap: f.controller,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'bottom sandbox button requires confirmation; cancel is harmless',
    (tester) async {
      final f = ResetFixture();
      await tester.runAsync(f.start);
      f.orphan();
      await page(tester, f);
      final button = find.byKey(const Key('apple-sandbox-reset'));
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(find.textContaining('其他账号已关联的交易保留'), findsOneWidget);
      expect(f.bridge.resets, 0);
      await tester.tap(find.text('取消').last);
      await tester.pumpAndSettle();
      expect(f.bridge.rows, hasLength(1));
      expect(f.bridge.resets, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets(
    'confirmed bottom reset displays result and does not pay automatically',
    (tester) async {
      final f = ResetFixture();
      f.store.records.add(saved());
      await tester.runAsync(f.start);
      f.orphan();
      await page(tester, f);
      final button = find.byKey(const Key('apple-sandbox-reset'));
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      await tester.tap(find.text('清除沙盒支付记录').last);
      await tester.pumpAndSettle();
      expect(f.bridge.resets, 1);
      expect(f.controller.hasPending, false);
      expect(find.text('沙盒支付记录已清除，可以重新购买。'), findsOneWidget);
      expect(f.backend.orderCalls, 0);
      expect(f.backend.verifyCalls, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets('production page hides reset button', (tester) async {
    final f = ResetFixture();
    f.bridge.isSandbox = false;
    await tester.runAsync(f.start);
    await page(tester, f);
    expect(find.byKey(const Key('apple-sandbox-reset')), findsNothing);
    await tester.pumpWidget(const SizedBox());
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('sandbox button fits short screen with large text', (
    tester,
  ) async {
    final f = ResetFixture();
    await tester.runAsync(f.start);
    await page(tester, f, scale: 1.8);
    expect(find.byKey(const Key('apple-sandbox-reset')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    debugDefaultTargetPlatformOverride = null;
  });
}
