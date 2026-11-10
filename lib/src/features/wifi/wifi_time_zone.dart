import '../../state.dart' show AppLanguage;

/// 轮播设置的时区（2026-11-05 同小程序 `utils/time-zone.js`；对接文档 20261105 第二节，20261105-1 第 2 条 / 3.4 改展示）。
/// 服务端按 timeZone 计算间隔 / 固定 / 纪念日的触发时刻，间隔与固定共用一个值。
///   · 只传 IANA 名（Asia/Shanghai 等），不传 UTC+8 这类固定偏移（有夏令时的地区会算错），也不传展示文案（会回 4000）；
///   · 默认：服务端回传了合法 IANA 名就用它；否则按手机当前 UTC 偏移推断（[detect]）。App 没有引入时区插件，
///     Dart 只拿得到偏移和缩写、拿不到 IANA 名，所以按偏移落到候选里同偏移的第一个（UTC+8 固定落 Asia/Shanghai），
///     夏令时期间按「标准偏移 + 1 小时」认有夏令时的候选；候选里也没有就用 Etc/GMT±N（合法 IANA 名，只是没有夏令时）。
///     小程序优先取系统 / Intl 给的 IANA 名，两端在非 UTC+8 地区可能推断出同偏移的不同城市，用户可在弹层里改；
///   · 展示：按 App 语种显示「国家 / 城市」一段文字（如「中国 / 北京」），不带 UTC 偏移；展示文案与提交值是两套数据。
///     不在候选里的时区（回显的 Asia/Kolkata、兜底的 Etc/GMT-5 等）没有译名，原样显示 IANA 名。
class WifiTimeZone {
  const WifiTimeZone(this.id, this.group, this.names, this.offset, {this.dst = false});

  final String id;
  final String group;

  /// 按 [AppLanguage] 顺序（简中 / 繁中 / 英 / 日）的「国家 / 城市」。
  final List<String> names;

  /// 标准时间偏移（分钟，东正西负），只在推断手机时区时用。
  final int offset;

  /// 是否有夏令时（夏令时期间偏移 = [offset] + 60）。
  final bool dst;
}

/// 时区弹层的一行。
class WifiTimeZoneOption {
  const WifiTimeZoneOption({required this.id, required this.group, required this.label, required this.showGroup});

  final String id;
  final String group;
  final String label;

  /// 同组只在第一行显示组名。
  final bool showGroup;
}

abstract final class WifiTimeZones {
  static const String defaultZone = 'Asia/Shanghai';

  static const Map<String, List<String>> _groupNames = {
    'china': ['中国', '中國', 'China', '中国'],
    'asia': ['亚洲', '亞洲', 'Asia', 'アジア'],
    'europe': ['欧洲', '歐洲', 'Europe', 'ヨーロッパ'],
    'america': ['美洲', '美洲', 'Americas', 'アメリカ大陸'],
    'oceania': ['大洋洲', '大洋洲', 'Oceania', 'オセアニア'],
    'current': ['当前', '目前', 'Current', '現在'],
  };

  /// 候选（对接文档 2.3），与小程序同一份。
  static const List<WifiTimeZone> zones = [
    WifiTimeZone('Asia/Shanghai', 'china', ['中国 / 北京', '中國 / 北京', 'China / Beijing', '中国 / 北京'], 480),
    WifiTimeZone('Asia/Hong_Kong', 'china', ['中国 / 香港', '中國 / 香港', 'China / Hong Kong', '中国 / 香港'], 480),
    WifiTimeZone('Asia/Macau', 'china', ['中国 / 澳门', '中國 / 澳門', 'China / Macau', '中国 / マカオ'], 480),
    WifiTimeZone('Asia/Taipei', 'china', ['中国 / 台北', '中國 / 臺北', 'China / Taipei', '中国 / 台北'], 480),
    WifiTimeZone('Asia/Tokyo', 'asia', ['日本 / 东京', '日本 / 東京', 'Japan / Tokyo', '日本 / 東京'], 540),
    WifiTimeZone('Asia/Seoul', 'asia', ['韩国 / 首尔', '韓國 / 首爾', 'South Korea / Seoul', '韓国 / ソウル'], 540),
    WifiTimeZone('Asia/Singapore', 'asia', ['新加坡', '新加坡', 'Singapore', 'シンガポール'], 480),
    WifiTimeZone('Asia/Bangkok', 'asia', ['泰国 / 曼谷', '泰國 / 曼谷', 'Thailand / Bangkok', 'タイ / バンコク'], 420),
    WifiTimeZone('Asia/Dubai', 'asia', ['阿联酋 / 迪拜', '阿聯酋 / 杜拜', 'UAE / Dubai', 'アラブ首長国連邦 / ドバイ'], 240),
    WifiTimeZone('Europe/London', 'europe', ['英国 / 伦敦', '英國 / 倫敦', 'UK / London', 'イギリス / ロンドン'], 0, dst: true),
    WifiTimeZone('Europe/Paris', 'europe', ['法国 / 巴黎', '法國 / 巴黎', 'France / Paris', 'フランス / パリ'], 60, dst: true),
    WifiTimeZone('Europe/Berlin', 'europe', ['德国 / 柏林', '德國 / 柏林', 'Germany / Berlin', 'ドイツ / ベルリン'], 60, dst: true),
    WifiTimeZone('Europe/Moscow', 'europe', ['俄罗斯 / 莫斯科', '俄羅斯 / 莫斯科', 'Russia / Moscow', 'ロシア / モスクワ'], 180),
    WifiTimeZone('America/New_York', 'america', ['美国 / 纽约', '美國 / 紐約', 'USA / New York', 'アメリカ / ニューヨーク'], -300, dst: true),
    WifiTimeZone('America/Chicago', 'america', ['美国 / 芝加哥', '美國 / 芝加哥', 'USA / Chicago', 'アメリカ / シカゴ'], -360, dst: true),
    WifiTimeZone('America/Denver', 'america', ['美国 / 丹佛', '美國 / 丹佛', 'USA / Denver', 'アメリカ / デンバー'], -420, dst: true),
    WifiTimeZone('America/Los_Angeles', 'america', ['美国 / 洛杉矶', '美國 / 洛杉磯', 'USA / Los Angeles', 'アメリカ / ロサンゼルス'], -480, dst: true),
    WifiTimeZone('Australia/Sydney', 'oceania', ['澳大利亚 / 悉尼', '澳洲 / 雪梨', 'Australia / Sydney', 'オーストラリア / シドニー'], 600, dst: true),
    WifiTimeZone('Australia/Perth', 'oceania', ['澳大利亚 / 珀斯', '澳洲 / 伯斯', 'Australia / Perth', 'オーストラリア / パース'], 480),
    WifiTimeZone('Pacific/Auckland', 'oceania', ['新西兰 / 奥克兰', '紐西蘭 / 奧克蘭', 'New Zealand / Auckland', 'ニュージーランド / オークランド'], 720, dst: true),
  ];

