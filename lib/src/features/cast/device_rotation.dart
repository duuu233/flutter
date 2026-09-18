/// 投屏导出时整幅构图的顺时针旋转角（度）：**两种取景方向各有自己的真源，互不通用**。
///
/// 与小程序 `utils/device-rotation.js` **同口径**（2026-09-18 对齐；在那之前 App 的横向角
/// 是写死的 270°，后台把这个产品配成 90° 之后两端就差了 180°——设备上看就是「反过来了」）：
///
/// - **横向 landscape** → 设备字段 `rotationDegree`；取不到/非法时保持历史 **270°**；
/// - **竖向 portrait** → 设备字段 `verticalRotation`（2026-08-04 新增）；取不到/非法时 **0° = 不旋转**。
///
/// ⚠️ **0 是合法角度**（设备明确要求不转），判空只能判 null / 空串，
/// 绝不能写成 `raw ?? 0 == 0 ? 默认角 : raw` 这种真假值判断——那会把「明确不转」当成缺失。
library;

abstract final class DeviceRotation {
  /// 横向缺省角（历史行为，不要改）。
  static const int landscapeFallbackDeg = 270;

  /// 竖向缺省角：产品口径「没有这个参数就不旋转」。
  static const int verticalFallbackDeg = 0;

  /// 横向角字段名。
  static const String landscapeKey = 'rotationDegree';

  /// 竖向角字段名。`verticalRotation` 是与后端约定的正式名，后两个只是大小写/后缀兼容，
  /// 后端定稿后可以删；**命中顺序即优先级**（与小程序 `VERTICAL_KEYS` 一致）。
  static const List<String> verticalKeys = <String>[
    'verticalRotation',
    'verticalRotationDegree',
    'verticalrotation',
  ];

  /// 从设备接口返回体里取横向导出角。
  static int landscapeDegreeFrom(Map<String, dynamic> data) =>
      _degree(data[landscapeKey], landscapeFallbackDeg);

  /// 从设备接口返回体里取竖向导出角。
  static int verticalDegreeFrom(Map<String, dynamic> data) =>
      _degree(_pickVertical(data), verticalFallbackDeg);

  /// 返回体里**有没有**带横向角这个键（值可以是 0）。详情接口合并时用它区分
  /// 「接口没给」和「接口给了 0」。
  static bool hasLandscapeKey(Map<String, dynamic> data) =>
      data.containsKey(landscapeKey);

  /// 返回体里**有没有**带竖向角（三个兼容名任意一个）。
  static bool hasVerticalKey(Map<String, dynamic> data) =>
      verticalKeys.any(data.containsKey);

  static Object? _pickVertical(Map<String, dynamic> data) {
    for (final key in verticalKeys) {
      final value = data[key];
      if (value != null && value != '') {
        return value;
      }
    }
    return null;
  }

  /// null / 空串 / 解不出数字 → [fallback]；其余按四舍五入取整
  /// （后端给的是整度数，小数只可能来自脏数据，不能直接截断成 0）。
  static int _degree(Object? raw, int fallback) {
    if (raw == null || raw == '') return fallback;
    if (raw is int) return raw;
    if (raw is num) return raw.isFinite ? raw.round() : fallback;
    if (raw is String) {
      final parsed = num.tryParse(raw.trim());
      if (parsed == null || !parsed.isFinite) return fallback;
      return parsed.round();
    }
    return fallback;
  }
}
