import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// 后端富文本（当前用于常见问题 `faqContent`）带 HTML 标签。小程序侧交给微信原生
/// `rich-text` 渲染，App 侧此前直接塞进 [Text]，`<p>xxx</p>` 会原样显示出来。
///
/// 这里实现一个**零依赖**的 HTML 子集渲染器，而不是引 `flutter_html`：
/// 本机不装构建链（见项目约定），三方包的依赖解析无法在本地验证；且 FAQ 富文本
/// 用到的标签集合很窄，自绘反而更可控、样式也能对齐设计稿。
///
/// 支持范围：
/// - 块级：`p` `div` `br` `h1`~`h6` `ul` `ol` `li` `blockquote` `tr`
/// - 行内：`b` `strong` `i` `em` `u` `s` `del` `a` `span` `font` `td`
/// - 图片：`img`（走 [CachedNetworkImage]，与图库共用磁盘缓存）
/// - 内联样式：`color` / `font-size` / `font-weight` / `font-style` /
///   `text-decoration` / `text-align`
/// - 实体：`&nbsp; &amp; &lt; &gt; &quot; &apos; &#39; &#\d+; &#x[0-9a-f]+;`
/// - 丢弃：`script` / `style` 及其内容、HTML 注释；其余未知标签只丢标签、保留文字
class SimpleHtmlText extends StatefulWidget {
  const SimpleHtmlText(
    this.html, {
    super.key,
    required this.baseStyle,
    this.linkColor = const Color(0xFF2F6BFF),
  });

  final String html;
  final TextStyle baseStyle;
  final Color linkColor;

  /// 内容里是否含 HTML 标签/实体。纯文本可以继续走普通 [Text]，省一次解析。
  static bool looksLikeHtml(String input) {
    if (input.isEmpty) {
      return false;
    }
    return _htmlProbe.hasMatch(input);
  }

  static final RegExp _htmlProbe = RegExp(
    r'<\s*/?\s*(br|p|div|ul|ol|li|h[1-6]|img|a|span|strong|b|em|i|u|s|del'
    r'|blockquote|table|tr|td|font|section|pre|code)\b[^>]*>|&(nbsp|amp|lt|gt|quot|apos|#\d+|#x[0-9a-fA-F]+);',
    caseSensitive: false,
  );

  @override
  State<SimpleHtmlText> createState() => _SimpleHtmlTextState();
}

class _SimpleHtmlTextState extends State<SimpleHtmlText> {
  /// 解析结果缓存：解析本身不贵，但 [TapGestureRecognizer] 必须由 State 持有并
  /// 在 dispose 时释放，所以不能放进 build 里每帧重建。
  _HtmlDocument? _document;

  @override
  void initState() {
    super.initState();
    _parse();
  }

  @override
  void didUpdateWidget(covariant SimpleHtmlText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.html != widget.html ||
        oldWidget.baseStyle != widget.baseStyle ||
        oldWidget.linkColor != widget.linkColor) {
      _disposeDocument();
      _parse();
    }
  }

  @override
  void dispose() {
    _disposeDocument();
    super.dispose();
  }

  void _parse() {
    _document = _HtmlParser(
      baseStyle: widget.baseStyle,
      linkColor: widget.linkColor,
    ).parse(widget.html);
  }

  void _disposeDocument() {
    for (final recognizer in _document?.recognizers ?? const <TapGestureRecognizer>[]) {
      recognizer.dispose();
    }
    _document = null;
  }

  @override
  Widget build(BuildContext context) {
    final blocks = _document?.blocks ?? const <Widget>[];
    if (blocks.isEmpty) {
      return const SizedBox.shrink();
    }
    if (blocks.length == 1) {
      return blocks.first;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: blocks,
    );
  }
}

/// 解析产物：块级 widget 列表 + 需要随 State 释放的手势识别器。
class _HtmlDocument {
  const _HtmlDocument(this.blocks, this.recognizers);

  final List<Widget> blocks;
  final List<TapGestureRecognizer> recognizers;
}

