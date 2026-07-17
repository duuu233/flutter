import 'package:flutter/material.dart';

import 'package:BoltStar/src/shared/widgets/figma_common.dart';
import '../../../shared/l10n/app_l10n.dart';
import 'legal_document_view.dart';

/// 用户协议页面，简中正文与小程序 `subpackages/settings/agreement` 保持一致；
/// en/ja 为对应译文，繁中由简中经 l10n 自动转换（与全 App 文案同规则）。
class UserAgreementPage extends StatelessWidget {
  const UserAgreementPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    return FigmaScreen(
      title: l10n.setAgreementTitle,
      scrollable: false,
      bodyPadding: EdgeInsets.zero,
      body: LegalDocumentView(
        title: l10n.pick(
          '《BoltStar 用户协议》',
          'BoltStar User Agreement',
          '「BoltStar 利用規約」',
        ),
        updatedAt: '2026-5-13',
        effectiveAt: '2026-5-13',
        sections: _sectionsFor(l10n),
      ),
    );
  }

  List<LegalSection> _sectionsFor(AppL10n l10n) {
    return [
      LegalSection(
        heading: l10n.pick('前言', 'Introduction', 'はじめに'),
        body: l10n.pick(
          '欢迎使用 BoltStar。在使用本应用前，请您仔细阅读《用户协议》以及《隐私政策》。'
              '您注册、登录或使用本应用的行为，即表示您已充分理解并同意接受本协议的全部条款约束。',
          'Welcome to BoltStar. Please read the User Agreement and Privacy '
              'Policy carefully before using the App. By registering, '
              'logging in, or using the App, you acknowledge that you have '
              'fully understood and agreed to be bound by all terms of this '
              'Agreement.',
          'BoltStar をご利用いただきありがとうございます。本アプリをご利用になる前に、'
              '「利用規約」および「プライバシーポリシー」をよくお読みください。'
              '登録・ログイン・利用をもって、本規約のすべての条項を十分に理解し、'
              'これに同意したものとみなされます。',
        ),
      ),
      LegalSection(
        heading: l10n.pick('一、服务说明', '1. Service Description', '一、サービス内容'),
        body: l10n.pick(
          '1. 本应用由 BoltStar 团队提供照片管理、设备连接、照片投屏等核心服务。\n'
              '2. 我们将尽最大努力保障服务稳定性，但因网络故障、设备问题、第三方服务影响等不可抗因素导致的服务中断或异常，'
              '我们不承担责任，但会尽力协助处理。\n'
              '3. 我们保留随时修改、升级或终止部分或全部服务的权利，修改或终止前会通过 App 内公告提前告知您。',
          '1. The App is provided by the BoltStar team and offers core '
              'services such as photo management, device connection, and '
              'photo casting.\n'
              '2. We will do our best to keep the service stable. However, '
              'we are not liable for service interruptions or anomalies '
              'caused by factors beyond our control, such as network '
              'failures, device issues, or third-party services, though we '
              'will do our best to assist.\n'
              '3. We reserve the right to modify, upgrade, or terminate '
              'some or all of the services at any time. You will be '
              'notified in advance via in-app announcements.',
          '1. 本アプリは BoltStar チームが提供し、写真管理・デバイス接続・写真投影などの'
              '中核サービスを提供します。\n'
              '2. サービスの安定性維持に最善を尽くしますが、ネットワーク障害・デバイスの問題・'
              '第三者サービスの影響など不可抗力に起因するサービスの中断・異常について当社は責任を負いません。'
              'ただし、解決に向けて可能な限り協力します。\n'
              '3. 当社は、サービスの一部または全部をいつでも変更・更新・終了する権利を留保します。'
              '実施前にアプリ内のお知らせで事前に通知します。',
        ),
      ),
      LegalSection(
        heading: l10n.pick(
          '二、账号注册与使用规则',
          '2. Account Registration and Usage Rules',
          '二、アカウント登録と利用ルール',
        ),
        body: l10n.pick(
          '1. 您需提供真实、有效的信息完成账号注册，并对您账号下的所有行为负责。\n'
              '2. 您应妥善保管账号、密码及验证码信息，因您自身原因导致的账号被盗、信息泄露或财产损失，由您自行承担责任。',
          '1. You must provide true and valid information to register an '
              'account, and you are responsible for all activities under '
              'your account.\n'
              '2. Please keep your account, password, and verification '
              'codes safe. You are responsible for any account theft, '
              'information leakage, or property loss caused by your own '
              'actions.',
          '1. 真実かつ有効な情報でアカウント登録を行い、アカウント下のすべての行為に責任を負うものとします。\n'
              '2. アカウント・パスワード・認証コードは適切に管理してください。'
              'お客様自身の原因によるアカウントの盗用・情報漏えい・財産上の損失は、お客様の責任となります。',
        ),
      ),
    ];
  }
}
