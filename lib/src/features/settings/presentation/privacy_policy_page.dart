import 'package:flutter/material.dart';

import 'package:BoltStar/src/shared/widgets/figma_common.dart';
import '../../../shared/l10n/app_l10n.dart';
import 'legal_document_view.dart';

/// 隐私政策页面。
///
/// ⚠️ **正文固定英文，不随语种设置切换**（2026-08-13 产品要求，2026-09-10 换版时沿用）：
/// 法务只出具了中英两版，App 端口径就是英文；其余语种没有对应的、经审阅的文本，
/// 机翻一份法律文本再摆到设置页里，比只给英文更糟——所以这里**不走** `AppL10n.pick`，
/// 页面标题仍随语种（那只是入口名字，不是条款）。
///
/// 正文由法务 docx「BoltStar Privacy Policy (EN) 20260909.docx」逐块转换而来（转换脚本
/// 一次性使用、未入仓，做法见对应变更记录）。这是**法律文本**：改动只能来自法务给的新文档，
/// 重新生成，不要在这里改措辞。文档自带的目录（TOC）没有转换进来——页面没有锚点跳转能力。
/// 文档版本：Last Updated: August 28, 2026  Effective Date: To be completed  Version: VI.0
/// ⚠️ 生效日期在法务原文里就是「To be completed」，端上照抄；发版前需要法务补上真实日期。
class PrivacyPolicyPage extends StatelessWidget {
  const PrivacyPolicyPage({super.key});

  @override
  Widget build(BuildContext context) {
    return FigmaScreen(
      // 页面标题＝设置页那一行的名字，仍随语种；正文见类注释，固定英文。
      title: AppL10n.of(context).setPrivacyTitle,
      scrollable: false,
      bodyPadding: EdgeInsets.zero,
      body: LegalDocumentView(
        title: 'BoltStar Privacy Policy',
        updatedAt: 'August 28, 2026',
        effectiveAt: 'To be completed',
        intro: 'BoltStar (Shenzhen) New Energy Technology Co., Ltd. ("we") is '
            'the operator and personal information processor of the BoltStar '
            'e-paper photo frame and its companion app (including the iOS '
            'app, the Android app, and the WeChat mini program, hereinafter '
            'collectively the "App").\nWe understand how important personal '
            'information is to you. This Policy explains what information we '
            'collect and why, how we use and share it, and how long we keep '
            'it, as well as how you can exercise your rights. Provisions '
            'closely related to your rights and interests, and parts '
            'involving sensitive personal information and system permissions, '
            'are highlighted in bold; please read them with particular care. '
            'The core functions of this App rely on Bluetooth and the photos '
            'you actively select; please make sure you understand this Policy '
            'before use.',
        sections: privacyPolicySections,
      ),
    );
  }

