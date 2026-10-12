import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../network/boltfox_api.dart';
import '../../network/api_session.dart';
import 'star_coin_api.dart';

enum AppleIapPhase {
  idle,
  loading,
  purchasing,
  deferred,
  verifying,
  pending,
  resume,
  credited,
  canceled,
  failed,
  unavailable,
}

class AppleIapProduct {
  const AppleIapProduct({required this.id, required this.price});
  final String id;
  final String price;
}

/// status=0 only validates a receipt. Match the individual transaction before
/// considering the separate business-order and balance confirmation.
class AppleReceiptVerification {
  AppleReceiptVerification.fromJson(Map<String, dynamic> json)
    : valid = int.tryParse('${json['status']}') == 0,
      response = _response(json['responseData']);

  final bool valid;
  final Map<String, dynamic> response;

  static Map<String, dynamic> _response(Object? value) {
    try {
      final decoded = value is String ? jsonDecode(value) : value;
      return decoded is Map ? decoded.cast<String, dynamic>() : const {};
    } catch (_) {
      return const {};
    }
  }

  bool matches(String transactionId, String productId) {
    if (!valid || transactionId.isEmpty || productId.isEmpty) return false;
    final receipt = response['receipt'];
    final rows = [
      if (receipt is Map && receipt['in_app'] is List)
        ...receipt['in_app'] as List,
      if (response['latest_receipt_info'] is List)
        ...response['latest_receipt_info'] as List,
    ];
    return rows.whereType<Map>().any(
      (row) =>
          '${row['transaction_id']}' == transactionId &&
          '${row['product_id']}' == productId &&
          row['cancellation_date'] == null &&
          row['cancellation_date_ms'] == null &&
          (row['quantity'] == null || '${row['quantity']}' == '1'),
    );
  }
}

abstract class AppleIapBridge {
  Future<bool> initialize(void Function(Map<String, dynamic>) onEvent);
  Future<AppleIapProduct> product(String productId);
  Future<void> buy(String productId, String accountToken);
  Future<List<Map<String, dynamic>>> pending();
  Future<String> receipt({required bool refreshIfMissing});
  Future<void> finish(String transactionId, String accountToken);
  Future<void> acknowledgeFailure(String accountToken);
}

class MethodChannelAppleIapBridge implements AppleIapBridge {
  @override
  Future<void> acknowledgeFailure(String accountToken) => channel
      .invokeMethod<void>('acknowledgeFailure', {'accountToken': accountToken});
  static const channel = MethodChannel('com.boltfox.boltstar/apple_iap');

  @override
  Future<bool> initialize(void Function(Map<String, dynamic>) onEvent) async {
    channel.setMethodCallHandler((call) async {
      if (call.method == 'transactionUpdated' && call.arguments is Map) {
        onEvent((call.arguments as Map).cast<String, dynamic>());
      }
    });
    final data = await channel.invokeMapMethod<String, dynamic>('initialize');
    final device = '${data?['device'] ?? ''}';
    if (device.isNotEmpty) ApiSession.instance.device = device;
    return data?['canMakePayments'] == true;
  }

  @override
  Future<AppleIapProduct> product(String productId) async {
    final data = await channel.invokeMapMethod<String, dynamic>('product', {
      'productId': productId,
    });
    final id = '${data?['productId'] ?? ''}';
    final price = '${data?['localizedPrice'] ?? ''}';
    if (id != productId || price.isEmpty) {
      throw PlatformException(code: 'product_unavailable');
    }
    return AppleIapProduct(id: id, price: price);
  }

  @override
  Future<void> buy(String productId, String accountToken) =>
      channel.invokeMethod<void>('buy', {
        'productId': productId,
        'accountToken': accountToken,
      });

  @override
  Future<List<Map<String, dynamic>>> pending() async {
    final rows = await channel.invokeListMethod<dynamic>('pendingTransactions');
    return (rows ?? [])
        .whereType<Map>()
        .map((row) => row.cast<String, dynamic>())
        .toList();
  }

  @override
  Future<String> receipt({required bool refreshIfMissing}) async {
    final data = await channel.invokeMethod<String>('receipt', {
      'refreshIfMissing': refreshIfMissing,
    });
    if (data == null || data.isEmpty || base64Decode(data).isEmpty) {
      throw PlatformException(code: 'receipt_missing');
    }
    return data;
  }

