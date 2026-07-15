import 'package:BoltStar/src/features/account/data/wechat_authorization_client.dart';
import 'package:BoltStar/src/features/account/presentation/auth_page.dart';
import 'package:BoltStar/src/state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeWeChatAuthorizationClient implements WeChatAuthorizationClient {
  int callCount = 0;

  @override
  Future<String> authorize() async {
    callCount += 1;
    throw const WeChatAuthorizationException('测试微信授权失败');
  }
}

void main() {
  testWidgets('登录页展示微信授权入口并在授权前校验协议', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final fakeClient = _FakeWeChatAuthorizationClient();

    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(375, 812);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      MaterialApp(
        home: AuthPage(
          state: PhotoFrameState.seeded(),
          weChatAuthorizationClient: fakeClient,
        ),
      ),
    );
    await tester.pump();

    final weChatButton = find.bySemanticsLabel('微信授权登录');
    expect(weChatButton, findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Image &&
            widget.image is AssetImage &&
            (widget.image as AssetImage).assetName ==
                'assets/images/login-wx-icon.png',
      ),
      findsOneWidget,
    );

    expect(tester.getSize(weChatButton), const Size(48, 48));

    await tester.tap(weChatButton);
    await tester.pump();

    expect(fakeClient.callCount, 0);
    expect(find.text('请先阅读并同意用户协议和隐私政策'), findsOneWidget);

    // AppToast 会在两秒后自动移除，推进假时钟以免测试结束时遗留计时器。
    await tester.pump(const Duration(seconds: 3));
  });
}
