import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:BoltStar/src/network/api_client.dart';
import 'package:BoltStar/src/network/api_config.dart';
import 'package:BoltStar/src/network/api_exception.dart';
import 'package:BoltStar/src/network/api_session.dart';
import 'package:BoltStar/src/network/dithering_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 抖动出帧 2026-10-23 起改调我方后端 /Client/Basic/imageDitheringBinDownload：
/// 参数同原第三方接口，鉴权用本 App 用户自己的 userToken，不再有第三方 token。
/// 2026-11-02 起基地址先取 download-endpoint 的 data（如 https://api.boltfox.cn/），再拼同一路径，参数不变；
/// 取不到回落 ApiConfig.baseUrl，成功缓存。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<http.Request> sent;
  late List<http.Request> endpointSent;
  late Future<http.Response> Function(http.Request) endpointHandle;
  late Directory tmp;
  late String imagePath;

  http.Response json(Map<String, dynamic> body) => http.Response(
    jsonEncode(body),
    200,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );

  void useClient(Future<http.Response> Function(http.Request) handle) {
    ApiClient.instance.httpClient = MockClient((request) {
      if (request.url.toString() == DitheringApi.endpointUrl) {
        endpointSent.add(request);
        return endpointHandle(request);
      }
      sent.add(request);
      return handle(request);
    });
  }

  http.Response frameResponse(Uint8List frame) => http.Response.bytes(
    frame,
    200,
    headers: {'content-type': 'application/octet-stream'},
  );

  setUp(() async {
    sent = <http.Request>[];
    endpointSent = <http.Request>[];
    endpointHandle = (_) async =>
        json({'code': 0, 'msg': 'ok', 'data': 'https://api.boltfox.cn/'});
    DitheringApi.resetEndpointCache();
    SharedPreferences.setMockInitialValues({});
    ApiSession.instance.setTokens(userToken: 'user-token', jwtToken: 'jwt');
    tmp = await Directory.systemTemp.createTemp('dithering_api_test');
    imagePath = '${tmp.path}/image.jpg';
    await File(imagePath).writeAsBytes([0xFF, 0xD8, 0xFF, 0xD9]);
  });

  tearDown(() async {
    ApiSession.instance.clear();
    ApiClient.instance.httpClient = http.Client();
    await tmp.delete(recursive: true);
  });

  test('发到我方后端，带自己的 userToken 与原参数，返回二进制帧原样交回', () async {
    final frame = Uint8List.fromList(List<int>.generate(64, (i) => i));
    useClient(
      (_) async => http.Response.bytes(
        frame,
        200,
        headers: {'content-type': 'application/octet-stream'},
      ),
    );

    final bytes = await DitheringApi.requestFrameBin(
      filePath: imagePath,
      type: '1',
    );

    expect(bytes, frame);
    expect(sent, hasLength(1));
    final request = sent.single;
    expect(request.method, 'POST');
    expect(request.url.origin, 'https://api.boltfox.cn');
    expect(request.url.path, '/Client/Basic/imageDitheringBinDownload');
    expect(endpointSent, hasLength(1), reason: '先取一次出帧基地址');
    expect(endpointSent.single.method, 'GET');
    expect(endpointSent.single.headers['userToken'], 'user-token');
    expect(request.headers['userToken'], 'user-token');
    expect(request.url.queryParameters['userToken'], 'user-token');
    expect(request.headers['content-type'], startsWith('multipart/form-data'));
    final body = latin1.decode(request.bodyBytes);
    expect(body, contains('name="color"\r\n\r\nBWRYGB'));
    expect(body, contains('name="imageDitheringModes"\r\n\r\n2'));
    expect(body, contains('name="type"\r\n\r\n1'));
    expect(body, contains('name="file"; filename="image.jpg"'));
  });

  test('业务报错回 JSON：抛 retMsg，不当成帧、不重试', () async {
    useClient((_) async => json({'retCode': 500, 'retMsg': '图片处理失败'}));

    await expectLater(
      DitheringApi.requestFrameBin(filePath: imagePath, type: '0'),
      throwsA(
        isA<ApiException>()
            .having((e) => e.message, 'message', '图片处理失败')
            .having((e) => e.isAuthError, 'isAuthError', isFalse),
      ),
    );
    expect(sent, hasLength(1));
  });

  test('登录过期（retCode 401）：按鉴权失效抛出并清本地登录态', () async {
    useClient((_) async => json({'retCode': 401, 'retMsg': 'expired'}));

    await expectLater(
      DitheringApi.requestFrameBin(filePath: imagePath, type: '0'),
      throwsA(
        isA<ApiException>().having((e) => e.isAuthError, 'isAuthError', isTrue),
      ),
    );
    expect(sent, hasLength(1));
    expect(ApiSession.instance.userToken, isEmpty);
  });

  test('网络失败退避重试，三次都失败才报错', () async {
    useClient((_) async => throw http.ClientException('connection reset'));

    await expectLater(
      DitheringApi.requestFrameBin(filePath: imagePath, type: '0'),
      throwsA(
        isA<ApiException>().having((e) => e.code, 'code', 'DITHERING_NETWORK'),
      ),
    );
    expect(sent, hasLength(3));
  });

  test('基地址成功后缓存：第二次出帧不再取', () async {
    final frame = Uint8List.fromList(List<int>.generate(8, (i) => i));
    useClient((_) async => frameResponse(frame));
    await DitheringApi.requestFrameBin(filePath: imagePath, type: '0');
    await DitheringApi.requestFrameBin(filePath: imagePath, type: '0');
    expect(endpointSent, hasLength(1));
    expect(sent, hasLength(2));
  });

  test('反代域名带路径：基地址去尾 / 后照拼', () async {
    endpointHandle = (_) async =>
        json({'code': 0, 'data': 'https://proxy.example.com/api/'});
    final frame = Uint8List.fromList(List<int>.generate(8, (i) => i));
    useClient((_) async => frameResponse(frame));
    await DitheringApi.requestFrameBin(filePath: imagePath, type: '0');
    expect(
      '${sent.single.url.origin}${sent.single.url.path}',
      'https://proxy.example.com/api/Client/Basic/imageDitheringBinDownload',
    );
    expect(sent.single.url.queryParameters['userToken'], 'user-token');
  });

  test('取基地址失败（网络 / code≠0 / data 非地址）回落默认域名且不缓存', () async {
    final frame = Uint8List.fromList(List<int>.generate(8, (i) => i));
    useClient((_) async => frameResponse(frame));

    endpointHandle = (_) async => throw http.ClientException('timeout');
    await DitheringApi.requestFrameBin(filePath: imagePath, type: '0');
    expect(sent.last.url.origin, Uri.parse(ApiConfig.baseUrl).origin);

    endpointHandle = (_) async => json({'code': 500, 'msg': 'error'});
    await DitheringApi.requestFrameBin(filePath: imagePath, type: '0');
    expect(sent.last.url.origin, Uri.parse(ApiConfig.baseUrl).origin);

    endpointHandle = (_) async => json({'code': 0, 'data': 'not-a-url'});
    await DitheringApi.requestFrameBin(filePath: imagePath, type: '0');
    expect(sent.last.url.origin, Uri.parse(ApiConfig.baseUrl).origin);

    expect(endpointSent, hasLength(3), reason: '失败不缓存，每次重新取');
  });
}
