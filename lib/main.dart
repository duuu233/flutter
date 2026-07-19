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
  // 热重启/异常退出残留清扫（best-effort）：Dart 侧单例重建后 connected=false，
  // 但原生侧的连接保活前台服务可能仍在跑——表现为热重启后通知栏保活常驻、
  // 设备被残留 GATT 占线搜不到。冷启动时本就没有服务在跑，停一次是无害空调用。
  unawaited(NativeDeviceApi.stopConnectionKeepAliveService());
  // 状态栏透明（Android）：让每页自己的头部背景直接透到状态栏区域。
  // ⚠️ 别改回不透明色——曾设 0xFFF7EDE2，冷启动的首页/我的 头图上就压着一条
  // 米色实心带（这两页没有自己的 AnnotatedRegion，这里设什么就驻留什么）；
  // 进一次内页后 FigmaScreen 的 transparent 注解驻留下来，问题看似"自愈"，
  // 实为同一页面两种状态栏。真正的全局兜底是根组件 builder 上的
  // AnnotatedRegion（bolt_star_app.dart），这里保持同值，只覆盖首帧前的空窗。
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
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
