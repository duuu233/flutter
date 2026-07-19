import 'package:BoltStar/src/shared/widgets/simple_html_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 把渲染出来的所有文本块按顺序拼成纯文本，便于断言解析结果。
List<String> _renderedBlocks(WidgetTester tester) {
  return tester
      .widgetList<Text>(find.byType(Text))
      .map((text) => text.textSpan?.toPlainText() ?? text.data ?? '')
      .toList();
}

Future<void> _pumpHtml(WidgetTester tester, String html) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SimpleHtmlText(
          html,
          baseStyle: const TextStyle(fontSize: 12),
        ),
      ),
    ),
  );
}

void main() {
  group('looksLikeHtml', () {
    test('识别标签与实体，纯文本不误判', () {
      expect(SimpleHtmlText.looksLikeHtml('<p>你好</p>'), isTrue);
      expect(SimpleHtmlText.looksLikeHtml('第一行<br/>第二行'), isTrue);
      expect(SimpleHtmlText.looksLikeHtml('空格&nbsp;分隔'), isTrue);
      expect(SimpleHtmlText.looksLikeHtml('普通文本，没有标签'), isFalse);
      expect(SimpleHtmlText.looksLikeHtml('1 < 2 且 3 > 2'), isFalse);
      expect(SimpleHtmlText.looksLikeHtml(''), isFalse);
    });
  });

  testWidgets('<p> 渲染成独立段落，标签本身不出现在正文里', (tester) async {
    await _pumpHtml(tester, '<p>第一段</p><p>第二段</p>');

    final blocks = _renderedBlocks(tester);
    expect(blocks, ['第一段', '第二段']);
    // 回归点：此前整串 HTML 被塞进 Text，标签会原样显示。
    expect(find.textContaining('<p>'), findsNothing);
  });

  testWidgets('<br> 在段内换行，不拆成两个块', (tester) async {
    await _pumpHtml(tester, '第一行<br/>第二行');

    expect(_renderedBlocks(tester), ['第一行\n第二行']);
  });

  testWidgets('解码 HTML 实体', (tester) async {
    await _pumpHtml(tester, '<p>a&nbsp;b &amp; c &lt;tag&gt; &#65;</p>');

    expect(_renderedBlocks(tester), ['a\u{00A0}b & c <tag> A']);
  });

  testWidgets('列表渲染出项目符号与序号', (tester) async {
    await _pumpHtml(
      tester,
      '<ul><li>甲</li><li>乙</li></ul><ol><li>一</li><li>二</li></ol>',
    );

    expect(_renderedBlocks(tester), ['• 甲', '• 乙', '1. 一', '2. 二']);
  });

  testWidgets('丢弃 script/style 及其内容', (tester) async {
    await _pumpHtml(
      tester,
      '<style>.a{color:red}</style><p>正文</p><script>alert(1)</script>',
    );

    expect(_renderedBlocks(tester), ['正文']);
  });

  testWidgets('未闭合标签不会让后续文字串味', (tester) async {
    // 富文本编辑器常产出 <p><span>x</p> 这种未闭合结构：
    // 按名弹栈保证 <span> 的样式不会漏到下一段。
    await _pumpHtml(tester, '<p><b>粗体</b>正常</p><p>下一段</p>');

    final blocks = _renderedBlocks(tester);
    expect(blocks, ['粗体正常', '下一段']);

    final second = tester.widgetList<Text>(find.byType(Text)).last;
    final spans = <InlineSpan>[];
    second.textSpan?.visitChildren((span) {
      spans.add(span);
      return true;
    });
    // 第二段不应继承第一段的加粗
    for (final span in spans) {
      if (span is TextSpan && (span.text ?? '').contains('下一段')) {
        expect(span.style?.fontWeight, isNot(FontWeight.w600));
      }
    }
  });

  testWidgets('折叠多余空白，标题与未知标签只保留文字', (tester) async {
    await _pumpHtml(
      tester,
      '<h2>  标题  </h2><div><span>未知标签内的</span>文字</div>',
    );

    expect(_renderedBlocks(tester), ['标题', '未知标签内的文字']);
  });

  testWidgets('纯文本输入原样渲染', (tester) async {
    await _pumpHtml(tester, '没有任何标签的答案');

    expect(_renderedBlocks(tester), ['没有任何标签的答案']);
  });
}