  static int _lang(AppLanguage language) => switch (language) {
    AppLanguage.zh => 0,
    AppLanguage.zhHant => 1,
    AppLanguage.en => 2,
    AppLanguage.ja => 3,
  };

  static WifiTimeZone? find(String id) {
    for (final zone in zones) {
      if (zone.id == id) {
        return zone;
      }
    }
    return null;
  }

  /// 形如 Area/City（含 Etc/GMT-8、America/Argentina/Buenos_Aires）；UTC+8、GMT+8 这类固定偏移不算。
  static bool isIana(Object? value) => RegExp(r'^[A-Za-z]+(/[A-Za-z0-9_+\-]+)+$').hasMatch('${value ?? ''}'.trim());

  static String groupName(String key, AppLanguage language) => _groupNames[key]?[_lang(language)] ?? key;

  /// 展示文案：候选里的按语种给「国家 / 城市」；不在候选里的原样显示 IANA 名。
  static String label(String id, AppLanguage language) => find(id)?.names[_lang(language)] ?? id;

  /// 手机时区：按 [offsetMinutes]（缺省取当前 `DateTime.now().timeZoneOffset`）推断，见类注释。
  static String detect({int? offsetMinutes}) {
    final offset = offsetMinutes ?? DateTime.now().timeZoneOffset.inMinutes;
    if (offset == 480) {
      return defaultZone;
    }
    for (final zone in zones) {
      if (zone.offset == offset) {
        return zone.id;
      }
    }
    for (final zone in zones) {
      if (zone.dst && zone.offset + 60 == offset) {
        return zone.id;
      }
    }
    if (offset % 60 == 0 && offset.abs() <= 14 * 60) {
      final hours = offset ~/ 60;
      // Etc/GMT 的符号与习惯相反：Etc/GMT-8 = UTC+8
      return hours == 0 ? 'Etc/GMT' : 'Etc/GMT${hours > 0 ? '-' : '+'}${hours.abs()}';
    }
    return defaultZone;
  }

  /// 选择列表：分组 + 搜索。每行只有一段展示文案（按语种）；搜索认 IANA 名与四种语种的译名、分组名，不区分大小写。
  /// [current] 不在候选里时放到最前面「当前」一组，保证回显的值能看到、能选回。
  static List<WifiTimeZoneOption> options(String keyword, String current, AppLanguage language) {
    final word = keyword.trim().toLowerCase();
    final rows = <({String id, String group, String label})>[];
    if (current.isNotEmpty && find(current) == null) {
      if (word.isEmpty || current.toLowerCase().contains(word)) {
        rows.add((id: current, group: groupName('current', language), label: current));
      }
    }
    for (final zone in zones) {
      final text = [zone.id, ...zone.names, ...?_groupNames[zone.group]].join(' ').toLowerCase();
      if (word.isEmpty || text.contains(word)) {
        rows.add((id: zone.id, group: groupName(zone.group, language), label: zone.names[_lang(language)]));
      }
    }
    return [
      for (var i = 0; i < rows.length; i++)
        WifiTimeZoneOption(
          id: rows[i].id,
          group: rows[i].group,
          label: rows[i].label,
          showGroup: i == 0 || rows[i - 1].group != rows[i].group,
        ),
    ];
  }
}
