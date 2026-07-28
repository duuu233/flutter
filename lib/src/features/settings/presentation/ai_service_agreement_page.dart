import 'package:flutter/material.dart';

import 'package:BoltStar/src/shared/widgets/figma_common.dart';
import '../../../shared/l10n/app_l10n.dart';
import 'legal_document_view.dart';

/// BoltStar AI 服务协议。
///
/// 简中正文与小程序 `subpackages/settings/ai-agreement` 保持一致；繁中由
/// [AppL10n] 自动转换，英文和日文使用对应译文。
class AiServiceAgreementPage extends StatelessWidget {
  const AiServiceAgreementPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final date = l10n.pick('2026年7月28日', 'July 28, 2026', '2026年7月28日');
    return FigmaScreen(
      title: l10n.aiServiceAgreementTitle,
      scrollable: false,
      bodyPadding: EdgeInsets.zero,
      body: LegalDocumentView(
        title: l10n.pick(
          '《BoltStar AI服务协议》',
          'BoltStar AI Service Agreement',
          '「BoltStar AIサービス規約」',
        ),
        updatedAt: date,
        effectiveAt: date,
        intro: _introFor(l10n),
        sections: _sectionsFor(l10n),
      ),
    );
  }

  String _introFor(AppL10n l10n) {
    return l10n.pick(
      '欢迎使用AI服务。本协议是您（以下称“用户”）与 [启和明(深圳)新能源科技有限公司] '
          '（以下称“我们”）之间，关于使用我们提供的AI功能（以下称“本服务”）的法律协议。'
          '请您在使用本服务前仔细阅读。',
      'Welcome to the AI Service. This Agreement is a legal agreement between '
          'you (the “User”) and [Qihe Ming (Shenzhen) New Energy Technology '
          'Co., Ltd.] (“we”, “us” or “our”) concerning your use of the AI '
          'features we provide (the “Service”). Please read it carefully '
          'before using the Service.',
      'AIサービスへようこそ。本規約は、お客様（以下「ユーザー」といいます）と'
          '[Qihe Ming (Shenzhen) New Energy Technology Co., Ltd.]'
          '（以下「当社」といいます）との間で、当社が提供するAI機能'
          '（以下「本サービス」といいます）の利用について定める法的な規約です。'
          '本サービスをご利用になる前に、よくお読みください。',
    );
  }

  List<LegalSection> _sectionsFor(AppL10n l10n) {
    return [
      LegalSection(
        heading: l10n.pick('1. 服务说明', '1. Service Description', '1. サービス内容'),
        body: l10n.pick(
          '1.1 本服务基于“阿里云百炼”大模型服务平台提供技术支持，为您提供包括文本对话、'
              'AI图片生成、AI图片美化等功能。\n\n'
              '1.2 本服务仅限您在同意本协议后，于我们指定的小程序或App内使用。',
          '1.1 The Service is technically supported by the Alibaba Cloud Model '
              'Studio foundation-model platform and provides features including '
              'text chat, AI image generation, and AI image enhancement.\n\n'
              '1.2 You may use the Service only after agreeing to this Agreement '
              'and only within a mini program or App designated by us.',
          '1.1 本サービスは、Alibaba Cloud Model Studioの大規模モデルサービス'
              'プラットフォームによる技術支援に基づき、テキスト対話、AI画像生成、'
              'AI画像加工などの機能を提供します。\n\n'
              '1.2 本サービスは、本規約に同意した後、当社が指定するミニプログラム'
              'またはアプリ内でのみ利用できます。',
        ),
      ),
      LegalSection(
        heading: l10n.pick(
          '2. 数据使用与授权',
          '2. Data Use and Authorization',
          '2. データの利用と許諾',
        ),
        body: l10n.pick(
          '2.1 授权：为提供本服务，您授权我们将您主动提交的文字或图片内容传输至'
              '“阿里云百炼”AI服务进行处理。\n\n'
              '2.2 数据处理：您明确知悉并同意，您发送的内容仅用于处理您本次的AI请求，'
              '不会被存储，也不会被用于任何模型训练或优化。\n\n'
              '2.3 技术提供方：本服务的底层AI技术由阿里云计算有限公司（或其关联公司）提供。',
          '2.1 Authorization: To provide the Service, you authorize us to '
              'transmit text or images that you actively submit to Alibaba '
              'Cloud Model Studio AI services for processing.\n\n'
              '2.2 Data processing: You expressly acknowledge and agree that '
              'content you send is used only to process your current AI request, '
              'will not be stored, and will not be used for any model training '
              'or optimization.\n\n'
              '2.3 Technology provider: The underlying AI technology for the '
              'Service is provided by Alibaba Cloud Computing Co., Ltd. or its affiliates.',
          '2.1 許諾：本サービスを提供するため、お客様は、自ら送信したテキスト'
              'または画像を処理のためAlibaba Cloud Model StudioのAIサービスへ'
              '送信することを当社に許諾します。\n\n'
              '2.2 データ処理：送信内容は今回のAIリクエストの処理にのみ使用され、'
              '保存されず、いかなるモデルの学習または最適化にも使用されないことを、'
              'お客様は明確に理解し同意するものとします。\n\n'
              '2.3 技術提供者：本サービスの基盤AI技術は、Alibaba Cloud Computing '
              'Co., Ltd.またはその関連会社が提供します。',
        ),
      ),
      LegalSection(
        heading: l10n.pick('3. 用户使用规范', '3. Acceptable Use', '3. ユーザーの利用ルール'),
        body: l10n.pick(
          '您承诺在使用本服务时，不会提交、生成或传播以下内容：\n'
              '3.1 违反中华人民共和国法律法规及政策的内容；\n'
              '3.2 色情、低俗、淫秽或性暗示内容；\n'
              '3.3 暴力、恐怖、血腥或宣扬犯罪的内容；\n'
              '3.4 侮辱、诽谤、威胁、骚扰或侵害他人合法权益的内容；\n'
              '3.5 其他违背公序良俗、社会公德或可能损害本服务声誉的内容。',
          'When using the Service, you agree not to submit, generate, or distribute:\n'
              '3.1 Content that violates the laws, regulations, or policies of '
              'the People’s Republic of China;\n'
              '3.2 Pornographic, vulgar, obscene, or sexually suggestive content;\n'
              '3.3 Violent, terrorist, bloody, or crime-promoting content;\n'
              '3.4 Content that insults, defames, threatens, harasses, or '
              'infringes the lawful rights of others;\n'
              '3.5 Other content contrary to public order, good morals, or '
              'social ethics, or that may harm the reputation of the Service.',
          '本サービスの利用時、以下の内容を送信、生成または拡散しないことを約束します。\n'
              '3.1 中華人民共和国の法令または政策に違反する内容\n'
              '3.2 わいせつ、低俗、卑わい、または性的な示唆を含む内容\n'
              '3.3 暴力、テロ、流血、または犯罪を助長する内容\n'
              '3.4 他者を侮辱、中傷、脅迫、嫌がらせし、または他者の適法な権利を'
              '侵害する内容\n'
              '3.5 その他、公序良俗や社会道徳に反し、または本サービスの信用を'
              '損なうおそれのある内容',
        ),
      ),
      LegalSection(
        heading: l10n.pick('4. 违规处理', '4. Enforcement', '4. 違反時の措置'),
        body: l10n.pick(
          '为维护良好使用环境，对于违反本协议第3条规范的账号，我们将采取以下阶梯式处理：\n\n'
              '违规次数｜处理措施\n'
              '第1次｜AI功能封禁24小时\n'
              '第2次｜AI功能封禁24小时\n'
              '第3次｜AI功能封禁24小时\n'
              '累计3次后，每新增1次｜AI功能封禁24小时\n'
              '累计满9次｜AI功能永久封禁\n\n'
              '说明：封禁仅针对本AI服务，不影响您使用小程序/App的其他功能。'
              '您可通过指定渠道申诉。',
          'To maintain a safe environment, accounts that violate Section 3 '
              'will be handled on the following graduated basis:\n\n'
              'Violation count | Action\n'
              '1st | 24-hour AI feature suspension\n'
              '2nd | 24-hour AI feature suspension\n'
              '3rd | 24-hour AI feature suspension\n'
              'After 3 total, each additional violation | 24-hour AI feature suspension\n'
              '9 total | Permanent AI feature suspension\n\n'
              'Suspensions apply only to this AI Service and do not affect '
              'other mini program/App features. You may appeal through the designated channel.',
          '良好な利用環境を維持するため、第3条に違反したアカウントには'
              '以下の段階的措置を適用します。\n\n'
              '違反回数｜措置\n'
              '1回目｜AI機能を24時間停止\n'
              '2回目｜AI機能を24時間停止\n'
              '3回目｜AI機能を24時間停止\n'
              '累計3回以降、新たな違反ごと｜AI機能を24時間停止\n'
              '累計9回｜AI機能を永久停止\n\n'
              '停止対象は本AIサービスのみで、ミニプログラムまたはアプリの'
              'その他の機能には影響しません。指定された窓口から異議を申し立てることができます。',
        ),
      ),
      LegalSection(
        heading: l10n.pick(
          '5. AI生成内容标识',
          '5. AI-Generated Content Labeling',
          '5. AI生成コンテンツの表示',
        ),
        body: l10n.pick(
          '5.1 您知悉并同意，为遵守法律法规，由本服务生成的图片或文本内容，'
              '可能带有“AI生成”等显著标识。\n\n'
              '5.2 您在发布或传播由本服务生成的非真实信息时，应依法自行进行显著标识。',
          '5.1 You acknowledge and agree that, to comply with applicable laws '
              'and regulations, images or text generated by the Service may '
              'carry a prominent label such as “AI-generated.”\n\n'
              '5.2 When publishing or distributing non-authentic information '
              'generated by the Service, you must add a prominent label as required by law.',
          '5.1 法令を遵守するため、本サービスが生成した画像またはテキストには、'
              '「AI生成」などの明確な表示が付される場合があることを理解し、同意するものとします。\n\n'
              '5.2 本サービスが生成した事実ではない情報を公開または拡散する場合、'
              '法令に従って自ら明確な表示を付けなければなりません。',
        ),
      ),
      LegalSection(
        heading: l10n.pick('6. 免责声明', '6. Disclaimer', '6. 免責事項'),
        body: l10n.pick(
          '6.1 由于人工智能技术的局限性，本服务生成的内容不保证绝对准确、可靠或完整，'
              '仅供您参考，不代表我们的立场或观点。\n\n'
              '6.2 对于任何专业领域问题（如医疗、法律、金融等），请咨询专业人士，'
              '我们不承担因依赖本服务生成内容而产生的任何直接或间接损失。\n\n'
              '6.3 您应对使用本服务的行为及后果独立承担全部责任。',
          '6.1 Due to the limitations of artificial intelligence, content '
              'generated by the Service is not guaranteed to be completely '
              'accurate, reliable, or complete. It is for reference only and '
              'does not represent our position or views.\n\n'
              '6.2 For professional matters such as medical, legal, or financial '
              'issues, consult a qualified professional. We are not liable for '
              'any direct or indirect loss arising from reliance on content '
              'generated by the Service.\n\n'
              '6.3 You bear full and independent responsibility for your use '
              'of the Service and its consequences.',
          '6.1 AI技術の限界により、本サービスが生成する内容の絶対的な正確性、'
              '信頼性または完全性は保証されません。参考情報にすぎず、当社の立場'
              'または見解を示すものではありません。\n\n'
              '6.2 医療、法律、金融などの専門分野に関する問題は、専門家へご相談ください。'
              '本サービスの生成内容を信頼したことにより生じる直接または間接の損失について、'
              '当社は責任を負いません。\n\n'
              '6.3 本サービスの利用行為およびその結果について、お客様が単独で'
              'すべての責任を負うものとします。',
        ),
      ),
      LegalSection(
        heading: l10n.pick('7. 知识产权', '7. Intellectual Property', '7. 知的財産権'),
        body: l10n.pick(
          '7.1 您上传至本服务的原始内容的知识产权归您所有。\n\n'
              '7.2 在现行法律允许的范围内，本服务基于您指令生成的内容，其知识产权由您享有，'
              '您应自行判断其是否具有知识产权及权利归属，并承担相应责任。',
          '7.1 You retain the intellectual property rights in original content '
              'that you upload to the Service.\n\n'
              '7.2 To the extent permitted by applicable law, you own any '
              'intellectual property rights in content generated by the Service '
              'from your instructions. You must determine for yourself whether '
              'such rights exist and who owns them, and bear the corresponding responsibility.',
          '7.1 本サービスにアップロードした原コンテンツの知的財産権は、'
              'お客様に帰属します。\n\n'
              '7.2 現行法で認められる範囲において、お客様の指示に基づき本サービスが'
              '生成した内容の知的財産権はお客様に帰属します。その内容に知的財産権が'
              '成立するか、および権利の帰属については自ら判断し、相応の責任を負うものとします。',
        ),
      ),
      LegalSection(
        heading: l10n.pick(
          '8. 协议变更与联系方式',
          '8. Changes and Contact',
          '8. 規約の変更とお問い合わせ',
        ),
        body: l10n.pick(
          '8.1 我们可能根据法律法规或服务升级需要，适时更新本协议。'
              '更新后的协议将在此页面公布。\n\n'
              '8.2 如您对本协议有任何疑问，或对违规处理有异议，'
              '可通过邮箱联系我们：boltstarservice@boltstar.net',
          '8.1 We may update this Agreement as necessary due to legal or '
              'regulatory changes or service upgrades. The updated Agreement '
              'will be published on this page.\n\n'
              '8.2 For questions about this Agreement or objections to an '
              'enforcement action, contact us by email: boltstarservice@boltstar.net',
          '8.1 法令の変更またはサービス更新の必要に応じて、本規約を改定する場合があります。'
              '改定後の規約は本ページに掲載します。\n\n'
              '8.2 本規約に関するご質問または違反措置への異議申し立ては、'
              'boltstarservice@boltstar.net までメールでお問い合わせください。',
        ),
      ),
    ];
  }
}
