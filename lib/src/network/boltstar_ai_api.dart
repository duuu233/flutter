import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'api_session.dart';

/// BoltStar AI（星宝）第三方接口层。对齐小程序 `utils/ai-api.js`
/// （文档：`photo-album/assets/BoltStar-SSE-前端接入文档 -改.md` 与
/// `photo-album/docs/reference/ai/BoltStar-API-Doc-v2-1.0.4.md`，**当前对接版本**）。
///
/// **不复用 `ApiClient`**：AI 服务是独立第三方（阿里云 FC），Base URL、响应结构
/// （`success/code/data/params/detail`）、错误码体系都与 BoltFox 后端不同，
/// 公共参数（userToken/language 头）也不适用，硬塞进去只会两边互相迁就。
/// 失败一律抛 [AiApiException]，由 `features/ai/ai_i18n.dart` 按语种/区间分发提示。
///
/// ## 鉴权（2026-07-29 起网关强制）
/// 每个请求带 `Authentication: Bearer <jwtToken>`（注意是 **Authentication** 不是
/// Authorization），token 取自 [ApiSession]，与 BoltFox 后端用的是同一枚。
/// 缺失时网关直接回 `{Code: JWTTokenIsMissing}`，由 [gatewayErrorMessage] 转成可展示文案。
///
/// ⚠️ 这一段是 2026-08-07 才补上的：此前本文件**从未发送过该头**，而网关早在 07-29 就强制了。
/// 之所以一直没炸出来，只是因为 `features/ai/ai_entry.dart` 的 `kAiEntryEnabled = false`
/// 把入口整体屏蔽着。开放入口前这条必须在真机上验一次。
///
/// ## 流式（SSE）
/// 2026-08-07 起 `/chat` 走 SSE（[chatStream]），服务地址整体切到流式版部署 [baseUrl]。
/// 此前这里写着「小程序 `wx.request` 不支持 SSE，所以 App 也先不上」—— **该结论已作废**：
/// 小程序靠 `enableChunked` + `onChunkReceived` 早就收上流了，两端现在是同一条链路。
class BoltStarAiApi {
  BoltStarAiApi({required this.userId});

  /// AI 侧用户标识：`boltfox_<用户id>`（同一 user_id 多端历史互通，文档 §5.3.5）。
  /// 未登录时调用方应传入兜底值 `boltfox_demo_user`（见 [demoUserId]）。
  final String userId;

  /// 服务地址（流式版部署）。会话/历史/删除这些接口也都在这个域名下，
  /// 与 `/chat` 共用同一份会话数据。
  static const String baseUrl =
      'https://boltstagent-web-jncfttrxvt.ap-southeast-1.fcapp.run';

  /// 旧的非流式部署。只剩一个用途：[chat] 这条降级链路（流式异常时手动回退用），
  /// 两个部署是同一套服务、同一份会话数据，回退期间会话/历史不会对不上。
  static const String nonStreamBaseUrl =
      'https://boltstaat-agent-fwdomalzks.ap-southeast-1.fcapp.run';

  /// 未登录兜底 user_id（保证 demo 可跑通，对齐小程序 getAiUserId）。
  static const String demoUserId = 'boltfox_demo_user';

  /// 普通接口 15s。建会话/列表/历史这些秒级接口就该早点报错，让用户对着菊花等几分钟没意义。
  static const Duration defaultTimeout = Duration(seconds: 15);

  /// `/chat` 与 `/image/enhance` 涉及生图，放宽到 600s（对齐小程序）：切流式后长回复 + 生图
  /// 很容易顶到这条线，而流式下用户看得见进度，被前端掐断比干等更糟。
  ///
  /// ⚠️ 这只是**客户端**这一侧的上限。若真机失败稳定发生在明显更短的时刻（60s/180s 之类），
  /// 那是上游 FC 函数超时或网关空闲回收先跳了，调这个数字没用，得找后端。
  static const Duration generateTimeout = Duration(seconds: 600);

  /// 流式请求等**响应头**的超时。不能用 [defaultTimeout] 那 15s：SSE 的响应头虽然通常立刻
  /// 就回，但网关排队/冷启动时会拖，被 15s 掐掉会变成一个莫名其妙的 30002。
  static const Duration streamHeaderTimeout = Duration(seconds: 60);

  /// 流式收流的**空闲**超时：两个 chunk 之间超过这么久没动静就判定连接已死。
  /// 用空闲而非总时长，是因为 SSE 本来就会持续推进度事件；真卡死时也不必干等满 600s。
  /// 首个事件前的等待（约 15s，等 LLM 第一轮返回）远在这条线内。
  static const Duration streamIdleTimeout = Duration(seconds: 120);

