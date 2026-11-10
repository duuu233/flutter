/// WiFi 版设备分享（2026-10-29，同小程序 `utils/wifi-share.js`）的纯逻辑：
/// 详情页「删除设备」只给所有者（「共享设备」入口 2026-11-05 起接收者也有，进去只看不改），共享设备页分出所有者与接收者，
/// 卡片路径与小程序接受页一致。
/// 简化版（服务端未做邀请码）：卡片路径带设备号 / 产品 ID / 设备名 / 所有者 userId 与昵称，
/// 对方在小程序接受页以非所有者绑定（isToHave=0、shareUserId=所有者 userId）。
/// 有效期（2026-11-04，同小程序）：卡片带分享时的服务器时间戳 t（getCurrentTime），小程序接受页用 chkTimeValid 判断是否过期，
/// 过期规则在服务端；不带 t 的卡片小程序按无效处理。仍没有一次性 / 撤回，有效期内卡片被转发时拿到的人都能加入。
library;

/// 是否所有者：isToHave=1 是；带分享者 shareUserId 的是接收者；两者都没有的是分享上线前绑定的老记录，按所有者算。
bool wifiIsOwner(Map<String, dynamic> detail) {
  if ('${detail['isToHave'] ?? ''}' == '1') {
    return true;
  }
  final shareUserId = num.tryParse('${detail['shareUserId'] ?? ''}') ?? 0;
  return shareUserId <= 0;
}

/// 分享列表的一行。
class WifiShareMember {
  const WifiShareMember({
    required this.id,
    required this.name,
    required this.avatar,
    required this.joinedAt,
    this.canDel = false,
  });

  factory WifiShareMember.fromRow(Map<String, dynamic> row) => WifiShareMember(
    id: '${row['userProductId'] ?? ''}',
    name: '${row['userName'] ?? row['nickName'] ?? ''}'.trim(),
    avatar: '${row['avatar'] ?? row['avatarUrl'] ?? ''}'.trim(),
    // 加入时间取分享列表接口的 joinTime，原样显示；为空页面显示「--」（2026-10-29 同小程序，不再拿 createTime 兜底）
    joinedAt: '${row['joinTime'] ?? ''}'.trim(),
    // 能否解绑（2026-11-05 接口新增 isCanDel，后端控制，== 1 才显示「移除」；字符串 '1' 也认，同小程序 toMember）
    canDel: num.tryParse('${row['isCanDel'] ?? ''}') == 1,
  );

  final String id;
  final String name;
  final String avatar;
  final String joinedAt;

  /// 成员接口 isCanDel == 1：这一行显示「移除」、能解绑；前端不再按所有者 / 接收者判断（2026-11-05，同小程序）。
  final bool canDel;
}

/// 列表 → 所有者 + 接收者：isToHave=1 的是所有者（固定第一栏），其余是接收者；
/// 列表里没有所有者时用 [fallbackOwner]：只有所有者本人进来时传当前用户；接收者传 null（否则会把自己显示成所有者）。
({WifiShareMember? owner, List<WifiShareMember> members}) wifiSplitMembers(
  List<Map<String, dynamic>> rows,
  WifiShareMember? fallbackOwner,
) {
  WifiShareMember? owner;
  final members = <WifiShareMember>[];
  for (final row in rows) {
    if (owner == null && '${row['isToHave'] ?? ''}' == '1') {
      owner = WifiShareMember.fromRow(row);
    } else {
      members.add(WifiShareMember.fromRow(row));
    }
  }
  return (owner: owner ?? fallbackOwner, members: members);
}

/// getCurrentTime 的 retData → 时间戳字符串（原样，不换算单位）；不是正整数返回 null（不能分享）。
String? wifiShareTime(dynamic data) {
  final text = '${data ?? ''}'.trim();
  if (!RegExp(r'^\d+$').hasMatch(text) || (int.tryParse(text) ?? 0) <= 0) {
    return null;
  }
  return text;
}

/// 小程序接受页路径（与小程序 `buildAcceptPath` 同格式）：d 设备号（带冒号）、p 产品 ID、u 所有者 userId、n 设备名、o 所有者昵称、
/// t 分享时的服务器时间戳（原样）。
class WifiShareLink {
  WifiShareLink._();

  static const String acceptPage = '/subpackages/device/wifi-share-accept/wifi-share-accept';

  static String acceptPath({
    required String deviceId,
    required Object productId,
    required String ownerUserId,
    String deviceName = '',
    String ownerName = '',
    String shareTime = '',
  }) {
    final pairs = <String, String>{
      'd': deviceId,
      'p': '$productId',
      'u': ownerUserId,
      'n': deviceName,
      'o': ownerName,
      't': shareTime,
    }..removeWhere((_, value) => value.trim().isEmpty);
    return '$acceptPage?${pairs.entries.map((e) => '${e.key}=${Uri.encodeComponent(e.value)}').join('&')}';
  }
}
