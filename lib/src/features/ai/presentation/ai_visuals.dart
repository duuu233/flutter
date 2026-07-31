/// AI 模块（星宝）的共用视觉零件与色值 —— 聊天页与会话列表页共享。
///
/// 2026-07-31 按小程序 `assets/ai/UI` 视觉稿同步：整套配色从原来的冷灰蓝
/// （#F2F5FC / #2A2D32）换成暖米白 + 橙（#F8F5EF / #FF6F25），所有图标都换成
/// `assets/images/ai-*.png` 里与小程序**同一批**的位图，不再用 Material 字体图标 ——
/// 两端图标形状必须一致，字体图标做不到。
///
/// ⚠️ 背景图本轮不同步（用户指定「flutter 先不改背景图」）：两页仍用全 App 统一的
/// `FigmaScreenBackground`，没有跟着小程序换成 AI 那张 OSS 全屏图。
library;

import 'package:flutter/material.dart';

/// 视觉稿里的小图标：等比放进方盒。
/// 图缺失时静默留白（保住布局占位），不摆一个刺眼的破图占位。
class AiIcon extends StatelessWidget {
  const AiIcon(this.asset, {super.key, required this.size, this.opacity});

  final String asset;
  final double size;

  /// 少数图标（如方向按钮里的比例图）在视觉稿里是压暗的。
  final double? opacity;

  @override
  Widget build(BuildContext context) {
    final Widget image = Image.asset(
      asset,
      width: size,
      height: size,
      fit: BoxFit.contain,
      errorBuilder: (context, error, stackTrace) =>
          SizedBox(width: size, height: size),
    );
    if (opacity == null) {
      return image;
    }
    return Opacity(opacity: opacity!, child: image);
  }
}

/// 主色：按钮/高亮文字用的品牌橙（小程序 #f26724 / #ff6f25 一系）。
const Color kAiOrange = Color(0xFFF26724);
const Color kAiOrangeStrong = Color(0xFFFF6F25);

/// 正文与次要文字。
const Color kAiText = Color(0xFF555555);
const Color kAiTextStrong = Color(0xFF292929);
const Color kAiTextMuted = Color(0xFF8B8B8B);

/// 页面兜底底色：背景图没加载出来时露出的颜色（取自小程序 `.ai-root` 的 background）。
const Color kAiPageFallback = Color(0xFFF8F5EF);
