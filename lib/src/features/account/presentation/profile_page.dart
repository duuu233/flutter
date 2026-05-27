import 'package:flutter/material.dart';

import 'package:BoltStar/src/shared/widgets/figma_common.dart';
import '../../../routes/app_routes.dart';
import '../../../state.dart';

/// 账户资料页：查看与编辑个人信息（头像、昵称、邮箱等）。
class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key, required this.state});

  final PhotoFrameState state;

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  late final TextEditingController _nicknameController;

  @override
  void initState() {
    super.initState();
    _nicknameController = TextEditingController(
      text: widget.state.currentUser.nickname,
    );
  }

  @override
  void dispose() {
    _nicknameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.state.currentUser;
    final emailText = user.email.isEmpty ? '暂未绑定' : user.email;

    return FigmaScreen(
      title: '个人信息',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 12),
          FigmaGlassCard(
            child: Column(
              children: [
                _AvatarRow(color: user.avatarColor),
                const FigmaFormDivider(),
                FigmaAccountField(
                  label: '昵称',
                  controller: _nicknameController,
                  hintText: '请输入昵称',
                ),
                const FigmaFormDivider(),
                FigmaInfoRow(label: 'ID', value: user.id),
                const FigmaFormDivider(),
                FigmaInfoRow(
                  label: '邮箱',
                  value: emailText,
                  onTap: () {
                    Navigator.of(context).pushNamed<void>(
                      user.email.isEmpty
                          ? AppRoutes.figmaBindEmailIncomplete
                          : AppRoutes.figmaModifyEmail,
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
      bottom: FigmaPrimaryButton(label: '保存资料', onPressed: _saveProfile),
    );
  }

  void _saveProfile() {
    final user = widget.state.currentUser;
    final feedback = widget.state.updateProfile(
      nickname: _nicknameController.text,
      email: user.email,
      signature: user.signature,
      avatarColor: user.avatarColor,
    );
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(feedback.message)));
  }
}

class _AvatarRow extends StatelessWidget {
  const _AvatarRow({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 61,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(
          children: [
            const Expanded(child: Text('头像', style: FigmaTextStyles.formLabel)),
            CircleAvatar(
              radius: 20,
              backgroundColor: color,
              child: const Icon(
                Icons.person_rounded,
                color: Colors.white,
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