  /// 阿里云网关 JWT 缺失错误的大写字段签名。
  ///
  /// BoltStar 自身使用 `{success, code, data, params, detail}`，这里仅对产品确认过
  /// 的固定 Code + Message 生成可展示文案。其它未知响应仍走标准兜底，不能借此
  /// 把任意网关字段或 [AiApiException.detail] 透传给用户。
  static const String _jwtTokenMissingCode = 'JWTTokenIsMissing';
  static const String _jwtTokenMissingMessage = 'the jwt token is missing';

  static String? gatewayErrorMessage(Map<String, dynamic>? body) {
    if (body == null ||
        body['Code'] != _jwtTokenMissingCode ||
        body['Message'] != _jwtTokenMissingMessage) {
      return null;
    }
    final requestId = body['RequestId']?.toString().trim() ?? '';
    return 'JWTTokenIsMissing：the jwt token is missing'
        '${requestId.isEmpty ? '' : '（RequestId: $requestId）'}';
  }

  /// 由用户 id 拼 AI 侧 user_id；[rawUserId] 为空时回退演示 id。
  static String userIdOf(String? rawUserId) {
    final id = (rawUserId ?? '').trim();
    return id.isEmpty ? demoUserId : 'boltfox_$id';
  }

  /// 请求头。每次现取 token（登录/退出后立即生效，不必重建 [BoltStarAiApi]）。
  ///
  /// 未登录（无 jwtToken）时**不带这个头照发**：网关会回 `JWTTokenIsMissing`，
  /// 走 [gatewayErrorMessage] 的白名单提示，不在端上另造一套错误。
  static Map<String, String> get _headers {
    final jwtToken = ApiSession.instance.jwtToken;
    return {
      'Content-Type': 'application/json',
      if (jwtToken.isNotEmpty) 'Authentication': 'Bearer $jwtToken',
    };
  }

  /// 响应结构兜底：流式版部署实测把 `/session/new` 的 `data.session` 包装层去掉了 ——
  /// 字段直接挂在 `data` 下，而文档 v1.0.4 §二写的仍是嵌套结构。两种都得吃：
  /// 先按文档取包装层，取不到就把 `data` 自己当结果。
  /// `/session/list`、`/chat/history` 是同样的「data 里再套一层」结构，一并兜住。
  static T? _unwrap<T>(
    Map<String, dynamic> body,
    String key,
    bool Function(Object?) isValid,
  ) {
    final data = body['data'];
    if (data is! Map) {
      // 扁平到极致：data 直接就是想要的东西（比如 sessions 直接是数组）
      return isValid(data) ? data as T : null;
    }
    final nested = data[key];
    if (isValid(nested)) {
      return nested as T;
    }
    return isValid(data) ? data as T : null;
  }

  /// 排障用：只留个头 + 总长度。响应体几十 KB，整段灌进日志既看不清也刷屏。
  static String _preview(String value, {int limit = 200}) {
    return value.length > limit
        ? '${value.substring(0, limit)}…(共 ${value.length} 字符)'
        : value;
  }

  // ── 基础请求 ─────────────────────────────────────────────

