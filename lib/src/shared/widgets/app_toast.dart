import 'package:flutter/material.dart';

/// 居中吐司提示（对齐微信小程序 `wx.showToast` 的**居中**展示，替代 Flutter 默认底部 SnackBar）。
///
/// 用 [OverlayEntry] 在屏幕中央弹一个半透明黑底圆角气泡，短暂淡入停留后移除。
/// 同一时刻只保留一个：新提示会顶掉上一个。全 App 统一从这里出提示，保证一致。
class AppToast {
  AppToast._();

  static OverlayEntry? _current;
  static int _seq = 0;

  /// 在屏幕中央弹出 [message]，[duration] 后自动消失。空串忽略。
  /// 无可用 Overlay（context 未挂载到导航树）时静默返回，不抛异常。
  static void show(
    BuildContext context,
    String message, {
    Duration duration = const Duration(milliseconds: 2000),
  }) {
    if (message.trim().isEmpty) {
      return;
    }
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) {
      return;
    }

    _current?.remove();
    _current = null;
    final seq = ++_seq;

    final entry = OverlayEntry(builder: (_) => _ToastBubble(message: message));
    _current = entry;
    overlay.insert(entry);

    Future<void>.delayed(duration, () {
      // 期间没有被新提示顶掉才移除（避免重复 remove 同一 entry）。
      if (seq == _seq && identical(_current, entry)) {
        entry.remove();
        _current = null;
      }
    });
  }
}

class _ToastBubble extends StatelessWidget {
  const _ToastBubble({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final maxWidth = MediaQuery.of(context).size.width * 0.72;
    return IgnorePointer(
      child: Center(
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0, end: 1),
          duration: const Duration(milliseconds: 160),
          builder: (_, value, child) => Opacity(opacity: value, child: child),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.82),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  height: 1.4,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
