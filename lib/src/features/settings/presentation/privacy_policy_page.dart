import 'package:flutter/material.dart';

import 'package:BoltStar/src/shared/widgets/figma_common.dart';
import 'legal_document_view.dart';

/// 隐私政策页面，对应 UI 稿「隐私政策」。正文为占位文案，接入正式条款时替换 [_sections]。
class PrivacyPolicyPage extends StatelessWidget {
  const PrivacyPolicyPage({super.key});

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
            child: FigmaTopNavigation(title: '隐私政策'),
          ),
          Positioned(
            left: 0,
            top: 100,
            right: 0,
            bottom: 0,
            child: LegalDocumentView(
              title: '《BoltStar 隐私政策》',
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
        '欢迎使用 BoltStar（以下简称“本应用”）。我们非常重视您的个人信息及隐私保护。本政策将帮助您了解我们如何收集、使用、'
        '存储和保护您的个人信息，以及您享有的相关权利。请在使用本应用前仔细阅读并充分理解本政策的各项条款。',
  ),
  LegalSection(
    heading: '一、我们收集的信息',
    body:
        '1. 您主动提供的信息：如手机号码（123456789）、邮箱地址等账号注册信息，以及您在使用本应用过程中填写的个人资料、反馈信息等。\n'
        '2. 自动收集的信息：包括设备型号、操作系统版本、网络状态等，用于保障服务稳定与功能优化。\n'
        '3. 设备连接信息：为完成相框设备的蓝牙搜索与连接，我们会读取必要的蓝牙与位置信息。',
  ),
  LegalSection(
    heading: '二、信息的使用',
    body:
        '我们仅在为您提供服务所必需的范围内使用上述信息，包括账号登录、设备绑定、照片投屏、服务通知等，'
        '不会将您的个人信息用于本政策未载明的其他用途。',
  ),
  LegalSection(
    heading: '三、信息的存储与保护',
    body:
        '我们将采取符合行业标准的安全措施保护您的个人信息，防止数据遭到未经授权的访问、披露、使用、修改或丢失。'
        '当前演示版本不会将照片数据上传至云端服务器。',
  ),
  LegalSection(
    heading: '四、您的权利',
    body:
        '您有权随时访问、更正、删除您的个人信息，也可以通过“用户注销”功能注销账号。注销后，您的相关数据将被删除且无法恢复。',
  ),
  LegalSection(
    heading: '五、政策更新',
    body:
        '我们可能会适时更新本隐私政策。更新后将在本应用内以适当方式通知您。继续使用本应用即视为您接受更新后的政策。',
  ),
];
