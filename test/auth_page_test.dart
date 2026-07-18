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
    // 校验失败走居中吐司（AppToast，2026-07-19 由「知道了」确认框改成吐司）：
    // 只有 160ms 淡入，没有路由入场动画。pumpAndSettle 会一直泵到没有动画为止。
    await tester.pumpAndSettle();

    expect(fakeClient.callCount, 0);
    expect(find.text('请先阅读并同意用户协议和隐私政策'), findsOneWidget);

    // 吐司靠 Future.delayed 自动收起（warn 用 3s）。不等它跑完，测试结束时
    // 会因为「A Timer is still pending」失败；同时也让 AppToast 的静态
    // OverlayEntry 归位，不残留到同文件的后续用例。
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
  });
}