  /// 发一次请求并返回**整个响应体**（`code=10001`「历史已过期」这类「成功但带语义」的场景
  /// 需要调用方看 code，所以不只回 data）。
  ///
  /// 返回的 [AiCall] 带 [AiCall.abort]，供「停止生成」中断在途请求：
  /// `http.Client.close()` 对 IOClient 是 `force: true`，在途请求会立即断开。
  AiCall<Map<String, dynamic>> _request({
    required String path,
    String method = 'POST',
    Map<String, dynamic>? body,
    Duration? timeout,
    String? base,
  }) {
    final client = http.Client();
    var aborted = false;
    final uri = Uri.parse('${base ?? baseUrl}$path');
    final headers = _headers;
    final payload = body == null ? null : jsonEncode(body);

    Future<http.Response> send() {
      switch (method) {
        case 'GET':
          return client.get(uri, headers: headers);
        case 'DELETE':
          return client.delete(uri, headers: headers, body: payload);
        default:
          return client.post(uri, headers: headers, body: payload);
      }
    }

    Future<Map<String, dynamic>> run() async {
      http.Response response;
      try {
        response = await send().timeout(timeout ?? defaultTimeout);
      } on Object catch (error) {
        // 用户主动终止：用专有标记让调用方静默处理，不弹错误提示
        if (aborted) {
          throw const AiApiException.aborted();
        }
        // 网络失败/超时归为「响应超时」30002，提示语可重试
        throw AiApiException(code: 30002, detail: '$error');
      } finally {
        client.close();
      }

      Map<String, dynamic>? json;
      try {
        final decoded = jsonDecode(utf8.decode(response.bodyBytes));
        if (decoded is Map<String, dynamic>) {
          json = decoded;
        }
      } catch (_) {
        json = null;
      }
      final gatewayMessage = gatewayErrorMessage(json);
      if (gatewayMessage != null) {
        throw AiApiException(
          code: 31001,
          detail: gatewayMessage,
          userMessage: gatewayMessage,
        );
      }
      if (response.statusCode == 200 &&
          json != null &&
          json['success'] == true) {
        return json;
      }
      final code = json == null ? null : json['code'];
      if (code != null) {
        throw AiApiException(
          code: int.tryParse('$code') ?? 31001,
          params: json?['params'] is Map
              ? Map<String, dynamic>.from(json!['params'] as Map)
              : null,
          detail: json?['detail']?.toString(),
        );
      }
      // 非标响应（网关 502 等）归为上游错误
      throw AiApiException(
        code: 30001,
        detail: 'HTTP ${response.statusCode}',
      );
    }

    return AiCall<Map<String, dynamic>>(run(), () {
      aborted = true;
      client.close();
    });
  }

  Future<Map<String, dynamic>> _await({
    required String path,
    String method = 'POST',
    Map<String, dynamic>? body,
    Duration? timeout,
  }) {
    return _request(path: path, method: method, body: body, timeout: timeout)
        .future;
  }

  // ── 会话 ─────────────────────────────────────────────────

  /// `POST /session/new` — 新建会话。
  ///
  /// `title` 默认「新对话」，后端在首条用户消息后自动填成该消息**前 20 字**（v1.0.4 §二）。
  ///
  /// ⚠️ **每个用户最多 20 个会话**（v1.0.4 §5.2），超限抛 code=20013 `MAX_SESSIONS_REACHED`；
  /// 重试对它没意义，调用方应传 `onSessionLimit` 把用户引到会话列表页删旧的
  /// （见 `features/ai/ai_i18n.dart handleError`）。这也是为什么建会话被收敛到
  /// **只有「首次发送」一个时机**（见 `ai_chat_page._createSession` 上方注释）：
  /// 进页面/点「新对话」就先建，用户看看就走会白占额度。
  Future<AiSession> newSession() async {
    final body = await _await(path: '/session/new', body: {'user_id': userId});
    // 嵌套（data.session，文档 v1.0.4）与扁平（字段直接在 data 上，流式版部署实测）都认
    final session = _unwrap<Map>(
      body,
      'session',
      (value) =>
          value is Map && '${value['session_id'] ?? ''}'.isNotEmpty,
    );
    if (session == null) {
      // 两种结构都对不上（又改协议了）：别让调用方拿着空 sessionId 往下跑，
      // 那会在 /chat 上以一个不知所云的错误爆出来。按上游错误抛，日志里留 detail 好定位。
      throw const AiApiException(code: 30001, detail: 'SESSION_MISSING');
    }
    return AiSession.fromJson(Map<String, dynamic>.from(session));
  }

  /// `GET /session/list` — 会话列表（后端按更新时间倒序）。
  Future<List<AiSession>> listSessions() async {
    final body = await _await(
      path: '/session/list?user_id=${Uri.encodeQueryComponent(userId)}',
      method: 'GET',
    );
    // data.sessions（文档）与 data 直接是数组（若后端同样扁平化）都认
    final list = _unwrap<List>(body, 'sessions', (value) => value is List);
    if (list == null) {
      return const [];
    }
    return list
        .whereType<Map>()
        .map((item) => AiSession.fromJson(Map<String, dynamic>.from(item)))
        .toList();
  }

  /// `DELETE /session` — 删除会话（含全部历史，不可恢复）。
  Future<void> deleteSession(String sessionId) async {
    await _await(
      path: '/session',
      method: 'DELETE',
      body: {'user_id': userId, 'session_id': sessionId},
    );
  }

  // ── 消息历史 ──────────────────────────────────────────────

