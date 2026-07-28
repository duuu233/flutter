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
        sections: _sectionsFor(l10n),
      ),
    );
  }

  List<LegalSection> _sectionsFor(AppL10n l10n) {
    return [
      LegalSection(
        heading: l10n.pick('1. 服务说明', '1. Service Description', '1. サービス内容'),
        body: l10n.pick(
          '本协议适用于你使用本应用提供的AI相关功能，包括但不限于：\n'
              '• AI文本对话\n'
              '• AI图片生成（文生图）\n'
              '• AI图片美化（图生图）\n\n'
              '上述功能由阿里云百炼（阿里云计算有限公司）提供底层AI技术服务。',
          'This Agreement applies to the AI features provided by the App, '
              'including but not limited to:\n'
              '• AI text chat\n'
              '• AI image generation (text-to-image)\n'
              '• AI image enhancement (image-to-image)\n\n'
              'The underlying AI technology for these features is provided '
              'by Alibaba Cloud Model Studio (Alibaba Cloud Computing Co., Ltd.).',
          '本規約は、本アプリが提供する以下のAI関連機能に適用されます。\n'
              '• AIテキスト対話\n'
              '• AI画像生成（テキストから画像）\n'
              '• AI画像加工（画像から画像）\n\n'
              'これらの機能の基盤AI技術は、Alibaba Cloud Computing Co., Ltd.'
              'のAlibaba Cloud Model Studioによって提供されます。',
        ),
      ),
      LegalSection(
        heading: l10n.pick(
          '2. 数据使用与授权',
          '2. Data Use and Authorization',
          '2. データの利用と許諾',
        ),
        body: l10n.pick(
          '为了向你提供AI服务，你需要知悉并授权以下内容：\n'
              '• 数据传输：你发送的文字或图片内容，将被传输至阿里云百炼AI服务进行处理。\n'
              '• 数据处理：你发送的内容仅用于本次AI处理操作，不会被存储或用于模型训练。\n'
              '• 数据用途：阿里云百炼仅作为技术处理方，不会将你的内容用于任何其他目的。\n\n'
              '你授权本应用将你主动提交的内容传输至阿里云百炼进行处理，授权仅在你使用AI功能时生效。',
          'To provide the AI services, you acknowledge and authorize the following:\n'
              '• Data transfer: Text or images you send will be transmitted '
              'to Alibaba Cloud Model Studio for processing.\n'
              '• Data processing: Your content is used only for the current '
              'AI operation and will not be stored or used for model training.\n'
              '• Data purpose: Alibaba Cloud Model Studio acts only as a '
              'technical processor and will not use your content for any other purpose.\n\n'
              'You authorize the App to transmit content you actively submit '
              'to Alibaba Cloud Model Studio. This authorization applies only '
              'while you use AI features.',
          'AIサービスの提供にあたり、以下の内容を確認し、許諾する必要があります。\n'
              '• データ送信：送信したテキストまたは画像は、処理のためAlibaba Cloud '
              'Model Studioへ送信されます。\n'
              '• データ処理：送信内容は今回のAI処理にのみ使用され、保存またはモデル学習に'
              '利用されることはありません。\n'
              '• データ用途：Alibaba Cloud Model Studioは技術処理者としてのみ機能し、'
              '送信内容をその他の目的に利用しません。\n\n'
              'お客様は、能動的に送信した内容を本アプリがAlibaba Cloud Model Studioへ'
              '送信することを許諾します。この許諾はAI機能の利用時にのみ有効です。',
        ),
      ),
      LegalSection(
        heading: l10n.pick('3. 使用规范', '3. Acceptable Use', '3. 利用ルール'),
        body: l10n.pick(
          '使用AI功能时，你承诺不提交、不传播以下内容：\n'
              '• 违反法律法规的内容\n'
              '• 色情、低俗内容\n'
              '• 暴力、恐怖内容\n'
              '• 侮辱、诽谤他人内容\n'
              '• 其他违法违规或违背公序良俗的内容\n\n'
              '本应用已接入阿里云内容安全审核服务，所有提交内容均会自动进行合规检测。',
          'When using AI features, you agree not to submit or distribute:\n'
              '• Content that violates laws or regulations\n'
              '• Pornographic or vulgar content\n'
              '• Violent or terrorist content\n'
              '• Content that insults or defames others\n'
              '• Other illegal content or content contrary to public order and good morals\n\n'
              'The App uses Alibaba Cloud content moderation. All submitted '
              'content is automatically checked for compliance.',
          'AI機能の利用時、以下の内容を送信または拡散しないことに同意するものとします。\n'
              '• 法令に違反する内容\n'
              '• わいせつまたは低俗な内容\n'
              '• 暴力的またはテロに関する内容\n'
              '• 他者を侮辱または中傷する内容\n'
              '• その他、違法または公序良俗に反する内容\n\n'
              '本アプリはAlibaba Cloudのコンテンツ安全審査サービスを導入しており、'
              'すべての送信内容は自動的に適合性チェックを受けます。',
        ),
      ),
      LegalSection(
        heading: l10n.pick('4. 违规处理', '4. Enforcement', '4. 違反時の措置'),
        body: l10n.pick(
          '为维护良好的使用环境，对于违反使用规范的用户，将采取以下处理措施：\n\n'
              '违规次数｜处理措施\n'
              '第1次｜警告提醒，AI功能封禁24小时\n'
              '第2次｜AI功能封禁24小时\n'
              '第3次｜AI功能封禁24小时\n'
              '累计3次后，每新增1次｜AI功能封禁24小时\n'
              '累计满9次｜AI功能永久封禁\n\n'
              '说明：封禁仅针对AI功能，不影响你使用应用的其他功能。'
              '如对封禁有异议，可联系客服申诉。',
          'To maintain a safe environment, violations are handled as follows:\n\n'
              'Violation count | Action\n'
              '1st | Warning and 24-hour AI feature suspension\n'
              '2nd | 24-hour AI feature suspension\n'
              '3rd | 24-hour AI feature suspension\n'
              'After 3 total, each additional violation | 24-hour AI feature suspension\n'
              '9 total | Permanent AI feature suspension\n\n'
              'Suspensions apply only to AI features and do not affect other '
              'App functions. You may contact customer support to appeal.',
          '安全な利用環境を維持するため、違反には以下の措置を適用します。\n\n'
              '違反回数｜措置\n'
              '1回目｜警告およびAI機能の24時間停止\n'
              '2回目｜AI機能の24時間停止\n'
              '3回目｜AI機能の24時間停止\n'
              '累計3回以降、新たな違反ごと｜AI機能の24時間停止\n'
              '累計9回｜AI機能の永久停止\n\n'
              '停止対象はAI機能のみで、その他のアプリ機能には影響しません。'
              '異議がある場合はカスタマーサポートへ申し立てることができます。',
        ),
      ),
      LegalSection(
        heading: l10n.pick('5. 免责声明', '5. Disclaimer', '5. 免責事項'),
        body: l10n.pick(
          '• AI生成内容仅供参考，本应用不对AI生成内容的准确性、完整性、合法性承担保证责任。\n'
              '• 你应对使用AI功能产生的内容自行判断和负责。\n'
              '• 本应用保留随时修改、暂停或终止AI服务的权利，会尽可能提前通知。',
          '• AI-generated content is for reference only. The App does not '
              'guarantee its accuracy, completeness, or legality.\n'
              '• You are responsible for evaluating and using content produced '
              'through AI features.\n'
              '• The App may modify, suspend, or terminate AI services at any '
              'time and will provide advance notice where reasonably possible.',
          '• AI生成内容は参考情報です。本アプリはその正確性、完全性、合法性を保証しません。\n'
              '• AI機能で生成された内容については、お客様自身が判断し責任を負うものとします。\n'
              '• 本アプリはAIサービスを随時変更・停止・終了する権利を留保し、'
              '可能な限り事前に通知します。',
        ),
      ),
      LegalSection(
        heading: l10n.pick(
          '6. 协议的变更',
          '6. Changes to this Agreement',
          '6. 規約の変更',
        ),
        body: l10n.pick(
          '本应用可能根据法律法规变化或服务升级需要，适时更新本协议。'
              '更新后的协议会在本页面发布，并在你下次使用AI功能时提醒你查阅。',
          'The App may update this Agreement in response to legal or regulatory '
              'changes or service upgrades. The revised Agreement will be '
              'published on this page, and you will be reminded to review it '
              'the next time you use AI features.',
          '法令の変更またはサービス更新に応じて、本規約を改定する場合があります。'
              '改定後の規約は本ページに掲載し、次回AI機能を利用する際に確認を促します。',
        ),
      ),
      LegalSection(
        heading: l10n.pick('7. 联系方式', '7. Contact', '7. お問い合わせ'),
        body: l10n.pick(
          '如对本协议有任何疑问，或对封禁处理有异议，可通过邮箱方式联系我们：'
              'boltstarservice@boltstar.net',
          'For questions about this Agreement or to appeal a suspension, '
              'contact us by email: boltstarservice@boltstar.net',
          '本規約に関するご質問または利用停止への異議申し立ては、'
              'boltstarservice@boltstar.net までメールでお問い合わせください。',
        ),
      ),
    ];
  }
}
