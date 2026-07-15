import 'package:flutter/material.dart';

import 'package:BoltStar/src/shared/widgets/figma_common.dart';
import '../../../shared/l10n/app_l10n.dart';
import 'legal_document_view.dart';

/// 用户协议页面，正文与小程序 `subpackages/settings/agreement` 保持一致。
class UserAgreementPage extends StatelessWidget {
  const UserAgreementPage({super.key});

  @override
  Widget build(BuildContext context) {
    return FigmaScreen(
      title: AppL10n.of(context).setAgreementTitle,
      scrollable: false,
      bodyPadding: EdgeInsets.zero,
      body: const LegalDocumentView(
        title: '《BoltStar 用户协议》',
        updatedAt: '2026-5-13',
        effectiveAt: '2026-5-13',
        sections: _sections,
      ),
    );
  }
}

const List<LegalSection> _sections = [
  LegalSection(
    heading: '前言',
    body:
        '欢迎使用 BoltStar。在使用本应用前，请您仔细阅读《用户协议》以及《隐私政策》。'
        '您注册、登录或使用本应用的行为，即表示您已充分理解并同意接受本协议的全部条款约束。',
  ),
  LegalSection(
    heading: '一、服务说明',
    body:
        '1. 本应用由 BoltStar 团队提供照片管理、设备连接、照片投屏等核心服务。\n'
        '2. 我们将尽最大努力保障服务稳定性，但因网络故障、设备问题、第三方服务影响等不可抗因素导致的服务中断或异常，'
        '我们不承担责任，但会尽力协助处理。\n'
        '3. 我们保留随时修改、升级或终止部分或全部服务的权利，修改或终止前会通过 App 内公告提前告知您。',
  ),
  LegalSection(
    heading: '二、账号注册与使用规则',
    body:
        '1. 您需提供真实、有效的信息完成账号注册，并对您账号下的所有行为负责。\n'
        '2. 您应妥善保管账号、密码及验证码信息，因您自身原因导致的账号被盗、信息泄露或财产损失，由您自行承担责任。',
  ),
];
