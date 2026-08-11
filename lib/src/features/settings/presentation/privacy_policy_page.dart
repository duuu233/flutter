import 'package:flutter/material.dart';

import 'package:BoltStar/src/shared/widgets/figma_common.dart';
import '../../../shared/l10n/app_l10n.dart';
import 'legal_document_view.dart';

/// 隐私政策页面，简中正文与小程序 `subpackages/settings/privacy` 保持一致；
/// en/ja 为对应译文，繁中由简中经 l10n 自动转换（与全 App 文案同规则）。
class PrivacyPolicyPage extends StatelessWidget {
  const PrivacyPolicyPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    return FigmaScreen(
      title: l10n.setPrivacyTitle,
      scrollable: false,
      bodyPadding: EdgeInsets.zero,
      body: LegalDocumentView(
        title: l10n.pick(
          '《BoltStar 隐私政策》',
          'BoltStar Privacy Policy',
          '「BoltStar プライバシーポリシー」',
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
          '欢迎使用 BoltStar（以下简称“本应用”）。我们深知个人信息对您的重要性，并将以高度审慎的态度保护您的个人信息安全。'
              '本政策旨在向您说明我们如何收集、使用、存储、共享和保护您的个人信息。',
          'Welcome to BoltStar (the "App"). We fully understand how important '
              'your personal information is to you, and we protect it with the '
              'utmost care. This policy explains how we collect, use, store, '
              'share, and protect your personal information.',
          'BoltStar（以下「本アプリ」）をご利用いただきありがとうございます。'
              '当社は個人情報の重要性を深く認識し、細心の注意をもってお客様の個人情報を保護します。'
              '本ポリシーは、当社が個人情報をどのように収集・利用・保存・共有・保護するかを説明するものです。',
        ),
      ),
      LegalSection(
        heading: l10n.pick(
          '一、我们收集哪些信息?',
          '1. What Information We Collect',
          '一、収集する情報',
        ),
        body: l10n.pick(
          '1. 您主动提供的信息\n'
              '• 注册 / 登录信息：如手机号、验证码、账号信息等。\n'
              '• 您在使用服务时主动上传或填写的内容，例如资料、反馈信息等。\n'
              '2. 自动收集的信息\n'
              '• 终端信息：终端型号、操作系统版本、唯一终端识别码、网络类型、IP 地址等。\n'
              '• 日志信息：使用时长、功能访问路径、异常日志等，用于优化产品体验。',
          '1. Information you provide\n'
              '• Registration / login information, such as phone number, '
              'verification code, and account details.\n'
              '• Content you upload or enter while using the service, such '
              'as profile data and feedback.\n'
              '2. Information collected automatically\n'
              '• Device information: device model, OS version, unique '
              'device identifier, network type, IP address, etc.\n'
              '• Log information: usage duration, feature access paths, '
              'crash logs, etc., used to improve the product experience.',
          '1. お客様が提供する情報\n'
              '• 登録／ログイン情報：電話番号、認証コード、アカウント情報など。\n'
              '• サービス利用時にアップロード・入力した内容（プロフィール、フィードバックなど）。\n'
              '2. 自動的に収集される情報\n'
              '• デバイス情報：機種、OS バージョン、デバイス識別子、ネットワーク種別、IP アドレスなど。\n'
              '• ログ情報：利用時間、機能アクセス経路、異常ログなど（製品体験の改善に使用）。',
        ),
      ),
      LegalSection(
        heading: l10n.pick(
          '二、我们如何使用这些信息?',
          '2. How We Use This Information',
          '二、情報の利用方法',
        ),
        body: l10n.pick(
          '用于提供、维护和优化本应用的核心服务，包括账号安全、设备连接、照片投屏和客户支持。',
          'We use this information to provide, maintain, and improve the '
              "App's core services, including account security, device "
              'connection, photo casting, and customer support.',
          'アカウントの安全、デバイス接続、写真の投影、カスタマーサポートなど、'
              '本アプリの中核サービスの提供・維持・改善のために利用します。',
        ),
      ),
    ];
  }
}