  /// 章节正文。**公开**是为了让单测能直接断言（法律文本要能回归：章节数、
  /// 第八章是不是跨境传输、表格列数是否整齐），不是给别处复用的。共 14 章。
  static const List<LegalSection> privacyPolicySections = <LegalSection>[
    LegalSection(
      heading: '1. Scope of Application',
      blocks: <LegalBlock>[
        LegalText('This Policy applies to the following products and services '
            'we provide under the BoltStar brand: the iOS app, the Android '
            'app, and the WeChat mini program, as well as their connection '
            'and data transmission with the BoltStar e-paper photo frame (the '
            '"Device").'),
        LegalText('This Policy does not apply to (1) third-party services you '
            'navigate to from this App (such as WeChat Pay and Apple In-App '
            'Purchase), where your information is handled by the third '
            'parties under their own privacy policies; and (2) other apps you '
            'install yourself.'),
        LegalText('For specific notices about AI features, see also the '
            'in-app BoltStar AI Service Agreement; where this Policy is '
            'inconsistent with it, the provisions on AI data processing in '
            'the BoltStar AI Service Agreement shall prevail.'),
      ],
    ),
    LegalSection(
      heading: '2. How We Collect and Use Your Personal Information',
      blocks: <LegalBlock>[
        LegalText('We collect information only to achieve the specific '
            'business functions below, in accordance with the minimum '
            'necessity principle. Refusing to provide non-essential '
            'information does not affect your use of other functions.'),
        LegalText('2.1 Account Registration and Log-in (Essential Function)', subHeading: true),
        LegalText('Collection: mobile phone number (sensitive personal '
            'information). On the iOS / Android apps, it is obtained from '
            'your active input and verified via SMS; in the WeChat mini '
            'program, after you tap to authorize, it is provided by WeChat as '
            'encrypted phone number data and decrypted on our servers.', bullet: true),
        LegalText('Collection: the nickname and avatar you set within this '
            'App (optional; can be changed or left blank at any time).', bullet: true),
        LegalText('Generated and saved: your account identifier (user ID) and '
            'login credentials (Token).', bullet: true),
        LegalText('Purpose: to create and identify your account, save your '
            'device bindings and content, and safeguard account security.', bullet: true),
        LegalText('Note: the mobile phone number is the unique identifier of '
            'your account; without it you cannot register, log in, or use '
            'functions that require an account (device binding, album, AI, '
            'Star Coins).', bullet: true),
        LegalText('2.2 Searching for, Binding, and Connecting the E-Paper '
            'Device (Essential Function)', subHeading: true),
        LegalText('Permission: Bluetooth . Used to search for nearby BoltStar '
            'devices, establish connections with them, and send and receive '
            'commands. We scan only for BoltStar Bluetooth devices supported '
            'by this App and will not scan for or connect to Bluetooth '
            'devices of other brands or types.', bullet: true),
        LegalText('Permission: Location . Both iOS and Android require an app '
            'to obtain location permission before scanning for nearby '
            'low-energy Bluetooth devices, which is why we request this '
            'permission; this App only temporarily uses the system permission '
            'credential for Bluetooth device search, and does not collect, '
            'store, upload, or analyze your geographic location coordinates '
            'or movement tracks, nor use the location permission for '
            'advertising, user profiling, or other purposes.', bullet: true),
        LegalText('Collection (from the device itself, not from your phone): '
            'the device hardware ID (serial number), device model and screen '
            'specifications, firmware version, battery level, and the status '
            'of image storage slots in the device.', bullet: true),
        LegalText('Collection: the name you set for the device, and the '
            'slideshow playback mode and switching interval.', bullet: true),
        LegalText('Purpose: to bind the device to your account, display '
            'device status in the app, correctly transfer and delete images '
            'on the device, and determine whether a firmware upgrade is '
            'needed.', bullet: true),
        LegalText('2.3 Photo Casting and "My Album" (Core Function)', subHeading: true),
        LegalText('Permission: photo album (read) . The system picker is '
            'opened only when you actively tap "Select Photos"; we receive '
            'only the photos you actively select this time, and will not '
            'read, scan, or upload other photos in your album.', bullet: true),
        LegalText('Collection and processing: the photos you select will be '
            'cropped, compressed, and converted into a device-displayable '
            'image format on your phone; to complete the conversion and '
            'create casting records, the photos are uploaded to our servers '
            'and the image processing service (see Section 5), and then '
            'transferred to your device via Bluetooth.', bullet: true),
        LegalText('Collection: casting records (time, target device, storage '
            'slot of the image in the device, and result status).', bullet: true),
        LegalText('Purpose: to complete casting, display and manage casted '
            'photos in "My Album", and support deleting photos in the device.', bullet: true),
        LegalText('2.4 AI Creation (Optional Function)', subHeading: true),
        LegalText('Collection: the text you actively type in AI conversations '
            'and the images you actively upload (from the photo album or '
            'camera).', bullet: true),
        LegalText('Permission: microphone (optional). Recording occurs only '
            'while you press and hold the "Hold to Speak" button, to '
            'transcribe your speech into text and insert it into the '
            'conversation; recording stops as soon as you release, and the '
            'speech-to-text conversion is completed locally on your device; '
            'the audio data is not uploaded to our servers.', bullet: true),
        LegalText('Permission: camera (optional). Invoked only when you '
            'actively choose "Take Photo".', bullet: true),
        LegalText('Permission: photo album (write) (optional). Only when you '
            'actively tap "Save Image" will AI-generated images be saved to '
            'your album.', bullet: true),
        LegalText('Sharing: to generate results, the above text and images '
            'will be transferred to the "Volcano Engine" AI service (provided '
            'by Beijing Volcano Engine Technology Co., Ltd.) for processing. '
            'Such content is used only to process your current request and '
            'will not be used for model training.', bullet: true),
        LegalText('Collection: AI conversation records (your questions, the '
            'AI\'s replies, and the addresses of generated images), used to '
            'let you review history in the app. Conversation records are '
            'retained on the server for only the most recent 7 days and are '
            'automatically cleared upon expiration.', bullet: true),
        LegalText('Note: before you first use the AI features, we will notify '
            'you in a separate pop-up and obtain your consent; declining does '
            'not affect your use of other features of this App.', bullet: true),
        LegalText('2.5 Star Coin Purchase and Consumption (Optional Function)', subHeading: true),
        LegalText('Collection: your Star Coin balance, order numbers, and '
            'purchase and consumption transaction records.', bullet: true),
        LegalText('Note: the payment process is completed by third-party '
            'payment channels — via Apple In-App Purchase (App Store) on iOS, '
            'and via WeChat Virtual Payment in the WeChat mini program. We do '
            'not collect, and cannot access, your payment account information '
            'such as bank card numbers or payment passwords ; we only receive '
            'payment results and order numbers from the channels for '
            'crediting purposes.', bullet: true),
        LegalText('2.6 Firmware Upgrade (Essential Function)', subHeading: true),
        LegalText('Collection: the device\'s current firmware version, and '
            'the progress and result status during the upgrade.', bullet: true),
        LegalText('Purpose: to determine whether a new version is available, '
            'transfer the firmware package to the device, and show you the '
            'reason in case of failure.', bullet: true),
        LegalText('2.7 Security and Troubleshooting (Essential Function)', subHeading: true),
        LegalText('Collection: terminal device information (phone model, '
            'operating system type and version, platform identifier, network '
            'status) and operation logs (function call times, error codes, '
            'and anomalies during Bluetooth and casting processes).', bullet: true),
        LegalText('Purpose: to adapt Bluetooth parameters to different phone '
            'models, identify and locate faults, and safeguard service and '
            'account security. Such information is not used to identify your '
            'personal identity, nor for advertising.', bullet: true),
        LegalText('2.8 Exceptions to Obtaining Consent', subHeading: true),
        LegalText('Under laws and regulations, we do not need your prior '
            'consent to collect and use your information in the following '
            'circumstances: where it is necessary for concluding or '
            'performing a contract to which you are a party; where it is '
            'necessary for performing statutory duties or obligations; where '
            'it is necessary to protect the life, health, and property of '
            'natural persons in response to a public health emergency or '
            'other emergency; where it is processing information you have '
            'disclosed yourself or that has been lawfully made public, within '
            'a reasonable scope; and other circumstances prescribed by laws '
            'and administrative regulations.'),
      ],
    ),
    LegalSection(
      heading: '3. System Permissions We Invoke',
      blocks: <LegalBlock>[
        LegalText('All permissions are requested only when you first use the '
            'corresponding function, and are never requested all at once at '
            'startup; you may deny or revoke them at any time — denial '
            'affects only that function, not other functions.'),
        LegalTable(
          head: <String>['Permission', 'Use scenario and purpose', 'Impact if denied'],
          rows: <List<String>>[
            <String>[
              'Bluetooth',
              'Search for, bind to, and connect BoltStar e-paper photo frames; transfer photos and firmware; read the device\'s battery level and status',
              'Cannot search for or connect to devices; casting, device management, and firmware upgrade are all unavailable',
            ],
            <String>[
              'Location (while in use)',
              'As required by the system: location permission is required to scan for nearby low-energy Bluetooth devices . Used only for Bluetooth scanning; no tracks are collected, and it is not used for profiling or advertising',
              'Cannot discover nearby devices; binding and reconnection cannot be completed',
            ],
            <String>[
              'Photo album (read)',
              'You actively select photos to cast, or upload images in AI conversations',
              'Cannot pick images from the album; you can use the camera or the Official Gallery instead',
            ],
            <String>[
              'Photo album (write)',
              'When you actively tap Save, AI-generated images are stored in the album',
              'Cannot save images to the album; does not affect generation or casting',
            ],
            <String>[
              'Camera',
              'You actively choose "Take Photo" to upload in AI conversations',
              'Cannot take photos to upload; you can pick from the album instead',
            ],
            <String>[
              'Microphone',
              '"Hold to Speak" in AI conversations: speech is transcribed into text; recording stops when you release, and no audio files are saved',
              'Cannot input by voice; you can type with the keyboard instead',
            ],
            <String>[
              'Speech recognition',
              'Transcribes the above audio into text. On iOS, the system\'s speech recognition capability is used and no third-party recognition service is integrated',
              'Cannot convert speech to text',
            ],
            <String>[
              'Network access',
              'Log-in, syncing of devices and content, AI services, downloading firmware packages and images',
              'This App cannot function properly',
            ],
            <String>[
              'Keep screen on',
              'Prevents the screen from sleeping and interrupting transfers during casting and firmware upgrades (no personal information involved)',
              '—',
            ],
          ],
        ),
        LegalText('How to withdraw: On iOS, go to "Settings → Privacy & '
            'Security → the relevant permission" or "Settings → BoltStar"; on '
            'Android, go to "Settings → Apps → BoltStar → Permissions"; in '
            'the WeChat mini program, go to "WeChat → Me → Settings → Privacy '
            '→ Authorization Management", or tap "···" at the top right of '
            'the mini program → "Settings". Withdrawing a permission does not '
            'affect the validity of processing activities previously carried '
            'out based on your authorization.'),
      ],
    ),
    LegalSection(
      heading: '4. How We Use Local Storage',
      blocks: <LegalBlock>[
        LegalText('To keep you logged in and preserve your experience, we '
            'store a small amount of data locally on your device, including: '
            'login credentials, your basic account profile, the currently '
            'selected device and its connection information, temporary paths '
            'of images pending casting, and app launch time logs. How to '
            'clear: logging out or deleting your account clears login '
            'credentials and account-related caches; you may also uninstall '
            'the app (or delete the mini program) to clear all local data. '
            'This App does not use advertising cookies or cross-app tracking '
            'identifiers.'),
      ],
    ),
    LegalSection(
      heading: '5. How We Share, Transfer, and Publicly Disclose',
      blocks: <LegalBlock>[
        LegalText('We do not sell your personal information. We share it only '
            'in the following necessary circumstances:'),
        LegalTable(
          head: <String>['Recipient', 'Information shared', 'Purpose and scenario'],
          rows: <List<String>>[
            <String>[
              'Beijing Volcano Engine Technology Co., Ltd. ("Volcano Engine" AI services)',
              'What you actively send in AI conversations: text and images',
              'Generate text replies, generate or beautify images. Used only for the current request; not used for model training',
            ],
            <String>[
              'Image processing provider: Jiangxi Xingtai Technology Co., Ltd.',
              'The photos you select for casting (including AI-generated images)',
              'Its image dithering algorithm is invoked to convert images into six-color frame data adapted to the e-paper screen, so as to achieve casting. This processing serves only your single operation command; after processing is completed, we do not store your uploaded original images or the processed data in any form.',
            ],
            <String>[
              'Tencent (WeChat)',
              'Authorization credentials required for log-in and phone number authorization data; order information for virtual payment within the mini program',
              'WeChat log-in and WeChat mini program virtual payment',
            ],
            <String>[
              'Apple Inc.',
              'Order and transaction information for in-app purchases on iOS',
              'To complete in-app purchases (Star Coins)',
            ],
            <String>[
              'Cloud service and object storage provider: Alibaba Cloud Computing Co., Ltd.',
              'Account data, device data, and image files',
              'Providing server hosting, databases, and image storage',
            ],
          ],
        ),
        LegalText('We sign data processing agreements with the above '
            'recipients, requiring them to process information in accordance '
            'with this Policy and applicable laws and regulations. Transfer: '
            'except where personal information needs to be transferred due to '
            'merger, division, dissolution, bankruptcy, or similar reasons, '
            'we will not transfer your personal information; where a transfer '
            'is truly necessary, we will require the recipient to remain '
            'bound by this Policy, or obtain your consent again. Public '
            'disclosure: except with your explicit consent or as required by '
            'judicial or administrative authorities under the law, we will '
            'not publicly disclose your personal information.'),
      ],
    ),
    LegalSection(
      heading: '6. List of Third-Party SDKs / Plugins and Services',
      blocks: <LegalBlock>[
        LegalTable(
          head: <String>['Name', 'Provider', 'Use scenario', 'Information processed'],
          rows: <List<String>>[
            <String>[
              'Volcano Engine AI services',
              'Beijing Volcano Engine Technology Co., Ltd.',
              'AI text chat, text-to-image, image beautification',
              'The text and images you send for the current request',
            ],
            <String>[
              'WeChat Simultaneous Interpretation plugin (WechatSI) (WeChat mini program only)',
              'Tencent',
              'Speech-to-text for "Hold to Speak"',
              'Recorded audio (for transcription, processed in real time)',
            ],
            <String>[
              'WeChat open capabilities / virtual payment (WeChat mini program only)',
              'Tencent',
              'WeChat log-in, phone number acquisition, virtual payment',
              'Login credentials, phone number authorization data, and order information',
            ],
            <String>[
              'Apple In-App Purchase (StoreKit) (iOS only)',
              'Apple Inc.',
              'In-app purchase of Star Coins',
              'Transaction and order information',
            ],
            <String>[
              'Image dithering processing service',
              'Jiangxi Xingtai Technology Co., Ltd.',
              'Converting photos into six-color frame data for e-paper',
              'Images you select for casting',
            ],
          ],
        ),
      ],
    ),
    LegalSection(
      heading: '7. Storage Location and Retention Periods',
      blocks: <LegalBlock>[
        LegalText('Storage location: we store your personal information on '
            'servers of Alibaba Cloud Computing Co., Ltd..', bullet: true),
        LegalText('Account and device data: retained from the date of your '
            'registration until the date you delete your account; after '
            'deletion we will delete or anonymize it, except where retention '
            'for verification is required by laws and regulations, judicial '
            'authorities, or regulatory authorities.', bullet: true),
        LegalText('AI conversation records: on the server side, only the most '
            'recent 7 days are retained and they are automatically cleared '
            'upon expiration.', bullet: true),
        LegalText('Casted photos and records: retained until you delete the '
            'record in the app or delete your account. Please note: deleting '
            'a record in the app does not delete the images already displayed '
            'on the device ; images in the device must be cleared via the '
            'in-app "Delete / Clear All" function or by restoring the device '
            'to factory settings.', bullet: true),
        LegalText('Transaction records: retained as required by tax and '
            'accounting laws and regulations, usually for no less than 5 '
            'years.', bullet: true),
        LegalText('Audio recordings: not saved; released as soon as '
            'transcription is completed.', bullet: true),
        LegalText('After the above periods, we will delete or anonymize your '
            'personal information.', bullet: true),
      ],
    ),
    LegalSection(
      heading: '8. Cross-Border Transfer of Personal Information',
      blocks: <LegalBlock>[
        LegalText('The text and images you actively input in the AI creation '
            'features are transferred to the AI service gateway we deploy in '
            'Singapore (ap-southeast-1 region) for processing, to complete '
            'text replies, text-to-image generation, and image '
            'beautification. Apart from AI-related data, your other personal '
            'information (account, devices, casted photos, etc.) is stored '
            'within the People\'s Republic of China.'),
        LegalText('For the above cross-border provision of AI data, we will '
            'separately obtain your consent before you first use the AI '
            'features. We hereby inform you of the following:'),
        LegalText('Overseas recipient: Beijing Volcano Engine Technology Co., '
            'Ltd. (the AI service provider, whose service gateway is deployed '
            'in Singapore).', bullet: true),
        LegalText('Contact information: see Section 13 of this Policy.', bullet: true),
        LegalText('Purpose of processing: to generate text replies, generate '
            'or beautify images.', bullet: true),
        LegalText('Method of processing: the AI service gateway receives the '
            'text and images you send for the current request, uses them only '
            'to process that request, does not use them for model training, '
            'and does not retain the original content after processing '
            '(conversation records are retained for only 7 days on domestic '
            'servers).', bullet: true),
        LegalText('Types of personal information: the text you actively input '
            'and the images you actively upload in AI conversations.', bullet: true),
        LegalText('How to exercise rights against the overseas recipient: you '
            'may contact us via the means in Section 13 of this Policy to '
            'exercise rights such as access, correction, deletion, and '
            'withdrawal of consent.', bullet: true),
        LegalText('We provide data overseas only after satisfying statutory '
            'conditions such as passing a security assessment or entering '
            'into standard contracts, ensuring that your personal information '
            'receives abroad a level of protection equivalent to that within '
            'China.'),
      ],
    ),
    LegalSection(
      heading: '9. How We Protect Your Personal Information',
      blocks: <LegalBlock>[
        LegalText('Transport layer: network communications between our '
            'servers and third-party services are all encrypted via HTTPS.', bullet: true),
        LegalText('Access control: least-privilege, on-demand authorization '
            'is applied to personal information, and employee access requires '
            'approval and is logged.', bullet: true),
        LegalText('Account security: login credentials have a validity period '
            'and an expiration mechanism; after expiration, re-login is '
            'required.', bullet: true),
        LegalText('Device connection: commands are sent to the e-paper photo '
            'frame only after device identity verification, preventing '
            'accidental operations on other people\'s devices.', bullet: true),
        LegalText('Security incident response: in the unfortunate event of a '
            'personal information security incident, we will, as required by '
            'law, promptly inform you via push notifications, in-app '
            'announcements, or email of the situation, the measures we have '
            'taken, and suggestions for your self-protection, and report to '
            'the regulatory authorities.', bullet: true),
        LegalText('Please note: the internet is not an absolutely secure '
            'environment ; please keep your account and verification codes '
            'safe and do not disclose them to others.', bullet: true),
      ],
    ),
    LegalSection(
      heading: '10. Your Rights',
      blocks: <LegalBlock>[
        LegalText('In accordance with the Personal Information Protection Law '
            'of the People\'s Republic of China and other laws and '
            'regulations, you have the following rights over your personal '
            'information:'),
        LegalText('Access and copying: view your account profile in "Me → '
            'Personal Information"; to obtain a copy, contact us via the '
            'means in Section 13.', bullet: true),
        LegalText('Correction and supplementation: modify your nickname and '
            'avatar in "Me → Personal Information"; change the device name in '
            'the device details.', bullet: true),
        LegalText('Deletion: you may delete casting records, album content, '
            'AI conversations, and bound devices yourself.', bullet: true),
        LegalText('Withdrawal of consent: you may revoke granted permissions '
            'in the system settings (see Section 3); you may stop the '
            'relevant processing by ceasing to use the AI features in the '
            'app.', bullet: true),
        LegalText('Account deletion: submit via "Me → Settings → Delete '
            'Account"; after deletion we will delete or anonymize all '
            'information related to you stored on our servers , including '
            'your account profile, casting records, and AI conversations, as '
            'well as the original images you uploaded (photos used for album '
            'display and re-casting). This operation is irreversible . Please '
            'clear the photos in your e-paper device before deleting your '
            'account — after deletion, the binding between your account and '
            'the device is released, and you will no longer be able to delete '
            'images already cast to the device via this App (images in the '
            'device are not automatically cleared when the account is '
            'deleted).', bullet: true),
        LegalText('Explanation: you have the right to ask us to explain our '
            'personal information processing rules.', bullet: true),
        LegalText('Obtaining copies and portability: where the conditions set '
            'by the national cyberspace administration are met, you may '
            'request that we transfer your personal information to a personal '
            'information processor you designate.', bullet: true),
        LegalText('We will respond within 15 working days after receiving '
            'your request and verifying your identity. We may refuse repeated '
            'requests without legitimate grounds, requests requiring '
            'disproportionate cost, or requests that could harm the '
            'legitimate rights and interests of others, and will explain the '
            'reasons.'),
      ],
    ),
    LegalSection(
      heading: '11. Protection of Minors',
      blocks: <LegalBlock>[
        LegalText('This App is primarily intended for adults. If you are a '
            'minor under 14 years of age, please be sure to read this Policy '
            'accompanied by your parents or other guardians, and use this App '
            'and provide personal information only after your guardian\'s '
            'consent. We do not proactively collect minors\' personal '
            'information for marketing purposes. If we discover that we have '
            'collected the personal information of a minor under 14 years of '
            'age without the guardian\'s prior consent, we will delete the '
            'relevant data as soon as possible. If a guardian discovers such '
            'circumstances, they may contact us via the means in Section 13 '
            'to request deletion.'),
      ],
    ),
    LegalSection(
      heading: '12. Updates to This Policy',
      blocks: <LegalBlock>[
        LegalText('To provide better services, or due to changes in laws and '
            'regulations or our business, we may revise this Policy from time '
            'to time. After a revision, we will notify you in a prominent '
            'manner within the app (pop-up, announcement, or update prompt) '
            'and update the "Last Updated" date at the top. Where the '
            'revision involves major changes to the purposes, methods, or '
            'types of personal information processing, we will obtain your '
            'consent again. If you do not agree to the revised content, you '
            'may stop using this App and delete your account.'),
      ],
    ),
    LegalSection(
      heading: '13. How to Contact Us',
      blocks: <LegalBlock>[
        LegalText('Personal information protection email: '
            'boltstarservice@boltstar.net', bullet: true),
        LegalText('Company name: Qihe Ming (Shenzhen) New Energy Technology '
            'Co., Ltd.', bullet: true),
        LegalText('Registered address: Room 516, Hantang Building, No. 1 '
            'Xinglong Street, Zhongxin Street Community, Shahe Subdistrict, '
            'Nanshan District, Shenzhen', bullet: true),
        LegalText('We will respond within 15 working days after receiving '
            'your questions, comments, or complaints. If you are not '
            'satisfied with our response, you may also file complaints with '
            'regulatory authorities such as the cyberspace, '
            'telecommunications, public security, and market regulation '
            'authorities or bring a lawsuit before a people\'s court with '
            'jurisdiction at the defendant\'s domicile.'),
      ],
    ),
    LegalSection(
      heading: '14. Appendix: List of Personal Information Collected',
      blocks: <LegalBlock>[
        LegalText('This list is intended to present the collection situation '
            'to you in one place, and also corresponds to the basis for '
            'filling in the App Store "App Privacy" labels.'),
        LegalTable(
          head: <String>['Information type', 'Necessary?', 'Collection scenario', 'Linked to identity?', 'Used for tracking?'],
          rows: <List<String>>[
            <String>[
              'Mobile phone number (sensitive)',
              'Yes',
              'Registration and log-in',
              'Yes',
              'No',
            ],
            <String>[
              'Nickname and avatar',
              'No',
              'Completing your profile',
              'Yes',
              'No',
            ],
            <String>[
              'Photos (actively selected by you)',
              'Yes (casting feature)',
              'Casting, AI upload',
              'Yes',
              'No',
            ],
            <String>[
              'Audio (recordings)',
              'No',
              'AI voice input (instant transcription, not retained)',
              'No',
              'No',
            ],
            <String>[
              'User content (AI chat text and generated results)',
              'No',
              'AI creation (retained on server for 7 days)',
              'Yes',
              'No',
            ],
            <String>[
              'Location permission (no location data collected)',
              'Yes (prerequisite for Bluetooth scanning)',
              'Searching for nearby devices',
              'No',
              'No',
            ],
            <String>[
              'Bound device information (hardware ID, model, firmware, battery)',
              'Yes',
              'Device binding and connection',
              'Yes',
              'No',
            ],
            <String>[
              'Purchase and consumption records',
              'Yes (purchase feature)',
              'Star Coin top-up and consumption',
              'Yes',
              'No',
            ],
            <String>[
              'Terminal information and operation logs',
              'Yes',
              'Compatibility, troubleshooting, security',
              'No',
              'No',
            ],
          ],
        ),
        LegalText('We do not track users across apps or websites, do not '
            'integrate third-party advertising networks, and do not sell '
            'personal information.'),
        LegalText('BoltStar (Shenzhen) New Energy Technology Co., Ltd. · '
            'BoltStar'),
        LegalText('This Policy takes effect on the effective date stated at '
            'the top of this document.'),
      ],
    ),
  ];
}
