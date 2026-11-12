import 'dart:io';

import 'package:BoltStar/src/shared/widgets/app_widgets.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 开关与加载转圈样式（2026-11-12，同小程序）。
///
/// 缺陷：① Material 3 的 Switch 关闭时是白底灰描边、小灰钮，小程序原生 switch 关闭是浅灰底、白圆钮、没有描边
/// （消息中心「只看未读」、轮播设置的启用开关最明显）；② 没指定颜色的 CircularProgressIndicator 取主题 primary
/// 深青色，与全站橙色加载不一致。
void main() {
  String read(String path) => File(path).readAsStringSync().replaceAll(RegExp(r'//[^\n]*'), '');

  testWidgets('AppSwitch：两态无描边，打开橙色、关闭浅灰，圆钮白色', (tester) async {
    await tester.pumpWidget(
      const CupertinoApp(home: Center(child: AppSwitch(value: false, onChanged: null))),
    );
    final cupertino = tester.widget<CupertinoSwitch>(find.byType(CupertinoSwitch));
    expect(cupertino.activeTrackColor, AppSwitch.activeColor);
    expect(cupertino.inactiveTrackColor, AppSwitch.inactiveColor);
    expect(cupertino.thumbColor, Colors.white);
    expect(AppSwitch.activeColor, const Color(0xFFFF6A20), reason: '同小程序 switch color="#ff6a20"');
  });

  test('消息中心、轮播设置、TF 卡、投屏预览的开关都用 AppSwitch', () {
    for (final path in [
      'lib/src/features/wifi/presentation/wifi_messages_page.dart',
      'lib/src/features/wifi/presentation/wifi_slideshow_page.dart',
      'lib/src/features/wifi/presentation/wifi_tf_page.dart',
      'lib/src/features/cast/presentation/cast_preview_page.dart',
    ]) {
      final source = read(path);
      expect(source, contains('AppSwitch('), reason: path);
      expect(RegExp(r'(?<![A-Za-z])Switch\(').hasMatch(source), isFalse, reason: '$path 不再用 Material Switch');
    }
  });

  test('加载转圈统一橙色：主题默认色与 WiFi 页首屏加载', () {
    expect(read('lib/src/app/app_theme.dart'), contains('progressIndicatorTheme: const ProgressIndicatorThemeData(color: Color(0xFFEB5F1B))'));
    expect(kLoadingOrange, const Color(0xFFEB5F1B));
    for (final name in ['messages', 'slideshow', 'sleep', 'device_info', 'share']) {
      final source = read('lib/src/features/wifi/presentation/wifi_${name}_page.dart');
      expect(source, contains('PageLoading()'), reason: name);
      expect(source, isNot(contains('CircularProgressIndicator()')), reason: name);
    }
  });
}
