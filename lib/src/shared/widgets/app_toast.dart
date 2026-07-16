import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

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
    // 播报给读屏器：OverlayEntry 短暂出现又消失，TalkBack/VoiceOver 用户
    // 否则完全感知不到提示内容。
    SemanticsService.announce(message, Directionality.of(context));

    // 长文案按阅读速度加时（每 10 个字符约 +300ms，封顶 6s），2 秒读不完 40 字的错误提示。
    // ⚠️ 不能写成 `duration.clamp(下界, 6000)`：消息超过 ~190 字时下界 > 上界，
    // `num.clamp` 会直接抛 ArgumentError —— 后端/网络返回长错误文案时一弹 toast 就崩。
    final readingMs = 300 + message.length * 30;
    final wantedMs = readingMs > duration.inMilliseconds
        ? readingMs
        : duration.inMilliseconds;
    final effective = Duration(
      milliseconds: wantedMs > 6000 ? 6000 : wantedMs,
    );
    Future<void>.delayed(effective, () {
      // 期间没有被新提示顶掉才移除（避免重复 remove 同一 entry）。
      if (seq == _seq && identical(_current, entry)) {
        entry.remove();
        _current = null;
      }
    });
  }

  /// 错误 / 警告类提示默认停留 3 秒，对齐小程序 `toast.warn` 的最新时长。
  static void warn(BuildContext context, String message) {
    show(context, message, duration: const Duration(milliseconds: 3000));
  }
}

class _ToastBubble extends StatelessWidget {
  const _ToastBubble({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Center(
        // ⚠️ 必须包一层 Material：OverlayEntry 挂在 Navigator 的 Overlay 上，
        // 不在任何 Material 之下，而 Text 缺少 Material 祖先时会被 Flutter 渲染成
        // **黄色双下划线**（调试用的 fallback 文本样式）。这正是 toast 出现下划线的原因。
        // MaterialType.transparency = 只提供文本样式/排版上下文，不画任何背景。
        // 下面再显式写死 `decoration: TextDecoration.none` 双保险。
        child: Material(
          type: MaterialType.transparency,
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0, end: 1),
            duration: const Duration(milliseconds: 160),
            builder: (_, value, child) => Opacity(opacity: value, child: child),
            // 盒子尺寸对齐小程序 components/toast 的 `.gtoast__box`：
            // max-width 560rpx(=280) / min-width 160rpx(=80) / padding 22×32rpx(=11×16)
            // / 背景 rgba(17,17,17,.82) / 圆角 16rpx(=8)。
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 280, minWidth: 80),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 11,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF111111).withValues(alpha: 0.82),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  message,
                  textAlign: TextAlign.center,
                  // .gtoast__text → 28rpx(=14) / line-height 42rpx(=1.5)
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    height: 1.5,
                    fontWeight: FontWeight.w400,
                    decoration: TextDecoration.none,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