  @override
  Future<void> finish(String transactionId, String accountToken) =>
      channel.invokeMethod<void>('finish', {
        'transactionId': transactionId,
        'accountToken': accountToken,
      });
}

abstract class AppleIapStore {
  Future<List<Map<String, dynamic>>> load();
  Future<void> save(List<Map<String, dynamic>> records);
}

class PreferencesAppleIapStore implements AppleIapStore {
  static const key = 'boltstar.appleIap.pending.v1';

  @override
  Future<List<Map<String, dynamic>>> load() async {
    final value = (await SharedPreferences.getInstance()).getString(key);
    if (value == null) return [];
    return (jsonDecode(value) as List)
        .map((row) => (row as Map).cast<String, dynamic>())
        .toList();
  }

  @override
  Future<void> save(List<Map<String, dynamic>> records) async {
    final saved = await (await SharedPreferences.getInstance()).setString(
      key,
      jsonEncode(records),
    );
    if (!saved) throw StateError('Apple purchase record could not be saved');
  }
}

abstract class AppleIapBackend {
  Future<StarOrder> createOrder(StarPackage package);
  Future<int?> balance();
  Future<bool> orderPaid(String orderNo);
  Future<AppleReceiptVerification> verify(String receipt);
}

class ApiAppleIapBackend implements AppleIapBackend {
  @override
  Future<StarOrder> createOrder(StarPackage package) =>
      StarCoinApi.createOrder(package: package, payType: StarPayType.apple);

