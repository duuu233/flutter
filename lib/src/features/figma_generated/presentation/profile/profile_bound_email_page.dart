import 'package:flutter/material.dart';

import '../widgets/figma_common.dart';

class ProfileBoundEmailPage extends StatefulWidget {
  const ProfileBoundEmailPage({super.key, this.onSave, this.onModifyEmail});

  final VoidCallback? onSave;
  final VoidCallback? onModifyEmail;

  @override
  State<ProfileBoundEmailPage> createState() => _ProfileBoundEmailPageState();
}

class _ProfileBoundEmailPageState extends State<ProfileBoundEmailPage> {
  final TextEditingController _nicknameController = TextEditingController(
    text: '江江江',
  );

  @override
  void dispose() {
    _nicknameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FigmaPhoneFrame(
      child: Stack(
        children: [
          const FigmaPageBackground(),
          const Positioned(
            left: 0,
            top: 0,
            width: 375,
            height: 90,
            child: FigmaTopNavigation(title: '个人信息'),
          ),
          Positioned(
            left: 24,
            top: 109,
            width: 327,
            height: 244,
            child: FigmaGlassCard(
              child: Column(
                children: [
                  const _AvatarRow(),
                  const FigmaFormDivider(),
                  FigmaAccountField(
                    label: '昵称',
                    controller: _nicknameController,
                    hintText: '请输入昵称',
                  ),
                  const FigmaFormDivider(),
                  const FigmaInfoRow(label: 'ID', value: '123456'),
                  const FigmaFormDivider(),
                  FigmaInfoRow(
                    label: '邮箱',
                    value: '123456789@qq.com',
                    onTap: widget.onModifyEmail,
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            left: 26,
            top: 543,
            width: 323,
            height: 64,
            child: FigmaPrimaryButton(
              label: '保存资料',
              height: 64,
              onPressed: widget.onSave,
            ),
          ),
          const FigmaBottomHomeIndicator(),
        ],
      ),
    );
  }
}

class _AvatarRow extends StatelessWidget {
  const _AvatarRow();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 61,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(
          children: [
            const Expanded(child: Text('头像', style: FigmaTextStyles.formLabel)),
            Container(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFFE7E7E7),
              ),
              child: const Icon(
                Icons.person_rounded,
                color: Color(0x992A2B2B),
                size: 24,
              ),
            ),
            const SizedBox(width: 6),
            const Icon(
              Icons.chevron_right_rounded,
              color: Color(0x992A2B2B),
              size: 18,
            ),
          ],
        ),
      ),
    );
  }
}
