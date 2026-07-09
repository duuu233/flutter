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
                  trailing: Image.asset(
                    'assets/images/edit-icon01.png',
                    width: 14,
                    height: 14,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) {
                      return const Icon(
                        Icons.edit_outlined,
                        size: 14,
                        color: Color(0x992A2B2B),
                      );
                    },
                  ),
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

  bool _saving = false;

  Future<void> _saveProfile() async {
    if (_saving) {
      return;
    }
    final user = widget.state.currentUser;
    setState(() => _saving = true);
    final feedback = await widget.state.updateProfile(
      nickname: _nicknameController.text,
      email: user.email,
      signature: user.signature,
      avatarColor: user.avatarColor,
    );
    if (!mounted) {
      return;
    }
    setState(() => _saving = false);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(feedback.message)));
  }
}

/// 头像行（小程序 `.avatar-row`）：头像 `mine-header.png`（64rpx≈32 圆形）+ 右侧箭头。
class _AvatarRow extends StatelessWidget {
  const _AvatarRow({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 60,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(
          children: [
            const Expanded(child: Text('头像', style: FigmaTextStyles.formLabel)),
            Container(
              width: 32,
              height: 32,
              clipBehavior: Clip.antiAlias,
              decoration: const BoxDecoration(shape: BoxShape.circle),
              child: Image.asset(
                'assets/images/mine-header.png',
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return Container(
                    color: color,
                    child: const Icon(
                      Icons.person_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                  );
                },
              ),
            ),
            const SizedBox(width: 9),
            const Icon(
              Icons.chevron_right_rounded,
              color: Color(0xFF777E88),
              size: 18,
            ),
          ],
        ),
      ),
    );
  }
}
