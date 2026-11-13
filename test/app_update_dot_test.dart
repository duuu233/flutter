import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:BoltStar/src/state.dart';

/// App 新版本红点（2026-11-14）：最近一次 checkAppVersion 有新版本就在「我的 → 设置」「设置 → 检查更新」亮红点，
/// 4=不提示升级除外；强制升级弹窗规则不变（只看 compulsory=1 且有新版本）。
AppVersionInfo _info({bool hasUpdate = true, int compulsory = 3}) => AppVersionInfo(
      hasUpdate: hasUpdate,
      currentVersion: '1.0.1',
      latestVersion: '1.0.2',
      downloadUrl: 'https://example.com/app.apk',
      description: '',
      compulsory: compulsory,
    );

void main() {
  test('红点判定：有新版本才亮，不提示升级除外', () {
    expect(_info().showsDot, isTrue, reason: '普通 / 弱提示升级');
    expect(_info(compulsory: 1).showsDot, isTrue, reason: '强制升级也亮');
    expect(_info(compulsory: 2).showsDot, isTrue);
    expect(_info(compulsory: 4).showsDot, isFalse, reason: '不提示升级不亮');
    expect(_info(hasUpdate: false).showsDot, isFalse, reason: '已是最新不亮');
    expect(_info(compulsory: 1).isCompulsory, isTrue, reason: '强制升级弹窗规则不变');
    expect(_info(compulsory: 3).isCompulsory, isFalse);
  });

  test('接入位置', () {
    String read(String path) => File(path).readAsStringSync();
    final state = read('lib/src/state.dart');
    expect(state.contains('_appVersion = info;'), isTrue, reason: '每次检查都记下结果');
    expect(state.contains('bool get appUpdateDot => _appVersion?.showsDot ?? false;'), isTrue);
    final mine = read('lib/src/features/mine/presentation/mine_page.dart');
    expect(RegExp(r"title: AppL10n\.of\(context\)\.mineSettings,\s*dot: widget\.state\.appUpdateDot,").hasMatch(mine), isTrue,
        reason: '我的 → 设置');
    final settings = read('lib/src/features/settings/presentation/settings_page.dart');
    expect(RegExp(r'title: l10n\.checkUpdate,\s*dot: state\.appUpdateDot,').hasMatch(settings), isTrue, reason: '设置 → 检查更新');
  });
}
