import 'dart:async';

import 'package:flutter/painting.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

/// 会话结束时清除图片缓存。
///
/// ## 为什么是隐私问题、而不只是省空间
/// 退出登录 / 注销 / 登录态失效这三条路径原来只清了**内存里的业务列表**
/// （`_devices` / `_castRecords`），但用户的照片本体留在两层缓存里：
///
/// - **内存**：`PaintingBinding.imageCache` 里已解码的位图；
/// - **磁盘**：`cached_network_image` 的缓存目录，默认 **30 天 / 200 个对象**。
///
/// 于是换账号后，B 用户虽然看不到 A 的列表，但 A 的照片文件仍完整躺在本机上；
/// 注销（账号已在服务端删除）后本地照片也还在。共用设备的场景下这是实打实的泄露。
///
/// ## 磁盘清理为什么是异步 + 吞错
/// `emptyCache()` 要遍历删文件，几十上百个 IO；登出必须**立刻**返回让 UI 弹回登录页，
/// 不能被它拖住。删不干净的后果只是残留，不该阻断登出——所以全程吞错。
class ImageCacheCleanup {
  ImageCacheCleanup._();

  /// 清空内存 + 磁盘两层图片缓存。
  ///
  /// 内存部分同步完成（就在本方法返回前生效），磁盘部分后台进行。
  /// 调用点：`PhotoFrameState` 的 `logout` / `deleteAccount` / `_handleSessionExpired`。
  static void clearAll() {
    // 内存：clear() 清"缓存着但没人在用"的，clearLiveImages() 清"正在显示"的。
    // 登出瞬间页面正在被 popUntil 卸载，live 表里那些马上就没人引用了，一并放掉。
    final cache = PaintingBinding.instance.imageCache;
    cache.clear();
    cache.clearLiveImages();
    // 磁盘：后台删，失败不影响登出。
    unawaited(_clearDiskCache());
  }

  static Future<void> _clearDiskCache() async {
    try {
      await DefaultCacheManager().emptyCache();
    } catch (_) {
      // 残留优于卡住登出流程。
    }
  }
}
