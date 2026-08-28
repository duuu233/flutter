import 'package:flutter/material.dart';

import 'package:BoltStar/src/shared/widgets/figma_common.dart';
import '../../../shared/l10n/app_l10n.dart';
import 'legal_document_view.dart';

/// 隐私政策页面。
///
/// ⚠️ **正文固定英文，不随语种设置切换**（2026-08-13 产品要求）：法务只出具了英文版
/// （`docs/legal/privacy-policy-en.html`），其余语种没有对应的、经审阅的文本。
/// 机翻一份法律文本再摆到设置页里，比只给英文更糟——所以这里**不走** `AppL10n.pick`，
/// 页面标题仍随语种（那只是入口名字，不是条款）。
///
/// 正文由 `docs/legal/privacy-policy-en.html` 逐块转换而来（转换脚本见对应变更记录），
/// 这是**法律文本**：改动只能来自法务给的新 HTML，重新生成，不要在这里改措辞。
/// 文档版本：Last Updated: August 13, 2026 Effective Date: August 13, 2026 Version: v3.0
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
        updatedAt: 'August 13, 2026',
        effectiveAt: 'August 13, 2026',
        intro: 'Qiheming (Shenzhen) New Energy Technology Co., Ltd. (hereinafter "we", '
            '"us", or "our") is the operator and personal information processor of '
            'the BoltStar e-paper photo frame and its companion applications '
            '(including the iOS App, Android App, and WeChat Mini Program, '
            'collectively the "App").\nWe understand the importance of your '
            'personal information. This Policy explains what information we '
            'collect, why we collect it, how we use and share it, and how long we '
            'retain it, as well as how you can exercise your rights. Provisions '
            'that are closely related to your rights, as well as those involving '
            'sensitive personal information and system permissions, are marked in '
            'bold for your attention. The core functions of the App rely on '
            'Bluetooth and the photos you actively select. Please make sure you '
            'understand this Policy before using the App.',
        sections: privacyPolicySections,
      ),
    );
  }

  /// 章节正文。**公开**是为了让单测能直接断言（法律文本要能回归：章节数、
  /// 第八章是不是跨境传输、表格列数是否整齐），不是给别处复用的。
  /// 版本 v3.0，共 14 章。
  static const List<LegalSection> privacyPolicySections = <LegalSection>[
    LegalSection(
      heading: '1. Scope of Application',
      blocks: <LegalBlock>[
        LegalText('This Policy applies to the following products and services we provide '
            'under the BoltStar brand: the iOS App, Android App, WeChat Mini '
            'Program, and the connection and data transfer between them and the '
            'BoltStar e-paper photo frame (the "Device").'),
        LegalText('This Policy does not apply to: (1) third-party services accessed '
            'through the App (such as WeChat Pay and Apple In-App Purchase), which '
            'process your information under their own privacy policies; (2) other '
            'applications you install on your own.'),
        LegalText('For specific notices regarding AI features, please also refer to the '
            'in-app BoltStar AI Service Agreement. In the event of any '
            'inconsistency between this Policy and the BoltStar AI Service '
            'Agreement, the latter\'s provisions on AI data processing shall '
            'prevail.'),
      ],
    ),
    LegalSection(
      heading: '2. How We Collect and Use Your Personal Information',
      blocks: <LegalBlock>[
        LegalText('We collect information only to achieve the specific business functions '
            'described below, following the principle of minimal necessity. '
            'Refusing to provide non-essential information does not affect your use '
            'of other functions.'),
        LegalText('2.1 Account Registration and Login (Essential Function)', subHeading: true),
        LegalText('Collected: mobile phone number (sensitive personal information). On '
            'the iOS / Android App, it is obtained through your active input and '
            'SMS verification; on the WeChat Mini Program, it is provided by WeChat '
            'as encrypted phone number data after your authorization and decrypted '
            'by our servers.', bullet: true),
        LegalText('Collected: your nickname and avatar set within the App (optional; can '
            'be modified or left blank at any time).', bullet: true),
        LegalText('Generated and stored: your account identifier (user ID) and login '
            'credential (Token).', bullet: true),
        LegalText('Purpose: to create and identify your account, store your device '
            'binding relationships and content, and ensure account security.', bullet: true),
        LegalText('Note: the mobile phone number is the unique identifier of your '
            'account. Without providing it, you cannot register or log in, nor use '
            'functions that require an account (device binding, album, AI, Star '
            'Coins).', bullet: true),
        LegalText('2.2 Searching, Binding, and Connecting E-Paper Devices (Essential '
            'Function)', subHeading: true),
        LegalText('Permission: Bluetooth. Used to search for nearby BoltStar devices, '
            'establish connections, and send/receive commands. We only scan for '
            'BoltStar Bluetooth devices supported by this App, and will not scan '
            'for or connect to Bluetooth devices of other brands or types.', bullet: true),
        LegalText('Permission: Location. Both iOS and Android operating systems require '
            'the App to obtain location permission before it can scan for nearby '
            'Bluetooth Low Energy devices, and we therefore need to request this '
            'permission. We use it solely for Bluetooth scanning; we do not record, '
            'upload, or analyze your location track, nor use location results for '
            'advertising or profiling.', bullet: true),
        LegalText('Collected (from the device itself, not from your phone): device '
            'hardware ID (serial number), device model and screen specifications, '
            'firmware version, battery level, and the storage status of images on '
            'the device.', bullet: true),
        LegalText('Collected: the name you set for the device, the carousel playback '
            'mode, and the switching interval.', bullet: true),
        LegalText('Purpose: to bind the device to your account, display device status in '
            'the App, correctly transfer and delete images to/from the device, and '
            'determine whether a firmware upgrade is needed.', bullet: true),
        LegalText('2.3 Photo Casting and "My Album" (Core Function)', subHeading: true),
        LegalText('Permission: Photos (read). The system photo picker is opened only when '
            'you actively tap "Select Photos"; we only receive the photos you '
            'actively select this time, and will not read, scan, or upload any '
            'other photos in your album.', bullet: true),
        LegalText('Collected and processed: the photos you select are cropped, '
            'compressed, and converted to a display format compatible with the '
            'device on your phone; to complete the conversion and establish a '
            'casting record, the photos are uploaded to our servers and the image '
            'processing service (see Section 5), and then transferred to your '
            'device via Bluetooth.', bullet: true),
        LegalText('Collected: casting records (time, target device, storage location of '
            'the image on the device, result status).', bullet: true),
        LegalText('Purpose: to complete casting, display and manage cast photos in "My '
            'Album", and support deleting photos from the device.', bullet: true),
        LegalText('2.4 AI Creation (Optional Function)', subHeading: true),
        LegalText('Collected: text you actively enter and images you actively upload '
            '(from the album or camera) in AI conversations.', bullet: true),
        LegalText('Permission: Microphone (optional). Recording only occurs while you '
            'hold the "Hold to Talk" button, to transcribe speech into text for the '
            'conversation; recording stops when you release, and we do not save the '
            'audio file.', bullet: true),
        LegalText('Permission: Camera (optional). Invoked only when you actively choose '
            'to "Take a Photo".', bullet: true),
        LegalText('Permission: Photos (write) (optional). Invoked only when you actively '
            'tap "Save Image" to save the AI-generated image to your album.', bullet: true),
        LegalText('Shared: to generate results, the above text and images are transmitted '
            'to the "Volcano Engine" AI service (provided by Beijing Volcano Engine '
            'Technology Co., Ltd.) for processing. Such content is used only to '
            'process your current request and will not be used for model training.', bullet: true),
        LegalText('Collected: AI conversation records (your questions, AI replies, and '
            'addresses of generated images), used to let you review history within '
            'the App. Conversation records are retained on the server for only the '
            'most recent 7 days and are automatically deleted upon expiration.', bullet: true),
        LegalText('Note: before using AI features for the first time, we will provide a '
            'separate pop-up notice and obtain your consent; if you refuse, other '
            'functions of the App remain unaffected.', bullet: true),
        LegalText('2.5 Purchase and Consumption of Star Coins (Optional Function)', subHeading: true),
        LegalText('Collected: your Star Coin balance, order number, and purchase and '
            'consumption records.', bullet: true),
        LegalText('Note: payment is completed through third-party payment channels — '
            'Apple In-App Purchase (App Store) on iOS, and WeChat virtual payment '
            'in the WeChat Mini Program. We do not collect and cannot access your '
            'bank card number, payment password, or other payment account '
            'information; we only receive the payment result and order number from '
            'the channel for crediting.', bullet: true),
        LegalText('2.6 Firmware Upgrade (Essential Function)', subHeading: true),
        LegalText('Collected: the current firmware version of the device, and the '
            'progress and result status during the upgrade process.', bullet: true),
        LegalText('Purpose: to determine whether a new version is available, transfer the '
            'firmware package to the device, and show the reason in case of '
            'failure.', bullet: true),
        LegalText('2.7 Security and Troubleshooting (Essential Function)', subHeading: true),
        LegalText('Collected: terminal device information (phone model, operating system '
            'type and version, platform identifier, network status) and operation '
            'logs (function invocation time, error codes, and abnormal information '
            'during Bluetooth and casting processes).', bullet: true),
        LegalText('Purpose: to adapt Bluetooth parameters for different phone models, '
            'identify and locate faults, and ensure service and account security. '
            'Such information is not used to identify your personal identity and is '
            'not used for advertising.', bullet: true),
        LegalText('2.8 Exceptions to Obtaining Consent', subHeading: true),
        LegalText('In accordance with laws and regulations, we may collect and use your '
            'information without your prior consent in the following circumstances: '
            'where it is necessary to conclude or perform a contract to which you '
            'are a party; where it is necessary to perform statutory duties or '
            'obligations; where it is necessary to respond to public health '
            'emergencies or to protect the life, health, and property safety of '
            'natural persons in emergencies; where we process information that you '
            'have made public or that has otherwise been lawfully made public, '
            'within a reasonable scope; and other circumstances prescribed by laws '
            'and administrative regulations.'),
      ],
    ),
    LegalSection(
      heading: '3. System Permissions We Access',
      blocks: <LegalBlock>[
        LegalText('All permissions are requested only when you first use the '
            'corresponding function, and are not requested all at once upon launch. '
            'You may refuse or revoke them at any time; refusal only affects that '
            'function and does not affect other functions.'),
        LegalTable(
          head: <String>['Permission', 'Scenario and Purpose', 'Impact of Refusal'],
          rows: <List<String>>[
            <String>['Bluetooth', 'Search for, bind, and connect to the BoltStar e-paper photo '
                  'frame; transfer photos and firmware; read device battery and '
                  'status', 'Unable to search for and connect to the device; casting, device '
                  'management, and firmware upgrade become unavailable'],
            <String>['Location (while using)', 'System requirement: location permission is required to scan for '
                  'nearby Bluetooth Low Energy devices. Used only for Bluetooth '
                  'scanning; no track is collected, and it is not used for '
                  'profiling or advertising', 'Unable to scan for nearby devices, and unable to complete '
                  'binding and reconnection'],
            <String>['Photos (read)', 'You actively select photos to cast, or upload images in AI '
                  'conversations', 'Unable to select images from the album; you may switch to taking '
                  'photos or using the official image library'],
            <String>['Photos (write)', 'When you actively tap "Save", save the AI-generated image to '
                  'your album', 'Unable to save images to the album; does not affect generation '
                  'or casting'],
            <String>['Camera', 'You actively choose "Take a Photo" to upload in AI conversations', 'Unable to take and upload photos; you may switch to selecting '
                  'from the album'],
            <String>['Microphone', '"Hold to Talk" in AI conversations, transcribing speech to text; '
                  'recording stops when you release, audio files are not saved', 'Unable to use voice input; you may switch to keyboard input'],
            <String>['Speech Recognition', 'Transcribe the above recording to text. The iOS App uses the '
                  'system\'s built-in speech recognition capability and does not '
                  'integrate any third-party recognition service', 'Unable to convert speech to text'],
            <String>['Network Access', 'Login, device and content synchronization, AI services, '
                  'downloading firmware packages and images', 'The App cannot function normally'],
            <String>['Keep Screen On', 'Prevent the screen from turning off and interrupting the '
                  'transfer during casting and firmware upgrade (does not involve '
                  'personal information)', '—'],
          ],
        ),
        LegalText('How to revoke: On iOS, go to "Settings → Privacy & Security → the '
            'corresponding permission" or "Settings → BoltStar"; on Android, go to '
            '"Settings → Apps → BoltStar → Permissions"; in the WeChat Mini '
            'Program, go to "WeChat → Me → Settings → Privacy → Authorization '
            'Management" or the Mini Program\'s "···" menu → "Settings". Revoking a '
            'permission does not affect the validity of processing activities '
            'already carried out based on your prior authorization.'),
      ],
    ),
    LegalSection(
      heading: '4. How We Use Local Storage',
      blocks: <LegalBlock>[
        LegalText('To ensure login status and user experience, we store a small amount of '
            'data locally on your device, including: login credentials, your basic '
            'account information, the currently selected device and its connection '
            'information, temporary image paths pending casting, and app launch '
            'time logs. How to clear: logging out or deleting your account clears '
            'the login credentials and account-related cache; you may also '
            'uninstall the App (or delete the Mini Program) to clear all local '
            'data. This App does not use advertising cookies or cross-app tracking '
            'identifiers.'),
      ],
    ),
    LegalSection(
      heading: '5. How We Share, Transfer, and Publicly Disclose',
      blocks: <LegalBlock>[
        LegalText('We do not sell your personal information. We share it only in the '
            'following necessary circumstances:'),
        LegalTable(
          head: <String>['Recipient', 'Shared Information', 'Purpose and Scenario'],
          rows: <List<String>>[
            <String>['Beijing Volcano Engine Technology Co., Ltd. ("Volcano Engine" AI '
                  'service)', 'The text and images you actively send in AI conversations', 'Generate text replies, and generate or beautify images. Used '
                  'only for the current request; not used for model training'],
            <String>['Image processing service provider: Jiangxi Xingtai Technology '
                  'Co., Ltd.', 'The photos you select for casting (including AI-generated '
                  'images)', 'Convert images into display data compatible with the e-paper '
                  'device for casting; used only for a single operation, and the '
                  'processed images are not stored in any form'],
            <String>['Tencent (WeChat)', 'Authorization credentials and phone number authorization data '
                  'required for login; order information for in-Mini-Program '
                  'virtual payment', 'WeChat login and WeChat Mini Program virtual payment'],
            <String>['Apple Inc.', 'Order and transaction information for iOS in-app purchases', 'Complete in-app purchases (Star Coins)'],
            <String>['Cloud service and object storage provider: Alibaba Cloud '
                  'Computing Ltd.', 'Account data, device data, image files', 'Provide server hosting, databases, and image storage'],
          ],
        ),
        LegalText('We will sign data processing agreements with the above recipients and '
            'require them to process information in accordance with this Policy and '
            'applicable laws and regulations. Transfer: Except for the need to '
            'transfer personal information due to merger, division, dissolution, '
            'bankruptcy, etc., we will not transfer your personal information; '
            'where a transfer is truly necessary, we will require the recipient to '
            'remain bound by this Policy, otherwise we will obtain your consent '
            'again. Public disclosure: We will not publicly disclose your personal '
            'information except with your explicit consent or as required by law to '
            'cooperate with judicial or administrative authorities.'),
      ],
    ),
    LegalSection(
      heading: '6. List of Third-Party SDKs / Plugins and Services',
      blocks: <LegalBlock>[
        LegalTable(
          head: <String>['Name', 'Provider', 'Usage Scenario', 'Information Processed'],
          rows: <List<String>>[
            <String>['Volcano Engine AI Service', 'Beijing Volcano Engine Technology Co., Ltd.', 'AI text conversation, text-to-image, image beautification', 'Text and images you send this time'],
            <String>['WeChat Simultaneous Interpretation Plugin (WechatSI) WeChat Mini '
                  'Program only', 'Tencent', 'Speech-to-text for "Hold to Talk"', 'Audio recording (for transcription, processed in real time)'],
            <String>['WeChat Open Capabilities / Virtual Payment WeChat Mini Program '
                  'only', 'Tencent', 'WeChat login, obtaining phone number, virtual payment', 'Login credentials, phone number authorization data, order '
                  'information'],
            <String>['Apple In-App Purchase (StoreKit) iOS only', 'Apple Inc.', 'In-app purchase of Star Coins', 'Transaction and order information'],
            <String>['Image Dithering Service', 'Jiangxi Xingtai Technology Co., Ltd.', 'Convert photos into six-color display data for the e-paper '
                  'device', 'Images you select for casting'],
          ],
        ),
      ],
    ),
    LegalSection(
      heading: '7. Storage Location and Retention Period',
      blocks: <LegalBlock>[
        LegalText('Storage location: We store your personal information on servers of '
            'Alibaba Cloud Computing Ltd.', bullet: true),
        LegalText('Account and device data: from the date of your registration until you '
            'delete your account; after deletion, we will delete or anonymize the '
            'data, unless a longer retention period is required by law or '
            'regulation.', bullet: true),
        LegalText('AI conversation records: retained on the server for only the most '
            'recent 7 days and automatically deleted upon expiration.', bullet: true),
        LegalText('Cast photos and records: retained until you delete the record in the '
            'App or delete your account. Please note: deleting records in the App '
            'does not delete images already displayed on the device; device images '
            'must be cleared through the in-App "Delete / Clear All" function or by '
            'resetting the device to factory settings.', bullet: true),
        LegalText('Transaction records: retained in accordance with tax and accounting '
            'laws and regulations, generally no less than 5 years.', bullet: true),
        LegalText('Audio recordings: not retained; released as soon as transcription is '
            'complete.', bullet: true),
        LegalText('After the above retention periods expire, we will delete or anonymize '
            'your personal information.', bullet: true),
      ],
    ),
    LegalSection(
      heading: '8. Cross-Border Transfer of Personal Information',
      blocks: <LegalBlock>[
        LegalText('The text and images you actively enter in the AI creation feature are '
            'transmitted to our AI service gateway deployed in Singapore '
            '(ap-southeast-1 region) for processing, to complete text replies, '
            'text-to-image, and image beautification. Except for AI-related data, '
            'your other personal information (account, device, cast photos, etc.) '
            'is stored within the People\'s Republic of China.'),
        LegalText('For the above cross-border provision of AI data, we will obtain your '
            'separate consent before you use the AI feature for the first time. We '
            'hereby inform you of the following:'),
        LegalText('Overseas recipient: Beijing Volcano Engine Technology Co., Ltd. (the '
            'AI service provider, whose service gateway is deployed in Singapore).', bullet: true),
        LegalText('Contact information: see Section 13 of this Policy.', bullet: true),
        LegalText('Processing purpose: to generate text replies and to generate or '
            'beautify images.', bullet: true),
        LegalText('Processing method: the AI service gateway receives the text and images '
            'you send this time, uses them only to process the current request, '
            'does not use them for model training, and does not retain the original '
            'content after processing (conversation records are retained only on '
            'domestic servers for 7 days).', bullet: true),
        LegalText('Types of personal information: the text you actively enter and the '
            'images you actively upload in AI conversations.', bullet: true),
        LegalText('How to exercise your rights against the overseas recipient: you may '
            'contact us through Section 13 of this Policy to exercise your rights '
            'of access, correction, deletion, withdrawal of consent, etc.', bullet: true),
        LegalText('We have lawfully completed a security assessment and entered into '
            'standard contracts, among other statutory conditions, before providing '
            'the data overseas, to ensure that your personal information receives a '
            'level of protection overseas equivalent to that within China.'),
      ],
    ),
    LegalSection(
      heading: '9. How We Protect Your Personal Information',
      blocks: <LegalBlock>[
        LegalText('Transport layer: network communications with our servers and '
            'third-party services use HTTPS encryption.', bullet: true),
        LegalText('Access control: personal information is subject to minimal-necessary '
            'authorization on a need-to-know basis, and employee access requires '
            'approval and is logged.', bullet: true),
        LegalText('Account security: login credentials have validity periods and '
            'invalidation mechanisms, and re-login is required after invalidation.', bullet: true),
        LegalText('Device connection: commands are issued to the e-paper photo frame only '
            'after device identity verification, to avoid operating other people\'s '
            'devices by mistake.', bullet: true),
        LegalText('Security incident response: In the unfortunate event of a personal '
            'information security incident, we will, as required by law, promptly '
            'inform you of the circumstances, the measures we have taken, and the '
            'precautions you can take, through push notifications, in-App '
            'announcements, or email, and report to the regulatory authorities.', bullet: true),
        LegalText('Please note: the Internet is not an absolutely secure environment. '
            'Please keep your account and verification codes safe and do not '
            'disclose them to others.', bullet: true),
      ],
    ),
    LegalSection(
      heading: '10. Your Rights',
      blocks: <LegalBlock>[
        LegalText('In accordance with the Personal Information Protection Law of the '
            'People\'s Republic of China and other laws and regulations, you have '
            'the following rights regarding your personal information:'),
        LegalText('Access and copy: view your account information in "Me → Personal '
            'Information"; to request a copy, contact us through Section 13.', bullet: true),
        LegalText('Correction and supplement: modify your nickname and avatar in "Me → '
            'Personal Information"; modify the device name in the device details.', bullet: true),
        LegalText('Deletion: you may delete casting records, album content, AI '
            'conversations, and bound devices on your own.', bullet: true),
        LegalText('Withdrawal of consent: you may revoke permissions you have granted in '
            'system settings (see Section 3), or stop using AI features within the '
            'App to cease the related processing.', bullet: true),
        LegalText('Account deletion: submit your request in "Me → Settings → Delete '
            'Account". After deletion, we will delete or anonymize all information '
            'related to you stored on our servers, including your account '
            'information, casting records, AI conversations, and the original '
            'images you uploaded (the photos used for album display and '
            're-casting). This operation is irreversible. Please clear the photos '
            'on your e-paper device before deletion — after deletion, the binding '
            'between your account and the device is released, and you will no '
            'longer be able to delete images already displayed on the device '
            'through the App (images on the device are not automatically cleared '
            'upon account deletion).', bullet: true),
        LegalText('Explanation: you have the right to request an explanation of our '
            'personal information processing rules.', bullet: true),
        LegalText('Obtain a copy and portability: where the conditions prescribed by the '
            'national cyberspace administration are met, you may request that we '
            'transfer your personal information to a personal information processor '
            'you designate.', bullet: true),
        LegalText('We will respond within 15 business days after receiving your request '
            'and verifying your identity. We may refuse requests that are '
            'repetitive without justification, require excessive cost, or may '
            'endanger the lawful rights and interests of others, and will explain '
            'the reasons.'),
      ],
    ),
    LegalSection(
      heading: '11. Protection of Minors',
      blocks: <LegalBlock>[
        LegalText('This App is primarily intended for adults. If you are a minor under '
            'the age of 14, please read this Policy in the company of your parent '
            'or other guardian, and use this App and provide personal information '
            'only with the guardian\'s consent. We do not actively collect personal '
            'information from minors for marketing purposes. If we discover that we '
            'have collected personal information of a minor under the age of 14 '
            'without prior guardian consent, we will delete the relevant data as '
            'soon as possible. Guardians who discover such circumstances may '
            'contact us through Section 13 to request deletion.'),
      ],
    ),
    LegalSection(
      heading: '12. Updates to This Policy',
      blocks: <LegalBlock>[
        LegalText('To provide better services or due to changes in laws, regulations, or '
            'our business, we may revise this Policy from time to time. After '
            'revision, we will notify you in a prominent manner within the App '
            '(pop-up, announcement, or update notice) and update the "Last Updated" '
            'date at the top of the page. In the event of material changes '
            'involving the purpose, method, or types of personal information '
            'processing, we will obtain your consent again. If you do not agree '
            'with the revised content, you may stop using the App and delete your '
            'account.'),
      ],
    ),
    LegalSection(
      heading: '13. How to Contact Us',
      blocks: <LegalBlock>[
        LegalText('Personal information protection email: boltstarservice@boltstar.net', bullet: true),
        LegalText('Company name: Qiheming (Shenzhen) New Energy Technology Co., Ltd.', bullet: true),
        LegalText('Registered address: 516, Hantang Building, No. 1 Xinglong Street, '
            'Zhongxin Street Community, Shahe Subdistrict, Nanshan District, '
            'Shenzhen', bullet: true),
        LegalText('We will respond to your questions, opinions, or complaints within 15 '
            'business days. If you are dissatisfied with our response, you may also '
            'file a complaint with regulatory authorities such as the cyberspace '
            'administration, telecommunications administration, public security, '
            'and market supervision administration, or file a lawsuit with the '
            'people\'s court with jurisdiction over the defendant\'s domicile.'),
      ],
    ),
    LegalSection(
      heading: '14. Appendix: Personal Information Collection List',
      blocks: <LegalBlock>[
        LegalText('This list is provided to show you our collection in a centralized '
            'manner, and also corresponds to the App Store "App Privacy" label '
            'disclosures.'),
        LegalTable(
          head: <String>['Information Type', 'Necessary', 'Collection Scenario', 'Linked to Identity', 'Used for Tracking'],
          rows: <List<String>>[
            <String>['Mobile phone number (sensitive)', 'Yes', 'Registration and login', 'Yes', 'No'],
            <String>['Nickname, avatar', 'No', 'Improving personal profile', 'Yes', 'No'],
            <String>['Photos (actively selected by you)', 'Yes (casting function)', 'Casting, AI upload', 'Yes', 'No'],
            <String>['Audio (recording)', 'No', 'AI voice input (real-time transcription, not retained)', 'No', 'No'],
            <String>['User content (AI conversation text and generated results)', 'No', 'AI creation (retained on server for 7 days)', 'Yes', 'No'],
            <String>['Location permission (location data not collected)', 'Yes (prerequisite for Bluetooth scanning)', 'Searching for nearby devices', 'No', 'No'],
            <String>['Bound device information (hardware ID, model, firmware, battery)', 'Yes', 'Device binding and connection', 'Yes', 'No'],
            <String>['Purchase and consumption records', 'Yes (purchase function)', 'Star Coin recharge and consumption', 'Yes', 'No'],
            <String>['Terminal information and operation logs', 'Yes', 'Compatibility, troubleshooting, security', 'No', 'No'],
          ],
        ),
        LegalText('We do not perform cross-App or cross-website user tracking, do not '
            'integrate third-party advertising networks, and do not sell personal '
            'information.'),
        LegalText('This Policy takes effect from the effective date stated at the top of '
            'the page.'),
      ],
    ),
  ];
}