  /// `GET /chat/history` — 拉取历史（**时间倒序**分页）。
  /// `expired=true` 即 code=10001（超 7 天自动清除），调用方按文档 toast `info.10001`。
  Future<AiHistory> getHistory(
    String sessionId, {
    int page = 1,
    int pageSize = 20,
  }) async {
    final query = <String>[
      'user_id=${Uri.encodeQueryComponent(userId)}',
      'session_id=${Uri.encodeQueryComponent(sessionId)}',
      'page=$page',
      'page_size=$pageSize',
    ].join('&');
    final body = await _await(path: '/chat/history?$query', method: 'GET');
    final data = body['data'];
    // data.data（文档）与 data 直接是数组（若后端同样扁平化）都认
    final list = _unwrap<List>(body, 'data', (value) => value is List);
    return AiHistory(
      expired: '${body['code']}' == '10001',
      list: list == null
          ? const []
          : list
                .whereType<Map>()
                .map(
                  (item) =>
                      AiHistoryItem.fromJson(Map<String, dynamic>.from(item)),
                )
                .toList(),
      // 扁平结构下没有 total 这个字段。不拿 list.length 顶替：会话列表页用 page_size=1
      // 探总数，顶替出来的 1 会被当成「1 条消息」显示，比不显示更糟。
      total: data is Map ? (int.tryParse('${data['total']}') ?? 0) : 0,
    );
  }

  /// `DELETE /chat/history` — 删除单条消息。
  Future<void> deleteMessage(String sessionId, String messageId) async {
    await _await(
      path: '/chat/history',
      method: 'DELETE',
      body: {
        'user_id': userId,
        'session_id': sessionId,
        'message_id': messageId,
      },
    );
  }

  // ⚠️ 2026-07-25 起本模块**不再提供任何「清空」能力**（对齐小程序）：会话级「清空全部」已下线，
  //    消息级 `clearHistory()`（`DELETE /chat/history/clear`）也一并删除（本就全项目无调用）。
  //    理由：接口没有批量删除，只能 for 循环串行打 DELETE（最坏 20 个请求），中途失败会留下
  //    「删了一半且无法回滚」的状态。清理一律逐条删：会话用 [deleteSession]、消息用 [deleteMessage]。
  //    别再加回来，见 photo-album/docs/2026-07-24-AI模块开发进度.md。

  // ── 对话 / 生图 ───────────────────────────────────────────

  /// `/chat` 的请求体。流式与非流式**完全一致**（接入文档：请求参数一个字没动）。
  Map<String, dynamic> _chatPayload({
    required String sessionId,
    required String message,
    required String imgOrientation,
    String? imgStyle,
    String? modelType,
    List<String> imageUrls = const [],
    double? temperature,
  }) {
    return {
      'user_id': userId,
      // 2026-08-12 新增：小程序/APP 登录接口下发的 `userToken`（BoltFox 的公共参数那一枚，
      // **不是** Authentication 头里的 jwtToken），AI 网关拿它回 BoltFox 侧核对用户与扣费。
      // ⚠️ 参数名按 AI 侧要求是**全小写 `usertoken`**，别顺手改成驼峰——服务端按字面取，
      // 名字或取值错了都不会报错，只会静默变成「服务端认不出这个用户」。
      // 未登录时是空串，仍原样发出：让服务端自己判，比端上悄悄省掉字段好排查
      //（何况未登录时 Authentication 头也缺，网关那关先就过不去）。
      'usertoken': ApiSession.instance.userToken,
      'session_id': sessionId,
      'message': message,
      'img_orientation': imgOrientation,
      if (imgStyle != null && imgStyle.isNotEmpty) 'img_style': imgStyle,
      // 生图模型档位（lite / pro，**不传即 pro**）。页面暂无选档入口，所以正常情况下
      // 这一项不会出现在请求体里，行为与加这个参数之前完全一致。
      if (modelType != null && modelType.isNotEmpty) 'model_type': modelType,
      if (imageUrls.isNotEmpty) 'image_urls': imageUrls,
      if (temperature != null) 'temperature': temperature,
    };
  }

