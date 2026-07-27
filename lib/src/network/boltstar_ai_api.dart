import 'dart:convert';

import 'package:http/http.dart' as http;

/// BoltStar AI（星宝）第三方接口层。对齐小程序 `utils/ai-api.js`
/// （文档：`photo-album/assets/ai/BoltStar-API-Doc-v2-1.0.4.md`，**当前对接版本**）。
///
/// **不复用 `ApiClient`**：AI 服务是独立第三方（阿里云 FC），Base URL、响应结构
/// （`success/code/data/params/detail`）、错误码体系都与 BoltFox 后端不同，
/// 公共参数（userToken/language 头）也不适用，硬塞进去只会两边互相迁就。
/// 失败一律抛 [AiApiException]，由 `features/ai/ai_i18n.dart` 按语种/区间分发提示。
///
/// ## 流式 vs 非流式
/// 小程序 `wx.request` 不支持 SSE，只能走非流式 URL + 客户端打字机；**App 侧本可以走流式**，
/// 但本轮先与小程序保持同一条链路（非流式 + 打字机），避免两端表现不一致、也少一处联调面。
/// 流式 Base URL 保留在 [streamBaseUrl] 备后续启用。
class BoltStarAiApi {
  BoltStarAiApi({required this.userId});

  /// AI 侧用户标识：`boltfox_<用户id>`（同一 user_id 多端历史互通，文档 §5.3.5）。
  /// 未登录时调用方应传入兜底值 `boltfox_demo_user`（见 [demoUserId]）。
  final String userId;

  static const String nonStreamBaseUrl =
      'https://boltstaat-agent-fwdomalzks.ap-southeast-1.fcapp.run';

  /// 流式（SSE）地址，本轮未启用，勿在本文件内使用。
  static const String streamBaseUrl =
      'https://boltstagent-web-jncfttrxvt.ap-southeast-1.fcapp.run';

  /// 未登录兜底 user_id（保证 demo 可跑通，对齐小程序 getAiUserId）。
  static const String demoUserId = 'boltfox_demo_user';

  /// 普通接口 15s；`/chat` 与 `/image/enhance` 涉及生图（上游文生图可能 30s+）放宽到 120s。
  static const Duration defaultTimeout = Duration(seconds: 15);
  static const Duration generateTimeout = Duration(seconds: 120);

  /// 由用户 id 拼 AI 侧 user_id；[rawUserId] 为空时回退演示 id。
  static String userIdOf(String? rawUserId) {
    final id = (rawUserId ?? '').trim();
    return id.isEmpty ? demoUserId : 'boltfox_$id';
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
  }) {
    final client = http.Client();
    var aborted = false;
    final uri = Uri.parse('$nonStreamBaseUrl$path');
    const headers = {'Content-Type': 'application/json'};
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
      if (response.statusCode == 200 && json != null && json['success'] == true) {
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
    final data = body['data'];
    final session = data is Map ? data['session'] : null;
    return AiSession.fromJson(
      session is Map ? Map<String, dynamic>.from(session) : const {},
    );
  }

  /// `GET /session/list` — 会话列表（后端按更新时间倒序）。
  Future<List<AiSession>> listSessions() async {
    final body = await _await(
      path: '/session/list?user_id=${Uri.encodeQueryComponent(userId)}',
      method: 'GET',
    );
    final data = body['data'];
    final list = data is Map ? data['sessions'] : null;
    if (list is! List) {
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
    final list = data is Map ? data['data'] : null;
    return AiHistory(
      expired: '${body['code']}' == '10001',
      list: list is List
          ? list
                .whereType<Map>()
                .map(
                  (item) =>
                      AiHistoryItem.fromJson(Map<String, dynamic>.from(item)),
                )
                .toList()
          : const [],
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

  /// `POST /chat`（非流式）— 对话 / 一键生图 / 图文多模态。
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
    List<String> imageUrls = const [],
    double? temperature,
  }) {
    final call = _request(
      path: '/chat',
      body: {
        'user_id': userId,
        'session_id': sessionId,
        'message': message,
        'img_orientation': imgOrientation,
        if (imgStyle != null && imgStyle.isNotEmpty) 'img_style': imgStyle,
        if (imageUrls.isNotEmpty) 'image_urls': imageUrls,
        if (temperature != null) 'temperature': temperature,
      },
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

/// 一次可中断的 AI 请求：[future] 拿结果，[abort] 主动终止（对齐小程序 promise.abort()）。
class AiCall<T> {
  const AiCall(this.future, this.abort);

  final Future<T> future;
  final void Function() abort;
}

/// AI 接口错误：`code` 决定提示文案与处理方式（见 `features/ai/ai_i18n.dart`）。
/// [detail] 是**排障信息，严禁展示给用户**（文档红线），只打日志。
class AiApiException implements Exception {
  const AiApiException({required this.code, this.params, this.detail})
    : aborted = false;

  /// 用户主动「停止生成」：调用方应静默处理，不弹任何提示。
  const AiApiException.aborted()
    : code = 0,
      params = null,
      detail = 'aborted',
      aborted = true;

  final int code;
  final Map<String, dynamic>? params;
  final String? detail;
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
class AiChatReply {
  const AiChatReply({required this.text, required this.images});

  final String text;
  final List<String> images;
}
