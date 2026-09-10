import 'package:flutter/material.dart';

import 'package:BoltStar/src/shared/widgets/figma_common.dart';
import '../../../shared/l10n/app_l10n.dart';
import 'legal_document_view.dart';

/// 用户协议页面。
///
/// ⚠️ **正文固定英文，不随语种设置切换**（2026-09-10 产品要求，与隐私政策同一口径）：
/// 法务只出具了中英两版，App 端取英文、小程序端取简中；其余语种没有对应的、经审阅的
/// 文本，机翻一份法律文本再摆到设置页里，比只给英文更糟——所以这里**不走**
/// `AppL10n.pick`，页面标题仍随语种（那只是入口名字，不是条款）。
///
/// 2026-09-10 之前这一页是 2026-5-13 的旧短文（前言 + 服务说明 + 账号规则三节、中英日
/// 三份译文），与小程序端同源；法务这次给的是 15 章全文，含星币、AI、固件升级、
/// 违规处理阶梯表与争议解决，旧短文整体作废。
///
/// 正文由法务 docx「BoltStar User Agreement (EN) 20260909(1).docx」逐块转换而来（转换脚本
/// 一次性使用、未入仓，做法见对应变更记录）。这是**法律文本**：改动只能来自法务给的新文档，
/// 重新生成，不要在这里改措辞。文档自带的目录（TOC）没有转换进来——页面没有锚点跳转能力。
///
/// ⚠️ 相对法务原文有三处经产品确认的**排版**修正（措辞一字未改，逐条列在转换脚本里）：
///   ① 生效日期原文是 `[To be completed: effective date]`，按产品口径填 September 10, 2026；
///   ② 粗体 run 边界造成的句号后缺空格 6 处（如 `app.If`、`bold.By`）已补齐；
///   ③ 同一来源的标点前多空格 1 处（`(App Store) ; in the WeChat`）已收齐。
/// 文档版本：Last Updated: August 28, 2026  Effective Date: September 10, 2026  Version: V1.0
class UserAgreementPage extends StatelessWidget {
  const UserAgreementPage({super.key});

  @override
  Widget build(BuildContext context) {
    return FigmaScreen(
      // 页面标题＝设置页那一行的名字，仍随语种；正文见类注释，固定英文。
      title: AppL10n.of(context).setAgreementTitle,
      scrollable: false,
      bodyPadding: EdgeInsets.zero,
      body: LegalDocumentView(
        title: 'BoltStar User Agreement',
        updatedAt: 'August 28, 2026',
        effectiveAt: 'September 10, 2026',
        intro: 'This Agreement is entered into between you and BoltStar '
            '(Shenzhen) New Energy Technology Co., Ltd. ("we") regarding your '
            'use of the companion app for the BoltStar e-paper photo frame '
            '(including the iOS app, the Android app, and the WeChat mini '
            'program, hereinafter collectively the "App").\nBefore '
            'registering, logging in, or using this App, please read this '
            'Agreement in full and carefully, especially the disclaimer '
            'clauses, limitation-of-liability clauses, virtual property (Star '
            'Coins) clauses, and dispute resolution clauses marked in bold. '
            'By checking to agree, registering, logging in, or otherwise '
            'using this App, you are deemed to have fully understood and '
            'agreed to be bound by the entire contents of this Agreement. If '
            'you do not agree to any provision of this Agreement, please stop '
            'using this App immediately.',
        sections: userAgreementSections,
      ),
    );
  }