  /// `POST /chat`（**流式 SSE，当前主链路**）— 对话 / 一键生图 / 图文多模态。
  ///
  /// [onEvent] 逐个收原始事件：
  /// - `pre_text {content}` 预描述。推**两条**：先秒回一句占位的「星宝努力思考创作中」，
  ///   约 3s 后 LLM 出结果再推真文案。调用方直接覆盖即可，不必分辨是哪一条；
  /// - `progress {progress, stage, message}` 里程碑，只有 5/15/30/45/50/80/85/90/100 这几级
  ///   （中间读数要调用方自己补，见 `ai_chat_page` 的 `_pumpProgress`）。
  ///   `message` 是服务端下发的进度文案，有就直接显示，不必再自己维护 stage→文案 映射表；
  /// - `image {content}` 生成图 URL，排在 `progress 90 (uploaded)` **之后**，不是 50%
  ///   （50 那级只是初稿完成，图还没下载上传完、URL 拿不到）；
  /// - `text {content}` 回复文字，每次 1~3 字，调用方自行追加渲染；
  /// - `done {orientation}` 结束。
  ///
  /// 同时把 text/image 汇总成与 [chat] 一样的 [AiChatReply] 返回，供调用方兜底校对。
  /// 返回的 [AiCall] 带 `abort()`，页面「停止生成」时调用。
  AiCall<AiChatReply> chatStream({
    required String sessionId,
    required String message,
    required String imgOrientation,
    String? imgStyle,
    String? modelType,
    List<String> imageUrls = const [],
    double? temperature,
    void Function(AiStreamEvent event)? onEvent,
  }) {
    final client = http.Client();
    var aborted = false;

    Future<AiChatReply> run() async {
      final textBuffer = StringBuffer();
      final images = <String>[];
      var orientation = '';
      var done = false;
      var eventCount = 0;
      AiApiException? streamError;
      // 原始文本只在「还没解析出任何事件」时留着（用来把非 SSE 的错误体解出来）。
      // 正常流一旦跑起来就别再攒了，几十 KB 的回复没必要在内存里存两份。
      final rawBuffer = StringBuffer();

      final parser = AiSseParser((json) {
        eventCount += 1;
        final event = AiStreamEvent.fromJson(json);
        switch (event.type) {
          case 'text':
            textBuffer.write(event.content);
          case 'image':
            if (event.content.isNotEmpty) {
              images.add(event.content);
            }
          case 'done':
            done = true;
            if (event.orientation.isNotEmpty) {
              orientation = event.orientation;
            }
          case 'error':
            // 服务端在流里报错（事件形状未在文档中固定，尽量兼容）
            streamError = AiApiException(
              code: event.code ?? 30001,
              detail: event.detail.isNotEmpty ? event.detail : 'stream error',
            );
          default:
            break;
        }
        // 回调抛错不能连累整条流（页面 setState 出问题时尤其）
        try {
          onEvent?.call(event);
        } catch (error) {
          debugPrint('[BoltStar] SSE 事件处理异常 $error');
        }
      });

      http.StreamedResponse response;
      try {
        final request = http.Request('POST', Uri.parse('$baseUrl/chat'))
          ..headers.addAll(_headers)
          ..body = jsonEncode(
            _chatPayload(
              sessionId: sessionId,
              message: message,
              imgOrientation: imgOrientation,
              imgStyle: imgStyle,
              modelType: modelType,
              imageUrls: imageUrls,
              temperature: temperature,
            ),
          );
        response = await client.send(request).timeout(streamHeaderTimeout);
      } on Object catch (error) {
        client.close();
        if (aborted) {
          throw const AiApiException.aborted();
        }
        throw AiApiException(code: 30002, detail: '$error');
      }

      // 非 200 一律不是 SSE，是网关/服务端直接回的 JSON 错误体：整段读出来按它报错
      if (response.statusCode != 200) {
        String body;
        try {
          body = await response.stream.transform(_utf8Stream).join();
        } on Object {
          body = '';
        } finally {
          client.close();
        }
        throw _errorFromBody(body) ??
            AiApiException(
              code: 30001,
              detail: 'HTTP ${response.statusCode} body=${_preview(body)}',
            );
      }

      try {
        // ⚠️ 多字节字符必然被切在 chunk 边界上（一个汉字 3 字节）。Dart 的 [Utf8Decoder]
        // 作为流转换器**自带跨块续接**（内部保留半个序列等下一块），所以这里不必像小程序
        // 那样手写字节缓存 —— 但顺序不能反：必须先 timeout(字节流) 再 transform(解码)。
        await for (final chunk
            in response.stream.timeout(streamIdleTimeout).transform(
              _utf8Stream,
            )) {
          if (eventCount == 0) {
            rawBuffer.write(chunk);
          }
          parser.push(chunk);
        }
      } on Object catch (error) {
        if (aborted) {
          throw const AiApiException.aborted();
        }
        // 流中途断了。已经吐出过事件的话页面上是有内容的，仍按错误抛，
        // 由页面决定「保留已上屏的部分 + 提示一句」还是整条换失败卡。
        throw AiApiException(code: 30002, detail: '$error');
      } finally {
        client.close();
      }

      parser.flush();
      final error = streamError;
      if (error != null) {
        throw error;
      }

      if (eventCount == 0) {
        final body = rawBuffer.toString();
        // 最后一搏：服务端曾把事件分隔符转义成**字面的 `\n`**（反斜杠 + n 两个字符），
        // 整个响应体成了一行、一个真换行都没有，解析器一个事件都拿不到。
        // 只在这条「否则必然失败」的路径上还原一次，正常流一步都不碰。
        if (kEscapedEventSeparator.hasMatch(body)) {
          parser.push(unescapeEventSeparators(body));
          parser.flush();
        }
        if (eventCount > 0) {
          debugPrint(
            '[BoltStar] 响应体的事件分隔符是字面 \\n 而非真换行（SSE 格式不合规，需后端修）；'
            '已还原并解析出 $eventCount 个事件，本次无逐字流式效果',
          );
          final lateError = streamError;
          if (lateError != null) {
            throw lateError;
          }
        } else {
          // 还原也救不回来：多半是服务端直接回了 JSON（错误体），按它报错；
          // 都不是的话就是响应体形状不对，把开头一并带上，一次就能定位。
          throw _errorFromBody(body) ??
              AiApiException(
                code: 30001,
                detail: 'EMPTY_STREAM body=${_preview(body)}',
              );
        }
      }

      return AiChatReply(
        text: textBuffer.toString(),
        images: images,
        orientation: orientation,
        done: done,
      );
    }

    return AiCall<AiChatReply>(run(), () {
      aborted = true;
      client.close();
    });
  }

