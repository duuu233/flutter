import 'package:flutter/material.dart';

import 'package:BoltStar/src/shared/widgets/figma_common.dart';
import '../../../shared/l10n/app_l10n.dart';
import 'legal_document_view.dart';

/// 隐私政策页面，正文与小程序 `subpackages/settings/privacy` 保持一致。
class PrivacyPolicyPage extends StatelessWidget {
  const PrivacyPolicyPage({super.key});

  @override
  Widget build(BuildContext context) {
    return FigmaScreen(
      title: AppL10n.of(context).setPrivacyTitle,
      scrollable: false,
      bodyPadding: EdgeInsets.zero,
      body: const LegalDocumentView(
        title: '《BoltStar 隐私政策》',
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
        '欢迎使用 BoltStar（以下简称“本应用”）。我们深知个人信息对您的重要性，并将以高度审慎的态度保护您的个人信息安全。'
        '本政策旨在向您说明我们如何收集、使用、存储、共享和保护您的个人信息。',
  ),
  LegalSection(
    heading: '一、我们收集哪些信息?',
    body:
        '1. 您主动提供的信息\n'
        '• 注册 / 登录信息：如手机号、验证码、账号信息等。\n'
        '• 您在使用服务时主动上传或填写的内容，例如资料、反馈信息等。\n'
        '2. 自动收集的信息\n'
        '• 设备信息：设备型号、操作系统版本、唯一设备识别码、网络类型、IP 地址等。\n'
        '• 日志信息：使用时长、功能访问路径、异常日志等，用于优化产品体验。',
  ),
  LegalSection(
    heading: '二、我们如何使用这些信息?',
    body: '用于提供、维护和优化本应用的核心服务，包括账号安全、设备连接、照片投屏和客户支持。',
  ),
];
