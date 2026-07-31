import 'package:shared_preferences/shared_preferences.dart';

/// 「最近一次绑定的设备」记忆（移植小程序 `RECENTLY_BOUND_DEVICE_KEY`，2026-07-31）。
///
/// 用途只有一个：设备列表排序的第二优先级——**正在连接的设备置顶，其次是刚绑定的设备**
///（需求第 6 项）。刚绑完一台设备回到列表，用户第一眼要找的就是它；后端列表顺序按绑定时间
/// 未必稳定，也可能把新设备排到十几台之后。
///
/// 只存一个 `userProductId`，本机保存：换账号后这个主键与新用户无关，退出登录时清掉
///（同 [DeviceIdentityRegistry] 的理由）。读不到 / 存储不可用一律回落空串——
/// 排序退化成「连接优先 + 接口原序」，不影响功能。
class RecentlyBoundDevice {
  RecentlyBoundDevice._();

  static final RecentlyBoundDevice instance = RecentlyBoundDevice._();

  static const String _storageKey = 'recently_bound_device_id';

  /// 内存镜像。null = 尚未从磁盘读回。
  String? _cached;

  /// 同步读当前值（未加载过时返回空串）。排序发生在 build 里，不能等异步。
  String get value => _cached ?? '';

  /// 从磁盘读回并填充内存镜像。页面 initState 里调一次即可。
  Future<String> load() async {
    final cached = _cached;
    if (cached != null) {
      return cached;
    }
    var value = '';
    try {
      final sp = await SharedPreferences.getInstance();
      value = sp.getString(_storageKey)?.trim() ?? '';
    } catch (_) {
      // 偏好不可用：降级为纯内存，排序退化成「连接优先 + 接口原序」。
    }
    _cached = value;
    return value;
  }

  Future<void> remember(String deviceId) async {
    final id = deviceId.trim();
    if (id.isEmpty) {
      return;
    }
    _cached = id;
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(_storageKey, id);
    } catch (_) {
      // 同上：写失败只影响下次冷启动的排序。
    }
  }

  /// 退出登录 / 注销 / 解绑这一台时清掉。
  Future<void> clear() async {
    _cached = '';
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.remove(_storageKey);
    } catch (_) {}
  }
}
