import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// 冷启动时清扫上一次运行遗留的临时图片产物。
///
/// ## 为什么需要它
/// 两个写入点都用「前缀 + 微秒时间戳」命名，**永不重名、也就永不覆盖**，
/// 而它们从来没有删除路径——装机后一直累积到用户手动清缓存为止：
///
/// - `cast_edit_*.jpg`（`CastImageEditor._write`）：每次旋转 / 裁剪一张，
///   尺寸是设备分辨率的 JPEG（q92）。用户在预览页反复调整就反复产出。
/// - `recast_*.jpg`（`CastManagementFigmaPage._downloadToTemp`）：每次「重新投屏」
///   下载一张**完整原图**。这个最占地方。
///
/// ## 为什么在冷启动扫、而不是用完就删
/// 这两个路径产出后都会被**交给别的页面继续用**（预览页 → 裁剪器 → 投屏流程，
/// 中途还会来回 push/pop），谁是"最后一个用完的人"在调用链上并不收敛——
/// 在任一使用点顺手删，都可能删掉另一个还挂在栈上的页面正在显示的图
/// （`avatar_upload.dart:69-72` 记录过同一个坑）。
///
/// 冷启动这一刻没有任何页面存活、没有任何 `File` 句柄挂着，是唯一能
/// **无歧义**判定「这些文件全是垃圾」的时机。
///
/// ## 残留范围
/// 单次运行内产出的文件仍会累积到下次冷启动——这是刻意的取舍（换来零误删风险）。
/// 上限是一次会话的编辑量，不再是"装机以来的全部"。
///
/// 头像产物 `boltstar_avatar_*.jpg` **不在清扫范围**：它落在选图器的缓存目录
/// （`source.parent.path`，随平台/插件变化）而不是 [Directory.systemTemp]，
/// 且单个 ≤100KB，交给系统回收即可（见 `avatar_upload.dart` 注释）。
class TempCacheSweeper {
  TempCacheSweeper._();

  /// 清扫目标前缀。新增临时图片写入点时**记得把前缀加进来**。
  static const List<String> _prefixes = <String>['cast_edit_', 'recast_'];

  static const String _suffix = '.jpg';

  /// 冷启动清扫，全程 best-effort：任何一步失败都不能影响启动。
  ///
  /// 调用点在 `main()`，`unawaited` 不阻塞首帧。
  static Future<void> sweepOnColdStart() async {
    try {
      final dir = Directory.systemTemp;
      if (!await dir.exists()) {
        return;
      }
      var deleted = 0;
      var freed = 0;
      // followLinks: false —— 不跟符号链接出目录；recursive 默认 false，只扫当层。
      await for (final entity in dir.list(followLinks: false)) {
        if (entity is! File) {
          continue;
        }
        final name = entity.uri.pathSegments.last;
        if (!name.endsWith(_suffix)) {
          continue;
        }
        if (!_prefixes.any(name.startsWith)) {
          continue;
        }
        try {
          // 先取体积再删：删掉之后 stat 不到，日志里就没有"省了多少"。
          final size = await entity.length();
          await entity.delete();
          deleted++;
          freed += size;
        } catch (_) {
          // 单个文件删不掉（被占用 / 权限）不影响其余文件，继续扫。
        }
      }
      if (deleted > 0) {
        debugPrint(
          '[TempCacheSweeper] 已清理上次运行的临时图片 $deleted 个，'
          '释放 ${(freed / 1024 / 1024).toStringAsFixed(1)}MB',
        );
      }
    } catch (error) {
      debugPrint('[TempCacheSweeper] ⚠️ 清扫失败（忽略）：$error');
    }
  }
}