  /// 流式响应里混进来的**非 SSE** 响应体（网关 403 JSON、服务端直接回业务错误 JSON）。
  static AiApiException? _errorFromBody(String text) {
    if (text.trim().isEmpty) {
      return null;
    }
    Map<String, dynamic>? json;
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map<String, dynamic>) {
        json = decoded;
      }
    } catch (_) {
      return null;
    }
    final gatewayMessage = gatewayErrorMessage(json);
    if (gatewayMessage != null) {
      return AiApiException(
        code: 31001,
        detail: gatewayMessage,
        userMessage: gatewayMessage,
      );
    }
    if (json != null && json['success'] == false && json['code'] != null) {
      return AiApiException(
        code: int.tryParse('${json['code']}') ?? 31001,
        params: json['params'] is Map
            ? Map<String, dynamic>.from(json['params'] as Map)
            : null,
        detail: json['detail']?.toString(),
      );
    }
    return null;
  }

  /// `POST /chat`（非流式）— **仅降级用**：流式在某些网络环境下异常时手动回退这条链路。
  ///
  /// - [imgOrientation] **必传**：vertical / horizontal / square；
  /// - [imgStyle] 仅一键生图传：cartoon / landscape / portrait / anime（文档 §5.3.2）；
  /// - [imageUrls] 图文多模态（v1.0.3 §二）：最多 4 张，服务端按「张数 + 生图关键词」自行分流
  ///   （1 张+关键词=图生图美化 / 多张+关键词=友好拒绝 / 其余=分析讨论），**前端不判关键词**；
  ///   超 4 张服务端回 20012，页面已在选图时拦截。
  ///
  /// 返回的 [AiCall] 带 `abort()`，页面「停止生成」调用。
  ///
  /// ⚠️ v1.0.4 起 `new_session` 参数**已废弃**（会话是不是新的由后端自己判断），入参一并删除。
  /// 同时「你好，我是星宝✨」这句自我介绍接口也**不再返回**了——它是纯前端静态展示
  /// （`ai_chat_page` 的招呼语空态），所以 [AiChatReply.text] 里不会再带招呼语前缀，别去剥它。
  AiCall<AiChatReply> chat({
    required String sessionId,
    required String message,
    required String imgOrientation,
    String? imgStyle,
    String? modelType,
    List<String> imageUrls = const [],
    double? temperature,
  }) {
    final call = _request(
      path: '/chat',
      // 非流式响应只有旧部署给得了，这里显式打回旧地址（见 [nonStreamBaseUrl]）
      base: nonStreamBaseUrl,
      body: _chatPayload(
        sessionId: sessionId,
        message: message,
        imgOrientation: imgOrientation,
        imgStyle: imgStyle,
        modelType: modelType,
        imageUrls: imageUrls,
        temperature: temperature,
      ),
      timeout: generateTimeout,
    );
    return AiCall<AiChatReply>(
      call.future.then((body) {
        final data = body['data'];
        final images = data is Map ? data['images'] : null;
        return AiChatReply(
          text: data is Map ? (data['text']?.toString() ?? '') : '',
          images: images is List
              ? images.map((e) => e.toString()).where((e) => e.isNotEmpty).toList()
              : const [],
        );
      }),
      call.abort,
    );
  }

  /// `POST /image/enhance` — 图片美化（图生图）。[imageUrl] 须是可公网访问的地址
  /// （先经 `setFileUpload` 上传原图拿 URL）。
  ///
  /// v1.0.3 起主链路改走 [chat] 的 `image_urls`（覆盖多图讨论/拒绝等全部场景），
  /// 本接口保留作独立入口。
  AiCall<String> enhanceImage(String imageUrl, {String? prompt}) {
    final call = _request(
      path: '/image/enhance',
      body: {
        'user_id': userId,
        'image_url': imageUrl,
        if (prompt != null && prompt.isNotEmpty) 'prompt': prompt,
      },
      timeout: generateTimeout,
    );
    return AiCall<String>(
      call.future.then((body) {
        final data = body['data'];
        return data is Map ? (data['image']?.toString() ?? '') : '';
      }),
      call.abort,
    );
  }
}

