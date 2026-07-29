import 'dart:async';
import 'dart:convert';

import 'package:BoltStar/src/network/api_client.dart';
import 'package:BoltStar/src/network/api_session.dart';
import 'package:BoltStar/src/network/boltfox_api.dart';
import 'package:BoltStar/src/state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 微信授权登录的一次性 code 约束（docs/integration/WECHAT_LOGIN_SETUP.md 七）：
/// 一次业务调用最多发一次 HTTP 请求。code 被后端消费过一次后，重发必被微信判 40163，
/// 用户看到的只是「微信登录失败」，所以这条不变量必须由测试守住。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<http.Request> sent;

  /// 装一个记账用的假客户端；每个用例自行决定响应或抛错。
  void useClient(Future<http.Response> Function(http.Request) handle) {
    ApiClient.instance.httpClient = MockClient((request) {
      sent.add(request);
      return handle(request);
    });
  }

  http.Response okLogin() => http.Response(
    jsonEncode({
      'retCode': 200,
      'retData': {
        'userToken': 'user-token',
        'jwtToken': 'jwt-token',
        'nickName': '微信用户',
        'userNo': 'U1001',
      },
    }),
    200,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );

  setUp(() {
    sent = <http.Request>[];
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() {
    ApiSession.instance.clear();
    ApiClient.instance.httpClient = http.Client();
  });

  test('提交到 App 专用接口，body 只带 code，且不带登录态', () async {
    useClient((_) async => okLogin());

    await BoltFoxApi.weChatMobileLogin(code: 'wx-code-1');

    expect(sent, hasLength(1));
    final request = sent.single;
    expect(request.method, 'POST');
    // 小程序手机号一键登录接口（setWechatAppLogin）不能用于移动应用 OAuth。
    expect(request.url.path, '/Client/User/setWechatAuthorizLogin');
    expect(jsonDecode(request.body), {'code': 'wx-code-1'});
    // device / language / terminal 走公共参数（swagger DTO 注释：通过 headers 传递）。
    expect(request.headers['terminal'], isNotEmpty);
    expect(request.headers['language'], isNotEmpty);
    // 未登录接口：不带 userToken（header 与 query 都不带）。
    expect(request.headers.containsKey('userToken'), isFalse);
    expect(request.url.queryParameters.containsKey('userToken'), isFalse);
  });

  test('超时不重试：一次业务调用只发一次请求', () async {
    // 直接抛 TimeoutException 等价于 `.timeout(ApiConfig.timeout)` 触发的那个，
    // 免得为了等 10s 真超时把测试拖成慢用例。
    useClient((_) async {
      throw TimeoutException('simulated');
    });

    await expectLater(
      BoltFoxApi.weChatMobileLogin(code: 'wx-code-2'),
      throwsA(anything),
    );

    expect(sent, hasLength(1));
  });

  test('连接中断不重试：一次业务调用只发一次请求', () async {
    useClient((_) async {
      throw http.ClientException('Connection closed before full header');
    });

    await expectLater(
      BoltFoxApi.weChatMobileLogin(code: 'wx-code-3'),
      throwsA(anything),
    );

    expect(sent, hasLength(1));
  });

  test('对照组：普通接口连接中断仍自动重试', () async {
    useClient((_) async {
      throw http.ClientException('Connection closed before full header');
    });

    await expectLater(
      BoltFoxApi.userLogin(email: 'a@b.com', password: 'secret'),
      throwsA(anything),
    );

    // 首次 + networkRetryMax(2) 次重试。这条挂了说明关重试的开关误伤了全局。
    expect(sent, hasLength(3));
  });

  test('同一个 code 不会被提交第二次', () async {
    useClient((_) async => okLogin());
    final state = PhotoFrameState.seeded();

    final first = await state.loginWithWeChatCode('wx-code-4');
    expect(first.success, isTrue);
    expect(sent, hasLength(1));

    // 失败提示上连点、或页面重建后拿旧 code 再调：必须在客户端就被挡掉。
    final second = await state.loginWithWeChatCode('wx-code-4');
    expect(second.success, isFalse);
    expect(sent, hasLength(1));
  });

  test('登录成功写入两种会话凭证', () async {
    useClient((_) async => okLogin());
    final state = PhotoFrameState.seeded();

    final feedback = await state.loginWithWeChatCode('wx-code-5');

    expect(feedback.success, isTrue);
    expect(ApiSession.instance.userToken, 'user-token');
    expect(ApiSession.instance.jwtToken, 'jwt-token');
    expect(ApiSession.instance.isLoggedIn, isTrue);
  });

  test('缺 jwtToken 时不切登录态', () async {
    useClient(
      (_) async => http.Response(
        jsonEncode({
          'retCode': 200,
          'retData': {'userToken': 'user-token'},
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      ),
    );
    final state = PhotoFrameState.seeded();

    final feedback = await state.loginWithWeChatCode('wx-code-6');

    expect(feedback.success, isFalse);
    expect(ApiSession.instance.isLoggedIn, isFalse);
  });
}