  /// 章节正文。**公开**是为了让单测能直接断言（法律文本要能回归：章节数、
  /// 第九章的违规处理表列数是否整齐），不是给别处复用的。共 15 章。
  static const List<LegalSection> userAgreementSections = <LegalSection>[
    LegalSection(
      heading: '1. Formation and Amendment of the Agreement',
      blocks: <LegalBlock>[
        LegalText('This Agreement includes the body of the Agreement and all '
            'rules related to this App that we have published or may publish '
            'in the future, including the BoltStar Privacy Policy and the '
            'BoltStar AI Service Agreement. Such rules constitute an integral '
            'part of this Agreement and have the same legal effect as this '
            'Agreement.', bullet: true),
        LegalText('We have the right to amend this Agreement in response to '
            'changes in laws and regulations or business needs. After any '
            'amendment, we will notify you in a prominent manner within the '
            'app. If you continue to use this App after an amendment takes '
            'effect, you are deemed to have accepted the amended content; if '
            'you do not accept it, you should stop using this App and may '
            'delete your account.', bullet: true),
      ],
    ),
    LegalSection(
      heading: '2. Service Contents',
      blocks: <LegalBlock>[
        LegalText('This App provides companion services for the BoltStar '
            'e-paper photo frame (the "Device"), currently including:'),
        LegalText('Device management: search for, bind to, connect to, and '
            'rename the device via Bluetooth; view the device\'s battery '
            'level, firmware version, and storage capacity; set the slideshow '
            'playback mode and switching interval; delete photos in the '
            'device or clear them all with one tap.', bullet: true),
        LegalText('Photo casting: select local photos; after cropping, '
            'composition, and frame conversion, transfer them to the device '
            'via Bluetooth for display.', bullet: true),
        LegalText('My Album: view and manage records of successfully casted '
            'photos, with multi-select deletion supported.', bullet: true),
        LegalText('Official Gallery: browse the image materials we provide, '
            'favorite them, and cast them.', bullet: true),
        LegalText('AI creation: text chat, text-to-image generation, image '
            'upload for beautification, and casting of the generated results.', bullet: true),
        LegalText('Star Coins: in-app virtual items consumed to use AI '
            'capabilities; purchasable within the app.', bullet: true),
        LegalText('Firmware upgrade: detect and upgrade the device firmware '
            'via Bluetooth.', bullet: true),
        LegalText('We may add, adjust, or discontinue some functions from '
            'time to time; the actual display in the version you use shall '
            'prevail. Functions and payment methods may differ across '
            'platforms (iOS / Android / WeChat mini program).'),
      ],
    ),
    LegalSection(
      heading: '3. Account Registration, Use, and Deletion',
      blocks: <LegalBlock>[
        LegalText('You need to complete registration and log-in as prompted '
            'on the page. You shall ensure that the mobile phone number and '
            'other information you provide is true, accurate, and lawful and '
            'valid; if false information prevents you from using the services '
            'or causes losses, you shall bear the consequences yourself.', bullet: true),
        LegalText('The account is for your personal use only and may not be '
            'lent, transferred, sold, or otherwise licensed to others. You '
            'shall properly keep your account and verification codes safe. '
            'Any operation performed through your account is deemed to be '
            'your own act, and you shall bear the resulting liability.', bullet: true),
        LegalText('If you discover that your account has been illegally used '
            'by others or has security vulnerabilities, please notify us '
            'immediately via the means in Section 15.', bullet: true),
        LegalText('Account deletion: you may delete your account yourself via '
            '"Me → Settings → Delete Account". After deletion, the account '
            'data will be deleted or anonymized; the Star Coin balance, '
            'casting records, AI conversations, and device bindings in the '
            'account will be cleared together and cannot be recovered, and '
            'unconsumed Star Coins will not be refunded (except as otherwise '
            'provided by laws and regulations). Please clear the photos in '
            'your device yourself before deleting your account— after '
            'deletion, the binding is released, and you will no longer be '
            'able to delete the images already displayed on the device '
            'through this App.', bullet: true),
      ],
    ),
    LegalSection(
      heading: '4. Device Connection and Usage Rules',
      blocks: <LegalBlock>[
        LegalText('This App communicates with the device via Bluetooth Low '
            'Energy (BLE), and the device supports connection with only one '
            'phone at a time. Before use, please make sure the device is '
            'powered on, sufficiently charged, and close to the phone.', bullet: true),
        LegalText('The operating system requires the App to obtain location '
            'permission before it can scan for nearby Bluetooth devices. '
            'Please grant it when prompted by the system; otherwise the '
            'device cannot be found.', bullet: true),
        LegalText('A device can be bound by different accounts in turn. '
            'Unbinding or deleting your account does not automatically clear '
            'the images already displayed on the device; please handle them '
            'yourself.', bullet: true),
        LegalText('Do not power off the device, disconnect Bluetooth, exit '
            'the app, or let the phone sleep during casting or firmware '
            'upgrade, otherwise the operation may fail.', bullet: true),
      ],
    ),
    LegalSection(
      heading: '5. Photo Casting and Content Rules',
      blocks: <LegalBlock>[
        LegalText('You may cast only photos that you took or created yourself '
            'or for which you have lawfully obtained authorization. You are '
            'responsible for the legality of the content you cast, and you '
            'must not cast content that infringes others\' portrait rights, '
            'copyrights, or privacy, or that violates laws and regulations.', bullet: true),
        LegalText('Due to the limitations of e-paper display technology, the '
            'colors, gradation, and sharpness presented by the device differ '
            'from those of a phone screen, and casted images must go through '
            'cropping, composition, and color conversion. Such differences '
            'are technical characteristics and do not constitute product '
            'quality issues.', bullet: true),
        LegalText('During casting, the photos you select are uploaded to our '
            'servers and the image processing service for frame conversion; '
            'see the BoltStar Privacy Policy for details.', bullet: true),
        LegalText('Deleting a casting record in the app does not delete the '
            'image in the device, and vice versa; please follow the on-screen '
            'instructions to operate them separately.', bullet: true),
      ],
    ),
    LegalSection(
      heading: '6. AI Creation Services',
      blocks: <LegalBlock>[
        LegalText('AI features are optional services. Before first use, you '
            'must separately read and agree to the BoltStar AI Service '
            'Agreement; declining does not affect your use of other features '
            'of this App.', bullet: true),
        LegalText('The text or images you actively send in AI conversations '
            'will be transferred to the "Volcano Engine" AI service (provided '
            'by Beijing Volcano Engine Technology Co., Ltd.) for processing. '
            'The content sent is used only for the current operation and will '
            'not be used for model training.', bullet: true),
        LegalText('AI-generated content is produced automatically by '
            'algorithms and may be inaccurate, incomplete, or not as you '
            'expected; it does not constitute any professional advice. Please '
            'judge and verify it yourself before use. We do not guarantee the '
            'accuracy or applicability of generated content.', bullet: true),
        LegalText('You must not use AI features to generate or disseminate '
            'content that violates the conduct rules in Section 9. You shall '
            'bear responsibility for third-party claims arising from your '
            'input or your use of generated content.', bullet: true),
        LegalText('Subject to compliance with this Agreement, you own the '
            'intellectual property rights in the images and text materials '
            'you upload or shoot yourself; output generated by public AI '
            'models carries no exclusive rights — identical inputs may '
            'produce similar outputs, and we may provide equivalent AI '
            'generation services to other users.', bullet: true),
        LegalText('AI conversation records are retained on the server for '
            'only the most recent 7 days and are automatically cleared upon '
            'expiration; please save any content you wish to keep yourself.', bullet: true),
        LegalText('AI services depend on third-party capabilities and '
            'networks and may experience queuing, timeouts, or temporary '
            'unavailability; where Star Coins have been deducted but no '
            'result was produced due to our fault, please contact us via the '
            'means in Section 15 for handling.', bullet: true),
      ],
    ),
    LegalSection(
      heading: '7. Star Coins and Payment Rules',
      blocks: <LegalBlock>[
        LegalText('Star Coins are virtual items within this App used to '
            'redeem consumable services such as AI generation, and are not '
            'prepaid cards, have no monetary value, cannot be exchanged for '
            'or withdrawn as cash, and cannot be transferred between users.', bullet: true),
        LegalText('Purchase channels: purchases are completed on iOS via '
            'Apple In-App Purchase (App Store); in the WeChat mini program '
            'via WeChat Virtual Payment. Actual crediting is subject to our '
            'server records. Purchases are also governed by the terms of the '
            'corresponding payment platforms.', bullet: true),
        LegalText('Pricing and consumption rules are subject to the tiers and '
            'the "Star Coin Consumption Rules" displayed in the app at the '
            'time. We may adjust the tiers and consumption rules from time to '
            'time; adjustments apply only to purchases and consumption made '
            'after the adjustment and are not retroactive.', bullet: true),
        LegalText('Refunds: For Star Coins purchased through any channel, if '
            'you need a refund, please first apply through the corresponding '
            'channel (Apple App Store or WeChat Pay), which will conduct '
            'preliminary handling under its own rules. If you disagree with '
            'the channel\'s handling result, or the channel is unable to '
            'handle it, you may contact us, and we will make a final decision '
            'after verification in accordance with this Agreement and '
            'applicable laws and regulations. Star Coins, once consumed '
            '(i.e., used to generate AI content, etc.), will not be refunded. '
            'Where duplicate charges or non-crediting occur due to our '
            'system, we will reissue or refund after verification.', bullet: true),
        LegalText('Star Coins have no expiration date; when an account is '
            'permanently banned or deleted, the account data will be deleted '
            'or anonymized, and the Star Coin balance and device bindings in '
            'the account will be cleared together and cannot be recovered; in '
            'normal voluntary account deletion, unconsumed Star Coins will '
            'not be refunded; if Star Coins cannot be used normally due to a '
            'failure of our system, you may contact customer service with '
            'proof for verification and handling.', bullet: true),
        LegalText('You should purchase through official channels. Where Star '
            'Coins are obtained by purchasing through unofficial channels, or '
            'by improper means such as plug-ins, scripts, or exploiting '
            'vulnerabilities, we have the right to reclaim the corresponding '
            'Star Coins and handle the account according to the severity of '
            'the circumstances.', bullet: true),
      ],
    ),
    LegalSection(
      heading: '8. Firmware Upgrades and Device Risk Notices',
      blocks: <LegalBlock>[
        LegalText('To fix issues or improve the experience, we may release '
            'device firmware updates and prompt you to upgrade within the '
            'app. Some versions may be mandatory updates; failure to upgrade '
            'may cause some functions to become unavailable.', bullet: true),
        LegalText('During the upgrade, please wait patiently for the result; '
            'unexpected interruption may render the e-paper device unusable. '
            'During the upgrade, please keep the device sufficiently powered, '
            'keep the phone close to the device, and do not exit the upgrade '
            'page or let the phone sleep.', bullet: true),
        LegalText('If a failed upgrade leaves the device unconnectable, '
            'please try re-entering the mini program / app or power-cycling '
            'the device; if it still cannot be recovered, please contact us '
            'via the means in Section 15 for assistance.', bullet: true),
        LegalText('Damage caused by failure to follow instructions, '
            'unauthorized interruption of the upgrade, use of unofficial '
            'firmware, or unauthorized disassembly or modification of the '
            'device is not covered by the warranty.', bullet: true),
      ],
    ),
    LegalSection(
      heading: '9. User Conduct and Violation Handling',
      blocks: <LegalBlock>[
        LegalText('You undertake that, when using this App (including '
            'casting, AI creation, and any content submission), you will not '
            'submit, generate, or disseminate any of the following content:'),
        LegalText('Content that violates the laws, regulations, and policies '
            'of the People\'s Republic of China;', bullet: true),
        LegalText('Pornographic, vulgar, obscene, or sexually suggestive '
            'content;', bullet: true),
        LegalText('Violent, terrorist, gory, or crime-glorifying content;', bullet: true),
        LegalText('Content that insults, defames, threatens, or harasses '
            'others, or infringes upon others\' legitimate rights and '
            'interests such as reputation, portrait rights, privacy, and '
            'intellectual property;', bullet: true),
        LegalText('Other content that violates public order and good morals '
            'or social ethics, or that may damage the reputation of this '
            'service.', bullet: true),
        LegalText('You also must not: use this App for any illegal '
            'activities; interfere with or disrupt the normal operation of '
            'the services through plug-ins, scripts, emulators, reverse '
            'engineering, or other means; or scrape, copy, or commercially '
            'use the data and materials of this App without permission.'),
        LegalText('Violation handling: for accounts violating the above '
            'rules, we will take the following tiered measures (consistent '
            'with the in-app BoltStar AI Service Agreement):'),
        LegalTable(
          head: <String>['Violation count', 'Measure'],
          rows: <List<String>>[
            <String>[
              '1st violation',
              'AI features banned for 24 hours',
            ],
            <String>[
              '2nd violation',
              'AI features banned for 24 hours',
            ],
            <String>[
              '3rd violation',
              'AI features banned for 24 hours',
            ],
            <String>[
              'After 3 cumulative violations, each additional violation',
              'AI features banned for 24 hours',
            ],
            <String>[
              'Upon 9 cumulative violations',
              'AI features permanently banned',
            ],
          ],
        ),
        LegalText('The ban applies only to AI services and does not affect '
            'your use of other features of this App. If you disagree with the '
            'handling, you may appeal via the means in Section 15. For '
            'serious circumstances or suspected violations of law, we have '
            'the right to terminate the services directly and report to the '
            'relevant authorities in accordance with the law.'),
      ],
    ),
    LegalSection(
      heading: '10. Intellectual Property',
      blocks: <LegalBlock>[
        LegalText('The intellectual property rights in this App and the '
            'software, interface designs, icons, text, Official Gallery '
            'materials, and other content it contains belong to us or the '
            'corresponding rights holders and are protected by law. Without '
            'written permission, you must not copy, modify, disseminate, '
            'rent, sell, or use them for any commercial purpose.', bullet: true),
        LegalText('The rights in photos and other content you upload remain '
            'yours or the original rights holders\'. To provide you with '
            'services such as casting, storage, display, and AI processing, '
            'you grant us a free, non-exclusive, sublicensable (only to '
            'third-party service providers necessary for providing this '
            'service) license to use, store, transmit, and process such '
            'content to the extent necessary for the services. This license '
            'terminates when you delete the content or delete your account '
            '(except where retention is required by laws and regulations).', bullet: true),
        LegalText('Official Gallery materials are provided solely for you to '
            'browse, favorite, and cast to your own device within this App, '
            'and may not otherwise be downloaded, distributed, or used for '
            'commercial purposes.', bullet: true),
      ],
    ),
    LegalSection(
      heading: '11. Disclaimer and Limitation of Liability',
      blocks: <LegalBlock>[
        LegalText('This App is provided on an "as is" basis. To the maximum '
            'extent permitted by law, we make no express or implied warranty '
            'that the services will be uninterrupted, error-free, or fully '
            'meet your specific needs.', bullet: true),
        LegalText('We are not liable for service interruptions, data loss, or '
            'losses caused by the following circumstances: force majeure '
            '(natural disasters, epidemics, government actions, etc.); '
            'failures of infrastructure such as networks, telecommunications, '
            'or power supply; problems with your phone, device, or operating '
            'system; failures or adjustments of third-party services (payment '
            'channels, AI services, image processing services, etc.); your '
            'failure to follow instructions, unauthorized interruption of '
            'upgrades, or use of unofficial firmware; and security incidents '
            'not attributable to our fault, such as hacker attacks or '
            'computer viruses.', bullet: true),
        LegalText('To the maximum extent permitted by law, the total '
            'compensation we are liable to pay you under this Agreement shall '
            'not exceed the amount you actually paid for the App\'s paid '
            'services in the 12 months preceding the occurrence of the '
            'damage. We are not liable for any indirect or incidental losses '
            'or punitive damages, or for losses of intangible assets such as '
            'data, goodwill, or profits. This limitation of liability does '
            'not apply to losses caused by our intentional misconduct or '
            'gross negligence, nor to circumstances where mandatory '
            'provisions of law provide otherwise', bullet: true),
        LegalText('This clause does not exclude or restrict liability that '
            'cannot be excluded or restricted by law, including liability for '
            'personal injury caused by our intentional misconduct or gross '
            'negligence.', bullet: true),
      ],
    ),
    LegalSection(
      heading: '12. Changes, Interruption, and Termination of Services',
      blocks: <LegalBlock>[
        LegalText('We have the right to change, suspend, or terminate part or '
            'all of the services according to business needs. For major '
            'changes or termination, we will notify you in advance via in-app '
            'announcements or other means; for brief interruptions required '
            'by system maintenance or upgrades, we will try to give advance '
            'notice.', bullet: true),
        LegalText('If you seriously violate this Agreement or laws and '
            'regulations, we have the right to suspend or terminate the '
            'services to you after notice, and reserve the right to pursue '
            'liability.', bullet: true),
        LegalText('After termination of the Agreement, the provisions of this '
            'Agreement on intellectual property, disclaimer and limitation of '
            'liability, and dispute resolution remain in effect.', bullet: true),
      ],
    ),
    LegalSection(
      heading: '13. Provisions for Minors',
      blocks: <LegalBlock>[
        LegalText('If you are a minor under 18 years of age, please read and '
            'agree to this Agreement under the accompaniment of your parents '
            'or other guardians before using this App; if you are under 14 '
            'years of age, you must obtain your guardian\'s consent before '
            'registering and using it. Minors\' use of paid functions '
            '(including purchasing Star Coins) should obtain the guardian\'s '
            'consent in advance. We encourage guardians to guide minors to '
            'use this App and the device reasonably, paying attention to eye '
            'health and usage duration.'),
      ],
    ),
    LegalSection(
      heading: '14. Governing Law and Dispute Resolution',
      blocks: <LegalBlock>[
        LegalText('The formation, validity, interpretation, performance, and '
            'dispute resolution of this Agreement are governed by the laws of '
            'the mainland of the People\'s Republic of China (excluding '
            'conflict-of-law rules).', bullet: true),
        LegalText('Disputes arising from this Agreement shall first be '
            'resolved through friendly negotiation between the parties; if '
            'negotiation fails, either party has the right to submit the '
            'dispute to a people\'s court with jurisdiction at the place '
            'where the company is registered (i.e., Nanshan District, '
            'Shenzhen) for resolution through litigation.', bullet: true),
        LegalText('If any provision of this Agreement is held invalid or '
            'unenforceable, it does not affect the validity of the remaining '
            'provisions.', bullet: true),
      ],
    ),
    LegalSection(
      heading: '15. Miscellaneous',
      blocks: <LegalBlock>[
        LegalText('Customer service and complaints email: '
            'boltstarservice@boltstar.net', bullet: true),
        LegalText('Company name: BoltStar (Shenzhen) New Energy Technology '
            'Co., Ltd.', bullet: true),
        LegalText('Registered address: Hantang Building, Overseas Chinese '
            'Town (OCT), Nanshan District, Shenzhen', bullet: true),
        LegalText('Related documents: BoltStar Privacy Policy, BoltStar AI '
            'Service Agreement', bullet: true),
        LegalText('We will respond within 15 working days after receiving '
            'your comments or complaints.'),
        LegalText('BoltStar (Shenzhen) New Energy Technology Co., Ltd. · '
            'BoltStar'),
        LegalText('This Agreement takes effect on the effective date stated '
            'at the top of this document.'),
      ],
    ),
  ];
}
