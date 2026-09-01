part of 'home_page.dart';

/// 首页相关页面统一的文字样式表。
///
/// 各场景共用：`navTitle`/`sectionTitle` 用于标题，`hi`/`welcome`/`brandFallback`
/// 用于已绑定问候语，`deviceCardTitle`/`deviceMeta` 用于设备卡，`bindTitle`/
/// `bindSubtitle`/`orangeLink` 用于绑定流程，`sheet*` 用于底部弹层。
class _HomeTextStyles {
  const _HomeTextStyles._();

  static const navTitle = TextStyle(
    color: Color(0xFF2A2B2B),
    fontSize: 17,
    fontWeight: FontWeight.w600,
    height: 1.2,
  );

  // .hello-title → font-size 82rpx(=41) / weight 500 / #2a2b2b / line-height 1
  static const hi = TextStyle(
    color: Color(0xFF2A2B2B),
    fontSize: 41,
    fontWeight: FontWeight.w500,
    height: 1,
  );

  // .hello-subtitle → font-size 40rpx(=20) / #545963 / line-height 1
  static const welcome = TextStyle(
    color: Color(0xFF545963),
    fontSize: 20,
    fontWeight: FontWeight.w400,
    height: 1,
  );

  // .hello-subtitle text → font-size 44rpx(=22) / weight 800 / #ff7a2e
  static const brand = TextStyle(
    color: Color(0xFFFF7A2E),
    fontSize: 22,
    fontWeight: FontWeight.w800,
    height: 1,
  );

  // .projection-title → font-size 32rpx(=16) / weight 600 / #2a2d32
  static const sectionTitle = TextStyle(
    color: Color(0xFF2A2D32),
    fontSize: 16,
    fontWeight: FontWeight.w600,
    height: 1.2,
  );

  // .empty-hint → font-size 26rpx(=13) / #2a2b2b 60%
  static const mutedBody = TextStyle(
    color: Color(0x992A2B2B),
    fontSize: 13,
    fontWeight: FontWeight.w400,
    height: 1.2,
  );

