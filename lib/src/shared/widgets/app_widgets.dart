import 'package:flutter/material.dart';

import '../l10n/app_l10n.dart';

/// 通用半透明内容面板。
///
/// 用于承载普通页面的主要信息区，保持圆角、描边和阴影一致。
class AppPanel extends StatelessWidget {
  const AppPanel({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        color: Colors.white.withValues(alpha: 0.76),
        border: Border.all(color: Colors.white.withValues(alpha: 0.86)),
        boxShadow: [
          BoxShadow(
            blurRadius: 22,
            offset: const Offset(0, 12),
            color: Colors.black.withValues(alpha: 0.06),
          ),
        ],
      ),
      child: child,
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader({super.key, required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 4),
        Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
      ],
    );
  }
}

/// 带图标和说明文案的入口卡片。
///
/// 适合用于首页快捷操作或功能入口，点击行为由调用方传入。
class ActionCard extends StatelessWidget {
  const ActionCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(28),
      onTap: onTap,
      child: Ink(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              accent.withValues(alpha: 0.18),
              accent.withValues(alpha: 0.06),
            ],
          ),
          border: Border.all(color: accent.withValues(alpha: 0.18)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: accent),
            const SizedBox(height: 16),
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 6),
            Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}

class HeroMetric extends StatelessWidget {
  const HeroMetric({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 132,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        color: Colors.white.withValues(alpha: 0.10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Colors.white.withValues(alpha: 0.76),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(color: Colors.white),
          ),
        ],
      ),
    );
  }
}

class StatTag extends StatelessWidget {
  const StatTag({
    super.key,
    required this.label,
    required this.icon,
    required this.foreground,
    required this.background,
  });

  final String label;
  final IconData icon;
  final Color foreground;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: background,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: foreground),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(color: foreground, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.label, required this.active});

  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final color = active ? const Color(0xFF2A9D8F) : const Color(0xFF6C757D);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: color.withValues(alpha: 0.12),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontWeight: FontWeight.w700),
      ),
    );
  }
}

/// 设备缩略图占位组件。
///
/// 当前项目还没有真实设备渲染图时，用主题色渐变保持列表视觉一致。
class DeviceIllustration extends StatelessWidget {
  const DeviceIllustration({super.key, required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            color.withValues(alpha: 0.95),
            color.withValues(alpha: 0.72),
          ],
        ),
      ),
      child: const Icon(Icons.desktop_windows_rounded, color: Colors.white),
    );
  }
}

/// 通用空状态组件，用于列表无数据或权限未准备好的兜底展示。
/// 首屏加载态（对应小程序 app.wxss 的全局 `.page-loading`：转圈 + 「加载中…」）。
///
/// 用法是**三分支互斥链**，loading 分支必须排他优先、写在最前：
/// ```dart
/// if (!state.albumLoaded) const PageLoading()
/// else if (photos.isEmpty) const EmptyState(...)
/// else ...列表
/// ```
/// 不要写成「空态 if」和「loading 遮罩 if」两条独立分支——那样首帧会同时命中空态。
class PageLoading extends StatelessWidget {
  const PageLoading({super.key, this.label});

  /// 加载文案，缺省「加载中…」。
  final String? label;

  /// 品牌橙。**不要用 `Theme.of(context).colorScheme.primary`** —— 主题的 primary 是
  /// 深青色 `#234E52`（见 app_theme.dart），而全 App 视觉上的主色其实是这个橙。
  /// 之前 CircularProgressIndicator 不指定颜色，默认取到那个深青，看着就是个深色圆环。
  static const _accent = Color(0xFFEB5F1B);

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 对齐小程序 app.wxss 的 `.page-loading__spinner`：
          // 64rpx(=32) 圆环、6rpx(=3) 描边、轨道 rgba(235,95,27,.18)、转动部分 #eb5f1b。
          const SizedBox(
            width: 32,
            height: 32,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              color: _accent,
              backgroundColor: Color(0x2EEB5F1B), // #EB5F1B @ 18%
            ),
          ),
          const SizedBox(height: 12), // .page-loading__text margin-top 24rpx
          Text(
            label ?? AppL10n.of(context).loading,
            // .page-loading__text → 26rpx(=13) / #8b9098。
            // 原来写的是**白色**文字 —— 而页面背景 bg01 是浅色的，等于隐形。
            style: const TextStyle(
              color: Color(0xFF8B9098),
              fontSize: 13,
              fontWeight: FontWeight.w400,
              decoration: TextDecoration.none,
            ),
          ),
        ],
      ),
    );
  }
}