/// 段落之间的间距标记。用独立类型是为了在收尾时能识别并去掉末尾多余的空隙。
class _HtmlGap extends StatelessWidget {
  const _HtmlGap(this.height);

  final double height;

  @override
  Widget build(BuildContext context) => SizedBox(height: height);
}

/// 行内样式栈的一层：一个标签带来的样式增量 + 可选的链接点击。
class _InlineFrame {
  _InlineFrame({required this.tag, this.style, this.recognizer});

  final String tag;
  final TextStyle? style;
  final TapGestureRecognizer? recognizer;
}

/// 列表上下文：区分有序/无序，并为有序列表维护序号。
class _ListFrame {
  _ListFrame(this.ordered);

  final bool ordered;
  int index = 0;
}

class _HtmlParser {
  _HtmlParser({required this.baseStyle, required this.linkColor});

  final TextStyle baseStyle;
  final Color linkColor;

  final List<Widget> _blocks = <Widget>[];
  final List<InlineSpan> _spans = <InlineSpan>[];
  final List<_InlineFrame> _inline = <_InlineFrame>[];
  final List<_ListFrame> _lists = <_ListFrame>[];
  final List<TapGestureRecognizer> _recognizers = <TapGestureRecognizer>[];

  TextAlign _align = TextAlign.start;

  /// 段间距：正文段落用 6，标题稍大。收尾会裁掉末尾的空隙。
  static const double _paragraphGap = 6;

  /// 每层列表的缩进。
  static const double _listIndent = 16;

  static const Map<String, String> _entities = <String, String>{
    'nbsp': ' ',
    'amp': '&',
    'lt': '<',
    'gt': '>',
    'quot': '"',
    'apos': "'",
    'ldquo': '“',
    'rdquo': '”',
    'lsquo': '‘',
    'rsquo': '’',
    'hellip': '…',
    'mdash': '—',
    'ndash': '–',
    'middot': '·',
    'times': '×',
    'copy': '©',
    'reg': '®',
  };

  static final RegExp _tagPattern = RegExp(
    r'<\s*(/?)\s*([a-zA-Z][a-zA-Z0-9]*)([^>]*)>',
    caseSensitive: false,
  );

  static final RegExp _attrPattern = RegExp(
    '''([a-zA-Z_:-][a-zA-Z0-9_:.-]*)\\s*=\\s*("([^"]*)"|'([^']*)'|([^\\s"'>]+))''',
  );

  _HtmlDocument parse(String html) {
    var cursor = 0;
    while (cursor < html.length) {
      // 用 allMatches(html, cursor) 而不是对 substring 反复 firstMatch：
      // 后者每轮都要复制一次剩余串，长富文本会退化成 O(n²)。
      final iterator = _tagPattern.allMatches(html, cursor).iterator;
      if (!iterator.moveNext()) {
        _appendText(html.substring(cursor));
        break;
      }
      final match = iterator.current;
      if (match.start > cursor) {
        _appendText(html.substring(cursor, match.start));
      }

      final closing = match.group(1) == '/';
      final tag = match.group(2)!.toLowerCase();
      final rawAttrs = match.group(3) ?? '';
      cursor = match.end;

      // script / style：连同内容整段丢弃，避免把 JS/CSS 当正文渲染出来。
      if (!closing && (tag == 'script' || tag == 'style')) {
        final endPattern = RegExp('<\\s*/\\s*$tag\\s*>', caseSensitive: false);
        final endIterator = endPattern.allMatches(html, cursor).iterator;
        cursor = endIterator.moveNext() ? endIterator.current.end : html.length;
        continue;
      }

      if (closing) {
        _closeTag(tag);
      } else {
        _openTag(tag, _parseAttributes(rawAttrs));
      }
    }

    _flush();
    // 末尾的段间距会在卡片底部撑出多余留白，去掉。
    while (_blocks.isNotEmpty && _blocks.last is _HtmlGap) {
      _blocks.removeLast();
    }
    return _HtmlDocument(_blocks, _recognizers);
  }

