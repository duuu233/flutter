import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../network/boltfox_api.dart';
import '../../network/api_session.dart';
import '../../network/api_exception.dart';
import '../../network/api_client.dart';
import 'star_coin_api.dart';
import 'apple_iap_diagnostics.dart';

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

bool _sameAccountToken(Object? first, Object? second) =>
    first is String &&
    second is String &&
    first.isNotEmpty &&
    first.toLowerCase() == second.toLowerCase();

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
      status = int.tryParse('${json['status']}'),
      environment = '${json['environment'] ?? ''}',
      response = _response(json['responseData']),
      rawResponseData = json['responseData'] is String
          ? json['responseData'] as String
          : json['responseData'] != null
          ? jsonEncode(json['responseData'])
          : '',
      exceptionMsg = '${json['exceptionMsg'] ?? ''}';

  final bool valid;
  final int? status;
  final String environment;
  final Map<String, dynamic> response;
  final String rawResponseData;
  final String exceptionMsg;

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

/// Device-wide sandbox maintenance; never used for normal purchase delivery.
abstract interface class AppleIapSandboxReset {
  bool get isSandbox;
  Future<Map<String, dynamic>> resetSandbox({
    required String productId,
    required List<String> protectedAccountTokens,
  });
}

class MethodChannelAppleIapBridge
    implements AppleIapBridge, AppleIapSandboxReset {
  @override
  bool isSandbox = false;

  @override
  Future<Map<String, dynamic>> resetSandbox({
    required String productId,
    required List<String> protectedAccountTokens,
  }) async =>
      await channel.invokeMapMethod<String, dynamic>('resetSandbox', {
        'productId': productId,
        'protectedAccountTokens': protectedAccountTokens,
      }) ??
      {};

  @override
  Future<void> acknowledgeFailure(String accountToken) => channel
      .invokeMethod<void>('acknowledgeFailure', {'accountToken': accountToken});
  static const channel = MethodChannel('com.boltfox.boltstar/apple_iap');
  String? bundleId;

  @override
  Future<bool> initialize(void Function(Map<String, dynamic>) onEvent) async {
    channel.setMethodCallHandler((call) async {
      if (call.method == 'transactionUpdated' && call.arguments is Map) {
        onEvent((call.arguments as Map).cast<String, dynamic>());
      }
    });
    AppleIapDiagnostics.log('initialize.request', const {});
    final data = await channel.invokeMapMethod<String, dynamic>('initialize');
    bundleId = data?['bundleId'] as String?;
    isSandbox = data?['sandboxResetAvailable'] == true;
    AppleIapDiagnostics.log('initialize.response', {
      'bundleId': bundleId,
      'sandboxResetAvailable': isSandbox,
      'canMakePayments': data?['canMakePayments'] == true,
    });
    final device = '${data?['device'] ?? ''}';
    if (device.isNotEmpty) ApiSession.instance.device = device;
    return data?['canMakePayments'] == true;
  }

  @override
  Future<AppleIapProduct> product(String productId) async {
    AppleIapDiagnostics.log('product.request', {'productId': productId});
    final data = await channel.invokeMapMethod<String, dynamic>('product', {
      'productId': productId,
    });
    final id = '${data?['productId'] ?? ''}';
    final price = '${data?['localizedPrice'] ?? ''}';
    AppleIapDiagnostics.log('product.response', {
      'requestedProductId': productId,
      'returnedProductId': id,
      'localizedPrice': price,
      'hasPrice': price.isNotEmpty,
    });
    if (id != productId || price.isEmpty) {
      throw PlatformException(
        code: 'product_unavailable',
        message: 'StoreKit product response is missing or does not match.',
        details: {
          'reason': id != productId
              ? 'product_id_mismatch'
              : 'localized_price_empty',
          'requestedProductId': productId,
          'returnedProductId': id,
          'hasPrice': price.isNotEmpty,
        },
      );
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

/// 一次 `getPayQuery` 查单的结果，原始字段原样留给诊断（2026-10-22：后端排查
/// 「验单成功、余额到账但查单一直未支付」需要看到实际返回）。
///
/// 判定口径不变：只有 `payState` 按整数解析为 1 才算已支付；查单报错仍按未支付处理，
/// 但错误类型/码/信息单独记下，不再和「后端返回未支付」混在一起。
class AppleOrderQuery {
  const AppleOrderQuery({
    required this.paid,
    this.responded = false,
    this.payState,
    this.payNo = '',
    this.exceptionMsg = '',
    this.errorType,
    this.errorCode,
    this.errorMessage,
  });

  factory AppleOrderQuery.fromResponse(Object? data) {
    final json = data is Map
        ? data.cast<String, dynamic>()
        : const <String, dynamic>{};
    final parsed = StarPayQuery.fromJson(json);
    return AppleOrderQuery(
      paid: parsed.paid,
      responded: true,
      payState: json['payState'],
      payNo: parsed.payNo,
      exceptionMsg: parsed.exceptionMsg,
    );
  }

  factory AppleOrderQuery.failed(Object error) => AppleOrderQuery(
    paid: false,
    errorType: error.runtimeType.toString(),
    errorCode: error is ApiException ? error.code : null,
    errorMessage: error is ApiException ? error.message : error.toString(),
  );

  final bool paid;

  /// 后端有业务返回（不论 payState 是什么）；false 表示查单本身失败。
  final bool responded;

  /// 后端返回的 `payState` 原值（数字、字符串或缺失时为 null），不做转换。
  final Object? payState;
  final String payNo;
  final String exceptionMsg;
  final String? errorType;
  final Object? errorCode;
  final String? errorMessage;

  Map<String, Object?> get diagnostics => responded
      ? {'payState': payState, 'payNo': payNo, 'exceptionMsg': exceptionMsg}
      : {'errorType': errorType, 'code': errorCode, 'message': errorMessage};
}

abstract class AppleIapBackend {
  Future<StarOrder> createOrder(StarPackage package);
  Future<int?> balance();
  Future<AppleOrderQuery> orderQuery(String orderNo);
  Future<AppleReceiptVerification> verify({
    required String receipt,
    required String orderNo,
    required String transactionId,
  });
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
  Future<AppleOrderQuery> orderQuery(String orderNo) async {
    try {
      return AppleOrderQuery.fromResponse(
        await BoltFoxApi.getPayQuery(
          orderNo: orderNo,
          payType: StarPayType.apple,
        ),
      );
    } catch (error) {
      return AppleOrderQuery.failed(error);
    }
  }

  @override
  Future<AppleReceiptVerification> verify({
    required String receipt,
    required String orderNo,
    required String transactionId,
  }) async {
    final data = await BoltFoxApi.setApplePayVerifyReceipt(
      receiptData: receipt,
      orderNo: orderNo,
      transactionId: transactionId,
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
    this.receiptReadDelays = const [
      Duration.zero,
      Duration(milliseconds: 250),
      Duration(milliseconds: 750),
    ],
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
  final List<Duration> receiptReadDelays;
  final List<Map<String, dynamic>> _records = [];
  Future<void>? _initializing;
  bool _working = false;
  bool _rerun = false;
  bool _rerunManual = false;
  bool _canPay = false;
  int _epoch = 0;
  String? _userId;
  AppleIapPhase phase = AppleIapPhase.idle;
  String? errorCode;
  int creditedTokens = 0;

  bool get busy => _working;
  bool get canResetSandbox =>
      supported &&
      _userId != null &&
      bridge is AppleIapSandboxReset &&
      (bridge as AppleIapSandboxReset).isSandbox;
  final _diagnostics = <String>[];
  List<String> get diagnostics => List.unmodifiable(_diagnostics);
  bool get hasPending => _records.any(
    (row) =>
        row['userId'] == _userId &&
        row['sandboxDiscarded'] != true &&
        row['supersededBy'] == null,
  );
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
    _rerunManual = false;
    _diagnostics.clear();
    _epoch++;
    _setPhase(AppleIapPhase.idle);
    if (supported && next != null) unawaited(retry());
  }

  bool _current(int epoch) => epoch == _epoch && _userId != null;

  void _diagnose(String stage, Map<String, Object?> fields) {
    if (_userId == null) return;
    // 正式包（release）不展示诊断面板，也就不在内存里留这些行（验单行含收据原文）。
    if (!kReleaseMode) {
      _diagnostics.add(AppleIapDiagnostics.format(stage, fields));
      if (_diagnostics.length > 160) _diagnostics.removeAt(0);
    }
    AppleIapDiagnostics.log(stage, fields);
    notifyListeners();
  }

  void _diagnoseError(String stage, Object error, {String? orderNo}) {
    _diagnose(stage, {
      'orderNo': ?orderNo,
      'errorType': error.runtimeType.toString(),
      'code': error is PlatformException
          ? error.code
          : error is ApiException
          ? '${error.code}'
          : 'unexpected_error',
      'message': error is PlatformException
          ? error.message
          : error is ApiException
          ? error.message
          : error.toString(),
      if (error is PlatformException && error.details is Map)
        ...(error.details as Map).map((key, value) => MapEntry('$key', value)),
    });
  }

  void _recordPhase(
    Map<String, dynamic> record,
    AppleIapPhase value, [
    String? code,
  ]) {
    if (record['supersededBy'] == null) _setPhase(value, code);
  }

  void _setPhase(AppleIapPhase value, [String? code]) {
    phase = value;
    errorCode = code;
    _diagnose('phase.changed', {'phase': value.name, 'code': ?code});
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
    final owned = _records.any(
      (record) =>
          record['userId'] == _userId &&
          record['sandboxDiscarded'] != true &&
          _sameAccountToken(record['accountToken'], event['accountToken']) &&
          record['productId'] == event['productId'],
    );
    _diagnose('transaction.updated', {
      'reason': owned ? 'owned_transaction' : 'unmatched_transaction',
      if (owned) 'state': event['state'],
      if (owned) 'productId': event['productId'],
      if (owned) 'transactionId': event['transactionId'],
      if (owned) ..._nativeErrorFields(event),
    });
    // Keep all mutations in the serialized retry pass, including cancellations.
    if (_working) {
      _rerun = true;
      return;
    }
    unawaited(retry());
  }

  Future<AppleIapProduct> prepare(StarPackage package) async {
    final fields = <String, Object?>{
      'goodsId': package.goodsId,
      'tokens': package.tokens,
      'productId': package.appleProductId,
      'supported': supported,
    };
    var stage = 'prepare.validation';
    AppleIapDiagnostics.log('prepare.request', fields);
    try {
      if (!supported || package.appleProductId.isEmpty) {
        throw PlatformException(
          code: 'product_unavailable',
          details: {
            'reason': !supported
                ? 'platform_unsupported'
                : 'apple_product_id_empty',
          },
        );
      }
      stage = 'prepare.initialize';
      await _initialize();
      stage = 'prepare.permission';
      AppleIapDiagnostics.log('prepare.initialized', {
        'canMakePayments': _canPay,
        if (bridge is MethodChannelAppleIapBridge)
          'bundleId': (bridge as MethodChannelAppleIapBridge).bundleId,
      });
      if (!_canPay) throw PlatformException(code: 'payment_not_allowed');
      stage = 'prepare.product';
      return await bridge.product(package.appleProductId);
    } catch (error) {
      AppleIapDiagnostics.failure(stage, error, fields);
      rethrow;
    }
  }

  void _diagnoseQueue(String stage, List<Map<String, dynamic>> rows) {
    for (final row in rows) {
      final otherAccount = _records.any(
        (record) =>
            record['userId'] != _userId &&
            _sameAccountToken(record['accountToken'], row['accountToken']) &&
            record['productId'] == row['productId'],
      );
      _diagnose(stage, {
        'reason': otherAccount ? 'other_account_transaction' : 'queue_entry',
        'source': row['source'] ?? 'unknown',
        'state': row['state'],
        'productId': row['productId'],
        if (!otherAccount) 'transactionId': row['transactionId'],
        'matchedCount': _records
            .where(
              (record) =>
                  record['userId'] == _userId &&
                  record['sandboxDiscarded'] != true &&
                  _sameAccountToken(
                    record['accountToken'],
                    row['accountToken'],
                  ) &&
                  record['productId'] == row['productId'],
            )
            .length,
      });
    }
  }

  /// Discards current-product sandbox recovery, preserving an archive locally.
  /// No order creation, receipt verification, balance change or backend deletion.
  Future<bool> resetSandbox(StarPackage package) async {
    if (_working || !supported || _userId == null) return false;
    _working = true;
    final resetUser = _userId;
    final epoch = _epoch;
    var stage = 'sandbox.reset';
    _diagnose('sandbox.reset.request', const {});
    _setPhase(AppleIapPhase.loading);
    try {
      await _initialize();
      if (!_current(epoch)) return false;
      if (!canResetSandbox) {
        throw PlatformException(code: 'sandbox_reset_unavailable');
      }
      if (_records.any(
        (row) =>
            row['userId'] == resetUser &&
            row['productId'] != package.appleProductId &&
            row['sandboxDiscarded'] != true &&
            row['supersededBy'] == null,
      )) {
        throw PlatformException(
          code: 'sandbox_reset_other_order',
          message:
              'A different product has a pending order. Open that product to clear it first.',
        );
      }
      final before = await bridge.pending();
      if (!_current(epoch)) return false;
      _diagnoseQueue('sandbox.reset.before', before);
      final result = await (bridge as AppleIapSandboxReset).resetSandbox(
        productId: package.appleProductId,
        protectedAccountTokens: _records
            .where((row) => row['userId'] != resetUser)
            .map((row) => row['accountToken'] as String)
            .toList(),
      );
      _diagnose('sandbox.reset.native', result);
      // Native finish can be asynchronous. Never claim success with entries left.
      final remaining = await bridge.pending();
      _diagnoseQueue('sandbox.reset.remaining', remaining);
      if (remaining.isNotEmpty) {
        throw PlatformException(
          code: 'sandbox_reset_incomplete',
          message:
              'Apple transactions are still pending. Wait and try clearing again.',
        );
      }
      stage = 'sandbox.reset.persist';
      final discarded = _records
          .where(
            (row) =>
                row['userId'] == resetUser &&
                row['productId'] == package.appleProductId &&
                row['sandboxDiscarded'] != true,
          )
          .toList();
      final archived = _records
          .map(
            (row) => <String, dynamic>{
              ...row,
              if (discarded.contains(row)) 'sandboxDiscarded': true,
            },
          )
          .toList();
      await store.save(archived);
      _records
        ..clear()
        ..addAll(archived);
      creditedTokens = 0;
      _diagnose('sandbox.reset.completed', {
        'pendingCount': 0,
        'removedCount': discarded.length,
      });
      if (_current(epoch)) _setPhase(AppleIapPhase.idle);
      return true;
    } catch (error) {
      _diagnoseError('$stage.failed', error);
      if (_current(epoch)) {
        _setPhase(
          AppleIapPhase.failed,
          error is PlatformException ? error.code : 'sandbox_reset_failed',
        );
      }
      return false;
    } finally {
      _working = false;
      notifyListeners();
      _runQueued();
    }
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

  Future<void> buy(StarPackage package, {bool newOrder = false}) async {
    if (_working || !supported || _userId == null) return;
    _working = true;
    final epoch = _epoch;
    Map<String, dynamic>? record;
    var stage = 'purchase.prepare';
    _diagnose('purchase.request', {
      'productId': package.appleProductId,
      'newOrder': newOrder,
    });
    _setPhase(AppleIapPhase.loading);
    try {
      await prepare(package); // No business order for an invalid Apple SKU.
      if (!_current(epoch)) return;
      final existing = _records
          .where(
            (row) =>
                row['userId'] == _userId &&
                row['sandboxDiscarded'] != true &&
                row['supersededBy'] == null,
          )
          .toList();
      stage = newOrder ? 'new_order.check' : 'purchase.queue';
      final transactions = await bridge.pending();
      if (!_current(epoch)) return;
      _diagnoseQueue('purchase.queue.entry', transactions);
      if (!newOrder && transactions.isNotEmpty) {
        _diagnose('purchase.queue.blocked', {
          'pendingCount': transactions.length,
        });
        throw PlatformException(code: 'payment_busy');
      }
      if (newOrder) {
        final unresolved = _records.any(
          (row) =>
              row['userId'] == _userId &&
              row['sandboxDiscarded'] != true &&
              (row['transactionId'] != null ||
                  row['verificationAttempted'] == true ||
                  row['receiptVerified'] == true ||
                  row['credited'] == true),
        );
        _diagnose(stage, {
          'pendingCount': transactions.length,
          'reason': unresolved
              ? 'previous_verification_or_transaction'
              : 'queue_checked',
        });
        if (transactions.isNotEmpty || unresolved) {
          throw PlatformException(
            code: 'new_order_blocked',
            message:
                'An Apple transaction still needs confirmation. Retry verification first.',
          );
        }
      }
      if (existing.isNotEmpty && !newOrder) {
        record = existing.first;
        if (record['productId'] != package.appleProductId ||
            record['transactionId'] != null) {
          throw PlatformException(code: 'unfinished_purchase');
        }
      } else {
        stage = 'order.baseline';
        final baseline = await backend.balance();
        if (!_current(epoch)) return;
        stage = 'order.create';
        _diagnose('order.create.request', {
          'goodsId': package.goodsId,
          'newOrder': newOrder,
        });
        final order = await backend.createOrder(package);
        if (!_current(epoch)) return;
        _diagnose('order.create.response', {
          'orderNo': order.orderNo,
          'baseline': baseline,
        });
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
        if (newOrder) {
          for (final previous in existing) {
            previous['supersededBy'] = order.orderNo;
            _diagnose('order.superseded', {
              'orderNo': previous['orderNo'],
              'supersededBy': order.orderNo,
              'reason': 'no_apple_transaction_found_record_retained',
            });
          }
        }
        _records.add(record);
        stage = 'order.persist';
        await _save(); // Durable mapping before StoreKit can charge the user.
      }
      if (!_current(epoch)) return;
      await _save();
      if (!_current(epoch)) return;
      stage = 'payment.start';
      _diagnose('payment.start.request', {
        'orderNo': record['orderNo'],
        'productId': record['productId'],
      });
      await bridge.buy(
        record['productId'] as String,
        record['accountToken'] as String,
      );
      if (_current(epoch)) {
        _diagnose('payment.start.accepted', {'orderNo': record['orderNo']});
      }
      if (_current(epoch)) _setPhase(AppleIapPhase.purchasing);
    } catch (error) {
      if (_current(epoch)) {
        _diagnoseError(
          '$stage.failed',
          error,
          orderNo: record?['orderNo'] as String?,
        );
      }
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

  Map<String, Object?> _nativeErrorFields(Map<String, dynamic> source) => {
    for (final key in [
      'nativeErrorDomain',
      'nativeErrorCode',
      'nativeMessage',
      'underlyingErrors',
    ])
      if (source.containsKey(key)) key: source[key],
  };

  Future<String?> _readReceipt(
    Map<String, dynamic> record,
    int epoch, {
    required bool manual,
  }) async {
    final delays = receiptReadDelays.isEmpty
        ? const [Duration.zero]
        : receiptReadDelays;
    for (var index = 0; index < delays.length; index++) {
      await Future<void>.delayed(delays[index]);
      if (!_current(epoch)) return null;
      _diagnose('receipt.request', {
        'orderNo': record['orderNo'],
        'transactionId': record['transactionId'],
        'manual': manual,
        'attempt': index + 1,
        'refreshIfMissing': false,
      });
      try {
        return await bridge.receipt(refreshIfMissing: false);
      } on PlatformException catch (error) {
        if (error.code != 'receipt_missing') rethrow;
        if (!_current(epoch)) return null;
        if (index + 1 < delays.length) {
          _diagnose('receipt.wait', {
            'orderNo': record['orderNo'],
            'attempt': index + 1,
            'reason': 'receipt_not_ready',
            'backendCalled': false,
          });
          continue;
        }
        if (!manual) rethrow;
        _diagnose('receipt.request', {
          'orderNo': record['orderNo'],
          'transactionId': record['transactionId'],
          'manual': true,
          'attempt': index + 2,
          'refreshIfMissing': true,
        });
        // One explicit refresh only. Apple failures/cancellations are never retried here.
        return await bridge.receipt(refreshIfMissing: true);
      }
    }
    return null;
  }

  /// Automatic recovery never repeats a POST whose result might have been lost.
  /// Only an explicit retry can resubmit that receipt; backend idempotency is
  /// still required. Missing receipts refresh only after that explicit action.
  Future<void> retry({bool manual = false}) async {
    if (!supported || _userId == null) return;
    if (_working) {
      _rerun = true;
      _rerunManual = _rerunManual || manual;
      return;
    }
    _working = true;
    final epoch = _epoch;
    var stage = 'recovery.initialize';
    Map<String, dynamic>? currentRecord;
    _diagnose('recovery.request', {'manual': manual});
    try {
      await _initialize();
      if (!_current(epoch)) return;
      stage = 'recovery.queue';
      final transactions = await bridge.pending();
      if (!_current(epoch)) return;
      _diagnose('recovery.queue.response', {
        'pendingCount': transactions.length,
      });
      _diagnoseQueue('recovery.queue.entry', transactions);
      final mine =
          _records
              .where(
                (record) =>
                    record['userId'] == _userId &&
                    record['sandboxDiscarded'] != true,
              )
              .toList()
            ..sort(
              (first, second) => (first['supersededBy'] == null ? 0 : 1)
                  .compareTo(second['supersededBy'] == null ? 0 : 1),
            );
      for (final record in mine) {
        currentRecord = record;
        stage = 'recovery.match';
        final matches = transactions
            .where(
              (tx) =>
                  _sameAccountToken(
                    tx['accountToken'],
                    record['accountToken'],
                  ) &&
                  tx['productId'] == record['productId'],
            )
            .toList();
        _diagnose('recovery.match.response', {
          'orderNo': record['orderNo'],
          'productId': record['productId'],
          'matchedCount': matches.length,
          'verificationAttempted': record['verificationAttempted'],
          'receiptVerified': record['receiptVerified'],
          if (record['supersededBy'] != null)
            'supersededBy': record['supersededBy'],
        });
        if (matches.isEmpty) {
          _diagnose('verify.blocked', {
            'orderNo': record['orderNo'],
            'reason': 'transaction_unmatched',
            'backendCalled': false,
          });
          if (record['supersededBy'] != null) continue;
          if (record['credited'] == true) {
            stage = 'transaction.finish';
            await _finish(record, epoch);
          } else {
            _recordPhase(
              record,
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
          _diagnose('transaction.failed', {
            'orderNo': record['orderNo'],
            'state': state,
            ..._nativeErrorFields(transaction),
          });
          _diagnose('verify.blocked', {
            'orderNo': record['orderNo'],
            'reason': 'apple_payment_failed',
            'backendCalled': false,
          });
          _records.remove(record);
          try {
            await _save();
          } catch (_) {
            _records.add(record);
            rethrow;
          }
          await bridge.acknowledgeFailure(record['accountToken'] as String);
          if (_current(epoch)) {
            _recordPhase(
              record,
              state == 'canceled'
                  ? AppleIapPhase.canceled
                  : AppleIapPhase.failed,
              'purchase_failed',
            );
          }
          continue;
        }
        if (state != 'purchased') {
          _diagnose('verify.blocked', {
            'orderNo': record['orderNo'],
            'state': state,
            'reason': 'transaction_not_purchased',
            'backendCalled': false,
          });
          _recordPhase(
            record,
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
          _diagnose('verify.blocked', {
            'orderNo': record['orderNo'],
            'reason': 'transaction_mismatch',
            'backendCalled': false,
          });
          _recordPhase(record, AppleIapPhase.pending, 'transaction_mismatch');
          continue;
        }
        record['transactionId'] = transactionId;
        _diagnose('transaction.purchased', {
          'orderNo': record['orderNo'],
          'transactionId': transactionId,
          'productId': record['productId'],
        });
        stage = 'transaction.persist';
        await _save();
        if (!_current(epoch)) return;
        if (record['credited'] == true) {
          stage = 'transaction.finish';
          await _finish(record, epoch);
          continue;
        }
        if (record['receiptVerified'] != true) {
          if (!manual && record['verificationAttempted'] == true) {
            _diagnose('verify.skipped', {
              'orderNo': record['orderNo'],
              'reason': 'previous_submission_requires_manual_retry',
            });
            _recordPhase(record, AppleIapPhase.pending);
            continue;
          }
          _recordPhase(record, AppleIapPhase.verifying);
          stage = 'receipt.read';
          final receipt = await _readReceipt(record, epoch, manual: manual);
          if (!_current(epoch) || receipt == null) return;
          _diagnose('receipt.response', {
            'orderNo': record['orderNo'],
            'receiptLength': receipt.length,
          });
          record['verificationAttempted'] = true;
          stage = 'verify.persist';
          await _save();
          if (!_current(epoch)) return;
          stage = 'verify';
          _diagnose('verify.request', {
            'orderNo': record['orderNo'],
            'transactionId': transactionId,
            'receiptLength': receipt.length,
            'receiptData': receipt,
          });
          final verified = await ApiClient.captureDiagnostics(
            () => backend.verify(
              receipt: receipt,
              orderNo: record['orderNo'] as String,
              transactionId: transactionId,
            ),
            onEvent: (httpStage, fields) {
              if (_current(epoch)) {
                _diagnose('verify.$httpStage', {
                  'orderNo': record['orderNo'],
                  'transactionId': transactionId,
                  ...fields,
                });
              }
            },
          );
          if (!_current(epoch)) return;
          final matchesReceipt = verified.matches(
            transactionId,
            record['productId'] as String,
          );
          _diagnose('verify.response', {
            'orderNo': record['orderNo'],
            'transactionId': transactionId,
            'status': verified.status,
            'environment': verified.environment,
            'hasResponseData': verified.response.isNotEmpty,
            'responseMatches': matchesReceipt,
            'responseData': verified.rawResponseData,
            if (verified.exceptionMsg.isNotEmpty)
              'exceptionMsg': verified.exceptionMsg,
          });
          if (!matchesReceipt) {
            _recordPhase(record, AppleIapPhase.pending, 'receipt_unverified');
            continue;
          }
          record['receiptVerified'] = true;
          await _save();
        }
        for (final delay in confirmationDelays) {
          await Future<void>.delayed(delay);
          if (!_current(epoch)) return;
          stage = 'delivery.order';
          final query = await backend.orderQuery(record['orderNo'] as String);
          if (!_current(epoch)) return;
          final paid = query.paid;
          _diagnose('delivery.order.response', {
            'orderNo': record['orderNo'],
            'orderPaid': paid,
            ...query.diagnostics,
          });
          stage = 'delivery.balance';
          final balance = await backend.balance();
          if (!_current(epoch)) return;
          final baseline = record['baseline'];
          final tokens = record['tokens'];
          _diagnose('delivery.balance.response', {
            'orderNo': record['orderNo'],
            'balance': balance,
            'baseline': baseline,
            if (baseline is int && tokens is int)
              'expectedBalance': baseline + tokens,
          });
          if (paid &&
              baseline is int &&
              tokens is int &&
              tokens > 0 &&
              balance != null &&
              balance >= baseline + tokens) {
            record['credited'] = true;
            stage = 'delivery.persist';
            await _save();
            if (!_current(epoch)) return;
            stage = 'transaction.finish';
            await _finish(record, epoch);
            break;
          }
        }
        if (_current(epoch) && _records.contains(record)) {
          _recordPhase(record, AppleIapPhase.pending, 'delivery_unconfirmed');
        }
      }
    } catch (error) {
      if (_current(epoch)) {
        if (stage == 'receipt.read') {
          _diagnose('verify.blocked', {
            'orderNo': currentRecord?['orderNo'],
            'reason': 'receipt_unavailable',
            'backendCalled': false,
          });
        }
        _diagnoseError(
          '$stage.failed',
          error,
          orderNo: currentRecord?['orderNo'] as String?,
        );
        if (currentRecord == null || currentRecord['supersededBy'] == null) {
          _setPhase(
            AppleIapPhase.pending,
            error is PlatformException ? error.code : 'confirmation_failed',
          );
        }
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
    if (!_current(epoch)) return;
    _diagnose('transaction.finished', {
      'orderNo': record['orderNo'],
      'transactionId': record['transactionId'],
    });
    _records.remove(record);
    try {
      await _save();
    } catch (_) {
      _records.add(record);
      rethrow;
    }
    if (record['supersededBy'] == null) {
      creditedTokens = record['tokens'] as int;
      if (_current(epoch)) _setPhase(AppleIapPhase.credited);
    }
  }

  void _runQueued() {
    if (!_rerun) return;
    _rerun = false;
    final manual = _rerunManual;
    _rerunManual = false;
    unawaited(retry(manual: manual));
  }
}
