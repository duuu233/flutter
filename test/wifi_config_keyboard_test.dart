import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// WiFi 配网页与配网状态页（2026-11-11，同小程序 `subpackages/device/wifi-config` / `wifi-provision`）。
///
/// 缺陷：① 输入框聚焦时全局 `inputDecorationTheme` 的橙色 `focusedBorder` 画在内层 TextField 上，
/// 紧贴文字、被裁掉，看起来不正常；② 在密码框打开键盘后点「下一步」，键盘留在配网状态页底部关不掉，
/// 后续页面也一直挡着；③ 头图、切换、小眼睛、WiFi 列表图标与小程序不同。
///
/// ⚠️ 只做源码静态核对（读源码、剥注释），图标观感与键盘收起仍需真机回归。
void main() {
  String read(String path) => File(path).readAsStringSync().replaceAll(RegExp(r'//[^\n]*'), '');
  final config = read('lib/src/features/wifi/presentation/wifi_config_page.dart');
  final provision = read('lib/src/features/wifi/presentation/wifi_provision_page.dart');
  final list = read('lib/src/features/wifi/presentation/wifi_list_page.dart');
  final glyphs = read('lib/src/features/wifi/presentation/wifi_glyphs.dart');

  test('输入框：内层不画主题边框，聚焦时整个框描橙边', () {
    expect(config, contains('focusedBorder: InputBorder.none'));
    expect(config, contains('enabledBorder: InputBorder.none'));
    expect(config, contains('filled: false'));
    expect(config, contains('focusNode: _focus'));
    expect(config, contains('focused ? const Color(0xFFFF6A24)'));
  });

  test('离开 WiFi 配网页前先收键盘，配网状态页进来再兜底收起', () {
    final next = config.substring(config.indexOf('void _goNext()'));
    expect(next.indexOf('_dismissKeyboard();'), lessThan(next.indexOf('.push<void>(')),
        reason: '下一步：先解除焦点再进配网状态页');
    final back = config.substring(config.indexOf('void _openWifiList()'), config.indexOf('void _goNext()'));
    expect(back, contains('_dismissKeyboard();'));
    expect(config, contains('FocusManager.instance.primaryFocus?.unfocus()'));
    expect(provision, contains("SystemChannels.textInput.invokeMethod<void>('TextInput.hide')"));
  });

  test('图标与小程序同源：头图、切换、小眼睛、WiFi 列表图标', () {
    expect(config, contains('const WifiProvisionArt()'));
    expect(config, contains('WifiSwitchGlyph('));
    expect(config, contains('WifiEyeGlyph(open: _showPassword'));
    expect(config, isNot(contains('Icons.visibility')));
    expect(config, isNot(contains('Icons.swap_horiz_rounded')));
    expect(provision, contains('const WifiProvisionArt()'));
    expect(list, contains('WifiBadgeGlyph('));
    expect(list, isNot(contains('Icons.wifi_rounded')));
    // 坐标照抄 SVG：抽查头图的三个主圆与云朵起笔
    for (final orb in ['Offset(92, 120), 56', 'Offset(300, 120), 66', 'Offset(508, 120), 56']) {
      expect(glyphs, contains('_orb(canvas, const $orb)'));
    }
    expect(glyphs, contains('..moveTo(486, 139)'));
  });

  test('配网状态页：跑完即恢复息屏', () {
    expect(provision, contains('await _run(l10n, stale);'));
    expect(provision, contains('unawaited(NativeDeviceApi.setKeepScreenOn(false));'));
  });
}
