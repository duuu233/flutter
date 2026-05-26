import 'package:flutter/material.dart';

import '../../../routes/app_routes.dart';
import '../../../shared/shared.dart';
import '../../../state.dart';

class MinePage extends StatelessWidget {
  const MinePage({super.key, required this.state});

  final PhotoFrameState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = state.currentUser;

    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 120),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(32),
                  color: Colors.white.withValues(alpha: 0.76),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.8),
                  ),
                  boxShadow: [
                    BoxShadow(
                      blurRadius: 24,
                      offset: const Offset(0, 14),
                      color: Colors.black.withValues(alpha: 0.08),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 32,
                          backgroundColor: user.avatarColor,
                          child: Text(
                            user.nickname.isNotEmpty
                                ? user.nickname.substring(0, 1).toUpperCase()
                                : 'F',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 22,
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                user.nickname,
                                key: const Key('mine-page-title'),
                                style: theme.textTheme.headlineSmall,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                state.isLoggedIn
                                    ? user.email
                                    : state.tr(
                                        zh: '未登录',
                                        en: 'Signed out',
                                        ja: '未ログイン',
                                      ),
                                style: theme.textTheme.bodyMedium,
                              ),
                            ],
                          ),
                        ),
                        FilledButton.tonal(
                          onPressed: () {
                            Navigator.of(
                              context,
                            ).pushNamed<void>(AppRoutes.auth);
                          },
                          child: Text(
                            state.tr(zh: '登录注册', en: 'Auth', ja: '認証'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(user.signature, style: theme.textTheme.bodyLarge),
                    const SizedBox(height: 18),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        StatTag(
                          label: '${state.totalPhotoCount}',
                          icon: Icons.photo_library_outlined,
                          foreground: theme.colorScheme.primary,
                          background: theme.colorScheme.primary.withValues(
                            alpha: 0.10,
                          ),
                        ),
                        StatTag(
                          label: '${state.devices.length}',
                          icon: Icons.devices_outlined,
                          foreground: const Color(0xFFD97757),
                          background: const Color(
                            0xFFD97757,
                          ).withValues(alpha: 0.12),
                        ),
                        StatTag(
                          label: '${state.successCount}/${state.failureCount}',
                          icon: Icons.receipt_long_outlined,
                          foreground: const Color(0xFF6B705C),
                          background: const Color(
                            0xFF6B705C,
                          ).withValues(alpha: 0.12),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              SectionHeader(
                title: state.tr(zh: '账户与资料', en: 'Account', ja: 'アカウント'),
                subtitle: state.tr(
                  zh: '邮箱密码登录、个人信息和头像管理。',
                  en: 'Email verification, profile and avatar management.',
                  ja: 'メール認証、プロフィール、アバター管理。',
                ),
              ),
              const SizedBox(height: 12),
              AppPanel(
                child: Column(
                  children: [
                    MenuTile(
                      icon: Icons.alternate_email_rounded,
                      title: state.tr(
                        zh: '登录注册 - app',
                        en: 'Email Login',
                        ja: 'メールログイン',
                      ),
                      subtitle: state.tr(
                        zh: '邮箱验证码注册 / 登录',
                        en: 'Register or sign in with email code',
                        ja: 'メール認証コードで登録 / ログイン',
                      ),
                      onTap: () {
                        Navigator.of(context).pushNamed<void>(AppRoutes.auth);
                      },
                    ),
                    const Divider(height: 24),
                    MenuTile(
                      icon: Icons.badge_outlined,
                      title: state.tr(zh: '个人信息', en: 'Profile', ja: 'プロフィール'),
                      subtitle: state.tr(
                        zh: '昵称、头像、ID、邮箱修改',
                        en: 'Nickname, avatar, ID and email update',
                        ja: 'ニックネーム、アバター、ID、メール変更',
                      ),
                      onTap: () {
                        Navigator.of(
                          context,
                        ).pushNamed<void>(AppRoutes.profile);
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              SectionHeader(
                title: state.tr(
                  zh: '资产与设备',
                  en: 'Assets & Devices',
                  ja: '資産と端末',
                ),
                subtitle: state.tr(
                  zh: '我的相册、设备管理与投屏记录。',
                  en: 'My Album, device management and cast records.',
                  ja: 'マイアルバム、端末管理、投映履歴。',
                ),
              ),
              const SizedBox(height: 12),
              AppPanel(
                child: Column(
                  children: [
                    MenuTile(
                      icon: Icons.photo_library_outlined,
                      title: state.tr(zh: '我的相册', en: 'My Album', ja: 'マイアルバム'),
                      subtitle: state.tr(
                        zh: '只显示成功上传至设备的照片数据',
                        en: 'Only shows photos successfully uploaded to devices',
                        ja: '端末へのアップロード成功分のみ表示',
                      ),
                      onTap: () {
                        Navigator.of(context).pushNamed<void>(AppRoutes.album);
                      },
                    ),
                    const Divider(height: 24),
                    MenuTile(
                      icon: Icons.devices_outlined,
                      title: state.tr(
                        zh: '我的设备',
                        en: 'My Devices',
                        ja: 'マイデバイス',
                      ),
                      subtitle: state.tr(
                        zh: '设备连接、电量、SN 码、权限、清空与轮播',
                        en: 'Connection, battery, SN, role, clear and carousel',
                        ja: '接続、電池、SN、権限、全削除、スライド設定',
                      ),
                      onTap: () {
                        Navigator.of(
                          context,
                        ).pushNamed<void>(AppRoutes.devices);
                      },
                    ),
                    const Divider(height: 24),
                    MenuTile(
                      icon: Icons.history_toggle_off_rounded,
                      title: state.tr(
                        zh: '投屏管理',
                        en: 'Cast Records',
                        ja: '投映管理',
                      ),
                      subtitle: state.tr(
                        zh: '成功 / 失败记录，支持再次投屏和删除',
                        en: 'Success / failure records with recast and delete',
                        ja: '成功 / 失敗履歴の再投映と削除',
                      ),
                      onTap: () {
                        Navigator.of(
                          context,
                        ).pushNamed<void>(AppRoutes.castManagement);
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              SectionHeader(
                title: state.tr(
                  zh: '帮助与设置',
                  en: 'Support & Settings',
                  ja: 'サポートと設定',
                ),
                subtitle: state.tr(
                  zh: '帮助文档、语言、隐私政策和账号退出。',
                  en: 'Guides, language, privacy policy and sign-out.',
                  ja: 'ガイド、言語、プライバシー、ログアウト。',
                ),
              ),
              const SizedBox(height: 12),
              AppPanel(
                child: Column(
                  children: [
                    MenuTile(
                      icon: Icons.menu_book_outlined,
                      title: state.tr(zh: '操作指南', en: 'Guides', ja: '操作ガイド'),
                      subtitle: state.tr(
                        zh: '按设备类型查看帮助文档',
                        en: 'Browse help documents by device type',
                        ja: '端末タイプ別のヘルプを表示',
                      ),
                      onTap: () {
                        Navigator.of(context).pushNamed<void>(AppRoutes.guide);
                      },
                    ),
                    const Divider(height: 24),
                    MenuTile(
                      icon: Icons.settings_outlined,
                      title: state.tr(zh: '设置', en: 'Settings', ja: '設定'),
                      subtitle: state.tr(
                        zh: '关于我们、联系方式、隐私政策、用户协议、语种设置',
                        en: 'About, contact, privacy policy, agreement and language',
                        ja: '会社情報、連絡先、プライバシー、規約、言語設定',
                      ),
                      onTap: () {
                        Navigator.of(
                          context,
                        ).pushNamed<void>(AppRoutes.settings);
                      },
                    ),
                  ],
                ),
              ),
            ]),
          ),
        ),
      ],
    );
  }
}
