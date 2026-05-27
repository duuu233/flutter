import 'package:flutter/material.dart';

import 'package:BoltStar/src/shared/widgets/figma_common.dart';

/// 账户资料页（未绑定邮箱）：展示资料并引导去绑定邮箱，对应 UI 稿「账户资料-未绑定邮箱」。
class ProfileUnboundEmailPage extends StatefulWidget {
  const ProfileUnboundEmailPage({super.key, this.onSave, this.onBindEmail});

  final VoidCallback? onSave;
  final VoidCallback? onBindEmail;

  @override
  State<ProfileUnboundEmailPage> createState() =>
      _ProfileUnboundEmailPageState();
}

class _ProfileUnboundEmailPageState extends State<ProfileUnboundEmailPage> {
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
    return FigmaScreen(
      title: '个人信息',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 12),
          FigmaGlassCard(
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
                  value: '暂未绑定',
                  onTap: widget.onBindEmail,
                ),
              ],
            ),
          ),
        ],
      ),
      bottom: FigmaPrimaryButton(label: '保存资料', onPressed: widget.onSave),
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