/// 首屏加载失败态（断网/接口失败且本地无数据可显示时）：
/// 提示 + 「重试」按钮。**不要**在这种场景下显示「暂无数据」空态——
/// 那是误导（用户会以为数据没了），空态只在确认成功且确实为空时用。
class PageLoadError extends StatelessWidget {
  const PageLoadError({super.key, required this.onRetry, this.message});

  /// 点「重试」重新发起加载。
  final VoidCallback onRetry;

  /// 提示文案，缺省「网络异常，请检查网络后重试」。
  final String? message;

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.wifi_off_rounded,
            size: 44,
            color: Color(0xFFB9C0CA),
          ),
          const SizedBox(height: 12),
          Text(
            message ?? l10n.loadFailedDesc,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF8B9098),
              fontSize: 13,
              fontWeight: FontWeight.w400,
              decoration: TextDecoration.none,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 36,
            child: OutlinedButton(
              onPressed: onRetry,
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFEB5F1B),
                side: const BorderSide(color: Color(0xFFEB5F1B)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 24),
              ),
              child: Text(l10n.retry),
            ),
          ),
        ],
      ),
    );
  }
}

/// 蒙层阻断式 loading（写操作专用：连接中 / 删除中 / 保存中 …），对齐小程序 `wx.showLoading({mask:true})`。
///
/// 读列表用页内的 [PageLoading] 骨架，**不要**用这个全屏遮罩；写操作才用它挡住误触。
///
/// ```dart
/// AppLoadingDialog.show(context, '连接设备中');
/// final result = await doSomething();
/// if (context.mounted) AppLoadingDialog.hide(context);
/// ```
class AppLoadingDialog {
  AppLoadingDialog._();

  /// 当前展示中的 loading 路由。[hide] 只精确移除它——之前是盲目
  /// `Navigator.pop()` 栈顶：若 loading 已被其它路径关掉（或从未弹出），
  /// 会误弹掉底下的业务页面，甚至在空栈上 pop 直接崩溃（修改密码发验证码
  /// 偶现闪退的一类根源）。
  static Route<void>? _route;

  static void show(BuildContext context, [String? text]) {
    if (_route != null) {
      return; // 已有 loading 在展示（约定成对调用，不该发生），不重复叠加。
    }
    final route = DialogRoute<void>(
      context: context,
      barrierDismissible: false,
      // 默认的 barrier 是 black54（54% 纯黑），整屏压成一片黑、把中间的转圈图标闷在里面。
      // 改成很淡的一层：既能挡住误触，又不至于糊掉页面。
      barrierColor: Colors.black.withValues(alpha: 0.18),
      builder: (_) => _LoadingBox(text: text),
    );
    _route = route;
    Navigator.of(context, rootNavigator: true).push(route).whenComplete(() {
      // 路由以任何方式出栈后清引用，防止 hide 拿着失效路由操作。
      if (identical(_route, route)) {
        _route = null;
      }
    });
  }

  /// 关闭 loading。务必与 [show] 成对调用。
  /// 只移除自己的对话框路由：重复调用 / loading 不在时静默返回，绝不误弹页面。
  static void hide(BuildContext context) {
    final route = _route;
    _route = null;
    if (route == null || !route.isActive) {
      return;
    }
    route.navigator?.removeRoute(route);
  }
}

class _LoadingBox extends StatelessWidget {
  const _LoadingBox({required this.text});

  /// 加载文案；null 时在 build 里按当前语言取默认「加载中…」。
  final String? text;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false, // 加载期间禁止返回键关掉遮罩
      // ⚠️ 必须包 Material：showDialog 的 builder 结果**不会**被自动包进 Material
      //（只有 Dialog/AlertDialog 才自带），而 Text 缺少 Material 祖先会被渲染成黄色双下划线。
      // 与 AppToast 同一个坑，同一个解法。
      child: Material(
        type: MaterialType.transparency,
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 22),
            decoration: BoxDecoration(
              // 与 AppToast 的气泡同色系，保持全 App 一致。
              color: const Color(0xFF111111).withValues(alpha: 0.82),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 30,
                  height: 30,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    // 深色盒子上用白圈；轨道给一层淡白，转起来更有质感。
                    color: Colors.white,
                    backgroundColor: Color(0x33FFFFFF),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  text ?? AppL10n.of(context).loading,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    height: 1.4,
                    fontWeight: FontWeight.w400,
                    decoration: TextDecoration.none,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: AppPanel(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.inbox_outlined,
                size: 48,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(title, style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
