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

  // .device-title → font-size 40rpx(=20) / weight 700 / #2a2d32
  static const deviceCardTitle = TextStyle(
    color: Color(0xFF2A2D32),
    fontSize: 20,
    fontWeight: FontWeight.w700,
    height: 1.2,
  );

  // .device-status / .battery-row → font-size 24rpx(=12) / #777e88
  static const deviceMeta = TextStyle(
    color: Color(0xFF777E88),
    fontSize: 12,
    fontWeight: FontWeight.w400,
    height: 1.2,
  );

  static const bindTitle = TextStyle(
    color: Color(0xFF2A2B2B),
    fontSize: 20,
    fontWeight: FontWeight.w600,
    height: 1.2,
  );

  static const bindSubtitle = TextStyle(
    color: Color(0x992A2B2B),
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

  static const deviceName = TextStyle(
    color: Color(0xFF2A2B2B),
    fontSize: 16,
    fontWeight: FontWeight.w600,
    height: 1.2,
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
