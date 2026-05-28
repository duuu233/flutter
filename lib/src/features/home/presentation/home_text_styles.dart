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

  static const hi = TextStyle(
    color: Color(0xFF2A2B2B),
    fontSize: 43,
    fontWeight: FontWeight.w500,
    height: 1,
  );

  static const welcome = TextStyle(
    color: Color(0xFF2A2B2B),
    fontSize: 21,
    fontWeight: FontWeight.w400,
    height: 1,
  );

  static const brandFallback = TextStyle(
    color: Color(0xFFFF7D36),
    fontSize: 22,
    fontWeight: FontWeight.w700,
    height: 1,
  );

  static const sectionTitle = TextStyle(
    color: Color(0xFF2A2B2B),
    fontSize: 17,
    fontWeight: FontWeight.w600,
    height: 1.2,
  );

  static const mutedBody = TextStyle(
    color: Color(0x992A2B2B),
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 1.2,
  );

  static const cardTitle = TextStyle(
    color: Color(0xFF2A2B2B),
    fontSize: 18,
    fontWeight: FontWeight.w600,
    height: 1.2,
  );

  static const cardSubtitle = TextStyle(
    color: Color(0x992A2B2B),
    fontSize: 12,
    fontWeight: FontWeight.w400,
    height: 1.2,
  );

  static const deviceCardTitle = TextStyle(
    color: Color(0xFF2A2B2B),
    fontSize: 23,
    fontWeight: FontWeight.w600,
    height: 1.2,
  );

  static const deviceMeta = TextStyle(
    color: Color(0x992A2B2B),
    fontSize: 13,
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

  static const sheetOptionTitle = TextStyle(
    color: Color(0xFF2A2B2B),
    fontSize: 16,
    fontWeight: FontWeight.w600,
    height: 1.15,
  );

  static const sheetOptionBody = TextStyle(
    color: Color(0x992A2B2B),
    fontSize: 12,
    fontWeight: FontWeight.w400,
    height: 1.2,
  );

  static const cancelButton = TextStyle(
    color: Color(0xFF2A2B2B),
    fontSize: 18,
    fontWeight: FontWeight.w500,
    height: 1.2,
    letterSpacing: 2,
  );
}
