import 'package:flutter/material.dart';

import '../l10n/app_l10n.dart';

/// 首屏加载态（对应小程序 app.wxss 的全局 `.page-loading`：转圈 + 「加载中…」）。
///
/// 用法是**三分支互斥链**，loading 分支必须排他优先、写在最前：
/// ```dart
/// if (!state.castRecordsLoaded) const PageLoading()
/// else if (records.isEmpty) ...页内空态
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
/// try {
///   result = await doSomething();
/// } finally {
///   AppLoadingDialog.hide(context); // 不做 mounted 门控，见 hide 的说明
/// }
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

  /// 关闭 loading。务必与 [show] 成对调用（推荐 try/finally，见下方说明）。
  /// 只移除自己的对话框路由：重复调用 / loading 不在时静默返回，绝不误弹页面。
  ///
  /// ⚠️ 调用侧不要用 `if (mounted)` 门控 hide：loading 在 root navigator 上且
  /// canPop:false，页面在 await 期间被卸载（会话过期 popUntil / Tab 切换换 child）
  /// 时若跳过 hide，蒙层会永久滞留、整个 App 假死只能杀进程。本方法实际不依赖
  /// 传入的 context（经 route.navigator 出栈），unmounted 时调用也安全——
  /// 统一写成 `try { await ... } finally { AppLoadingDialog.hide(context); }`。
  static void hide(BuildContext context) => hideIfAny();

  /// 无 context 版收口：供会话过期等全局导航前兜底关掉可能在展示的 loading。
  static void hideIfAny() {
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
