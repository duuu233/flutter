import 'package:flutter/material.dart';

/// 星币模块（星币管理 / 确认购买 / 记录）那几张白卡的卡底。
///
/// 小程序 `subpackages/token` 里同一套「白底 + 白描边 + 圆角 24rpx + 柔光投影」，
/// 只是不透明度按块微调，所以这里把三个 alpha 做成参数，各调用点照 CSS 原值写：
///
/// | 用处 | 小程序类 | fill / border / shadow |
/// | --- | --- | --- |
/// | 记录入口、消耗规则表 | `.record-entry` / `.rule-card` | .78 / .88 / .10 |
/// | 确认购买的套餐概览卡 | `.summary-card` | .86 / .90 / .10 |
/// | 支付方式行 | `.pay-row` | .80 / .88 / .08 |
///
/// ⚠️ **不是** 全站的 `FigmaGlassCard`（白 .55 / 圆角 14 / 投影 (0,12) blur 27）——
/// 那是另一套观感，本模块跟小程序对齐用不上它；反过来改 `FigmaGlassCard` 会牵动十几个页面。
/// 同样的取舍「我的」页 `_ServiceRow` 先做过一次。
class StarCard extends StatelessWidget {
  const StarCard({
    super.key,
    required this.child,
    required this.padding,
    this.fill = 0.78,
    this.border = 0.88,
    this.shadow = 0.10,
    this.borderColor,
    this.shadowColor = const Color(0xFF7D94B5),
    this.radius = 12,
  });

  final Widget child;
  final EdgeInsets padding;

  /// 白底不透明度（小程序 `background: rgba(255,255,255,x)`）。
  final double fill;

  /// 白描边不透明度（小程序 `border: 2rpx solid rgba(255,255,255,x)`）。
  final double border;

  /// 投影不透明度（小程序 `box-shadow: 0 16rpx 38rpx rgba(125,148,181,x)`）。
  final double shadow;

  /// 选中态等需要换描边颜色时传（如支付方式行的橙色描边），不传即白描边。
  final Color? borderColor;

  /// 投影颜色。选中态会换成主题橙（小程序 `.pay-row--active` 的
  /// `box-shadow: … rgba(255,106,30,.12)`），其余一律是那层冷灰。
  final Color shadowColor;

  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: fill),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: borderColor ?? Colors.white.withValues(alpha: border),
        ),
        boxShadow: [
          BoxShadow(
            // 0 16rpx 38rpx → 偏移 8、模糊 19
            color: shadowColor.withValues(alpha: shadow),
            blurRadius: 19,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }
}