  Map<String, String> _parseAttributes(String raw) {
    if (raw.trim().isEmpty) {
      return const <String, String>{};
    }
    final attrs = <String, String>{};
    for (final match in _attrPattern.allMatches(raw)) {
      final name = match.group(1)!.toLowerCase();
      final value = match.group(3) ?? match.group(4) ?? match.group(5) ?? '';
      attrs[name] = _decodeEntities(value);
    }
    return attrs;
  }

  void _openTag(String tag, Map<String, String> attrs) {
    final style = _styleFromAttributes(attrs);
    final align = _alignFromAttributes(attrs);

    switch (tag) {
      case 'br':
        // <br> 只在段内换行，不结束段落。
        _spans.add(const TextSpan(text: '\n'));
        return;
      case 'img':
        _appendImage(attrs);
        return;
      case 'hr':
        _flush();
        _blocks.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Divider(height: 1, thickness: 1, color: baseStyle.color?.withValues(alpha: 0.15)),
          ),
        );
        return;
      case 'p':
      case 'div':
      case 'section':
      case 'blockquote':
      case 'tr':
        _flush(gap: _paragraphGap);
        if (align != null) {
          _align = align;
        }
        _inline.add(_InlineFrame(tag: tag, style: style));
        return;
      case 'h1':
      case 'h2':
      case 'h3':
      case 'h4':
      case 'h5':
      case 'h6':
        _flush(gap: _paragraphGap);
        if (align != null) {
          _align = align;
        }
        final level = int.parse(tag.substring(1));
        // h1 相对正文放大 6pt，逐级递减 1pt，最小与正文同号。
        final double baseSize = baseStyle.fontSize ?? 14.0;
        final double headingSize = baseSize + (7 - level).clamp(0, 6).toDouble();
        _inline.add(
          _InlineFrame(
            tag: tag,
            style: (style ?? const TextStyle()).copyWith(
              fontSize: headingSize,
              fontWeight: FontWeight.w600,
            ),
          ),
        );
        return;
      case 'ul':
      case 'ol':
        _flush(gap: _paragraphGap);
        _lists.add(_ListFrame(tag == 'ol'));
        return;
      case 'li':
        _flush();
        final frame = _lists.isEmpty ? null : _lists.last;
        final marker = frame == null
            ? '• '
            : frame.ordered
                ? '${++frame.index}. '
                : '• ';
        _spans.add(TextSpan(text: marker, style: _currentStyle()));
        _inline.add(_InlineFrame(tag: tag, style: style));
        return;
      case 'b':
      case 'strong':
        _inline.add(
          _InlineFrame(
            tag: tag,
            style: (style ?? const TextStyle()).copyWith(fontWeight: FontWeight.w600),
          ),
        );
        return;
      case 'i':
      case 'em':
        _inline.add(
          _InlineFrame(
            tag: tag,
            style: (style ?? const TextStyle()).copyWith(fontStyle: FontStyle.italic),
          ),
        );
        return;
      case 'u':
        _inline.add(
          _InlineFrame(
            tag: tag,
            style: (style ?? const TextStyle()).copyWith(decoration: TextDecoration.underline),
          ),
        );
        return;
      case 's':
      case 'del':
      case 'strike':
        _inline.add(
          _InlineFrame(
            tag: tag,
            style: (style ?? const TextStyle()).copyWith(decoration: TextDecoration.lineThrough),
          ),
        );
        return;
      case 'a':
        _inline.add(_buildLinkFrame(attrs, style));
        return;
      case 'td':
      case 'th':
        // 表格不做真实布局：单元格之间补一个空格，至少不粘连成一坨。
        if (_spans.isNotEmpty) {
          _spans.add(const TextSpan(text: '  '));
        }
        _inline.add(_InlineFrame(tag: tag, style: style));
        return;
      default:
        // span / font / code / 其余未知标签：只吃样式，不影响结构。
        //
        // 即使没有样式也要压栈：`<span><span style=…>x</span>y</span>` 这种嵌套里，
        // 内层 `</span>` 必须弹掉内层那一帧；只在有样式时压栈的话，
        // 内层闭合会把外层的样式误弹掉，y 就跟着串味了。
        _inline.add(_InlineFrame(tag: tag, style: style));
        return;
    }
  }

  void _closeTag(String tag) {
    switch (tag) {
      case 'p':
      case 'div':
      case 'section':
      case 'blockquote':
      case 'tr':
      case 'h1':
      case 'h2':
      case 'h3':
      case 'h4':
      case 'h5':
      case 'h6':
        _popInline(tag);
        _flush(gap: _paragraphGap);
        _align = TextAlign.start;
        return;
      case 'ul':
      case 'ol':
        _popInline(tag);
        _flush(gap: _paragraphGap);
        if (_lists.isNotEmpty) {
          _lists.removeLast();
        }
        return;
      case 'li':
        _popInline(tag);
        _flush();
        return;
      case 'br':
      case 'img':
      case 'hr':
        return;
      default:
        _popInline(tag);
        return;
    }
  }

  /// 弹出行内样式栈里最近的同名标签。
  ///
  /// 用「按名查找」而不是无脑 removeLast：富文本编辑器产出的 HTML 经常有未闭合的
  /// 标签（`<p><span>x</p>`），无脑弹栈会把不相干的样式一起弹掉，导致后续文字串味。
  void _popInline(String tag) {
    for (var i = _inline.length - 1; i >= 0; i--) {
      if (_inline[i].tag == tag) {
        _inline.removeRange(i, _inline.length);
        return;
      }
    }
  }

  _InlineFrame _buildLinkFrame(Map<String, String> attrs, TextStyle? style) {
    final href = (attrs['href'] ?? '').trim();
    final linkStyle = (style ?? const TextStyle()).copyWith(
      color: linkColor,
      decoration: TextDecoration.underline,
      decorationColor: linkColor,
    );
    if (href.isEmpty || !href.startsWith(RegExp('https?://|mailto:|tel:', caseSensitive: false))) {
      // 站内相对链接在 App 里没有落点，只做样式、不给点击。
      return _InlineFrame(tag: 'a', style: linkStyle);
    }
    final recognizer = TapGestureRecognizer()
      ..onTap = () {
        // 失败静默：FAQ 里的外链打不开不该阻断阅读。
        launchUrl(Uri.parse(href), mode: LaunchMode.externalApplication).catchError((_) => false);
      };
    _recognizers.add(recognizer);
    return _InlineFrame(tag: 'a', style: linkStyle, recognizer: recognizer);
  }

  void _appendImage(Map<String, String> attrs) {
    final src = (attrs['src'] ?? '').trim();
    if (src.isEmpty || !src.startsWith(RegExp('https?://', caseSensitive: false))) {
      return;
    }
    _flush(gap: _paragraphGap);
    _blocks.add(
      ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: CachedNetworkImage(
          imageUrl: src,
          fit: BoxFit.fitWidth,
          width: double.infinity,
          // 富文本图片高度未知，占位和失败都收敛成细条，避免撑开空白。
          placeholder: (context, url) => const SizedBox(height: 2),
          errorWidget: (context, url, error) => const SizedBox.shrink(),
        ),
      ),
    );
    _blocks.add(const _HtmlGap(_paragraphGap));
  }

  void _appendText(String raw) {
    if (raw.isEmpty) {
      return;
    }
    var text = _decodeEntities(raw);
    // HTML 空白折叠：换行/制表当空格，连续空格并成一个。
    text = text.replaceAll(RegExp(r'[\t\r\n]+'), ' ').replaceAll(RegExp(' {2,}'), ' ');
    if (text.trim().isEmpty) {
      // 纯空白：只有在段中才保留一个空格，段首直接丢弃。
      if (_spans.isEmpty || text.isEmpty) {
        return;
      }
      text = ' ';
    } else if (_spans.isEmpty) {
      text = text.trimLeft();
    }
    if (text.isEmpty) {
      return;
    }
    _spans.add(
      TextSpan(
        text: text,
        style: _currentStyle(),
        recognizer: _currentRecognizer(),
      ),
    );
  }

  /// 去掉块尾多余的空白：`<h2>  标题  </h2>` 这类写法很常见，
  /// 尾随空格在居中/右对齐时会把文字顶偏。
  void _trimTrailingSpace() {
    while (_spans.isNotEmpty) {
      final last = _spans.last;
      if (last is! TextSpan || last.text == null) {
        return;
      }
      final trimmed = last.text!.replaceFirst(RegExp(r'[ \t]+$'), '');
      if (trimmed == last.text) {
        return;
      }
      _spans.removeLast();
      if (trimmed.isNotEmpty) {
        _spans.add(
          TextSpan(text: trimmed, style: last.style, recognizer: last.recognizer),
        );
        return;
      }
    }
  }

  TextStyle _currentStyle() {
    var style = const TextStyle();
    for (final frame in _inline) {
      final next = frame.style;
      if (next != null) {
        style = style.merge(next);
      }
    }
    return style;
  }

  TapGestureRecognizer? _currentRecognizer() {
    for (var i = _inline.length - 1; i >= 0; i--) {
      final recognizer = _inline[i].recognizer;
      if (recognizer != null) {
        return recognizer;
      }
    }
    return null;
  }

  void _flush({double gap = 0}) {
    _trimTrailingSpace();
    if (_spans.isEmpty) {
      return;
    }
    final indent = _lists.isEmpty ? 0.0 : _listIndent * (_lists.length - 1);
    _blocks.add(
      Padding(
        padding: EdgeInsets.only(left: indent),
        child: Text.rich(
          TextSpan(style: baseStyle, children: List<InlineSpan>.of(_spans)),
          textAlign: _align,
        ),
      ),
    );
    _spans.clear();
    if (gap > 0) {
      _blocks.add(_HtmlGap(gap));
    }
  }

  TextAlign? _alignFromAttributes(Map<String, String> attrs) {
    final declarations = _styleDeclarations(attrs['style']);
    final value = (declarations['text-align'] ?? attrs['align'] ?? '').toLowerCase();
    switch (value) {
      case 'center':
        return TextAlign.center;
      case 'right':
        return TextAlign.right;
      case 'justify':
        return TextAlign.justify;
      case 'left':
        return TextAlign.left;
      default:
        return null;
    }
  }

  TextStyle? _styleFromAttributes(Map<String, String> attrs) {
    final declarations = _styleDeclarations(attrs['style']);
    // <font color> 是老编辑器的产物，顺手兼容。
    final rawColor = declarations['color'] ?? attrs['color'];

    Color? color;
    if (rawColor != null) {
      color = _parseColor(rawColor);
    }

    double? fontSize;
    final rawSize = declarations['font-size'];
    if (rawSize != null) {
      final numeric = RegExp(r'([\d.]+)\s*(px|pt|rpx)?').firstMatch(rawSize);
      final parsed = numeric == null ? null : double.tryParse(numeric.group(1)!);
      if (parsed != null && parsed > 0) {
        // pt/rpx 粗略折算成逻辑像素，避免富文本字号比正文大出一个量级。
        final unit = numeric!.group(2);
        fontSize = unit == 'pt'
            ? parsed * 4 / 3
            : unit == 'rpx'
                ? parsed / 2
                : parsed;
      }
    }

    FontWeight? weight;
    final rawWeight = declarations['font-weight'];
    if (rawWeight != null) {
      final numeric = int.tryParse(rawWeight.trim());
      if (numeric != null) {
        weight = numeric >= 600 ? FontWeight.w600 : FontWeight.w400;
      } else if (rawWeight.contains('bold')) {
        weight = FontWeight.w600;
      } else if (rawWeight.contains('normal')) {
        weight = FontWeight.w400;
      }
    }

    FontStyle? fontStyle;
    final rawStyle = declarations['font-style'];
    if (rawStyle != null) {
      if (rawStyle.contains('italic') || rawStyle.contains('oblique')) {
        fontStyle = FontStyle.italic;
      } else if (rawStyle.contains('normal')) {
        fontStyle = FontStyle.normal;
      }
    }

    TextDecoration? decoration;
    final rawDecoration = declarations['text-decoration'];
    if (rawDecoration != null) {
      if (rawDecoration.contains('underline')) {
        decoration = TextDecoration.underline;
      } else if (rawDecoration.contains('line-through')) {
        decoration = TextDecoration.lineThrough;
      } else if (rawDecoration.contains('none')) {
        decoration = TextDecoration.none;
      }
    }

    if (color == null &&
        fontSize == null &&
        weight == null &&
        fontStyle == null &&
        decoration == null) {
      return null;
    }
    return TextStyle(
      color: color,
      fontSize: fontSize,
      fontWeight: weight,
      fontStyle: fontStyle,
      decoration: decoration,
    );
  }

  Map<String, String> _styleDeclarations(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return const <String, String>{};
    }
    final declarations = <String, String>{};
    for (final part in raw.split(';')) {
      final index = part.indexOf(':');
      if (index <= 0) {
        continue;
      }
      final key = part.substring(0, index).trim().toLowerCase();
      final value = part.substring(index + 1).trim().toLowerCase();
      if (key.isNotEmpty && value.isNotEmpty) {
        declarations[key] = value;
      }
    }
    return declarations;
  }

  Color? _parseColor(String raw) {
    var value = raw.trim().toLowerCase();
    if (value.startsWith('#')) {
      value = value.substring(1);
      if (value.length == 3) {
        value = value.split('').map((char) => '$char$char').join();
      }
      if (value.length == 6) {
        final parsed = int.tryParse(value, radix: 16);
        return parsed == null ? null : Color(0xFF000000 | parsed);
      }
      if (value.length == 8) {
        final parsed = int.tryParse(value, radix: 16);
        return parsed == null ? null : Color(parsed);
      }
      return null;
    }
    final rgb = RegExp(r'rgba?\(([^)]*)\)').firstMatch(value);
    if (rgb != null) {
      final parts = rgb.group(1)!.split(',').map((part) => part.trim()).toList();
      if (parts.length >= 3) {
        final r = int.tryParse(parts[0]);
        final g = int.tryParse(parts[1]);
        final b = int.tryParse(parts[2]);
        if (r != null && g != null && b != null) {
          final a = parts.length > 3 ? (double.tryParse(parts[3]) ?? 1) : 1.0;
          return Color.fromRGBO(r, g, b, a.clamp(0, 1).toDouble());
        }
      }
      return null;
    }
    return _namedColors[value];
  }

  static const Map<String, Color> _namedColors = <String, Color>{
    'black': Color(0xFF000000),
    'white': Color(0xFFFFFFFF),
    'red': Color(0xFFFF0000),
    'green': Color(0xFF008000),
    'blue': Color(0xFF0000FF),
    'gray': Color(0xFF808080),
    'grey': Color(0xFF808080),
    'orange': Color(0xFFFFA500),
    'yellow': Color(0xFFFFFF00),
    'purple': Color(0xFF800080),
  };

  String _decodeEntities(String input) {
    if (!input.contains('&')) {
      return input;
    }
    return input.replaceAllMapped(RegExp(r'&(#x?[0-9a-fA-F]+|[a-zA-Z]+);'), (match) {
      final body = match.group(1)!;
      if (body.startsWith('#')) {
        final isHex = body.length > 1 && (body[1] == 'x' || body[1] == 'X');
        final digits = isHex ? body.substring(2) : body.substring(1);
        final code = int.tryParse(digits, radix: isHex ? 16 : 10);
        if (code == null || code < 0 || code > 0x10FFFF) {
          return match.group(0)!;
        }
        return String.fromCharCode(code);
      }
      return _entities[body.toLowerCase()] ?? match.group(0)!;
    });
  }
}
