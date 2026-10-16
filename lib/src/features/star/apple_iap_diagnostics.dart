import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class _DiagnosticCapture {
  _DiagnosticCapture(this.onEntry);
  void Function(String)? onEntry;
}

/// Product preflight diagnostics only; receipt and account payloads are excluded.
abstract final class AppleIapDiagnostics {
  static const _keys = {
    'goodsId',
    'tokens',
    'productId',
    'supported',
    'canMakePayments',
    'bundleId',
    'code',
    'errorType',
    'message',
    'reason',
    'requestedProductId',
    'returnedProductId',
    'returnedProductIds',
    'invalidProductIds',
    'nativeErrorDomain',
    'nativeErrorCode',
    'nativeMessage',
    'underlyingErrors',
    'domain',
    'localizedPrice',
    'priceLocale',
    'hasPrice',
    'timeoutSeconds',
    'orderNo',
    'transactionId',
    'phase',
    'state',
    'manual',
    'newOrder',
    'pendingCount',
    'matchedCount',
    'receiptLength',
    'verificationAttempted',
    'receiptVerified',
    'status',
    'environment',
    'hasResponseData',
    'responseMatches',
    'orderPaid',
    'balance',
    'baseline',
    'expectedBalance',
    'supersededBy',
  };

  static final _captureKey = Object();

  /// Only this asynchronous preflight is collected, including in release builds.
  static Future<T> capture<T>(
    Future<T> Function() action, {
    required void Function(String) onEntry,
  }) {
    final capture = _DiagnosticCapture(onEntry);
    return runZoned(() async {
      try {
        return await action();
      } finally {
        capture.onEntry = null;
      }
    }, zoneValues: {_captureKey: capture});
  }

  static void log(String stage, Map<String, Object?> fields) {
    final onEntry = (Zone.current[_captureKey] as _DiagnosticCapture?)?.onEntry;
    if (!kDebugMode && onEntry == null) return;
    final line = format(stage, fields);
    onEntry?.call(line);
    if (kDebugMode) debugPrint(line);
  }

  static String format(String stage, Map<String, Object?> fields) =>
      '[AppleIAP] $stage: ${jsonEncode(_safe(fields))}';

  /// Preserve unexpected error fields on the page while masking private payloads.
  static String describeError(Object error, {StackTrace? stackTrace}) =>
      const JsonEncoder.withIndent('  ').convert(
        _redacted({
          'errorType': error.runtimeType.toString(),
          if (error is PlatformException) ...{
            'code': error.code,
            'message': error.message,
            'details': error.details,
            if (error.stacktrace != null || stackTrace != null)
              'stacktrace': error.stacktrace ?? stackTrace.toString(),
          } else ...{
            'message': error.toString(),
            if (stackTrace != null) 'stacktrace': stackTrace.toString(),
          },
        }),
      );

  static Object? _redacted(Object? value) {
    if (value is Map) {
      return {
        for (final entry in value.entries)
          '${entry.key}':
              RegExp(
                r'receipt|token|password|credential|authorization|authentication|applicationusername|appaccount|appleid|email|userid|accountid',
                caseSensitive: false,
              ).hasMatch('${entry.key}')
              ? '[redacted]'
              : _redacted(entry.value),
      };
    }
    if (value is Iterable) return value.map(_redacted).toList();
    if (value is String) return _text(value);
    return value == null || value is num || value is bool
        ? value
        : _text(value.toString());
  }

  static String _text(String value) => value
      .replaceAll(RegExp(r'https?://\S+', caseSensitive: false), '[url]')
      .replaceAll(RegExp(r'[\w.+-]+@[\w.-]+\.[A-Za-z]{2,}'), '[email]')
      .replaceAll(
        RegExp(
          r'"?(receiptData|latestReceipt|responseData|userToken|jwtToken|authorization|authentication|accountToken|password|token)"?\s*[:=]\s*("[^"]*"|\S+)',
          caseSensitive: false,
        ),
        '[redacted]',
      );

  static void failure(String stage, Object error, Map<String, Object?> fields) {
    final details = error is PlatformException && error.details is Map
        ? (error.details as Map)
        : const <Object?, Object?>{};
    log('$stage.failed', {
      ...details.map((key, value) => MapEntry('$key', value)),
      ...fields,
      'errorType': error.runtimeType.toString(),
      if (error is PlatformException) ...{
        'code': error.code,
        'message': error.message,
      },
      if (error is MissingPluginException) 'reason': 'native_bridge_missing',
    });
  }

  static Object? _safe(Object? value) {
    if (value is Map) {
      return {
        for (final entry in value.entries)
          if (_keys.contains(entry.key)) '${entry.key}': _safe(entry.value),
      };
    }
    if (value is Iterable) return value.take(20).map(_safe).toList();
    if (value is String) {
      final text = _text(value);
      return text.length > 600 ? '${text.substring(0, 600)}…' : text;
    }
    return value == null || value is num || value is bool ? value : null;
  }
}
