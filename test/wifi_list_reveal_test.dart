import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 选择 WiFi 页「搜一个显示一个」（2026-11-11，同小程序 `subpackages/device/wifi-list`）。
///
/// 缺陷：设备分批回 WiFi 列表时页面边收边显示，但转圈要等最后一批后再静默 5 秒才收，
/// 列表已经出来了头部还挂着「正在搜索网络...」；整批一次性出现，不像搜索设备页那样一个一个出来。
/// 现在：只在一条都没有时转圈；列表出来后头部即「重新搜索」（旧一轮结果作废）、底部手动输入同时出现；
/// 每批按信号从强到弱逐条亮出、新行淡入；扫描结束时没亮完的一次补齐。
///
/// ⚠️ 只做源码静态核对（读源码、剥注释），逐条节奏与观感仍需真机回归。
void main() {
  final page = File('lib/src/features/wifi/presentation/wifi_list_page.dart')
      .readAsStringSync()
      .replaceAll(RegExp(r'//[^\n]*'), '');

  test('列表出来后头部不再转圈，重新搜索与手动输入同时出现', () {
    expect(page, contains('if (_scanning && _list.isEmpty)'),
        reason: '只在一条都还没收到时转圈');
    expect(RegExp(r'if \(!_scanning \|\| _list\.isNotEmpty\)').allMatches(page).length, 3,
        reason: '头部「重新搜索」、底部「手动输入」与 _rescan 守卫同一条件：列表出来后即可用');
    expect(page, contains('onTap: _rescan'));
    expect(page, contains('else if (!_scanning && _tip.isNotEmpty)'));
  });

  test('每批交给逐条亮出，旧一轮作废，收尾补齐', () {
    expect(page, contains('_reveal(_toList(all))'), reason: '每批不再整批 setState');
    expect(page, isNot(contains('setState(() => _list = _toList(all))')));
    expect(page, contains('_scanSeq == seq'), reason: '重新搜索后旧一轮的批次 / 结果作废');
    expect(page, contains('Timer(_revealInterval, _revealNext)'));
    final tail = page.substring(page.indexOf('final items = _toList(list);'));
    expect(tail.indexOf('_resetReveal();'), lessThan(tail.indexOf('_list = items;')),
        reason: '结束时清掉定时器、没亮完的一次补齐');
    expect(page, contains('_revealTimer?.cancel();'));
  });

  test('新行淡入，按 ssid 作 key 不重播', () {
    expect(page, contains('_WifiRowFadeIn('));
    expect(page, contains('key: ValueKey<String>(_list[i].ssid)'));
    expect(page, contains('TweenAnimationBuilder<double>('));
  });
}