/// 收流用的 UTF-8 解码器。`allowMalformed: true` 是有意的：单个坏字节不该把整条流带崩，
/// 顶多糊一个字符。作为流转换器时它**自带跨块续接**，半个多字节序列会留到下一块再拼。
const Utf8Decoder _utf8Stream = Utf8Decoder(allowMalformed: true);

/// 服务端曾把 SSE 的事件分隔符转义成**字面的 `\n`**（反斜杠 + n 两个字符），
/// 整个响应体成了一行、一个真换行都没有 —— 解析器一个事件都拿不到。
///
/// ⚠️ 只还原**当分隔符用的**那些：即后面紧跟着 `data:`（中间可以再夹几个）或者已经到结尾的。
/// JSON 字符串正文里的 `\n`（回复文字本身带换行时就长这样）必须原样留着，
/// 否则会把一个事件的 JSON 从中间劈开，反而更糟。
final RegExp kEscapedEventSeparator = RegExp(r'\\n(?=(?:\\n)*(?:data:|$))');

String unescapeEventSeparators(String text) =>
    text.replaceAll(kEscapedEventSeparator, '\n');

/// SSE `data:` 行解析器。
///
/// 抽成独立类有两个理由：一是收流与解析可以分开测（不必起真网络，见
/// `test/boltstar_ai_sse_test.dart`）；二是「chunk 边界不保证落在行尾」这条约束
/// 只在这里体现，不必散到调用处。
class AiSseParser {
  AiSseParser(this.onEvent);

  final void Function(Map<String, dynamic> event) onEvent;

  /// 上一块结尾那半行，等下一块来拼。
  String _pending = '';

  void push(String text) {
    if (text.isEmpty) {
      return;
    }
    _pending += text;
    final lines = _pending.split('\n');
    _pending = lines.removeLast(); // 最后一行可能不完整
    for (final line in lines) {
      _emit(line);
    }
  }

  /// 连接结束时把残留的最后一行也吐出去（服务端最后一条没带换行时用得上）。
  void flush() {
    final rest = _pending;
    _pending = '';
    if (rest.trim().isNotEmpty) {
      _emit(rest);
    }
  }

  void _emit(String raw) {
    final line = raw.endsWith('\r')
        ? raw.substring(0, raw.length - 1)
        : raw;
    if (!line.startsWith('data:')) {
      return; // event:/id:/retry:/注释行/空行，本协议用不上
    }
    // 按 `data:` 之后 trim，而不是写死 slice(6)：服务端哪天不带那个空格也照样认
    final payload = line.substring(5).trim();
    if (payload.isEmpty || payload == '[DONE]') {
      return;
    }
    try {
      final decoded = jsonDecode(payload);
      if (decoded is Map<String, dynamic>) {
        onEvent(decoded);
      }
    } catch (_) {
      // 半条/脏数据：丢掉这一行就好，别把整条流带崩
      debugPrint('[BoltStar] SSE 数据行解析失败 ${BoltStarAiApi._preview(payload)}');
    }
  }
}

/// 一个 SSE 事件。字段按 [type] 取用，缺的给空值 —— 未知类型也照样构造出来，
/// 原样透传给页面，别在这一层把没见过的事件吃掉。
class AiStreamEvent {
  const AiStreamEvent({
    required this.type,
    this.content = '',
    this.progress,
    this.stage = '',
    this.message = '',
    this.orientation = '',
    this.mode = '',
    this.code,
    this.detail = '',
  });

