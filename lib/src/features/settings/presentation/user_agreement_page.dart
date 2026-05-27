import 'package:flutter/material.dart';

import 'package:BoltStar/src/shared/widgets/figma_common.dart';
import 'legal_document_view.dart';

/// 用户协议页面，对应 UI 稿「用户协议」。正文为占位文案，接入正式条款时替换 [_sections]。
class UserAgreementPage extends StatelessWidget {
  const UserAgreementPage({super.key});

  @override
  Widget build(BuildContext context) {
    return FigmaPhoneFrame(
      child: Stack(
        children: const [
          FigmaPageBackground(),
          Positioned(
            left: 0,
            top: 0,
            width: 375,
            height: 90,
            child: FigmaTopNavigation(title: '用户协议'),
          ),
          Positioned(
            left: 0,
            top: 100,
            right: 0,
            bottom: 0,
            child: LegalDocumentView(
              title: '《BoltStar 用户协议》',
              updatedAt: '2026-5-13',
              effectiveAt: '2026-5-13',
              sections: _sections,
            ),
          ),
          FigmaBottomHomeIndicator(),
        ],
      ),
    );
  }
}

const List<LegalSection> _sections = [
  LegalSection(
    heading: '前言',
    body:
        '欢迎使用 BoltStar（以下简称“本应用”）。本《用户协议》（以下简称“本协议”）是您与本应用运营方之间就使用本应用服务'
        '所订立的协议。请您在使用本应用前认真阅读并充分理解本协议各条款，一旦您开始使用本应用，即视为您已接受本协议的全部内容。',
  ),
  LegalSection(
    heading: '一、服务说明',
    body:
        '本应用为您提供相框设备绑定、照片管理、投屏展示等功能。我们将持续优化产品体验，并可能根据运营需要对服务内容进行调整、'
        '中断或终止，相关变更将提前通过本应用予以公告。',
  ),
  LegalSection(
    heading: '二、账号与安全',
    body:
        '1. 您应妥善保管账号及密码，对账号下的全部行为承担责任。\n'
        '2. 如发现账号被他人非法使用，请立即通知我们。\n'
        '3. 您承诺不利用本应用从事违反法律法规或损害他人合法权益的行为。',
  ),
  LegalSection(
    heading: '三、设备与照片',
    body:
        '设备所有者可配置设备权限、轮播模式并执行一键清空等操作；普通使用者仅可管理自己上传的照片。'
        '请确保您对上传的照片拥有合法权利，并对其内容负责。',
  ),
  LegalSection(
    heading: '四、免责声明',
    body:
        '因不可抗力、网络故障、设备问题等非本应用原因导致的服务中断或数据丢失，本应用在法律允许的范围内不承担相应责任。',
  ),
  LegalSection(
    heading: '五、协议变更',
    body:
        '我们有权根据法律法规及业务需要适时修订本协议。修订后的协议将在本应用内公布，若您继续使用本应用，即表示同意修订后的协议。',
  ),
];
