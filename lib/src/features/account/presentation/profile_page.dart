import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'package:BoltStar/src/shared/widgets/figma_common.dart';
import '../../../routes/app_routes.dart';
import '../../../shared/l10n/app_l10n.dart';
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
    // 进入时回后端刷新用户信息（对齐小程序 profile.js onShow getUserProfile）。
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final before = widget.state.currentUser.nickname;
      await widget.state.refreshCurrentUser();
      if (!mounted) {
        return;
      }
      final after = widget.state.currentUser.nickname;
      // 用户尚未改动昵称框时，同步为后端最新昵称。
      if (_nicknameController.text == before && after != before) {
        _nicknameController.text = after;
      }
      setState(() {});
    });
  }

  @override
  void dispose() {
    _nicknameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final user = widget.state.currentUser;
    final emailText = user.email.isEmpty ? l10n.accNotBound : user.email;

    return FigmaScreen(
      title: l10n.accProfileTitle,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 12),
          FigmaGlassCard(
            child: Column(
              children: [
                _AvatarRow(
                  color: user.avatarColor,
                  avatarUrl: user.avatarUrl,
                  onTap: _pickAndUploadAvatar,
                ),
                const FigmaFormDivider(),
                FigmaAccountField(
                  label: l10n.accNickname,
                  controller: _nicknameController,
                  hintText: l10n.accNicknameHint,
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
                  label: l10n.accEmail,
                  value: emailText,
                  onTap: () {
                    Navigator.of(context).pushNamed<void>(
                      user.email.isEmpty
                          ? AppRoutes.figmaBindEmailIncomplete
                          : AppRoutes.figmaModifyEmail,
                    );
                  },
                ),
                const FigmaFormDivider(),
                // 修改密码：原为已注册路由但无入口的孤儿页，这里接上入口。
                FigmaInfoRow(
                  label: l10n.accModifyPasswordTitle,
                  value: '',
                  onTap: () {
                    Navigator.of(context).pushNamed<void>(
                      AppRoutes.figmaModifyPassword,
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
      bottom: FigmaPrimaryButton(label: l10n.accSaveProfile, onPressed: _saveProfile),
    );
  }

  /// 点头像换头像：从相册选图 → 上传 → changeAvatar（对齐小程序 profile.js:48）。
  Future<void> _pickAndUploadAvatar() async {
    final picker = ImagePicker();
    final XFile? file;
    try {
      file = await picker.pickImage(source: ImageSource.gallery);
    } catch (_) {
      if (mounted) {
        AppToast.show(context, AppL10n.of(context).accAlbumReadFailed);
      }
      return;
    }
    if (file == null || !mounted) {
      return;
    }
    AppToast.show(context, AppL10n.of(context).accAvatarUploading);
    final feedback = await widget.state.updateAvatar(file.path);
    if (!mounted) {
      return;
    }
    setState(() {});
    AppToast.show(context, feedback.message);
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
    AppToast.show(context, feedback.message);
  }
}

/// 头像行（小程序 `.avatar-row`）：头像 `mine-header.png`（64rpx≈32 圆形）+ 右侧箭头。
class _AvatarRow extends StatelessWidget {
  const _AvatarRow({required this.color, this.avatarUrl = '', this.onTap});

  final Color color;
  final String avatarUrl;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final url = avatarUrl.trim();
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        height: 60,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  AppL10n.of(context).accAvatar,
                  style: FigmaTextStyles.formLabel,
                ),
              ),
              Container(
                width: 32,
                height: 32,
                clipBehavior: Clip.antiAlias,
                decoration: const BoxDecoration(shape: BoxShape.circle),
                child: url.isEmpty
                    ? Image.asset(
                        'assets/images/mine-header.png',
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) =>
                            _fallback(),
                      )
                    : Image.network(
                        url,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) =>
                            Image.asset(
                          'assets/images/mine-header.png',
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) =>
                              _fallback(),
                        ),
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
      ),
    );
  }

  Widget _fallback() {
    return Container(
      color: color,
      child: const Icon(Icons.person_rounded, color: Colors.white, size: 20),
    );
  }
}
