import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 低电量提醒的**入口覆盖**体检（2026-08-27）。
///
/// 小程序那边「主动点击才弹、自动连接不弹」是**结构上**成立的：所有主动操作都收口在
/// `active-device.ensureConnectedForAction`（弹），自动重连走 `ensureDeviceConnected`（不弹），
/// 一处改动全站生效。App 侧没有同名收口——每个页面各自调 `state.connectDevice`，
/// 提醒只能在各自的动作入口手动补一次（2026-08-21 先补了三处，其余留到本轮）。
///
/// 手补的东西会漏，所以把「哪些文件该弹、哪些绝对不许弹」钉在这里：
///   · 少一个入口 → 期望集合对不上，测试红；
///   · 新增一个调用点却没在这里登记 → 同样红，逼着下一个人先想清楚
///     「这条链路是用户按下按钮，还是流程内部自动重连」。
///
/// ⚠️ 只做文件粒度的静态核对（读源码、剥注释），不验证调用的时机与参数——
/// 那属于真机回归。分档逻辑本身另见 `low_battery_band_test.dart`。
void main() {
  const call = 'showLowBatteryTipIfNeeded(';

  /// 提醒函数自己的定义处，不算调用方。
  const definition = 'lib/src/shared/widgets/low_battery_tip.dart';

  /// **主动操作**入口：用户按下按钮 → 需要连接电子纸设备 → 该提醒电量。
  /// 与小程序 `docs/changes/2026-08-21-低电量弹窗与轮播已开启与微信支付文案.md`
  /// 第二节「逐个入口」那张表一一对应。
  const expected = <String>{
    // 首页「连接蓝牙」/「拍照·相册」投屏（含已连接那一支）
    'lib/src/features/home/presentation/home_page.dart',
    // 设备列表「连接」/「投屏」/ 进详情前的连接
    'lib/src/features/devices/presentation/devices_page.dart',
    // 详情页「连接」/「投屏」
    'lib/src/features/devices/presentation/device_details_page.dart',
    // 详情页「一键清空」（两步确认之前）
    'lib/src/features/devices/presentation/device_clear_flow.dart',
    // 详情页「固件升级 → 立刻更新」入口 + OTA 页「连接并升级」
    'lib/src/features/devices/presentation/ota_upgrade_page.dart',
    // 轮播设置页开关 / 轮播方式
    'lib/src/features/devices/presentation/carousel_settings_page.dart',
    // 「我的相册」再次投屏 / 删除
    'lib/src/features/gallery/presentation/gallery_page.dart',
    // 官方图库详情页「连接并投屏」
    'lib/src/features/gallery/official/official_gallery_detail_page.dart',
    // 投屏记录「再次投屏」
    'lib/src/features/cast/presentation/cast_management_figma_page.dart',
    // 投屏结果页「继续投屏」（再选图）
    'lib/src/features/cast/presentation/casting_progress_page.dart',
    // AI 对话页「投屏」
    'lib/src/features/ai/presentation/ai_chat_page.dart',
  };

  /// **自动连接**链路：用户没按按钮，弹窗只会打断正在跑的流程 —— 这几处永远不许出现提醒。
  /// 这是「自动连接不弹」这条产品口径在 App 侧唯一的红线。
  ///
  /// ⚠️ `casting_progress_page.dart` 两种链路都有（页内自动续连 + 结果页「继续投屏」按钮），
  /// 文件粒度分不开，所以它只在 expected 里、不在这份名单里。
  const forbidden = <String>{
    // 投屏/删除/轮播等内部的自动扫连
    'lib/src/state.dart',
    // 预览页进场预热连接
    'lib/src/features/cast/presentation/cast_preview_page.dart',
    // 图传过程中的续连
    'lib/src/features/cast/projection_service.dart',
    // BLE 连接层本身
    'lib/src/device/ble_controller.dart',
  };

  /// 剥掉 `//`、`///` 与 `/* */`：注释里讲清来龙去脉时必然会提到这个函数名。
  String stripComments(String source) {
    final withoutBlock = source.replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '');
    return withoutBlock.replaceAll(RegExp(r'^\s*///?.*$', multiLine: true), '');
  }

  final callers = <String>{};
  for (final entity in Directory('lib').listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) {
      continue;
    }
    final path = entity.path.replaceAll(r'\', '/');
    if (path == definition) {
      continue;
    }
    if (stripComments(entity.readAsStringSync()).contains(call)) {
      callers.add(path);
    }
  }

  test('每个主动操作入口都调了低电量提醒', () {
    expect(expected.difference(callers), isEmpty,
        reason: '这些入口漏了 showLowBatteryTipIfNeeded');
  });

  test('没有登记在册的新调用点', () {
    expect(callers.difference(expected), isEmpty,
        reason: '新增了调用点：先确认它是用户主动操作（补进 expected），'
            '还是流程内部的自动重连（那就不该弹）');
  });

  test('自动连接链路一律不弹', () {
    for (final path in forbidden) {
      expect(File(path).existsSync(), isTrue, reason: '$path 不见了，名单要跟着改');
      expect(callers.contains(path), isFalse,
          reason: '$path 是自动连接链路，弹窗会打断正在跑的流程');
    }
  });
}