  factory AiStreamEvent.fromJson(Map<String, dynamic> json) {
    return AiStreamEvent(
      type: json['type']?.toString() ?? '',
      content: json['content']?.toString() ?? '',
      progress: json['progress'] == null
          ? null
          : num.tryParse('${json['progress']}')?.toDouble(),
      stage: json['stage']?.toString() ?? '',
      message: json['message']?.toString() ?? '',
      orientation: json['orientation']?.toString() ?? '',
      // `mode` 事件的取值。同时认塞在 `content` 里的写法（对齐小程序取值方式）。
      mode: (json['mode'] ?? json['content'] ?? '').toString(),
      code: json['code'] == null ? null : int.tryParse('${json['code']}'),
      detail:
          json['detail']?.toString() ??
          json['message']?.toString() ??
          json['content']?.toString() ??
          '',
    );
  }

  final String type;
  final String content;
  final double? progress;
  final String stage;

  /// 服务端下发的进度文案（2026-08-07 新增）。有就直接显示，不必再自己维护 stage→文案 映射。
  final String message;
  final String orientation;

  /// 仅 `mode` 事件带（服务端 2026-08-07 新增）：`image` = 这一轮出图、`text` = 纯文字。
  /// 空串 = 没收到（老部署不推这个事件），调用方按「未知」兜底。
  final String mode;

  /// 仅 `error` 事件带。
  final int? code;
  final String detail;
}

/// 一次可中断的 AI 请求：[future] 拿结果，[abort] 主动终止（对齐小程序 promise.abort()）。
class AiCall<T> {
  const AiCall(this.future, this.abort);

  final Future<T> future;
  final void Function() abort;
}

/// AI 接口错误：`code` 决定提示文案与处理方式（见 `features/ai/ai_i18n.dart`）。
/// [detail] 是**排障信息，严禁展示给用户**（文档红线），只打日志。
/// [userMessage] 只允许由请求层对白名单网关响应生成，不接受任意服务端详情。
class AiApiException implements Exception {
  const AiApiException({
    required this.code,
    this.params,
    this.detail,
    this.userMessage,
  }) : aborted = false;

  /// 用户主动「停止生成」：调用方应静默处理，不弹任何提示。
  const AiApiException.aborted()
    : code = 0,
      params = null,
      detail = 'aborted',
      userMessage = null,
      aborted = true;

  final int code;
  final Map<String, dynamic>? params;
  final String? detail;
  final String? userMessage;
  final bool aborted;

  @override
  String toString() => 'AiApiException(code: $code, detail: $detail)';
}

/// 会话摘要（`/session/new`、`/session/list`）。
class AiSession {
  const AiSession({
    required this.sessionId,
    required this.title,
    required this.msgCount,
    required this.updatedAt,
  });

  factory AiSession.fromJson(Map<String, dynamic> json) {
    return AiSession(
      sessionId: json['session_id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      msgCount: int.tryParse('${json['msg_count']}') ?? 0,
      updatedAt:
          json['updated_at']?.toString() ?? json['created_at']?.toString() ?? '',
    );
  }

  final String sessionId;
  final String title;
  final int msgCount;

  /// ISO 时间串（列表页按「今天 HH:mm / 其余 MM-DD HH:mm」展示）。
  final String updatedAt;
}

/// 一条历史消息。`role=assistant` 且 `content` 以 http 开头即图片（文档 §6.5）。
class AiHistoryItem {
  const AiHistoryItem({
    required this.id,
    required this.role,
    required this.content,
  });

  factory AiHistoryItem.fromJson(Map<String, dynamic> json) {
    return AiHistoryItem(
      id: json['id']?.toString() ?? '',
      role: json['role']?.toString() ?? 'assistant',
      content: json['content']?.toString() ?? '',
    );
  }

  final String id;
  final String role;
  final String content;
}

class AiHistory {
  const AiHistory({
    required this.expired,
    required this.list,
    required this.total,
  });

  final bool expired;
  final List<AiHistoryItem> list;
  final int total;
}

/// `/chat` 的回复：文字 + 生成的图片地址（可能只有其一）。
///
/// 流式（[BoltStarAiApi.chatStream]）下这是**汇总结果**：事件已经逐个回调过了，
/// 这里再给一份完整的，供调用方兜底校对（比如某个 image 事件漏了，用它补上）。
/// [orientation] / [done] 只有流式会填。
class AiChatReply {
  const AiChatReply({
    required this.text,
    required this.images,
    this.orientation = '',
    this.done = false,
  });

  final String text;
  final List<String> images;
  final String orientation;
  final bool done;
}
