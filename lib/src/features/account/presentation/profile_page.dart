import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

import 'package:BoltStar/src/shared/widgets/app_widgets.dart';
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

  /// 已选、待随「保存资料」提交的本地头像。
  String? _pendingAvatarPath;

  /// 最近一次保存成功的本地头像：保存后继续用它回显（内容与刚上传的一致），
  /// 避免网络头像下载间隙/后端地址未生效时头像“消失”。
  String? _savedAvatarPath;

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
                  localPath: _pendingAvatarPath ?? _savedAvatarPath,
                  onTap: _pickAvatar,
                ),
                const FigmaFormDivider(),
                FigmaAccountField(
                  label: l10n.accNickname,
                  controller: _nicknameController,
                  hintText: l10n.accNicknameHint,
                  // 小程序 .nickname-input：值文字用灰色 #777e88（默认深色是 App 侧偏差）。
                  valueColor: const Color(0xFF777E88),
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
                // 小程序 `{{userInfo.id || '--'}}`：拿不到 ID 时占位，不留空。
                FigmaInfoRow(label: 'ID', value: user.id.isEmpty ? '--' : user.id),
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
                    Navigator.of(
                      context,
                    ).pushNamed<void>(AppRoutes.figmaModifyPassword);
                  },
                ),
              ],
            ),
          ),
          // 「保存资料」跟在表单卡下方（小程序 .profile-submit 固定在页面中上部、
          // 卡片之下，不是钉在屏幕底端），间距按 375×812 设计稿视觉取值。
          const SizedBox(height: 90),
          FigmaPrimaryButton(
            label: l10n.accSaveProfile,
            onPressed: _saveProfile,
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  /// 头像文件体积上限：100KB。原来直接传相机原图（4~12MB），弱网上传要几十秒
  /// （“头像上传过久”）；头像最终只在 ≤64lp 的圆圈里展示，100KB 绰绰有余。
  static const int _avatarMaxBytes = 100 * 1024;

  /// 头像像素长边上限：512px 在 3x 屏的 64lp 头像上仍然过采样 2 倍以上。
  static const double _avatarMaxEdge = 512;

  /// 点头像仅选择并本地回显；与小程序一致，头像和昵称在点「保存资料」时一起提交。
  Future<void> _pickAvatar() async {
    final picker = ImagePicker();
    final XFile? file;
    try {
      // 与 CastPhotoPicker 同思路：maxWidth/maxHeight/imageQuality 走平台原生
      // 降采样（Android inSampleSize / iOS CoreGraphics），顺带把 HEIC 转 JPEG。
      file = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: _avatarMaxEdge,
        maxHeight: _avatarMaxEdge,
        imageQuality: 85,
      );
    } catch (_) {
      if (mounted) {
        AppToast.warn(context, AppL10n.of(context).accCannotReadAlbum);
      }
      return;
    }
    if (file == null || !mounted) {
      return;
    }
    final compressed = await _ensureAvatarUnderLimit(file.path);
    if (!mounted) {
      return;
    }
    setState(() => _pendingAvatarPath = compressed);
  }

  /// 兜底压缩：原生降采样后一般已 <100KB，超限时用 image 包按质量阶梯重编码。
  /// 压缩失败（格式不支持等）退回原文件——上传慢总好过不能换头像。
  Future<String> _ensureAvatarUnderLimit(String path) async {
    try {
      final source = File(path);
      if (await source.length() <= _avatarMaxBytes) {
        return path;
      }
      final decoded = img.decodeImage(await source.readAsBytes());
      if (decoded == null) {
        return path;
      }
      var frame = decoded;
      if (frame.width > _avatarMaxEdge || frame.height > _avatarMaxEdge) {
        frame = frame.width >= frame.height
            ? img.copyResize(frame, width: _avatarMaxEdge.toInt())
            : img.copyResize(frame, height: _avatarMaxEdge.toInt());
      }
      List<int> bytes = img.encodeJpg(frame, quality: 80);
      for (final quality in const [70, 60, 50, 40]) {
        if (bytes.length <= _avatarMaxBytes) {
          break;
        }
        bytes = img.encodeJpg(frame, quality: quality);
      }
      final out = File('${source.parent.path}/boltstar_avatar_upload.jpg');
      await out.writeAsBytes(bytes, flush: true);
      return out.path;
    } catch (_) {
      return path;
    }
  }

  bool _saving = false;

  Future<void> _saveProfile() async {
    if (_saving) {
      return;
    }
    final user = widget.state.currentUser;
    setState(() => _saving = true);
    AppLoadingDialog.show(context, AppL10n.of(context).saving);
    final profileFeedback = await widget.state.updateProfile(
      nickname: _nicknameController.text,
      email: user.email,
      signature: user.signature,
      avatarColor: user.avatarColor,
    );
    if (!mounted) {
      return;
    }
    if (!profileFeedback.success) {
      AppLoadingDialog.hide(context);
      setState(() => _saving = false);
      AppToast.warn(context, profileFeedback.message);
      return;
    }

    final avatarPath = _pendingAvatarPath;
    if (avatarPath != null) {
      final avatarFeedback = await widget.state.updateAvatar(avatarPath);
      if (!mounted) {
        return;
      }
      if (!avatarFeedback.success) {
        AppLoadingDialog.hide(context);
        setState(() => _saving = false);
        AppToast.warn(context, avatarFeedback.message);
        return;
      }
    }

    AppLoadingDialog.hide(context);
    setState(() {
      _saving = false;
      // 头像已上传成功：转为「已保存」继续本地回显（与线上内容一致），
      // 不立刻切网络图——下载间隙会让头像闪空（“保存成功后头像不出来”）。
      if (avatarPath != null) {
        _savedAvatarPath = avatarPath;
      }
      _pendingAvatarPath = null;
    });
    // 保存成功后界面已刷新即为反馈，小程序同样不再弹成功提示。
  }
}

/// 头像行（小程序 `.avatar-row`）：头像 `mine-header.jpg`（64rpx≈32 圆形）+ 右侧箭头。
class _AvatarRow extends StatelessWidget {
  const _AvatarRow({
    required this.color,
    this.avatarUrl = '',
    this.localPath,
    this.onTap,
  });

  final Color color;
  final String avatarUrl;
  final String? localPath;
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
                child: localPath != null
                    ? Image.file(
                        File(localPath!),
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) =>
                            _defaultAvatar(),
                      )
                    : url.isEmpty
                    ? Image.asset(
                        'assets/images/mine-header.jpg',
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) =>
                            _fallback(),
                      )
                    : CachedNetworkImage(
                        imageUrl: url,
                        fit: BoxFit.cover,
                        // 32lp 圆形头像，按物理像素解码，避免原图全尺寸位图进内存。
                        memCacheWidth:
                            (32 * MediaQuery.devicePixelRatioOf(context))
                                .round(),
                        // 下载间隙先垫默认头像：不给 placeholder 时是空白圆，
                        // 看起来就像“头像丢了”。
                        placeholder: (context, imageUrl) => _defaultAvatar(),
                        errorWidget: (context, imageUrl, error) =>
                            _defaultAvatar(),
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

  Widget _defaultAvatar() {
    return Image.asset(
      'assets/images/mine-header.jpg',
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) => _fallback(),
    );
  }
}
