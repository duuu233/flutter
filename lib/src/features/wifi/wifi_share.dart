/// WiFi 版设备分享（2026-10-29，同小程序 `utils/wifi-share.js`）的纯逻辑：
/// 详情页「分享设备 / 删除设备」只给所有者，分享列表页分出所有者与接收者，卡片路径与小程序接受页一致。
/// 简化版（服务端未做邀请码）：卡片路径带设备号 / 产品 ID / 设备名 / 所有者 userId 与昵称，
/// 对方在小程序接受页以非所有者绑定（isToHave=0、shareUserId=所有者 userId）。
/// 已知风险：没有一次性 / 过期 / 撤回，卡片被转发时拿到的人都能加入，由服务端校验兜底。
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
  const WifiShareMember({required this.id, required this.name, required this.avatar, required this.joinedAt});

  factory WifiShareMember.fromRow(Map<String, dynamic> row) => WifiShareMember(
    id: '${row['userProductId'] ?? ''}',
    name: '${row['userName'] ?? row['nickName'] ?? ''}'.trim(),
    avatar: '${row['avatar'] ?? row['avatarUrl'] ?? ''}'.trim(),
    joinedAt: '${row['createTime'] ?? row['joinTime'] ?? row['addTime'] ?? ''}'.trim(),
  );

  final String id;
  final String name;
  final String avatar;
  final String joinedAt;
}

/// 列表 → 所有者 + 接收者：isToHave=1 的是所有者（固定第一栏），其余是接收者；
/// 列表里没有所有者时用 [fallbackOwner]（当前用户，进得来这页的就是所有者）。
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

/// 小程序接受页路径（与小程序 `buildAcceptPath` 同格式）：d 设备号（带冒号）、p 产品 ID、u 所有者 userId、n 设备名、o 所有者昵称。
class WifiShareLink {
  WifiShareLink._();

  static const String acceptPage = '/subpackages/device/wifi-share-accept/wifi-share-accept';

  static String acceptPath({
    required String deviceId,
    required Object productId,
    required String ownerUserId,
    String deviceName = '',
    String ownerName = '',
  }) {
    final pairs = <String, String>{
      'd': deviceId,
      'p': '$productId',
      'u': ownerUserId,
      'n': deviceName,
      'o': ownerName,
    }..removeWhere((_, value) => value.trim().isEmpty);
    return '$acceptPage?${pairs.entries.map((e) => '${e.key}=${Uri.encodeComponent(e.value)}').join('&')}';
  }
}
