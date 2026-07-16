import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:BoltStar/src/app.dart';
import 'package:BoltStar/src/native_device_api.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  _installCrashHandlers();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Color(0xFFF7EDE2),
      statusBarIconBrightness: Brightness.dark,
      statusBarBrightness: Brightness.light,
      systemNavigationBarColor: Colors.white,
      systemNavigationBarIconBrightness: Brightness.dark,
      systemNavigationBarDividerColor: Color(0xFFE5DED4),
    ),
  );
  runApp(const BoltStarApp());
}

/// 每次运行最多落盘多少条 Dart 错误：防止 build 期异常每帧重抛把日志文件刷爆。
int _dartErrorBudget = 20;

/// 全局错误钩子：Dart 侧未捕获异常写入原生崩溃日志文件（CrashLogger），
/// 与 JVM 未捕获异常同一现场，下次启动弹窗展示（见 bolt_star_app.dart）。
/// 注意：这**不改变**任何错误行为（控制台照常打印、该崩照崩），只负责留现场。
void _installCrashHandlers() {
  final defaultOnError = FlutterError.onError;
  FlutterError.onError = (details) {
    // 先走默认处理（debug 红屏/控制台打印照旧），再落盘。
    defaultOnError?.call(details);
    if (_dartErrorBudget > 0) {
      _dartErrorBudget--;
      unawaited(
        NativeDeviceApi.logDartError(
          kind: 'flutter-framework',
          error: details.exceptionAsString(),
          stack: '${details.stack ?? ''}',
        ),
      );
    }
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('[UncaughtAsync] $error\n$stack');
    if (_dartErrorBudget > 0) {
      _dartErrorBudget--;
      unawaited(
        NativeDeviceApi.logDartError(
          kind: 'dart-async',
          error: '$error',
          stack: '$stack',
        ),
      );
    }
    return true; // 已记录并打印，不再走引擎默认的重复上报。
  };
}