  @override
  Future<int?> balance() async {
    try {
      return (await StarCoinApi.fetchAccount()).balance;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<bool> orderPaid(String orderNo) async =>
      (await StarCoinApi.queryPay(
        orderNo: orderNo,
        payType: StarPayType.apple,
      ))?.paid ??
      false;

  @override
  Future<AppleReceiptVerification> verify(String receipt) async {
    final data = await BoltFoxApi.setApplePayVerifyReceipt(
      receiptData: receipt,
    );
    return AppleReceiptVerification.fromJson(
      data is Map ? data.cast<String, dynamic>() : const {},
    );
  }
}

/// Process-wide coordinator: receipts stay in StoreKit; only the order/user/UUID
/// mapping is persisted locally. An account switch invalidates in-flight work.
class AppleIapController extends ChangeNotifier {
  AppleIapController({
    AppleIapBridge? bridge,
    AppleIapStore? store,
    AppleIapBackend? backend,
    bool? supported,
    this.confirmationDelays = const [
      Duration.zero,
      Duration(seconds: 1),
      Duration(seconds: 2),
      Duration(seconds: 3),
    ],
  }) : bridge = bridge ?? MethodChannelAppleIapBridge(),
       store = store ?? PreferencesAppleIapStore(),
       backend = backend ?? ApiAppleIapBackend(),
       supported = supported ?? Platform.isIOS;

  static final instance = AppleIapController();
  final AppleIapBridge bridge;
  final AppleIapStore store;
  final AppleIapBackend backend;
  final bool supported;
  final List<Duration> confirmationDelays;
  final List<Map<String, dynamic>> _records = [];
  Future<void>? _initializing;
  bool _working = false;
  bool _rerun = false;
  bool _canPay = false;
  int _epoch = 0;
  String? _userId;
  AppleIapPhase phase = AppleIapPhase.idle;
  String? errorCode;
  int creditedTokens = 0;

  bool get busy => _working;
  bool get hasPending => _records.any((row) => row['userId'] == _userId);
  bool get canBuy =>
      supported &&
      _canPay &&
      _userId != null &&
      !_working &&
      (!hasPending || phase == AppleIapPhase.resume);

  void setUser(String? userId) {
    final next = userId == null || userId.isEmpty || userId == 'USR-GUEST'
        ? null
        : userId;
    if (_userId == next) return;
    _userId = next;
    _epoch++;
    _setPhase(AppleIapPhase.idle);
    if (supported && next != null) unawaited(retry());
  }

  bool _current(int epoch) => epoch == _epoch && _userId != null;

  void _setPhase(AppleIapPhase value, [String? code]) {
    phase = value;
    errorCode = code;
    notifyListeners();
  }

  Future<void> _initialize() async {
    if (_initializing != null) return _initializing;
    final future = () async {
      final rows = await store.load();
      for (final row in rows) {
        if ([
          'userId',
          'accountToken',
          'orderNo',
          'productId',
        ].any((key) => row[key] is! String || (row[key] as String).isEmpty)) {
          throw StateError('Invalid saved Apple purchase');
        }
      }
      _records
        ..clear()
        ..addAll(rows);
      _canPay = await bridge.initialize(_onEvent);
    }();
    _initializing = future;
    try {
      await future;
    } catch (_) {
      _initializing = null;
      rethrow;
    }
  }

  Future<void> _save() =>
      store.save(_records.map(Map<String, dynamic>.from).toList());

  void _onEvent(Map<String, dynamic> event) {
    // Keep all mutations in the serialized retry pass, including cancellations.
    if (_working) {
      _rerun = true;
      return;
    }
    unawaited(retry());
  }

  Future<AppleIapProduct> prepare(StarPackage package) async {
    if (!supported || package.appleProductId.isEmpty) {
      throw PlatformException(code: 'product_unavailable');
    }
    await _initialize();
    if (!_canPay) throw PlatformException(code: 'payment_not_allowed');
    return bridge.product(package.appleProductId);
  }

  static String _uuid() {
    final random = Random.secure();
    final bytes = List.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 15) | 64;
    bytes[8] = (bytes[8] & 63) | 128;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  Future<void> buy(StarPackage package) async {
    if (_working || !supported || _userId == null) return;
    _working = true;
    final epoch = _epoch;
    Map<String, dynamic>? record;
    _setPhase(AppleIapPhase.loading);
    try {
      await prepare(package); // No business order for an invalid Apple SKU.
      if (!_current(epoch)) return;
      final existing = _records
          .where((row) => row['userId'] == _userId)
          .toList();
      if (existing.isNotEmpty) {
        record = existing.first;
        if (record['productId'] != package.appleProductId ||
            record['transactionId'] != null) {
          throw PlatformException(code: 'unfinished_purchase');
        }
      } else {
        final baseline = await backend.balance();
        if (!_current(epoch)) return;
        final order = await backend.createOrder(package);
        if (!_current(epoch)) return;
        record = {
          'userId': _userId,
          'accountToken': _uuid(),
          'orderNo': order.orderNo,
          'productId': package.appleProductId,
          'tokens': package.totalTokens,
          'baseline': baseline,
          'verificationAttempted': false,
          'receiptVerified': false,
          'credited': false,
        };
        _records.add(record);
        await _save(); // Durable mapping before StoreKit can charge the user.
      }
      if (!_current(epoch)) return;
      await _save();
      if (!_current(epoch)) return;
      await bridge.buy(
        record['productId'] as String,
        record['accountToken'] as String,
      );
      if (_current(epoch)) _setPhase(AppleIapPhase.purchasing);
    } catch (error) {
      final code = error is PlatformException ? error.code : 'purchase_failed';
      // These native errors occur before add(payment). Ambiguous transport
      // failures retain the mapping, so a lost reply never creates another order.
      if (record != null &&
          const {
            'product_unavailable',
            'payment_not_allowed',
            'invalid_arguments',
          }.contains(code)) {
        _records.remove(record);
        try {
          await _save();
        } catch (_) {
          _records.add(record);
        }
      }
      if (_current(epoch)) _setPhase(AppleIapPhase.failed, code);
    } finally {
      _working = false;
      notifyListeners();
      _runQueued();
    }
  }

  /// Automatic recovery never repeats a POST whose result might have been lost.
  /// Only an explicit retry can resubmit that receipt; backend idempotency is
  /// still required. Missing receipts refresh only after that explicit action.
  Future<void> retry({bool manual = false}) async {
    if (!supported || _userId == null) return;
    if (_working) {
      _rerun = true;
      return;
    }
    _working = true;
    final epoch = _epoch;
    try {
      await _initialize();
      if (!_current(epoch)) return;
      final transactions = await bridge.pending();
      if (!_current(epoch)) return;
      final mine = _records.where((r) => r['userId'] == _userId).toList();
      for (final record in mine) {
        final matches = transactions
            .where(
              (tx) =>
                  tx['accountToken'] == record['accountToken'] &&
                  tx['productId'] == record['productId'],
            )
            .toList();
        if (matches.isEmpty) {
          if (record['credited'] == true) {
            await _finish(record, epoch);
          } else {
            _setPhase(
              record['transactionId'] == null
                  ? AppleIapPhase.resume
                  : AppleIapPhase.pending,
            );
          }
          continue;
        }
        final transaction = matches.first;
        final state = transaction['state'];
        if (state == 'failed' || state == 'canceled') {
          _records.remove(record);
          try {
            await _save();
          } catch (_) {
            _records.add(record);
            rethrow;
          }
          await bridge.acknowledgeFailure(record['accountToken'] as String);
          if (_current(epoch)) {
            _setPhase(
              state == 'canceled'
                  ? AppleIapPhase.canceled
                  : AppleIapPhase.failed,
              'purchase_failed',
            );
          }
          continue;
        }
        if (state != 'purchased') {
          _setPhase(
            state == 'deferred'
                ? AppleIapPhase.deferred
                : AppleIapPhase.purchasing,
          );
          continue;
        }
        final transactionId = '${transaction['transactionId'] ?? ''}';
        if (transactionId.isEmpty ||
            (record['transactionId'] != null &&
                record['transactionId'] != transactionId)) {
          _setPhase(AppleIapPhase.pending, 'transaction_mismatch');
          continue;
        }
        record['transactionId'] = transactionId;
        await _save();
        if (!_current(epoch)) return;
        if (record['credited'] == true) {
          await _finish(record, epoch);
          continue;
        }
        if (record['receiptVerified'] != true) {
          if (!manual && record['verificationAttempted'] == true) {
            _setPhase(AppleIapPhase.pending);
            continue;
          }
          _setPhase(AppleIapPhase.verifying);
          final receipt = await bridge.receipt(refreshIfMissing: manual);
          if (!_current(epoch)) return;
          record['verificationAttempted'] = true;
          await _save();
          if (!_current(epoch)) return;
          final verified = await backend.verify(receipt);
          if (!_current(epoch)) return;
          if (!verified.matches(transactionId, record['productId'] as String)) {
            _setPhase(AppleIapPhase.pending, 'receipt_unverified');
            continue;
          }
          record['receiptVerified'] = true;
          await _save();
        }
        for (final delay in confirmationDelays) {
          await Future<void>.delayed(delay);
          if (!_current(epoch)) return;
          final paid = await backend.orderPaid(record['orderNo'] as String);
          if (!_current(epoch)) return;
          final balance = await backend.balance();
          if (!_current(epoch)) return;
          final baseline = record['baseline'];
          final tokens = record['tokens'];
          if (paid &&
              baseline is int &&
              tokens is int &&
              tokens > 0 &&
              balance != null &&
              balance >= baseline + tokens) {
            record['credited'] = true;
            await _save();
            if (!_current(epoch)) return;
            await _finish(record, epoch);
            break;
          }
        }
        if (_current(epoch) && _records.contains(record)) {
          _setPhase(AppleIapPhase.pending);
        }
      }
    } catch (error) {
      if (_current(epoch)) {
        _setPhase(
          AppleIapPhase.pending,
          error is PlatformException ? error.code : 'confirmation_failed',
        );
      }
    } finally {
      _working = false;
      notifyListeners();
      _runQueued();
    }
  }

  Future<void> _finish(Map<String, dynamic> record, int epoch) async {
    await _save(); // Includes the credit acknowledgement, even after a restart.
    if (!_current(epoch)) return;
    await bridge.finish(
      record['transactionId'] as String,
      record['accountToken'] as String,
    );
    _records.remove(record);
    try {
      await _save();
    } catch (_) {
      _records.add(record);
      rethrow;
    }
    creditedTokens = record['tokens'] as int;
    if (_current(epoch)) _setPhase(AppleIapPhase.credited);
  }

  void _runQueued() {
    if (!_rerun) return;
    _rerun = false;
    unawaited(retry());
  }
}