  // .projection-name → font-size 36rpx(=18) / weight 700 / #2a2d32 / line-height 1
  // 六宫格入口（2026-08-21）：.entry-name 28rpx/600（颜色逐项不同，由卡片 copyWith 覆盖）、
  // .entry-desc 18rpx/#8f959d。
  // ⚠️ 2026-08-31 按需求把六宫格**大标题缩小一号**：14 → 13。
  // ⚠️ 2026-09-01 产品复看真机后又要「适度放大」（原话：目前是放得下的、不会显示 ...）：
  //    13 → 15。小程序 .entry-name 是 28rpx，而 rpx 按屏宽等比 —— 在 390 屏上就是 14.6，
  //    App 这边固定 13 因此看起来比小程序小一档，15 正好把这一档补回来。
  //
  // ⚠️ 这两个字号都只是**基准/上限**，不是最终值：
  //    · 标题由 [_HomeMainView._entryTitleFontSize] 按六条里最长的一条算共用字号，
  //      放不下就往下缩（日文「マイアップロード」一直是最长的那条，本轮前后都缩在 ~11.5，
  //      把基准从 13 抬到 15 对它一个像素都不影响）；
  //    · 副标题由 [_HomeMainView._entrySubtitleFontSize] 反过来算：**放得下才往上长**
  //      （最多 [_HomeMainView._entrySubtitleMaxFontSize]），长不动就退回这里的 9，
  //      所以本轮对副标题是「有余量的语言变大、没余量的与改前逐像素相同」；
  //      ⚠️ 2026-09-01 后半轮又按需求给**安卓**在算出来的值上再减一号
  //      （[_HomeMainView._entrySubtitleAndroidDelta]），**iOS 保持不变**；
  //      同日第三轮再给**安卓**加一条硬约束：从那个值继续往下试到「中文一行就装得下」，
  //      英文一行怎么都装不下、于是原样保持两行完整展示；
  //      ⚠️ 同日第四轮按需求「安卓还要小一个字号」，在上面两步之后**再统一减一号**
  //      （[_HomeMainView._entrySubtitleAndroidFinalDelta]），中文照旧单行、英文照旧两行完整；
  //      ⚠️ 同日第五轮需求「副标题安卓端需要再小二个字号」，就是把那个常量 1 → **3**
  //      （仍加在两步之后 —— 加进前两步的差值里中文一个像素都不会动），中文照旧单行、
  //      英文照旧两行完整。
  //      所以真机上的最终值：iOS 9~11，安卓 5~7，都不是这里的 9。
  static const entryTitle = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w600,
    height: 1.2,
  );

  static const entrySubtitle = TextStyle(
    color: Color(0xFF8F959D),
    fontSize: 9,
    fontWeight: FontWeight.w400,
    height: 1.2,
  );

  static const cardTitle = TextStyle(
    color: Color(0xFF2A2D32),
    fontSize: 18,
    fontWeight: FontWeight.w700,
    height: 1,
  );

  // .projection-desc → font-size 22rpx(=11) / #8a9099 / line-height 1
  static const cardSubtitle = TextStyle(
    color: Color(0xFF8A9099),
    fontSize: 11,
    fontWeight: FontWeight.w400,
    height: 1,
  );

  // .device-title → font-size 40rpx(=20) / weight 500 / #2a2d32
  static const deviceCardTitle = TextStyle(
    color: Color(0xFF2A2D32),
    fontSize: 20,
    fontWeight: FontWeight.w500,
    height: 1.2,
  );

  // .device-status / .battery-row → font-size 24rpx(=12) / #777e88
  static const deviceMeta = TextStyle(
    color: Color(0xFF777E88),
    fontSize: 12,
    fontWeight: FontWeight.w400,
    height: 1.2,
  );

  // .scan-title → 40rpx(=20) / weight 700 / #2a2d32
  static const bindTitle = TextStyle(
    color: Color(0xFF2A2D32),
    fontSize: 20,
    fontWeight: FontWeight.w700,
    height: 1,
  );

  // .scan-desc → 24rpx(=12) / #737a84
  static const bindSubtitle = TextStyle(
    color: Color(0xFF737A84),
    fontSize: 12,
    fontWeight: FontWeight.w400,
    height: 1.2,
  );

  static const orangeLink = TextStyle(
    color: Color(0xFFFF6A24),
    fontSize: 13,
    fontWeight: FontWeight.w400,
    height: 1.2,
  );

  static const sheetTitle = TextStyle(
    color: Color(0xFF2A2B2B),
    fontSize: 22,
    fontWeight: FontWeight.w600,
    height: 1.2,
  );

  static const sheetBody = TextStyle(
    color: Color(0xCC2A2B2B),
    fontSize: 13,
    fontWeight: FontWeight.w400,
    height: 1.2,
  );

  static const helpTitle = TextStyle(
    color: Color(0xFF2A2B2B),
    fontSize: 16,
    fontWeight: FontWeight.w600,
    height: 1.5,
  );

  static const helpBody = TextStyle(
    color: Color(0xCC2A2B2B),
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 1.55,
  );

  // .media-option-copy view → font-size 32rpx(=16) / weight 700 / #2a2d32
  static const sheetOptionTitle = TextStyle(
    color: Color(0xFF2A2D32),
    fontSize: 16,
    fontWeight: FontWeight.w700,
    height: 1.15,
  );

  // .media-option-copy text → font-size 22rpx(=11) / #858b96
  static const sheetOptionBody = TextStyle(
    color: Color(0xFF858B96),
    fontSize: 11,
    fontWeight: FontWeight.w400,
    height: 1,
  );

  static const cancelButton = TextStyle(
    color: Color(0xFF2A2B2B),
    fontSize: 18,
    fontWeight: FontWeight.w500,
    height: 1.2,
    letterSpacing: 2,
  );
}
