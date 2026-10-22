/// 设备图：按机型（产品的 broadcastId，即蓝牙广播名）区分，2026-10-22 起。
///
/// 与小程序 `utils/device-thumb.js` 同口径，改一端必须同步另一端：
///
/// | 机型 | 设备图 |
/// | --- | --- |
/// | EB-169（圆屏） | `home-device-circle-thumb.png` |
/// | EC-370 | `home-device-rectangle-thumb.png` |
/// | 其余（EF6-370 / EF6-589 等）与认不出的 | 原来那张 `home-device-thumb.png` |
///
/// 首页设备卡 / 我的设备 / 设备详情 / 搜索设备 / 命名弹窗 / 投屏选设备共用这里，
/// 别在页面里再写死某一张图——漏改一处只会安静地显示成别的机型。
abstract final class DeviceThumb {
  static const String defaultAsset = 'assets/images/home-device-thumb.png';
  static const String roundAsset = 'assets/images/home-device-circle-thumb.png';
  static const String rectangleAsset =
      'assets/images/home-device-rectangle-thumb.png';

  static const Map<String, String> _byBroadcastId = {
    'EB-169': roundAsset,
    'EC-370': rectangleAsset,
  };

  /// 文本里命中哪个机型的广播ID就返回那张图；大小写不敏感的包含匹配（与扫描白名单同口径）。
  static String? _ofText(String text) {
    final upper = text.toUpperCase();
    if (upper.trim().isEmpty) return null;
    for (final entry in _byBroadcastId.entries) {
      if (upper.contains(entry.key)) return entry.value;
    }
    return null;
  }

  /// 已绑定设备：设备列表接口下发的 `broadcastId` 优先；取不到时后台「形状类型」
  /// `shapeType == 1`（圆形）按 EB-169 圆屏处理；其余默认图。
  /// ⚠️ 设备名是用户起的，不参与判断，否则改个名图就变了。
  static String ofRecord({required String broadcastId, int? shapeType}) =>
      _ofText(broadcastId) ?? (shapeType == 1 ? roundAsset : defaultAsset);

  /// 搜索结果：按本次扫描的蓝牙广播名判断。
  static String ofScanName(String name) => _ofText(name) ?? defaultAsset;
}
