import 'package:flutter/material.dart';

import '../../../shared/shared.dart';
import '../../../state.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key, required this.state});

  final PhotoFrameState state;

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  static const _avatarColors = <Color>[
    Color(0xFFBC6C25),
    Color(0xFF3D5A80),
    Color(0xFF588157),
    Color(0xFFD97757),
    Color(0xFF6D597A),
  ];

  late final TextEditingController _nicknameController;
  late final TextEditingController _emailController;
  late final TextEditingController _signatureController;
  late Color _avatarColor;

  @override
  void initState() {
    super.initState();
    final user = widget.state.currentUser;
    _nicknameController = TextEditingController(text: user.nickname);
    _emailController = TextEditingController(text: user.email);
    _signatureController = TextEditingController(text: user.signature);
    _avatarColor = user.avatarColor;
  }

  @override
  void dispose() {
    _nicknameController.dispose();
    _emailController.dispose();
    _signatureController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    return SubPageScaffold(
      title: state.tr(zh: '个人信息', en: 'Profile', ja: 'プロフィール'),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          AppPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 34,
                      backgroundColor: _avatarColor,
                      child: Text(
                        _nicknameController.text.isNotEmpty
                            ? _nicknameController.text
                                  .substring(0, 1)
                                  .toUpperCase()
                            : 'F',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 24,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            state.tr(zh: '用户 ID', en: 'User ID', ja: 'ユーザー ID'),
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            state.currentUser.id,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _nicknameController,
                  decoration: InputDecoration(
                    labelText: state.tr(zh: '昵称', en: 'Nickname', ja: 'ニックネーム'),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    labelText: state.tr(
                      zh: '绑定邮箱',
                      en: 'Bound Email',
                      ja: '連携メール',
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _signatureController,
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: state.tr(
                      zh: '个性签名',
                      en: 'Signature',
                      ja: 'シグネチャ',
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  state.tr(zh: '头像样式', en: 'Avatar Style', ja: 'アバタースタイル'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: _avatarColors.map((color) {
                    final selected = color == _avatarColor;
                    return GestureDetector(
                      onTap: () {
                        setState(() {
                          _avatarColor = color;
                        });
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: color,
                          border: Border.all(
                            color: selected ? Colors.black : Colors.white,
                            width: selected ? 3 : 1.5,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: () {
                    final feedback = state.updateProfile(
                      nickname: _nicknameController.text,
                      email: _emailController.text,
                      signature: _signatureController.text,
                      avatarColor: _avatarColor,
                    );
                    ScaffoldMessenger.of(context)
                      ..hideCurrentSnackBar()
                      ..showSnackBar(SnackBar(content: Text(feedback.message)));
                  },
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                  ),
                  child: Text(state.tr(zh: '保存信息', en: 'Save', ja: '保存')),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
