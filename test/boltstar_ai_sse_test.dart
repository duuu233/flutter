import 'dart:convert';

import 'package:BoltStar/src/network/boltstar_ai_api.dart';
import 'package:flutter_test/flutter_test.dart';

/// 按 `photo-album/assets/BoltStar-SSE-前端接入文档 -改.md` §二「SSE 事件类型」逐条核对解析层。
/// 文档里的原始报文直接抄进来当用例，服务端改格式时这里先红。
///
/// 覆盖几处文档与标准 SSE 不一致、容易踩的地方：
/// - 文档的完整流示例用**单个 `\n`** 分隔事件（标准 SSE 是空行 `\n\n`）——两种都得吃；
/// - 报文里 `data: ` 带空格，而文档示例代码写死 `slice(6)`——我们按 `substring(5).trim()` 更稳；
/// - 多字节字符（汉字 3 字节 / emoji 4 字节）必然被 chunk 边界劈开，不能吐出半个字符；
/// - 服务端曾把事件分隔符转义成**字面 `\n`**，整个响应体成了一行。

/// 逐块把解码结果转给回调的 sink（生产里这个位置是 `parser.push`）。
class _ChunkSink implements Sink<String> {
  _ChunkSink(this.onChunk);

  final void Function(String chunk) onChunk;

  @override
  void add(String data) => onChunk(data);

  @override
  void close() {}
}

