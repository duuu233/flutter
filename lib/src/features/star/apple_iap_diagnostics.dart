import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

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
  };

  static void log(String stage, Map<String, Object?> fields) {
    if (!kDebugMode) return;
    debugPrint('[AppleIAP] $stage: ${jsonEncode(_safe(fields))}');
  }

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
      final text = value
          .replaceAll(RegExp(r'https?://\S+', caseSensitive: false), '[url]')
          .replaceAll(RegExp(r'[\w.+-]+@[\w.-]+\.[A-Za-z]{2,}'), '[email]')
          .replaceAll(
            RegExp(
              r'(receiptData|latestReceipt|responseData|userToken|jwtToken|authorization|authentication|accountToken|password|token)\s*[:=]\s*("[^"]*"|\S+)',
              caseSensitive: false,
            ),
            '[redacted]',
          );
      return text.length > 600 ? '${text.substring(0, 600)}…' : text;
    }
    return value == null || value is num || value is bool ? value : null;
  }
}
