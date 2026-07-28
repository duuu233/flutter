import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker_android/image_picker_android.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:BoltStar/src/app.dart';
import 'package:BoltStar/src/device/ble/ble_tuning.dart';
import 'package:BoltStar/src/device/ble/device_ble.dart';
import 'package:BoltStar/src/native_device_api.dart';
import 'package:BoltStar/src/shared/temp_cache_sweeper.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  _configureAndroidPhotoPicker();
  _installCrashHandlers();
  // 热重启/异常退出残留清扫（best-effort）：Dart 侧单例重建后 connected=false，
  // 但原生侧的连接保活前台服务可能仍在跑——表现为热重启后通知栏保活常驻、
  // 设备被残留 GATT 占线搜不到。冷启动时本就没有服务在跑，停一次是无害空调用。
  unawaited(NativeDeviceApi.stopConnectionKeepAliveService());
  // 上次运行遗留的临时图片产物（cast_edit_* / recast_*）清扫，见 TempCacheSweeper。
  unawaited(TempCacheSweeper.sweepOnColdStart());
  // 图传调优旋钮（「投屏性能自检」页里调的那几个值）跨启动保留。不 await：BLE 在启动后
  // 好几秒才可能用上，读 prefs 的这点时间不该挡首帧；读回来之前用的就是出厂默认值。
  unawaited(BleTuning.load());
  // flutter_blue_plus 默认把每次特征读写都打日志；图传一张图 ~1000 个包，iOS 上这份
  // os_log 开销直接落在传输热路径上。release 关掉，debug/profile 留 warning。
  FrameBleClient.applyPluginLogLevel();
  _configureImageCache();
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

/// Android 相册入口统一走系统 Photo Picker。
///
/// 该配置作用于进程内所有 ImagePicker 相册调用（投屏、首页头像、资料头像），
/// 只向 App 授予用户主动选中的图片，不需要整库读取权限。
void _configureAndroidPhotoPicker() {
  final implementation = ImagePickerPlatform.instance;
  if (implementation is ImagePickerAndroid) {
    implementation.useAndroidPhotoPicker = true;
  }
}

/// 收窄 Flutter 全局图片解码缓存的上限。
///
/// 默认是 **1000 个对象 / 100MB**，对本 App 偏高：图库一页 100 张，
/// 每格按 `memCacheWidth = 格宽 × devicePixelRatio` 解码（`gallery_page.dart:722`），
/// 3x 屏上单格解码后约 1MB 起步——填满默认额度就是 100MB **纯解码位图**，
/// 叠上原生侧 `MainActivity.decodeToRgba` 的 `w*h*4` 分配，低端机很容易撞上
/// LMK（系统低内存杀进程）。用户侧表现就是「切出去一会儿回来又是冷启动」。
///
/// 60MB 大约能存 50~60 格，覆盖一屏加上下各一屏的滚动缓冲，滚动不会明显反复解码；
/// 超出的部分本来也会被逐出，只是提前发生、峰值更低。
///
/// ⚠️ 这里只调**内存**缓存。磁盘缓存归 `cached_network_image`（gallery 已限
/// `maxWidthDiskCache: 800`），两者互不影响：内存逐出后从磁盘重建，不重新下载。
void _configureImageCache() {
  final cache = PaintingBinding.instance.imageCache;
  cache.maximumSizeBytes = 60 << 20; // 60MB
  cache.maximumSize = 200; // 个对象（默认 1000）
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
