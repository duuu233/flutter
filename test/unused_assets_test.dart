import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 图片资源体检（2026-08-21，与小程序 `tests/unused-assets.test.js` 同一套判据）。
///
/// 打包体积是硬指标：`pubspec.yaml` 注册的是 `assets/images/` **整个目录**，
/// 躺着不用的图一样会被打进包里。反过来，引用一张**不存在**的图 Flutter 不会编译报错，
/// 只会在运行时抛异常或落到 errorBuilder —— 本轮就在 `home_figma_common.dart` 里逮到两张
/// 从来不存在的 `home_background.png` / `home_wave_overlay.png`（靠 errorBuilder 兜着，没人发现）。
/// 两个方向都在这里钉住，以后加图删图不用再人肉扫一遍。
///
/// 判定规则：
///   · 只认**代码里活着的引用**（先剥注释）—— 注释里提到不算在用；
///   · 动态拼路径的图走白名单，但**豁免的理由必须还在**：下面会回源码核对那行拼接仍然存在，
///     拼接没了就说明这批图该重新审视，而不是继续无条件放行；
///   · 故意留着的图（产品要求可回滚的旧素材）同样走白名单，且要求认领它的注释还在。
void main() {
  final libDir = Directory('lib');
  final imagesDir = Directory('assets/images');

  /// 剥掉 `//`、`///` 与 `/* */`：注释里为了讲清来龙去脉必然还会提到已删/已停用的图。
  String stripComments(String source) {
    final withoutBlock = source.replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '');
    return withoutBlock.replaceAll(RegExp(r'^\s*///?.*$', multiLine: true), '');
  }

  final assetRef = RegExp(r'assets/images/[A-Za-z0-9_\-./]+\.(?:png|jpe?g|svg|gif|webp)');

  final liveRefs = <String>{};
  final sources = <String, String>{};
  for (final entity in libDir.listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) {
      continue;
    }
    final raw = entity.readAsStringSync();
    sources[entity.path] = raw;
    liveRefs.addAll(assetRef.allMatches(stripComments(raw)).map((m) => m.group(0)!));
  }
  final allSource = sources.values.join('\n');
  final liveSource = sources.values.map(stripComments).join('\n');

  final assetFiles = imagesDir
      .listSync(recursive: true)
      .whereType<File>()
      .map((f) => f.path.replaceAll(r'\', '/'))
      .toList()
    ..sort();

  test('代码引用的图必须真的存在（引用空文件不会编译报错，只会在运行时炸/落 errorBuilder）', () {
    final missing = liveRefs.where((ref) => !File(ref).existsSync()).toList()..sort();
    expect(missing, isEmpty, reason: '这些图被代码引用、但仓库里没有：$missing');
  });

  group('动态拼路径的白名单（豁免理由必须还在）', () {
    test('BatteryLevel 整目录：battery-\$level 拼出来的', () {
      expect(
        liveSource.contains(r'assets/images/BatteryLevel/battery-$'),
        isTrue,
        reason: '这行拼接没了就该重新核对 BatteryLevel 目录，而不是继续无条件豁免',
      );
    });

    test('device-list-icon01~03：按列表序号拼的，只取 1~3', () {
      expect(liveSource.contains(r'assets/images/device-list-icon0$'), isTrue);
      // 04/05 已于 2026-08-21 删除：`(index % 3) + 1` 永远取不到它们
      expect(File('assets/images/device-list-icon04.png').existsSync(), isFalse);
      expect(File('assets/images/device-list-icon05.png').existsSync(), isFalse);
    });

    test('ai-orientation-\$key-active：三个比例各一张', () {
      expect(liveSource.contains(r'assets/images/ai-orientation-$'), isTrue);
      for (final key in ['vertical', 'horizontal', 'square']) {
        expect(
          File('assets/images/ai-orientation-$key-active.png').existsSync(),
          isTrue,
          reason: '选中态图标是拼出来的，缺一张就是那一档点下去变空白',
        );
      }
    });
  });

  test('故意留着的图：认领它的注释还在，否则该跟着删', () {
    // 旧的暖白背景。2026-08-21 全站换成 bg02.jpg，产品要求「怕要换回去」先留着。
    expect(File('assets/images/bg01.png').existsSync(), isTrue);
    expect(
      allSource.contains('bg01.png'),
      isTrue,
      reason: 'bg01.png 靠 figma_common.dart 的回滚说明认领才留着；那段注释若已删，这张 1.1MB 的图也该删',
    );
  });

  test('assets/images 里不许有无人引用的图（白占包体）', () {
    const dynamicPrefixes = <String>[
      'assets/images/BatteryLevel/',
      'assets/images/device-list-icon0',
      'assets/images/ai-orientation-',
    ];
    const parked = <String>['assets/images/bg01.png'];

    final unused = assetFiles.where((path) {
      if (liveRefs.contains(path)) return false;
      if (parked.contains(path)) return false;
      return !dynamicPrefixes.any(path.startsWith);
    }).toList();

    expect(
      unused,
      isEmpty,
      reason:
          '这些图没有任何活着的引用：要么用起来，要么删掉；确实要留就加进 parked 白名单并写明理由。\n$unused',
    );
  });
}
