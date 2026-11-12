import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:BoltStar/src/features/wifi/wifi_share.dart';

/// 设备分享改为 H5 链接（2026-11-12）：App 分享 https 落地页链接 → 对方浏览器打开拉起
/// boltstar://share/accept?<同一串参数> → App 接受页 chkTimeValid + addUserProduct（isToHave=0、shareUserId=所有者）。
void main() {
  test('分享链接 = H5 落地页 + 与小程序卡片同格式的参数', () {
    final url = WifiShareLink.h5Url(
      deviceId: 'E3:48:C2:1E:D4:28',
      productId: 12,
      ownerUserId: '34',
      deviceName: '客厅 相框',
      ownerName: '小明',
      shareTime: '1762240000000',
    );
    expect(WifiShareLink.h5Page, 'https://iot.boltfox.cn/h5/share.html');
    expect(url, 'https://iot.boltfox.cn/h5/share.html?d=E3%3A48%3AC2%3A1E%3AD4%3A28&p=12&u=34&n=%E5%AE%A2%E5%8E%85%20%E7%9B%B8%E6%A1%86&o=%E5%B0%8F%E6%98%8E&t=1762240000000');
    expect(
      WifiShareLink.acceptPath(deviceId: 'E3:48:C2:1E:D4:28', productId: 12, ownerUserId: '34'),
      '/subpackages/device/wifi-share-accept/wifi-share-accept?d=E3%3A48%3AC2%3A1E%3AD4%3A28&p=12&u=34',
      reason: '小程序接受页路径格式不变',
    );
  });

  test('接受页参数：同小程序 parseAcceptQuery，缺任一必需项或 t 非正整数即无效', () {
    final ok = WifiShareInvite.parse({'d': ' E3:48:C2:1E:D4:28 ', 'p': '12', 'u': '34', 'n': '客厅', 'o': '小明', 't': '1762240000000'});
    expect(ok?.deviceId, 'E3:48:C2:1E:D4:28');
    expect(ok?.productId, 12);
    expect(ok?.ownerUserId, 34);
    expect(ok?.deviceName, '客厅');
    expect(ok?.ownerName, '小明');
    expect(ok?.shareTime, '1762240000000');
    final base = {'d': 'E3:48:C2:1E:D4:28', 'p': '12', 'u': '34', 't': '1762240000000'};
    expect(WifiShareInvite.parse(base)?.deviceName, '', reason: '设备名可缺');
    for (final key in ['d', 'p', 'u', 't']) {
      expect(WifiShareInvite.parse({...base}..remove(key)), isNull, reason: '缺 $key');
    }
    expect(WifiShareInvite.parse({...base, 'p': 'x'}), isNull);
    expect(WifiShareInvite.parse({...base, 'u': '-1'}), isNull);
    expect(WifiShareInvite.parse({...base, 't': '0'}), isNull);
    expect(WifiShareInvite.parse(null), isNull);
  });

  test('设备号比较去冒号 / 横线 / 空白并转大写；chkTimeValid 返回值识别', () {
    expect(wifiPlainDeviceNo('e3:48-c2 1e:d4:28'), 'E348C21ED428');
    expect(wifiShareValidFlag(true), isTrue);
    expect(wifiShareValidFlag('false'), isFalse);
    expect(wifiShareValidFlag(1), isTrue);
    expect(wifiShareValidFlag(null), isNull);
    expect(wifiShareValidFlag('x'), isNull);
  });

  String read(String path) => File(path).readAsStringSync();

  test('拉起链路：H5 跳的地址与 Android / iOS 登记的一致，原生记下交给 Dart 读走', () {
    final h5 = read('deploy/share/share.html');
    expect(h5, contains("var SCHEME = 'boltstar';"));
    expect(h5, contains("var APP_PATH = 'share/accept';"));
    final manifest = read('android/app/src/main/AndroidManifest.xml');
    expect(manifest, contains('android:name=".ShareLinkActivity"'));
    expect(manifest, contains('<data android:scheme="boltstar" android:host="share" android:path="/accept"/>'));
    expect(read('android/app/src/main/kotlin/com/boltfox/boltstar/MainActivity.kt'), contains('"consumeShareLink" -> result.success(ShareLink.consume())'));
    final plist = read('ios/Runner/Info.plist');
    expect(plist, contains('<string>boltstar</string>'));
    final scene = read('ios/Runner/SceneDelegate.swift');
    expect(scene, contains('willConnectTo session: UISceneSession'));
    expect(scene, contains('if ShareLinkStore.record(context.url) {'));
    expect(scene, contains('guard url.scheme?.lowercased() == "boltstar", url.host == "share", url.path == "/accept"'));
    expect(read('ios/Runner/AppDelegate.swift'), contains('case "consumeShareLink":'));
    final app = read('lib/src/app/bolt_star_app.dart');
    expect(RegExp(r'unawaited\(_maybeOpenShareInvite\(\)\)').allMatches(app).length, 3, reason: '闪屏结束 / 登录后 / 回前台三处');
    expect(app, contains('if (!mounted || _showSplash || !_state.isLoggedIn || !WifiShareInbox.hasPending)'));
  });

  test('接受页：再校验有效期、本人分享 / 已在列表拦下，接受按非所有者绑定', () {
    final page = read('lib/src/features/wifi/presentation/wifi_share_accept_page.dart');
    final accept = page.substring(page.indexOf('Future<void> _doAccept('));
    expect(accept.indexOf('_checkValid()'), lessThan(accept.indexOf('BoltFoxApi.addUserProduct(')));
    expect(accept.indexOf('wifiAcceptOwn'), lessThan(accept.indexOf('BoltFoxApi.addUserProduct(')));
    expect(accept.indexOf('wifiAcceptExists'), lessThan(accept.indexOf('BoltFoxApi.addUserProduct(')));
    expect(accept, contains('isToHave: 0,'));
    expect(accept, contains('shareUserId: invite.ownerUserId,'));
    final share = read('lib/src/features/wifi/presentation/wifi_share_page.dart');
    expect(share, contains('WifiShareLink.h5Url('));
    expect(share, isNot(contains('shareMiniProgram')));
  });

  test('分享页产品 ID / 设备号取详情接口（列表接口不下发 productId，缓存恒为 0 会一直置灰）', () {
    final share = read('lib/src/features/wifi/presentation/wifi_share_page.dart');
    final load = share.substring(share.indexOf('Future<void> _load() async {'));
    expect(load, contains("_detailProductId = productId is num ? productId.toInt() : int.tryParse('\${productId ?? ''}'.trim()) ?? 0;"));
    expect(load, contains("_detailSerial = canonicalDeviceSerial(detail['deviceId']);"));
    expect(share, contains('int get _productId => _detailProductId > 0 ? _detailProductId : _device.productId;'));
    expect(share, contains('_isOwner && _user.userId.isNotEmpty && _productId > 0 && _serial.isNotEmpty;'));
    final link = share.substring(share.indexOf('WifiShareLink.h5Url('));
    expect(link, contains('deviceId: _serial,'));
    expect(link, contains('productId: _productId,'));
    expect(share, isNot(contains('_device.productId > 0')));
  });

  test('点「分享设备」直接调系统分享面板（微信、WhatsApp、LINE 等都在面板里），不再有自定义弹层', () {
    final share = read('lib/src/features/wifi/presentation/wifi_share_page.dart');
    expect(share, contains("NativeDeviceApi.shareText(text: '\$title\\n\$url'"));
    expect(share, isNot(contains('_pickShareWay')));
    expect(share, isNot(contains('showModalBottomSheet')));
    expect(share, isNot(contains('WifiWeChatShare')));
    expect(File('lib/src/features/wifi/wifi_wechat_share.dart').existsSync(), isFalse);
    final api = read('lib/src/native_device_api.dart');
    expect(api, contains("_channel.invokeMethod<bool>('shareText'"));
    final android = read('android/app/src/main/kotlin/com/boltfox/boltstar/MainActivity.kt');
    expect(android, contains('"shareText" -> shareText(call, result)'));
    expect(android, contains('Intent.createChooser(send'));
    final ios = read('ios/Runner/AppDelegate.swift');
    expect(ios, contains('case "shareText":'));
    expect(ios, contains('UIActivityViewController(activityItems: [text]'));
    expect(ios, contains('popover.sourceView = presenter.view'));
  });
}