void main() {
  /// 把报文按**字节**切块喂进解析器，模拟真机收流 —— 汉字/emoji 必然被劈在块边界上。
  /// 解码走与生产同一条链路（[Utf8Decoder] 的分块转换），验的就是它的跨块续接。
  ///
  /// ⚠️ 这里不能用 `StringConversionSink.withCallback`：它是**攒到 close 才回调一次**，
  /// 那样就等于整段解码，跨块续接根本没被验到。必须用逐块 add 的 sink。
  List<Map<String, dynamic>> collect(
    List<String> lines, {
    String sep = '\n',
    int chunkSize = 7,
  }) {
    final events = <Map<String, dynamic>>[];
    final parser = AiSseParser(events.add);
    final decoder = const Utf8Decoder(
      allowMalformed: true,
    ).startChunkedConversion(_ChunkSink(parser.push));

    final bytes = utf8.encode(lines.join(sep) + sep);
    for (var i = 0; i < bytes.length; i += chunkSize) {
      final end = i + chunkSize > bytes.length ? bytes.length : i + chunkSize;
      decoder.add(bytes.sublist(i, end));
    }
    decoder.close();
    parser.flush();
    return events;
  }

  // ── 文档 §二 完整 SSE 流示例（生图场景），原文照抄 ──
  const docImageFlow = [
    'data: {"type":"pre_text","content":"正在为您绘制软萌可爱的小猫画面…"}',
    'data: {"type":"progress","progress":5,"stage":"starting"}',
    'data: {"type":"progress","progress":5,"stage":"request_sent"}',
    'data: {"type":"progress","progress":15,"stage":"generating"}',
    // 2026-08-07 服务端在 progress 上新增 message（文案改由后端下发）
    'data: {"type":"progress","progress":30,"stage":"generating","message":"正在创作图片"}',
    'data: {"type":"progress","progress":45,"stage":"generating"}',
    'data: {"type":"progress","progress":50,"stage":"partial_succeeded"}',
    'data: {"type":"progress","progress":80,"stage":"completed"}',
    'data: {"type":"progress","progress":85,"stage":"downloading"}',
    'data: {"type":"progress","progress":90,"stage":"uploaded"}',
    'data: {"type":"image","content":"https://inkstar.oss-.../xxx.jpg?…签名"}',
    'data: {"type":"text","content":"画面里"}',
    'data: {"type":"text","content":"是软乎乎"}',
    'data: {"type":"text","content":"的橘白奶猫。"}',
    'data: {"type":"progress","progress":100,"stage":"done"}',
    'data: {"type":"done","orientation":"square"}',
  ];

  const docTextFlow = [
    'data: {"type":"text","content":"你好呀"}',
    'data: {"type":"text","content":"😊我是星宝"}',
    'data: {"type":"text","content":"…"}',
    'data: {"type":"done","orientation":"square"}',
  ];

  group('AiSseParser', () {
    test('单 \\n 分隔（文档示例就是这么写的）', () {
      final events = collect(docImageFlow);
      expect(events.length, 16);
      expect(events.first['type'], 'pre_text');
      expect(events.first['content'], '正在为您绘制软萌可爱的小猫画面…');

      final text = events
          .where((e) => e['type'] == 'text')
          .map((e) => e['content'])
          .join();
      expect(text, '画面里是软乎乎的橘白奶猫。');
      expect(events.last['orientation'], 'square');
    });

    test('空行分隔（标准 SSE，真机实测就是这个）结果必须完全一致', () {
      final events = collect(docImageFlow, sep: '\n\n');
      expect(events.length, 16);
      expect(
        events
            .where((e) => e['type'] == 'text')
            .map((e) => e['content'])
            .join(),
        '画面里是软乎乎的橘白奶猫。',
      );
    });

    test('stage 与 message 原样透传，不在这一层解读或吃掉', () {
      final events = collect(docImageFlow);
      final stages = events
          .where((e) => e['type'] == 'progress')
          .map((e) => e['stage'])
          .toList();
      expect(stages, [
        'starting',
        'request_sent',
        'generating',
        'generating',
        'generating',
        'partial_succeeded',
        'completed',
        'downloading',
        'uploaded',
        'done',
      ]);
      // 页面优先用 message 出文案（见 ai_chat_page 的 _progressLabel），这一层必须原样带上
      final messages = events
          .where((e) => e['type'] == 'progress' && e['message'] != null)
          .map((e) => e['message'])
          .toList();
      expect(messages, ['正在创作图片']);
    });

    test('emoji 被 chunk 边界劈开也要完整还原', () {
      // chunkSize=3 保证劈中 4 字节的 emoji
      final events = collect(docTextFlow, sep: '\n\n', chunkSize: 3);
      expect(events.length, 4);
      final text = events
          .where((e) => e['type'] == 'text')
          .map((e) => e['content'] as String)
          .join();
      expect(text, '你好呀😊我是星宝…');
      expect(text.runes.map(String.fromCharCode).toList()[3], '😊');
    });

    test('data: 后面有没有空格都认', () {
      // 文档示例代码写死 slice(6)（依赖那个空格）。服务端哪天不带空格，
      // 那份示例会把 JSON 的第一个字符吃掉；我们按 substring(5).trim()，两种都认。
      final events = collect([
        'data:{"type":"text","content":"无空格"}',
        'data:  {"type":"text","content":"多空格"}',
        'data: {"type":"done","orientation":"vertical"}',
      ], sep: '\n\n');
      expect(
        events
            .where((e) => e['type'] == 'text')
            .map((e) => e['content'])
            .join(),
        '无空格多空格',
      );
      expect(events.last['orientation'], 'vertical');
    });

    test('脏数据行只丢自己，不把整条流带崩', () {
      final events = collect([
        'data: {"type":"text","content":"前"}',
        'data: {坏掉的 JSON',
        'event: ping',
        ': 这是注释行',
        'data: {"type":"text","content":"后"}',
      ], sep: '\n');
      expect(events.length, 2);
      expect(events.map((e) => e['content']).join(), '前后');
    });

    test('最后一条没带换行时，flush 也要把它吐出来', () {
      final events = <Map<String, dynamic>>[];
      final parser = AiSseParser(events.add)
        ..push('data: {"type":"done","orientation":"square"}');
      expect(events, isEmpty, reason: '还没 flush，最后一行留着等下一块');
      parser.flush();
      expect(events.length, 1);
      expect(events.first['orientation'], 'square');
    });
  });

  group('字面 \\n 分隔符的兜底还原', () {
    test('当分隔符用的 \\n 还原，JSON 正文里的 \\n 原样保留', () {
      // 服务端曾把整条响应挤成一行：事件之间是字面的反斜杠+n，而回复文字**本身**
      // 带的换行也长一样。只还原前者，还原后者会把一个事件的 JSON 从中间劈开。
      const body =
          r'data: {"type":"text","content":"第一行\n第二行"}\ndata: {"type":"done","orientation":"square"}';
      expect(kEscapedEventSeparator.hasMatch(body), isTrue);

      final events = <Map<String, dynamic>>[];
      AiSseParser(events.add)
        ..push(unescapeEventSeparators(body))
        ..flush();

      expect(events.length, 2);
      expect(events.first['content'], '第一行\n第二行', reason: '正文里的换行必须原样留着');
      expect(events.last['type'], 'done');
    });

    test('格式正常的报文不该被这条兜底碰到', () {
      const body =
          'data: {"type":"text","content":"正常"}\ndata: {"type":"done"}\n';
      expect(kEscapedEventSeparator.hasMatch(body), isFalse);
    });
  });

  group('AiStreamEvent', () {
    test('按文档字段取值，未知类型也照样构造出来', () {
      final event = AiStreamEvent.fromJson(const {
        'type': 'progress',
        'progress': 35,
        'stage': 'generating',
        'message': '正在创作图片',
      });
      expect(event.type, 'progress');
      expect(event.progress, 35);
      expect(event.stage, 'generating');
      expect(event.message, '正在创作图片');

      // 没见过的事件类型不能在这一层被吃掉：原样交给页面，由页面决定忽略
      final unknown = AiStreamEvent.fromJson(const {'type': '未来的新事件'});
      expect(unknown.type, '未来的新事件');
      expect(unknown.content, '');
      expect(unknown.progress, isNull);
    });
  });
}
