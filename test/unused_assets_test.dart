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
  // 只留剥过注释的那份：原来另有一份含注释的 allSource，专供「bg01.png 的认领注释还在吗」
  // 那条断言用；2026-08-27 那条反向成「文件不许存在」后就没有消费方了，留着只会被 analyze 报未使用。
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

  test('旧背景 bg01.png 已删，不许再塞回来', () {
    // 2026-08-21 全站换成 bg02.jpg 后，bg01.png 一度按产品要求「怕要换回去」留在包里；
    // 2026-08-27 产品确认不会换回去，图删掉（省 1.1 MB 包体），各页注释里的 bg01 字样一并改成 bg02。
    // 这条**反着钉**：原来是「必须还在 + 认领注释还在」，现在是「不许再出现」——
    // 重新加回来只会又变成一张没人引用的 1.1 MB 死重量。
    expect(
      File('assets/images/bg01.png').existsSync(),
      isFalse,
      reason: '旧背景已于 2026-08-27 删除；真要回滚请连同 figma_common 的说明一起改，别只把图塞回来',
    );
    // ⚠️ 只钉「文件不在」，不钉「代码里不许提它」：figma_common.dart 那段换背景说明里
    // 写着「旧背景已删」正是给下一个人看的，把注释也一并禁掉等于逼人删掉这段来龙去脉。
    // 真正要防的是图被悄悄塞回来——上面那条就够了。
  });

  test('assets/images 里不许有无人引用的图（白占包体）', () {
    const dynamicPrefixes = <String>[
      'assets/images/BatteryLevel/',
      'assets/images/device-list-icon0',
      'assets/images/ai-orientation-',
    ];
    // 故意保留的无引用素材：当前一张都没有（bg01.png 2026-08-27 已删）。
    // 再往里加必须写明理由与认领它的注释在哪，否则下一轮没人知道能不能删。
    const parked = <String>[];

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
