import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../debug_log.dart';

/// 联调日志浮窗（2026-11-12，同小程序 `components/debug-log`）：挂在 `MaterialApp.builder` 上，
/// 一处挂载所有页面（含弹窗、底部弹层之上）都有，不动任何页面布局。
///
/// 收起时左下角一颗「日志 N」小药丸（底部抬高，不压底部 Tab 与按钮栏）；点开展开日志框：
/// 「复制」全部、「清空」、「关闭」。开关见 [DebugLog.enabled]，关着时原样返回 [child]。
///
/// ⚠️ 这一层在 Navigator 之上，没有 Overlay：日志行用普通 Text（SelectableText 需要 Overlay），
/// 复制结果在标题栏里提示，不走 AppToast。
class DebugLogOverlay extends StatefulWidget {
  const DebugLogOverlay({super.key, required this.child});

  final Widget child;

  @override
  State<DebugLogOverlay> createState() => _DebugLogOverlayState();
}

class _DebugLogOverlayState extends State<DebugLogOverlay> {
  bool _open = false;
  String _hint = '';
  Timer? _hintTimer;
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    if (DebugLog.enabled) {
      DebugLog.instance.addListener(_onChanged);
    }
  }

  @override
  void dispose() {
    DebugLog.instance.removeListener(_onChanged);
    _hintTimer?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (!mounted) {
      return;
    }
    // 展开时停在底部才跟着滚到最新一行；往上翻着看的时候不打断
    final follow = !_scroll.hasClients || _scroll.position.pixels >= _scroll.position.maxScrollExtent - 24;
    setState(() {});
    if (_open && follow) {
      _jumpToEnd();
    }
  }

  void _jumpToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  void _toggle() {
    setState(() => _open = !_open);
    if (_open) {
      _jumpToEnd();
    }
  }

  Future<void> _copy() async {
    final text = DebugLog.instance.text;
    if (text.isEmpty) {
      _showHint('暂无日志');
      return;
    }
    await Clipboard.setData(ClipboardData(text: text));
    _showHint('已复制');
  }

  void _showHint(String hint) {
    _hintTimer?.cancel();
    setState(() => _hint = hint);
    _hintTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) {
        setState(() => _hint = '');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!DebugLog.enabled) {
      return widget.child;
    }
    final media = MediaQuery.of(context);
    final safeBottom = media.padding.bottom;
    final count = DebugLog.instance.count;
    return Stack(
      // child 是 Navigator，必须撑满；默认 loose 会让整个 App 塌掉
      fit: StackFit.expand,
      children: [
        widget.child,
        if (!_open)
          Positioned(
            left: 8,
            // 同小程序 `bottom: safe-area + 220rpx`：抬到底部 Tab / 按钮栏之上
            bottom: safeBottom + 110,
            // Navigator 之上没有 Material：不包一层的话 Text 会落到 MaterialApp 的报错字样（红字双下划线）
            child: Material(
              type: MaterialType.transparency,
              child: _Pill(count: count, onTap: _toggle),
            ),
          )
        else
          Positioned(
            left: 8,
            right: 8,
            bottom: safeBottom + 12,
            height: media.size.height * 0.56,
            child: Material(
              type: MaterialType.transparency,
              child: _Panel(
                lines: DebugLog.instance.lines,
                hint: _hint,
                scroll: _scroll,
                onCopy: _copy,
                onClear: DebugLog.instance.clear,
                onClose: _toggle,
              ),
            ),
          ),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: const Key('debug-log-pill'),
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0x9E25282D),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          '日志 $count',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            height: 1.4,
          ),
        ),
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({
    required this.lines,
    required this.hint,
    required this.scroll,
    required this.onCopy,
    required this.onClear,
    required this.onClose,
  });

  final List<DebugLogLine> lines;
  final String hint;
  final ScrollController scroll;
  final VoidCallback onCopy;
  final VoidCallback onClear;
  final VoidCallback onClose;

  static const TextStyle _button = TextStyle(color: Color(0xFFFFB27D), fontSize: 13);

  Widget _action(String label, VoidCallback onTap) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      child: Text(label, style: _button),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('debug-log-panel'),
      decoration: BoxDecoration(
        color: const Color(0xE614161A),
        borderRadius: BorderRadius.circular(10),
        boxShadow: const [BoxShadow(color: Color(0x40000000), blurRadius: 20, offset: Offset(0, 8))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(12, 6, 5, 6),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0x1FFFFFFF), width: 0.5)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    hint.isNotEmpty ? '联调日志 ${lines.length} · $hint' : '联调日志 ${lines.length}',
                    style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700),
                  ),
                ),
                _action('复制', onCopy),
                _action('清空', onClear),
                _action('关闭', onClose),
              ],
            ),
          ),
          Expanded(
            child: lines.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(10),
                    child: Text('（暂无）', style: TextStyle(color: Color(0xFFD9DDE3), fontSize: 11)),
                  )
                : ListView.builder(
                    controller: scroll,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    itemCount: lines.length,
                    itemBuilder: (context, index) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Text(
                        lines[index].text,
                        style: const TextStyle(color: Color(0xFFD9DDE3), fontSize: 11, height: 1.35),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// 进页面 / 返回时记一行「页面 → 路由」（同小程序浮窗在页面 show 时记的那行）。
/// 只记整页路由（[PageRoute]），弹窗 / 底部弹层不记；没起名的路由记路由类型。
class DebugLogRouteObserver extends NavigatorObserver {
  static String _name(Route<dynamic> route) => route.settings.name ?? '（未命名 ${route.runtimeType}）';

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PageRoute) {
      DebugLog.log('页面 → ${_name(route)}');
    }
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PageRoute && previousRoute is PageRoute) {
      DebugLog.log('页面 ← 返回 ${_name(previousRoute)}');
    }
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (newRoute is PageRoute) {
      DebugLog.log('页面 → ${_name(newRoute)}（替换）');
    }
  }
}
