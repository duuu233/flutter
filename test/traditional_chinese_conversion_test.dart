import 'package:BoltStar/src/shared/l10n/app_l10n.dart';
import 'package:BoltStar/src/shared/l10n/chinese_script.dart';
import 'package:BoltStar/src/state.dart';
import 'package:flutter_test/flutter_test.dart';

/// 繁中是由简中文案经 [toTraditionalChinese] 转出来的（2026-09-14 核对）。
///
/// 那次按 OpenCC 台湾标准把 App 里全部简中源文案（`_pick` / `pick` / `tr` 首参、后端 retMsg
/// 兜底表、固件升级失败细节，共 919 段）逐段对了一遍：字表漏了 58 个字（AI 服务协议、星宝、
/// 麦克风、竖向/横向、松开发送、电子纸……繁中下原样显示简体），另有三处转错。这里固定住。
void main() {
  test('AI 模块与全站高频文案：简体字都转成繁体', () {
    const cases = <(String, String)>[
      // AI 助手
      ('星宝努力思考中', '星寶努力思考中'),
      ('松开发送', '鬆開發送'),
      ('您的 AI 创作伙伴，有什么我可以帮您的吗？', '您的 AI 創作夥伴，有什麼我可以幫您的嗎？'),
      ('竖向', '豎向'),
      ('横向', '橫向'),
      ('需要麦克风权限', '需要麥克風權限'),
      ('违反法律法规', '違反法律法規'),
      ('请咨询专业人士', '請諮詢專業人士'),
      // 全站
      ('电子纸设备', '電子紙設備'),
      ('昵称不能为空', '暱稱不能為空'),
      ('当前余额不足', '當前餘額不足'),
      ('显示在这里', '顯示在這裡'),
      ('崩溃日志', '崩潰日誌'),
      ('注册成功', '註冊成功'),
      // 固件升级失败细节（繁中用户会看到原文）
      ('固件包已就绪', '固件包已就緒'),
      ('传输丢包或文件损坏', '傳輸丟包或文件損壞'),
    ];
    for (final (zh, expected) in cases) {
      expect(toTraditionalChinese(zh), expected, reason: zh);
    }
  });

  test('之前转错的三处', () {
    // 「复」一律转成「復」：复制应为「複製」。
    expect(toTraditionalChinese('已复制联系方式'), '已複製聯繫方式');
    // 字表里 0x6D4F（浏）被注释成「济」并映射到「濟」：浏览器变成「濟覽器」。
    expect(toTraditionalChinese('请确认已安装浏览器'), '請確認已安裝瀏覽器');
    // 字表里 0x8D5E（赞）被注释成「赏」并映射到「賞」：赞 → 賞。
    expect(toTraditionalChinese('赞'), isNot('賞'));
    expect(toTraditionalChinese('赏'), '賞');
  });

  test('一字多繁的只按词转，不误伤', () {
    expect(toTraditionalChinese('注意'), '注意'); // 不是「註意」
    expect(toTraditionalChinese('恢复'), '恢復'); // 不是「恢複」
    // 台湾通行写法，有意保持原字。
    expect(toTraditionalChinese('我已了解'), '我已了解');
  });

  test('繁中语种下 AppL10n 取到的是转换后的繁体', () {
    const l10n = AppL10n(AppLanguage.zhHant);
    expect(l10n.aiThinkingPlaceholder, '星寶努力思考中');
    expect(l10n.pick('松开发送', 'Release to send', '離して送信'), '鬆開發送');
  });
}
